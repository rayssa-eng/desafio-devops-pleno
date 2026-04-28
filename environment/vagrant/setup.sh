#!/bin/bash

# Cores para o log
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}==> Verificando dependencias locais (libvirt)...${NC}"
sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils vagrant-libvirt
sudo adduser $USER libvirt
sudo adduser $USER kvm

echo -e "${GREEN}==> Subindo a infraestrutura com Vagrant...${NC}"
VAGRANT_DEFAULT_PROVIDER=libvirt vagrant up

echo -e "${GREEN}==> Verificando o status do Cluster...${NC}"
vagrant ssh server -c "kubectl get nodes && kubectl get pods -A"

