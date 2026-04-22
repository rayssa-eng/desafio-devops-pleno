projeto-desafio-devops/
├── vagrant/
│   └── Vagrantfile       # Provisiona a VM com libvirt e instala o k3s
├── scripts/
│   └── install-istio.sh  # Script para automatizar o setup do Istio
├── kubernetes/
│   ├── base/             # Namespace, RequestAuth, PeerAuth (Zero Trust)
│   ├── service-1/        # YAML simples
│   ├── service-2/        # Helm Chart
│   └── service-3/        # YAML ou Helm
└── README.md             # Documentação e justificativa
