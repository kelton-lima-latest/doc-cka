# Dia 04

Problema: as VMs do cluster (`controlplane`, `node01`) só têm interface na rede NAT interna do Multipass (`mpqemubrzone1`, `10.97.0.0/24`). Essa rede não é roteada para a LAN física do notebook, então nenhum outro dispositivo da rede consegue acessar os serviços do cluster — mesmo expondo como NodePort, é preciso estar no próprio notebook e editar `/etc/hosts` para resolver o hostname (ex.: `defectdojo.dev-k8s-note.local`) para o IP interno do node.

Duas opções foram avaliadas:

1. **Gateway no host** (`scripts/05-lan-gateway.sh`) — encaminha uma porta da LAN do notebook para o IP:porta do serviço dentro da rede do Multipass. Implementado hoje (depois de duas tentativas — ver abaixo).
2. **Bridged networking** — as VMs recebem IP direto na LAN física (via `multipass set local.bridged-network=<interface>` + `multipass launch --network bridged`), sem precisar de gateway no host. **Não foi possível aplicar hoje**: o Multipass só lista interfaces cabeadas como elegíveis para bridge (`multipass networks`) e o notebook estava conectado só por Wi-Fi, com a porta Ethernet (`enp2s0f0`) sem cabo (`NO-CARRIER`). Bridging para Wi-Fi não é suportado pelo driver do Multipass no Linux (a maioria dos drivers/AP não suporta o modo de quadros 4-address necessário). **Decisão: usar a opção 2 na próxima vez que o cluster for recriado, desde que haja um cabo Ethernet conectado no host.** `scripts/01-provision-vms.sh` já aceita `VM_NETWORK=bridged` para isso.

## Opção 1 — Gateway no host (implementado)

```bash
sudo bash scripts/05-lan-gateway.sh
```

Solução final: um **proxy TCP** via `systemd-socket-proxyd` (binário do próprio systemd, nenhuma dependência extra). O script instala:
- `k8s-lan-gateway.socket` — escuta `0.0.0.0:80` (todas as interfaces, incluindo a Wi-Fi).
- `k8s-lan-gateway.service` (socket-activated) — `systemd-socket-proxyd TARGET_IP:TARGET_PORT`, relaying cada conexão recebida pra dentro do cluster.

Variáveis (env, opcionais):

| Variável      | Padrão         | Descrição                                                                 |
|---------------|----------------|-----------------------------------------------------------------------------|
| `WAN_PORT`    | `80`           | Porta que os outros dispositivos usam                                      |
| `TARGET_IP`   | `10.97.0.240`  | IP do `Service` LoadBalancer do Gateway (MetalLB), não do NodePort nem do node |
| `TARGET_PORT` | `80`           | Porta do Service (`kubectl get svc -n defectdojo cilium-gateway-platform-gateway`) |

Evitar NodePort/IP do node como alvo foi intencional: NodePort muda se o Service for recriado, e o IP do node amarra o gateway a uma VM específica. A VIP do MetalLB é estável independente de qual node está rodando o Envoy.

### Duas tentativas anteriores que não funcionaram (histórico)

**Tentativa 1 — DNAT via `iptables` (`-A`, append no final da chain).** O Multipass cria suas próprias regras na chain `FORWARD` pra cada rede NAT dele (`mpqemubrzone1/2/3` — aparecem como `/* generated for Multipass network ... */` em `iptables -L FORWARD`), incluindo um `REJECT` amplo pra qualquer tráfego de entrada nessas redes, **antes** de qualquer coisa que a gente adicione. Um `ACCEPT` anexado com `-A` no fim da chain nunca era avaliado — o `REJECT` do Multipass intercepta primeiro. Sintoma: DNAT aplicado corretamente (confirmado via contador de pacotes em `iptables -t nat -L PREROUTING -v`), mas `ERR_CONNECTION_REFUSED` do lado de fora mesmo assim.

**Tentativa 2 — DNAT via `iptables -I FORWARD 1` (insere no topo).** Corrigiu a ordem, funcionou na hora — mas as regras **desapareciam depois de um tempo** (confirmado: `iptables -t nat -L PREROUTING` voltava vazio, sem erro, sem reboot no meio). O Multipass reconcilia periodicamente as chains que gerencia e não tem como saber que nossas regras devem ficar; difícil competir com isso de forma confiável via `iptables` puro.

**Solução final — proxy TCP, sem tocar em `iptables`.** `systemd-socket-proxyd` não depende de NAT/`FORWARD` nem de `net.ipv4.ip_forward`: o host apenas abre uma conexão nova e normal (via `OUTPUT`, não via `FORWARD`) para `TARGET_IP:TARGET_PORT` a cada conexão recebida — o mesmo caminho que já funcionava direto (`curl http://10.97.0.240/` do próprio host sempre deu 200). Não compete com nada que o Multipass gerencie, então não há reconciliação pra atropelar.

### ALLOWED_HOSTS — resolvido no lado do app, não aqui

O gateway encaminha a porta e não resolve nomes — serviços que validam o cabeçalho `Host` (Django `ALLOWED_HOSTS`) rejeitariam acesso pelo IP com `400 DisallowedHost`. Em vez de exigir `/etc/hosts` por dispositivo (o que o objetivo original era evitar), a correção foi no app: `apps/defectdojo/values.yaml` (`alternativeHosts: ["*"]`) e `apps/defectdojo/manifests/httproute.yaml` (sem `hostnames`) no repo `platform-tools`, fazendo o DefectDojo aceitar qualquer `Host`. Outros serviços expostos por esse gateway que não tiverem esse ajuste ainda vão precisar de hostname resolvido por dispositivo.

### Observação

O proxy escuta em `0.0.0.0`, então não depende do IP da Wi-Fi do notebook (dinâmico via DHCP) — continua acessível em qualquer IP que o notebook receber. Se algum dispositivo da LAN precisar de um `/etc/hosts` apontando pra esse IP (ver seção ALLOWED_HOSTS acima), vale considerar reservar o IP do notebook no roteador pra essa entrada não precisar ser atualizada.

## Opção 2 — Bridged networking (próxima recriação do cluster)

Pré-requisito: notebook conectado por cabo Ethernet (verificar com `ip link show <interface>` — sem `NO-CARRIER`).

```bash
multipass networks                                  # lista interfaces elegíveis
multipass set local.bridged-network=<interface>      # ex.: enp2s0f0
VM_NETWORK=bridged ./scripts/setup-cluster.sh
```

Com isso as VMs recebem IP direto na faixa da LAN física, dispensando o gateway NAT da opção 1 — mas também passam a depender da rede cabeada estar sempre conectada.
