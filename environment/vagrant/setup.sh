#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}==> Verificando dependencias locais (libvirt)...${NC}"
sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils vagrant-libvirt
sudo adduser $USER libvirt
sudo adduser $USER kvm

echo -e "${GREEN}==> 2. Verificando possíveis conflitos no KVM/libvirt...${NC}"
# O vagrant-libvirt geralmente usa o nome da pasta como prefixo, ou o padrão 'vagrant'
PREFIX_DIR=${PWD##*/}
CONFLICTS=$(virsh list --all --name | grep -E "^(${PREFIX_DIR}_server|${PREFIX_DIR}_agent|vagrant_server|vagrant_agent)")

if [ -n "$CONFLICTS" ]; then
    echo -e "${YELLOW}[ATENÇÃO] Foram encontradas VMs antigas no libvirt que podem causar falha na execução:${NC}"
    echo "$CONFLICTS"
    
    read -p "Deseja que o script remova essas VMs automaticamente para garantir um ambiente limpo? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        for vm in $CONFLICTS; do
            echo -e "Limpando: $vm..."

            virsh destroy "$vm" >/dev/null 2>&1 || true
            virsh undefine "$vm" --remove-all-storage >/dev/null 2>&1 || true
        done
        rm -rf .vagrant/
        echo -e "${GREEN}Limpeza concluída!${NC}"
    else
        echo -e "${RED}Operação abortada pelo usuário. Limpe o ambiente manualmente e tente novamente.${NC}"
        exit 1
    fi
else
    echo "Nenhum conflito encontrado. Ambiente limpo!"
fi

echo -e "${GREEN}==> Subindo a infraestrutura com Vagrant...${NC}"
VAGRANT_DEFAULT_PROVIDER=libvirt vagrant up

echo -e "${GREEN}==> Verificando o status do Cluster...${NC}"
vagrant ssh server -c "kubectl get nodes && kubectl get pods -A"

