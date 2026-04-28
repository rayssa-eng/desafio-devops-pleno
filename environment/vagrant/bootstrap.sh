#!/bin/bash
set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
BASE_DIR="/home/vagrant/environment/kubernetes"

until kubectl cluster-info &> /dev/null; do
  echo "Aguardando API do Kubernetes..."
  sleep 5
done

echo "--- 2. Instalando Istio no Cluster ---"
curl -sL https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=default -y \
  --set values.pilot.tolerations[0].key='CriticalAddonsOnly' \
  --set values.pilot.tolerations[0].operator='Exists' \
  --set values.pilot.tolerations[0].effect='NoExecute' \
  --set values.global.proxy.autoInject=enabled \
  --set meshConfig.enablePrometheusMerge=true

echo "--- 3. Configurando Namespaces e Segurança (Kustomize) ---"
kubectl apply -k ${BASE_DIR}/cluster-setup/

echo "--- 3.5. Instalando o Helm ---"
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "--- 4. Fazendo Deploy dos Serviços (1, 2 e 3) ---"
kubectl apply -f ${BASE_DIR}/apps/service-1/
kubectl apply -f ${BASE_DIR}/apps/service-3/
helm install service-2 ${BASE_DIR}/apps/service-2/chart/ -n service-2

echo "--- 5. Instalando KEDA e Prometheus (Helm) ---"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm upgrade --install prometheus prometheus-community/prometheus -n monitoring \
  --timeout 20m \
  --set server.persistentVolume.enabled=false \
  --set-file extraScrapeConfigs=${BASE_DIR}/apps/prometheus/scrape-jobs.yaml

helm upgrade --install keda kedacore/keda -n autoscaling \
    --timeout 20m

echo "--- 6. Configurando o Autoscaling ---"
kubectl apply -f ${BASE_DIR}/apps/keda/scaler-service-1.yaml

echo "🚀 Bootstrap interno concluído com sucesso!"