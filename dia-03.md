# Dia 03 - Backup e Restore etcd

## Creating snapshot vms with multipass
Stop VMs:  
```bash
multipass stop control-plane node-01
```

Create Snapshot:
```bash
multipass snapshot control-plane --name 'pre-backup-restore-etcd'
```

## Install GO

Access root user
```bash
sudo su
```

Download binary
```bash
wget https://go.dev/dl/go1.26.0.linux-amd64.tar.gz
```

Remove any previous Go installation by deleting the /usr/local/go folder (if it exists), then extract the archive you just downloaded into /usr/local, creating a fresh Go tree in /usr/local/go:
```bash
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz
```

Add /usr/local/go/bin to the PATH environment variable.
You can do this by adding the following line to your $HOME/.profile or /etc/profile (for a system-wide installation):
```bash
export PATH=$PATH:/usr/local/go/bin
```

Verify that you've installed Go by opening a command prompt and typing the following command:
```bash
go version
```

## Install etcdcli

Clone the repo using the following command.
```bash
git clone -b v3.5.27 https://github.com/etcd-io/etcd.git
```

Change directory:
```bash
cd etcd
```

Run the build script:
```bash
./build
```

Add the full path to the bin directory to your path, for example:
```bash
export PATH="$PATH:`pwd`/bin"
```

Test that etcd is in your path:
```bash
etcd --version
```

## Backup etcd
You can create a snapshot by specifying the endpoint, certificates and key as shown below:
```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=<trusted-ca-file> --cert=<cert-file> --key=<key-file> \
  snapshot save <backup-file-location>
```

Where trusted-ca-file, cert-file and key-file can be obtained from the description of the etcd Pod.
```bash
sudo nano /etc/kubernetes/manifests/etcd.yaml
```

```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
--key=/etc/kubernetes/pki/etcd/server.key   snapshot save /var/lib/snapshot-etcd.db
```
## Restore etcd
Stop kube-apiserver.  
```bash
mkdir -p /home/ubuntu/kube-manifests-backup
```

```bash
mv /etc/kubernetes/manifests/kube-apiserver.yaml /home/ubuntu/kube-manifests-backup/
```

```bash
mv /etc/kubernetes/manifests/etcd.yaml /home/ubuntu/kube-manifests-backup/
```

```bash
mv /var/lib/etcd/ /var/lib/etcd-2
```

```bash
mv /home/ubuntu/kube-manifests-backup/*.yaml /etc/kubernetes/manifests/
```



## Links de referência
[Download GO](https://go.dev/dl/)  
[Install GO](https://go.dev/doc/install)  
[Download and install etcdcli](https://etcd.io/docs/v3.4/install/)  
[Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)  
[Multipass snapshot](https://documentation.ubuntu.com/multipass/latest/reference/command-line-interface/snapshot/)  
