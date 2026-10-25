#!/usr/bin/env bash
# Executado DENTRO de cada VM worker: adiciona o nó ao cluster.
# Uso: ./04-join-worker.sh '<comando kubeadm join completo, com sudo removido>'
set -euo pipefail

JOIN_COMMAND="${1:-}"

if [ -z "$JOIN_COMMAND" ]; then
  echo "Uso: $0 '<comando kubeadm join completo>'" >&2
  exit 1
fi

if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "Nó já faz parte de um cluster."
  exit 0
fi

sudo $JOIN_COMMAND
