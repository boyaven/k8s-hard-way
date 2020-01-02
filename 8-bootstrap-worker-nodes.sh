#!/bin/bash

# Bootstrap three Kubernetes worker nodes. The following components will be installed on each node: 
#   runc, container networking plugins, containerd, kubelet, and kube-proxy.
#
# from: //github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/09-bootstrapping-kubernetes-workers.md

source ./k8s-cluster.config

main() {
#  download_and_install_worker_binaries
  disable_swap
  configure_cni_networking
  configure_containerd
  configure_kubelet
  configure_kube_proxy
  start_worker_services
}

download_and_install_worker_binaries() {
  echo "Dowloading & installing binaries..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}

    cat <<EOF1 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	sudo apt-get update
	sudo apt-get -y install socat conntrack ipset
	wget -q --https-only --timestamping \
	  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.15.0/crictl-v1.15.0-linux-amd64.tar.gz \
	  https://github.com/opencontainers/runc/releases/download/v1.0.0-rc8/runc.amd64 \
	  https://github.com/containernetworking/plugins/releases/download/v0.8.2/cni-plugins-linux-amd64-v0.8.2.tgz \
	  https://github.com/containerd/containerd/releases/download/v1.2.9/containerd-1.2.9.linux-amd64.tar.gz \
	  https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kubectl \
	  https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-proxy \
	  https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kubelet
	sudo mkdir -p \
	  /etc/cni/net.d \
	  /opt/cni/bin \
	  /var/lib/kubelet \
	  /var/lib/kube-proxy \
	  /var/lib/kubernetes \
	  /var/run/kubernetes
	sudo chown $K8S_ADMIN_USER \
	  /etc/cni/net.d \
	  /opt/cni/bin \
	  /var/lib/kubelet \
	  /var/lib/kube-proxy \
	  /var/lib/kubernetes \
	  /var/run/kubernetes
	mkdir containerd
	tar -xvf crictl-v1.15.0-linux-amd64.tar.gz
	tar -xvf containerd-1.2.9.linux-amd64.tar.gz -C containerd
	sudo tar -xvf cni-plugins-linux-amd64-v0.8.2.tgz -C /opt/cni/bin/
	sudo mv runc.amd64 runc
	chmod +x crictl kubectl kube-proxy kubelet runc 
	sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
	sudo mv containerd/bin/* /bin/
EOF1
   done

} # download_and_install_worker_binaries() 

disable_swap() {
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}
    ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo swapoff -a"
  done 
} # disable_swap

configure_cni_networking() {
  echo "Configuring CNI networking..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}
    pod_cidr=${K8S_WORKER_POD_CIDR[$i]}

cat <<EOF2 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/etc/cni/net.d/10-bridge.conf"
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${pod_cidr}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF2

cat <<EOF3 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/etc/cni/net.d/99-loopback.conf"
{
    "cniVersion": "0.3.1",
    "name": "lo",
    "type": "loopback"
}
EOF3

  done
} # configure_cni_networking()

configure_containerd() {
  echo "Configuring containerd..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}

    # Create the containerd configuration file:
    ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo mkdir -p /etc/containerd/; sudo chown $K8S_ADMIN_USER /etc/containerd"

    cat << EOF4 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/etc/containerd/config.toml"
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
EOF4

    # Create the containerd.service systemd unit file:
    ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo chown $K8S_ADMIN_USER /etc/systemd/system"
    cat <<EOF5 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/etc/systemd/system/containerd.service"
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF5

  done
} # configure_containerd()


configure_kubelet() {
  echo "Configuring kubelet..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}
    pod_cidr=${K8S_WORKER_POD_CIDR[$i]}

    echo "Copying over certs..."
    pushd $K8S_PKI_DIR
      sudo scp -i $K8S_ADMIN_SSH_KEY ${instance}-key.pem ${instance}.pem $K8S_ADMIN_USER@$instance:/var/lib/kubelet/
      sudo scp -i $K8S_ADMIN_SSH_KEY ${instance}.kubeconfig $K8S_ADMIN_USER@$instance:/var/lib/kubelet/kubeconfig
      sudo scp -i $K8S_ADMIN_SSH_KEY ca.pem $K8S_ADMIN_USER@$instance:/var/lib/kubernetes/
    popd

    # Create the kubelet-config.yaml configuration file:
    cat <<EOF7 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/var/lib/kubelet/kubelet-config.yaml"
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "${K8S_CLUSTER_DNS_IP}"
podCIDR: "${pod_cidr}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${instance}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${instance}-key.pem"
EOF7

    # The resolvConf configuration is used to avoid loops 
    # when using CoreDNS for service discovery on systems running systemd-resolved.

    #Create the kubelet.service systemd unit file:
cat <<EOF8 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/etc/systemd/system/kubelet.service"
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF8

  done
} # configure_kubelet()

configure_kube_proxy() {
  echo "Configuring kube proxy..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}

    scp -i $K8S_ADMIN_SSH_KEY $K8S_PKI_DIR/kube-proxy.kubeconfig  $K8S_ADMIN_USER@${instance}:/var/lib/kube-proxy/kubeconfig

    # Create the kube-proxy-config.yaml configuration file:
    cat <<EOF9 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/var/lib/kube-proxy/kube-proxy-config.yaml"
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "${K8S_CLUSTER_CIDR}"
EOF9

    # Create the kube-proxy.service systemd unit file:
    cat <<EOF10 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "sudo cat >/etc/systemd/system/kube-proxy.service"
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF10

  done
} # configure_kube_proxy() {

start_worker_services() {
  echo "Starting worker services..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}

    cat <<EOF8 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	sudo systemctl daemon-reload
	sudo systemctl enable containerd kubelet kube-proxy
	sudo systemctl start containerd kubelet kube-proxy
EOF8
  done
}

main "$@"
