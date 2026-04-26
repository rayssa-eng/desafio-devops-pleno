cat << 'EOF' > setup.sh
#!/bin/bash

# Cores para o log
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}==> 1. Verificando dependencias locais (libvirt)...${NC}"
sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils vagrant-libvirt
sudo adduser $USER libvirt
sudo adduser $USER kvm

echo -e "${GREEN}==> 2. Subindo a infraestrutura com Vagrant...${NC}"
VAGRANT_DEFAULT_PROVIDER=libvirt vagrant up

echo -e "${GREEN}==> 3. Instalando Istio no Cluster...${NC}"
# Copiando o binário do istioctl do servidor para o seu host (opcional) ou rodando via SSH
vagrant ssh server -c "
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    curl -L https://istio.io/downloadIstio | sh -
    cd istio-*
    export PATH=\$PWD/bin:\$PATH
    istioctl install --set profile=default -y \
      --set values.pilot.tolerations[0].key='CriticalAddonsOnly' \
      --set values.pilot.tolerations[0].operator='Exists' \
      --set values.pilot.tolerations[0].effect='NoExecute' \
      --set values.global.proxy.autoInject=enabled \
      --set meshConfig.enablePrometheusMerge=true
"

echo -e "${GREEN}==> 4. Configurando Namespaces e Seguranca (Kustomize)...${NC}"
# Aplica a pasta que criamos anteriormente
vagrant ssh server -c "kubectl apply -k /vagrant/cluster-setup/"

echo -e "${GREEN}==> 5. Verificando o status do Cluster...${NC}"
vagrant ssh server -c "kubectl get nodes && kubectl get pods -A"

echo -e "${GREEN} [SUCESSO] Ambiente pronto para o Requisito 3!${NC}"
EOF

chmod +x setup.sh