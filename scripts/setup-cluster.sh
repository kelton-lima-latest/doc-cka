#!/usr/bin/env bash
# Orquestra a criação completa do cluster a partir do host, usando
# multipass para rodar os demais scripts dentro de cada VM.
# Uso: ./setup-cluster.sh [nome-control-plane] [nome-worker-1] [nome-worker-2] ...
# Se nenhum argumento for passado, usa CONTROL_PLANE_NAME/WORKER_NODES (env) ou os padrões abaixo.
# Outras variáveis opcionais: K8S_VERSION, VM_CPUS, VM_MEMORY, VM_DISK, VM_IMAGE
# DRY_RUN=1 imprime as ações sem executá-las (não transfere nem roda nada nas VMs).
#
# Depois do cluster pronto, se outros dispositivos da LAN precisarem acessar
# serviços expostos (NodePort), rode manualmente (requer sudo e root no
# host): scripts/05-lan-gateway.sh. Ver dia-04.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  CONTROL_PLANE_NAME="$1"
  shift
  WORKER_NODES="$*"
else
  CONTROL_PLANE_NAME="${CONTROL_PLANE_NAME:-controlplane}"
  WORKER_NODES="${WORKER_NODES:-node01}"
fi
K8S_VERSION="${K8S_VERSION:-1.34}"
export DRY_RUN="${DRY_RUN:-0}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "==> 1/4 Provisionando VMs"
"$SCRIPT_DIR/01-provision-vms.sh" "$CONTROL_PLANE_NAME" $WORKER_NODES

echo "==> 2/4 Preparando nós (containerd, kubeadm, kubelet, kubectl)"
for vm in "$CONTROL_PLANE_NAME" $WORKER_NODES; do
  echo "--- $vm ---"
  run multipass transfer "$SCRIPT_DIR/02-prepare-node.sh" "$vm:/tmp/02-prepare-node.sh"
  run multipass exec "$vm" -- chmod +x /tmp/02-prepare-node.sh
  run multipass exec "$vm" -- /tmp/02-prepare-node.sh "$K8S_VERSION"
done

echo "==> 3/4 Inicializando control-plane e instalando Cilium"
run multipass transfer "$SCRIPT_DIR/03-init-control-plane.sh" "$CONTROL_PLANE_NAME:/tmp/03-init-control-plane.sh"
run multipass exec "$CONTROL_PLANE_NAME" -- chmod +x /tmp/03-init-control-plane.sh
run multipass exec "$CONTROL_PLANE_NAME" -- /tmp/03-init-control-plane.sh

if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] multipass exec $CONTROL_PLANE_NAME -- cat /tmp/kubeadm-join-command.sh"
  JOIN_COMMAND="kubeadm join <dry-run>:6443 --token <dry-run> --discovery-token-ca-cert-hash sha256:<dry-run>"
else
  JOIN_COMMAND="$(multipass exec "$CONTROL_PLANE_NAME" -- cat /tmp/kubeadm-join-command.sh)"
fi

echo "==> 4/4 Adicionando workers ao cluster"
for vm in $WORKER_NODES; do
  echo "--- $vm ---"
  run multipass transfer "$SCRIPT_DIR/04-join-worker.sh" "$vm:/tmp/04-join-worker.sh"
  run multipass exec "$vm" -- chmod +x /tmp/04-join-worker.sh
  run multipass exec "$vm" -- /tmp/04-join-worker.sh "$JOIN_COMMAND"
done

echo
echo "Cluster pronto! Verificando nodes:"
run multipass exec "$CONTROL_PLANE_NAME" -- kubectl get nodes
