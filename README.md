# doc-cka

Este repositório contém a documentação prática para a certificação CKA (Certified Kubernetes Administrator). O objetivo é fornecer um passo a passo reprodutível para a criação de um cluster Kubernetes resiliente e moderno.

[dia-01](https://github.com/kelton-lima-latest/doc-cka/blob/main/dia-01.md): Bootstrap do Cluster — Provisionamento de VMs, configuração de runtime, inicialização do Control-plane e instalação da camada de rede com Cilium.  

[dia-02](https://github.com/kelton-lima-latest/doc-cka/blob/main/dia-02.md): Upgrade de Versão — Ciclo de vida do cluster, migração da v1.34 para v1.35, atualização de binários (kubeadm, kubectl, kubelet) e processos de manutenção com drain e uncordon.  

[dia-03](https://github.com/kelton-lima-latest/doc-cka/blob/main/dia-03.md): Backup e Restore do etcd — Snapshot do cluster, instalação do etcdctl, geração de backup consistente e recuperação do datastore do Kubernetes após parada do kube-apiserver.

[dia-04](https://github.com/kelton-lima-latest/doc-cka/blob/main/dia-04.md): Acesso da LAN aos serviços do cluster — Gateway NAT no host via `iptables`/systemd para expor serviços NodePort a outros dispositivos da rede, limitação de bridged networking com Wi-Fi e plano para usar bridge na próxima recriação do cluster.

