# Dia 04

Problema: as VMs do cluster (`controlplane`, `node01`) só têm interface na rede NAT interna do Multipass (`mpqemubrzone1`, `10.97.0.0/24`). Essa rede não é roteada para a LAN física do notebook, então nenhum outro dispositivo da rede consegue acessar os serviços do cluster — mesmo expondo como NodePort, é preciso estar no próprio notebook e editar `/etc/hosts` para resolver o hostname (ex.: `defectdojo.dev-k8s-note.local`) para o IP interno do node.

Duas opções foram avaliadas:

1. **Gateway NAT no host** (`scripts/05-lan-gateway.sh`) — DNAT via `iptables` no notebook, encaminhando uma porta da interface da LAN para o IP:porta do serviço dentro da rede do Multipass. Implementado hoje.
2. **Bridged networking** — as VMs recebem IP direto na LAN física (via `multipass set local.bridged-network=<interface>` + `multipass launch --network bridged`), sem precisar de gateway no host. **Não foi possível aplicar hoje**: o Multipass só lista interfaces cabeadas como elegíveis para bridge (`multipass networks`) e o notebook estava conectado só por Wi-Fi, com a porta Ethernet (`enp2s0f0`) sem cabo (`NO-CARRIER`). Bridging para Wi-Fi não é suportado pelo driver do Multipass no Linux (a maioria dos drivers/AP não suporta o modo de quadros 4-address necessário). **Decisão: usar a opção 2 na próxima vez que o cluster for recriado, desde que haja um cabo Ethernet conectado no host.** `scripts/01-provision-vms.sh` já aceita `VM_NETWORK=bridged` para isso.

## Opção 1 — Gateway NAT (implementado)

```bash
sudo bash scripts/05-lan-gateway.sh
```

O script (idempotente, pode rodar de novo com valores diferentes):
- Persiste `net.ipv4.ip_forward=1` (`/etc/sysctl.d/99-k8s-lan-gateway.conf`).
- Grava as regras de `iptables` (DNAT + FORWARD) em `/usr/local/sbin/k8s-lan-gateway.sh`.
- Instala e habilita `k8s-lan-gateway.service` (systemd), para as regras sobreviverem a reboot.

Variáveis (env, opcionais — padrão aponta para o NodePort atual do defectdojo no controlplane):

| Variável      | Padrão        | Descrição                                            |
|---------------|---------------|-------------------------------------------------------|
| `WAN_IF`      | `wlp3s0`      | Interface da LAN no notebook                          |
| `WAN_PORT`    | `80`          | Porta que os outros dispositivos usam                 |
| `TARGET_IP`   | `10.97.0.17`  | IP do node com o NodePort (controlplane)               |
| `TARGET_PORT` | `30941`       | NodePort do serviço (ex.: `defectdojo-django`)         |

### Limitação importante: ALLOWED_HOSTS

O gateway encaminha a porta, mas **não resolve nomes**. Serviços que validam o cabeçalho `Host` (ex.: Django `ALLOWED_HOSTS`, caso do DefectDojo — ver `apps/defectdojo/values.yaml` no repo `platform-tools`, `host: defectdojo.dev-k8s-note.local`) rejeitam acesso direto pelo IP do notebook com `400 DisallowedHost`.

Cada dispositivo da LAN ainda precisa resolver o hostname esperado para o IP do notebook na LAN, de uma destas formas:
- Uma entrada em `/etc/hosts` (ou equivalente) apontando `defectdojo.dev-k8s-note.local` para o IP do notebook — mesmo princípio de hoje, mas agora aponta para o notebook (acessível por todos na LAN) em vez do IP interno da VM (só acessível pelo próprio notebook).
- Ou configurar esse IP como servidor DNS do dispositivo/roteador (não implementado — exigiria dnsmasq no notebook + mudança no DHCP do roteador).

### Observação

O IP do notebook na LAN (`wlp3s0`) é dinâmico (DHCP). Se mudar, as regras de DNAT continuam válidas (estão amarradas à interface, não ao IP), mas qualquer `/etc/hosts` configurado nos outros dispositivos precisa ser atualizado. Vale considerar reservar esse IP para o notebook no roteador.

## Opção 2 — Bridged networking (próxima recriação do cluster)

Pré-requisito: notebook conectado por cabo Ethernet (verificar com `ip link show <interface>` — sem `NO-CARRIER`).

```bash
multipass networks                                  # lista interfaces elegíveis
multipass set local.bridged-network=<interface>      # ex.: enp2s0f0
VM_NETWORK=bridged ./scripts/setup-cluster.sh
```

Com isso as VMs recebem IP direto na faixa da LAN física, dispensando o gateway NAT da opção 1 — mas também passam a depender da rede cabeada estar sempre conectada.
