#!/usr/bin/env bash
# Instala um gateway no host (notebook) para que outros dispositivos da LAN
# consigam acessar serviços expostos no cluster Multipass (rede interna
# 10.97.0.0/24), sem precisar de bridged networking nem de alterar o
# /etc/hosts de cada dispositivo manualmente.
#
# Contexto: as VMs do cluster (controlplane/node01) só têm uma interface na
# rede NAT interna do Multipass (mpqemubrzone1, 10.97.0.0/24). Essa rede não é
# roteada para a LAN física, então nenhum outro dispositivo alcança os
# serviços do cluster sem passar pelo host.
#
# Isso é a OPÇÃO 1 (gateway no host). Ver dia-04.md para o contexto completo
# e para a OPÇÃO 2 (bridged networking), que deve ser usada na próxima vez
# que o cluster for recriado — mas só funciona com uma interface cabeada
# conectada (o Multipass não oferece bridge para Wi-Fi).
#
# Por que proxy TCP (systemd-socket-proxyd) e não DNAT/iptables: o Multipass
# gerencia suas próprias regras nas chains PREROUTING/FORWARD (reconciliadas
# periodicamente) e qualquer regra de DNAT/ACCEPT adicionada por fora acaba
# sendo removida depois de um tempo, sem aviso. Um proxy de aplicação evita
# essa disputa por completo: o host apenas abre uma conexão NOVA e normal
# (via OUTPUT, não via FORWARD) para TARGET_IP:TARGET_PORT a cada conexão
# recebida — não depende de NAT no kernel nem de net.ipv4.ip_forward.
#
# TARGET_IP/TARGET_PORT por padrão apontam para o IP do MetalLB (Service
# LoadBalancer do Gateway, `kubectl get svc -n defectdojo
# cilium-gateway-platform-gateway`), não para o NodePort nem para o IP de
# uma VM específica — assim não depende de qual node está rodando o Gateway
# nem do NodePort alocado.
#
# Uso: sudo bash 05-lan-gateway.sh
# Variáveis opcionais (env): WAN_PORT, TARGET_IP, TARGET_PORT
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute como root: sudo bash $0" >&2
  exit 1
fi

if [ ! -x /usr/lib/systemd/systemd-socket-proxyd ]; then
  echo "systemd-socket-proxyd não encontrado em /usr/lib/systemd/. Esse script depende dele (parte do systemd)." >&2
  exit 1
fi

WAN_PORT="${WAN_PORT:-80}"
TARGET_IP="${TARGET_IP:-10.97.0.240}"
TARGET_PORT="${TARGET_PORT:-80}"

# Remove a versão antiga baseada em DNAT/iptables, se existir.
if [ -f /etc/systemd/system/k8s-lan-gateway.service ] && grep -q 'k8s-lan-gateway.sh' /etc/systemd/system/k8s-lan-gateway.service 2>/dev/null; then
  echo "==> Removendo instalação antiga (DNAT/iptables)"
  systemctl disable --now k8s-lan-gateway.service 2>/dev/null || true
  rm -f /etc/systemd/system/k8s-lan-gateway.service /usr/local/sbin/k8s-lan-gateway.sh
fi

echo "==> Instalando k8s-lan-gateway.socket (escuta 0.0.0.0:$WAN_PORT) e .service (proxy para $TARGET_IP:$TARGET_PORT)"
cat >/etc/systemd/system/k8s-lan-gateway.socket <<EOF
[Unit]
Description=Socket LAN -> cluster (k8s-lan-gateway)

[Socket]
ListenStream=0.0.0.0:$WAN_PORT

[Install]
WantedBy=sockets.target
EOF

cat >/etc/systemd/system/k8s-lan-gateway.service <<EOF
[Unit]
Description=Proxy TCP LAN -> cluster (k8s-lan-gateway)
Requires=k8s-lan-gateway.socket

[Service]
ExecStart=/usr/lib/systemd/systemd-socket-proxyd $TARGET_IP:$TARGET_PORT
EOF

systemctl daemon-reload
systemctl enable --now k8s-lan-gateway.socket

WAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
echo
echo "==> Pronto. Proxy ativo (sem depender de iptables/NAT) e persistido via systemd."
echo "    Outros dispositivos da LAN acessam via: http://${WAN_IP:-<IP do notebook na LAN>}:${WAN_PORT}/"
echo
echo "    Se o serviço de destino validar o cabeçalho Host (ex.: Django"
echo "    ALLOWED_HOSTS), acessar pelo IP acima pode ser rejeitado (400"
echo "    DisallowedHost) a menos que esse serviço aceite qualquer Host —"
echo "    já é o caso do defectdojo (ver apps/defectdojo/values.yaml e"
echo "    manifests/httproute.yaml no repo platform-tools). Ver dia-04.md."
echo
echo "    O IP do notebook na LAN é dinâmico (DHCP), mas isso não afeta esse"
echo "    proxy: ele escuta em todas as interfaces (0.0.0.0), então continua"
echo "    acessível em qualquer IP que o notebook receber."
