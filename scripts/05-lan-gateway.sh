#!/usr/bin/env bash
# Instala um gateway NAT no host (notebook) para que outros dispositivos da LAN
# consigam acessar serviços expostos no cluster Multipass (rede interna
# 10.97.0.0/24), sem precisar de bridged networking nem de alterar o
# /etc/hosts de cada dispositivo manualmente.
#
# Contexto: as VMs do cluster (controlplane/node01) só têm uma interface na
# rede NAT interna do Multipass (mpqemubrzone1, 10.97.0.0/24). Essa rede não é
# roteada para a LAN física, então nenhum outro dispositivo alcança os
# serviços do cluster sem passar pelo host. Este script usa DNAT/iptables no
# host para encaminhar uma porta da interface da LAN até o IP:porta do
# serviço no cluster (hoje, o NodePort do Gateway/Envoy no controlplane).
#
# Isso é a OPÇÃO 1 (gateway NAT). Ver dia-04.md para o contexto completo e
# para a OPÇÃO 2 (bridged networking), que deve ser usada na próxima vez que
# o cluster for recriado — mas só funciona com uma interface cabeada
# conectada (o Multipass não oferece bridge para Wi-Fi).
#
# Uso: sudo bash 05-lan-gateway.sh
# Variáveis opcionais (env): WAN_IF, WAN_PORT, TARGET_IP, TARGET_PORT
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute como root: sudo bash $0" >&2
  exit 1
fi

WAN_IF="${WAN_IF:-wlp3s0}"
WAN_PORT="${WAN_PORT:-80}"
TARGET_IP="${TARGET_IP:-10.97.0.17}"
TARGET_PORT="${TARGET_PORT:-30941}"

echo "==> Persistindo net.ipv4.ip_forward=1 (sobrevive a reboot)"
cat >/etc/sysctl.d/99-k8s-lan-gateway.conf <<EOF
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

echo "==> Gravando /usr/local/sbin/k8s-lan-gateway.sh (WAN_IF=$WAN_IF WAN_PORT=$WAN_PORT -> TARGET_IP=$TARGET_IP TARGET_PORT=$TARGET_PORT)"
install -m 755 /dev/stdin /usr/local/sbin/k8s-lan-gateway.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

WAN_IF="$WAN_IF"
WAN_PORT="$WAN_PORT"
TARGET_IP="$TARGET_IP"
TARGET_PORT="$TARGET_PORT"

# DNAT: tráfego chegando na interface da LAN para WAN_PORT vai para o
# IP:porta do serviço dentro da rede do Multipass.
iptables -t nat -C PREROUTING -i "\$WAN_IF" -p tcp --dport "\$WAN_PORT" \\
  -j DNAT --to-destination "\$TARGET_IP:\$TARGET_PORT" 2>/dev/null || \\
iptables -t nat -A PREROUTING -i "\$WAN_IF" -p tcp --dport "\$WAN_PORT" \\
  -j DNAT --to-destination "\$TARGET_IP:\$TARGET_PORT"

# FORWARD: permite a conexão nova até o serviço e o retorno de conexões já
# estabelecidas (a reversão do DNAT na volta é automática via conntrack).
iptables -C FORWARD -p tcp -d "\$TARGET_IP" --dport "\$TARGET_PORT" -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || \\
iptables -A FORWARD -p tcp -d "\$TARGET_IP" --dport "\$TARGET_PORT" -m conntrack --ctstate NEW -j ACCEPT

iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \\
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
EOF

echo "==> Instalando serviço systemd k8s-lan-gateway.service (aplica as regras no boot)"
cat >/etc/systemd/system/k8s-lan-gateway.service <<'EOF'
[Unit]
Description=Gateway NAT (DNAT) para expor servicos do cluster Multipass na LAN
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/k8s-lan-gateway.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now k8s-lan-gateway.service

WAN_IP="$(ip -4 -o addr show "$WAN_IF" | awk '{print $4}' | cut -d/ -f1)"
echo
echo "==> Pronto. Regras aplicadas e persistidas (sysctl + systemd)."
echo "    Outros dispositivos da LAN acessam via: http://${WAN_IP}:${WAN_PORT}/"
echo
echo "    ATENÇÃO: o app atrás do NodePort valida o cabeçalho Host (Django"
echo "    ALLOWED_HOSTS). Acessar pelo IP acima pode ser rejeitado (400"
echo "    DisallowedHost) se o serviço exigir um hostname específico — nesse"
echo "    caso, cada dispositivo ainda precisa de uma entrada em /etc/hosts"
echo "    apontando o hostname esperado para ${WAN_IP} (ou configurar esse IP"
echo "    como servidor DNS do dispositivo/roteador). Ver dia-04.md."
echo
echo "    IP ${WAN_IP} é dinâmico (DHCP) — considere reservar esse IP para o"
echo "    notebook no roteador para as regras não precisarem ser refeitas."
