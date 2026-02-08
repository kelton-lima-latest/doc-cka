# Dia 01
No primeido dia, vamos criar nosso cluster para estudos. Ferramenta utilizada para criar VMs vai ser multipass da Canonical.

### Instalar multipass

```bash
snap install multipass
```

### Criar ambiente
A primeira instalação é mais demorada, pois está baixando a imagem do sistema operacional. Sistema operacional das VMs escolhido é Ubuntu 22.04 LTS (Jammy).

#### Criar control-plane

```bash
multipass launch jammy --name control-plane --cpus 2 --memory 8G --disk 20G
```

#### Criar node-01

```bash
multipass launch jammy --name node-01 --cpus 2 --memory 8G --disk 20G
```

#### Listar VMs multipass

```bash
multipass list
```

|Name                   |State             |IPv4             |Image            |
|-----------------------|------------------|-----------------|-----------------|
|control-plane          |Running           |10.13.90.123     |Ubuntu 22.04 LTS |
|node-01                |Running           |10.13.90.152     |Ubuntu 22.04 LTS |

#### Acessar as VMs

```bash
multipass shell control-plane
```

```bash
multipass shell node-01
```

### Pré configurações 
Script abaixo deve ser executado em **TODOS** os nós do cluster.

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Parâmetros de rede essenciais para o Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Instalar do kubeadm
As instruções abaixo são para instalação do Kubernetes 1.34.  
  
Atualize o índice de pacotes apt e instale os pacotes necessários para usar o repositório apt do Kubernetes:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Baixe a chave pública de assinatura para os repositórios de pacotes do Kubernetes. A mesma chave de assinatura é usada para todos os repositórios, portanto, você pode desconsiderar a versão na URL:

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Adicione o repositório apt adequado do Kubernetes.

```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Atualize o índice de pacotes apt, instale o kubelet, kubeadm e kubectl, e fixe suas versões:

```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

(Opcional) Ative o serviço kubelet antes de executar o kubeadm:

```bash
sudo systemctl enable --now kubelet
```

### Iniciar cluster  
```bash
sudo kubeadm init
```

Para começar a usar seu cluster, você precisa executar o seguinte como um usuário comum:
```bash
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Como alternativa, se você for o usuário root, poderá executar:
```bash
  export KUBECONFIG=/etc/kubernetes/admin.conf
```

Listar nodes do cluster. Status vai mudar de notready para ready, após instalação da camada de rede (CNI).
```bash
kubectl get nodes
```


### Configurar Cilium
Instalar ultima versão do Cilium CLI.

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

Instalar camada de rede do cluster (CNI).

```bash
sudo cilium install 
```

Verificar se status do nó control-plane está ready. Se sim, pode seguir com kubeadm join do worker.

```bash
kubectl get nodes
```

```bash
kubeadm token create --print-join-command
```

### Adicionar nó ao control-plane

```bash
sudo kubeadm join ip-control-plane:6443...
```

### Referências
https://v1-34.docs.kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/  
https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
