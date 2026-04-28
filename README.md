# Desafio DevOps Pleno — Malha de Serviços

Este repositório contém o provisionamento de infraestrutura e a configuração de uma malha de serviços (Service Mesh) utilizando Kubernetes (k3s) e Istio. Além disso, foi utilizado Prometheus para fins de monitoramento e KEDA para autoscaling horizontal.

## 1. Justificativa da Ferramenta de Provisionamento

Foi escolhido o **Vagrant** utilizando o provider **libvirt (KVM)**. Essa combinação facilita um ambiente local isolado, idêntico para qualquer avaliador, e com alta performance no Linux. Isto porque o Vagrant utiliza um arquivo - o `Vagrantfile` - que segue o princípio da Infraestrutura como Código, facilitando a reprodutibilidade, enquanto que o `libvirt` oferece performance de virtualização nativa no Linux, devido à sua interação de baixo nível com o KVM (Kernel-based Virtual Machine).

## 2. Arquitetura e Fluxo de Tráfego

A arquitetura foi projetada sobre um único nó (K3s/Vagrant) operando sob os princípios de Zero Trust Network. O ambiente utiliza o Istio para desacoplar a lógica de rede e segurança da aplicação, transferindo essas responsabilidades para os sidecars (Envoy Proxies) injetados em cada pod.

### 2.1 Topologia
* **`istio-system`:** Hospeda o Control Plane do Istio (`istiod`) e o Ingress Gateway (`istio-ingressgateway`), que atua como a porta de entrada do cluster.

* **service-1:** Exposto externamente para receber requisições de clientes. Executa sob a Service Account `service-1-sa`.
* **service-2:** Estritamente isolado do tráfego externo, configurado para ser acessível exclusivamente pelo `service-1`. Executa sob a Service Account `service-2-sa`.

* **service-3:** Também exposto diretamente a clientes externos, mas blindado lateralmente contra os outros serviços do cluster. Executa sob a Service Account `service-3-sa`.

### 2.2 Tráfego de rede
O roteamento ocorre em duas esferas principais:

* **Tráfego externo para dentro do Cluster**:

        O cliente faz uma requisição HTTP para o istio-ingressgateway.

        O recurso Gateway (service-1-gateway ou service-3-gateway) abre a porta 80.

        O VirtualService (service-1-vs ou service-3-vs) intercepta o tráfego destinado ao host service-1.local e o direciona para o pod do service-1 e faz a mesma coisa com o tráfego destinado ao service-3.local.

* **Comunição interna ao Cluster**:

        Quando o service-1 precisa acessar o service-2, um VirtualService secundário (route-to-service-2) gerencia a rota interna.

        Uma DestinationRule (mtls-to-service-2) força o Envoy do service-1 a iniciar um handshake TLS mútuo (ISTIO_MUTUAL) antes de enviar o pacote para o service-2.

### 2.3 Segurança e políticas aplicadas
* **Onde é validado o JWT:** 
    * A validação ocorre diretamente no Envoy sidecar do `service-1` e `service-3` (via `RequestAuthentication`). 
    * O recurso `RequestAuthentication` inspeciona o cabeçalho HTTP em busca do token assinado, identificando o remetente. Uma `AuthorizationPolicy` vinculada garante que nenhuma requisição externa passe sem um token JWT válido, bloqueando conexões anônimas na origem.

* **Onde o mTLS atua:** Configurado globalmente como `STRICT` no namespace `istio-system` (via `PeerAuthentication`), garantindo que toda a comunicação interna seja criptografada.
* **Uso da ServiceAccount nas AuthorizationPolicies:** 
    * **Isolamento do service-2 (*whitelisting*)**: A AuthorizationPolicy do service-2 possui uma regra `ALLOW` explícita. Ela avalia a identidade `mTLS` do cliente e só autoriza a conexão se o `source.principal` for a identidade do `service-1-sa`. Qualquer outra origem ou acesso anônimo é negado por padrão.

    * **Isolamento do service-3 (*blacklisting*):** Como o `service-3` atende a clientes externos validados via `JWT`, sua `AuthorizationPolicy` intra-cluster aplica uma regra de `DENY`. Ela bloqueia explicitamente qualquer tentativa de acesso interno caso o `source.principal` corresponda às identidades do `service-1-sa` ou `service-2-sa`, garantindo que não haja trânsito lateral indevido.


## 3. JWT e JWKS

* **Geração:** Utilizou-se um token estático pré-gerado (assinado via RSA) disponibilizado pelo repositório oficial de ferramentas de segurança do Istio.
* **Configuração:** O cluster foi configurado para confiar no emissor `testing@secure.istio.io`. A validação da assinatura ocorre localmente pelo Istio (sem necessidade de um Identity Provider dedicado no cluster), que consulta o endpoint público de chaves (**JWKS** - `jwksUri`) para confirmar a autenticidade do token.

## 4. Passo a Passo Reproduzível

O ambiente foi projetado para exigir o mínimo de intervenção humana possível. Assume-se uma máquina host baseada em Linux (Ubuntu/Debian) para a execução nativa do script.

### Passo 1: Clonar o repositório
Baixe o código e navegue até a pasta de provisionamento do Vagrant:

```bash
git clone <URL_DO_SEU_REPOSITORIO>
cd <NOME_DA_PASTA>/environment/vagrant
```

### Passo 2: Executar o Setup Automatizado
O script principal cuidará da instalação das dependências de virtualização (KVM/libvirt) no host e orquestrará a subida do cluster. *Nota: o script pedirá a senha do usuário (`sudo`) uma única vez para instalar os pacotes do libvirt.*

```bash
chmod +x setup.sh
./setup.sh
```

### Passo 3: Acompanhar a Automação (Hands-off)
A partir deste ponto, o processo é 100% automatizado. Você acompanhará no terminal a evolução das seguintes etapas:

