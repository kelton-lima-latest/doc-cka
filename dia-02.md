# Dia 02
### Upgrade de versão 1.34 para 1.35.

#### Comandos abaixo devem ser executados em **TODOS** os nós do cluster.

Atualize o índice de pacotes apt e instale os pacotes necessários para usar o repositório apt do Kubernetes(v1.35):  

```bash
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Baixe a chave pública de assinatura para os repositórios de pacotes do Kubernetes(v1.35). Aceite a mudança de chave pública.

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Adicione o repositório apt adequado do Kubernetes(v1.35).  
```bash
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Encontre a versão de patch mais recente do Kubernetes 1.35 usando o gerenciador de pacotes do SO:  
```bash
  sudo apt update
  sudo apt-cache madison kubeadm
```

Substitua x em 1.35.x-* pela versão de patch mais recente.
```bash
sudo apt-mark unhold kubeadm && \
sudo apt-get update && sudo apt-get install -y kubeadm='1.35.0-1.1' && \
sudo apt-mark hold kubeadm
```

### Upgrade control-plane.
Verifique o plano de upgrade  
```bash
sudo kubeadm upgrade plan
```

Escolha uma versão para o upgrade e execute o comando adequado. Por exemplo:  
```bash
sudo kubeadm upgrade apply v1.35.0
```

### Upgrade kubectl e kubelet  
```bash
sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet='1.35.0-1.1' kubectl='1.35.0-1.1' && \
sudo apt-mark hold kubelet kubectl
```
Reinicie o kubelet
```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

Verificar versão dos nós. Caso a nova versão esteja sendo listada, o upgrade ocorreu com sucesso.
```bash
kubectl get nodes
```

### Upgrade worders nodes

Digitar comando abaixo no control-plane.  
Prepare o nó para manutenção marcando-o como não agendável e evacuando as cargas de trabalho:
```bash
kubectl drain node-01 --ignore-daemonsets
```

Verificar comandos que devem serem executados em todos os nós do cluster.

```bash
sudo kubeadm upgrade node
```

### Upgrade kubectl e kubelet  
```bash
sudo apt-mark unhold kubelet kubectl && \
sudo apt-get update && sudo apt-get install -y kubelet='1.35.0-1.1' kubectl='1.35.0-1.1' && \
sudo apt-mark hold kubelet kubectl
```
Reinicie o kubelet
```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```
Digitar comando abaixo no control-plane.  
Torne o nó online novamente marcando-o como agendável:
```bash
kubectl uncordon node-01
```

### Verificar se atualização ocorreu com sucesso e se nó worker mostra status redy.
```bash
kubectl get nodes
```
