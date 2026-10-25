#!/usr/bin/env bash
# Provisiona as VMs do cluster (control-plane + workers) via multipass.
# Uso: ./01-provision-vms.sh [nome-control-plane] [nome-worker-1] [nome-worker-2] ...
# Se nenhum argumento for passado, usa CONTROL_PLANE_NAME/WORKER_NODES (env) ou os padrões abaixo.
# DRY_RUN=1 imprime as ações sem executá-las.
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

if [ "$#" -gt 0 ]; then
  CONTROL_PLANE_NAME="$1"
  shift
  WORKER_NODES="$*"
else
  CONTROL_PLANE_NAME="${CONTROL_PLANE_NAME:-controlplane}"
  WORKER_NODES="${WORKER_NODES:-node01}"
fi
VM_IMAGE="${VM_IMAGE:-jammy}"
VM_CPUS="${VM_CPUS:-2}"
VM_MEMORY="${VM_MEMORY:-4G}"
VM_DISK="${VM_DISK:-50G}"

if ! command -v multipass >/dev/null 2>&1; then
  echo "multipass não encontrado. Instalando via snap..."
  run sudo snap install multipass
fi

create_vm() {
  local name="$1"
  if multipass info "$name" >/dev/null 2>&1; then
    echo "VM '$name' já existe, pulando criação."
    return
  fi
  echo "Criando VM '$name' (cpus=$VM_CPUS, memory=$VM_MEMORY, disk=$VM_DISK)..."
  run multipass launch "$VM_IMAGE" --name "$name" --cpus "$VM_CPUS" --memory "$VM_MEMORY" --disk "$VM_DISK"
}

create_vm "$CONTROL_PLANE_NAME"
for node in $WORKER_NODES; do
  create_vm "$node"
done

echo
multipass list
