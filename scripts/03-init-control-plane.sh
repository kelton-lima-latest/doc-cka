#!/usr/bin/env bash
# Executado DENTRO da VM control-plane: kubeadm init, kubeconfig, Cilium CLI
# e instalação da CNI. Ao final, grava o comando de join em /tmp/kubeadm-join-command.sh.
set -euo pipefail

if [ -f /etc/kubernetes/admin.conf ]; then
  echo "Cluster já inicializado neste nó."
else
  sudo kubeadm init
fi

mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

export KUBECONFIG="$HOME/.kube/config"

if ! command -v cilium >/dev/null 2>&1; then
  echo "Instalando Cilium CLI..."
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  CLI_ARCH=amd64
  if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
  sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
  sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
  rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
fi

if ! kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q .; then
  echo "Instalando camada de rede Cilium..."
  cilium install --wait
else
  echo "Cilium já instalado."
fi

echo "Aguardando node control-plane ficar Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s

kubeadm token create --print-join-command | tee /tmp/kubeadm-join-command.sh