1. Instalação e configuração do `qemu-kvm` e `vagrant-libvirt` no host.
2. Download da imagem do SO e subida da VM via Vagrant.
3. Inicialização do *Control Plane* do K3s (gerando um token seguro automaticamente).
4. Execução do `bootstrap.sh` interno, que injeta a malha do Istio, configura o Kustomize, instala o stack de monitoramento (Prometheus + KEDA) e sobe os três serviços com suas respectivas políticas de segurança.

> ⏳ **Tempo estimado:** Entre 5 e 8 minutos (dependendo da velocidade de download das imagens).
> 
> Ao final da execução, os pods estarão subindo, com a maioria em estado `Running` e você verá a mensagem: **"🚀 Ambiente provisionado"**.
   
## 6. Justificativa de decisões não triviais

Durante o desenvolvimento da infraestrutura, algumas decisões arquiteturais foram tomadas para balancear segurança, performance e viabilidade do ambiente local:

* **K3s sem Traefik:** O K3s foi inicializado com a flag `--disable traefik`. Isso foi crucial para evitar conflitos de *bind* nas portas 80 e 443 do host, permitindo que o `istio-ingressgateway` assumisse o controle total do tráfego de borda. 

* **Escopo global do PeerAuthentication:** Em vez de aplicar o mTLS por namespace, optou-se por uma política `STRICT` alocada no namespace `istio-system` (comportamento global). Essa decisão garante que qualquer novo serviço adicionado futuramente ao cluster nasça protegido e com tráfego em texto plano bloqueado por padrão.

* **Algoritmo JWT e JWKS Remoto:** Utilizou-se o algoritmo **RS256** (padrão do *demo token* do Istio). Como o escopo do desafio é voltado para um ambiente de laboratório e dispensa explicitamente o uso de um Identity Provider (IdP), a escolha por um JWKS público hospedado no GitHub foi a decisão arquitetural mais enxuta.

* **Imagens Base (Containers):** Em vez de utilizar a imagem `httpbin` (como sugerido pra esse desafio), optou-se pela `curlimages/curl` operando em conjunto com utilitários simples (`nc` e `echo`). Essa decisão técnica foi tomada porque ter o `curl` embarcado nativamente no container facilita imensamente a validação das regras de comunicação leste-oeste: permite testar a conexão direta de um pod para outro (via `kubectl exec`) sem atritos.

* **Geração Dinâmica do Token do K3s:** Para evitar o hardcoding do token, o código Ruby no `Vagrantfile` gera o `K3S_TOKEN` via `SecureRandom` no primeiro boot e o oculta no arquivo `.k3s_token` (adicionado ao `.gitignore`).

---

## 7. (Bônus) Autoscaling Orientado a Eventos (KEDA + Prometheus)

Para este desafio, foi implementado um pipeline de autoscaling preditivo baseado na **camada L7 (Aplicação)**.

### Métrica e Algoritmo Escolhidos
* **Métrica:** `istio_requests_total` (Extraída diretamente da telemetria do Envoy/Istio via Prometheus).
* **Query PromQL:** `sum(increase(istio_requests_total{destination_app="service-1", reporter="destination"}[2m]))`
* **Justificativa do Algoritmo:** A função `increase` sobre uma janela móvel de `[2m]` (dois minutos) foi escolhida estrategicamente em vez da função `rate`. Isso permite que a infraestrutura absorva picos súbitos sem sofrer com *flapping* (o efeito "ioiô" de criar e destruir pods repetidamente por causa de variações de microssegundos), proporcionando estabilidade para a malha.
* **Threshold (Gatilho):** Definido no `ScaledObject` como `6000` requisições acumuladas. Na janela de 2 minutos, isso equivale a um limite de tolerância de aproximadamente **50 Requisições por Segundo (RPS)** por réplica antes que a latência comece a degradar e o KEDA decida escalar.

### Script k6 e Demonstração do Fluxo
Para validar a arquitetura, foi criado um script de teste de carga utilizando a ferramenta **k6** (`/tests/load-test.js`). 

**Configuração do Teste:**
* **Carga:** 10 Virtual Users (VUs) simultâneos rodando por 1 minuto.
* **Segurança:** O script injeta o token estático validado dinamicamente no header `Authorization: Bearer` para passar pela `AuthorizationPolicy` do Istio.

**Ciclo de Vida Demonstrado (Scale-up e Scale-down):**
1. **Pico de Carga:** O k6 injeta um volume de aproximadamente 94 RPS contra o `service-1-gateway`.
2. **Scale-up Instantâneo:** O Prometheus raspa a métrica, que cruza o threshold de 6000. O HPA gerenciado pelo KEDA entra em ação e dimensiona as réplicas do `service-1` de 1 para 5 (limite máximo estabelecido).
3. **Absorção:** O tráfego é balanceado pelo Istio entre os 5 pods ativos, garantindo 200 OK em todas as requisições.
4. **Scale-down Automático:** Após o fim do teste, o KEDA identifica a ausência de novas requisições. Respeitando a janela de *cooldown* configurada no cluster, os pods excedentes são finalizados graciosamente, retornando a capacidade ao mínimo de 1 réplica para otimização de custos de nuvem.
   
   
   
   
   . O Conflito (Port Bind Error)
Se você instalar o Istio em um k3s que já está rodando o Traefik:

    O Traefik já vai estar escutando nas portas 80 e 443.

    Quando o Istio Ingress Gateway tentar subir, ele também vai tentar se "conectar" (bind) às portas 80 e 443 do host.

    O Kubernetes vai falhar a subida do pod do Istio (ficará em estado Pending ou CrashLoopBackOff) acusando que a porta já está em uso (Address already in use).