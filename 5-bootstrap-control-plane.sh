#!/bin/bash

# Bootstrap the Kubernetes control plane across three compute instances and configure it for high availability.
# Also creates an external load balancer that exposes the Kubernetes API Servers to remote clients. 
# Installs the following components on each node: Kubernetes API Server, Scheduler, and Controller Manager.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/08-bootstrapping-kubernetes-controllers.md
#
# NOTE: deleted NodeRestriction admission controller plugin to work around RBAC issue w/ API server's ability to register nodes. See: https://github.com/kubernetes/kubernetes/issues/47695#issuecomment-342279247

source ./k8s-cluster.config

PKI_LIST="ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
		service-account-key.pem service-account.pem encryption-config.yaml"

main() {
#  download_and_install_controller_binaries
  configure_api_servers
  configure_controller_manager
  configure_scheduler
  start_controller_services
}

download_and_install_controller_binaries() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    cat <<EOF1 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	wget -q --show-progress --https-only --timestamping \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-apiserver" \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-controller-manager" \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-scheduler" \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kubectl"
	chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
	sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
EOF1
   done

} # download_and_install_controller_binaries() 

configure_api_servers() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}
    ip_addr=${K8S_CONTROLLER_IP_ADDR[$i]}

    cat <<EOF2 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	sudo mkdir -p /var/lib/kubernetes/
	sudo chown $K8S_ADMIN_USER /var/lib/kubernetes
EOF2

    pushd $K8S_PKI_DIR
    scp -i $K8S_ADMIN_SSH_KEY $PKI_LIST ${instance}:/var/lib/kubernetes/
    popd

    cat <<EOF3 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "cat >/etc/systemd/system/kube-apiserver.service"
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${ip_addr} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://${K8S_CONTROLLER_IP_ADDR[0]}:2379,https://${K8S_CONTROLLER_IP_ADDR[1]}:2379,https://${K8S_CONTROLLER_IP_ADDR[2]}:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=${K8S_SERVICE_CLUSTER_IP_RANGE} \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF3

  done
} # configure_api_servers()

configure_controller_manager() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    pushd $K8S_PKI_DIR
    scp -i $K8S_ADMIN_SSH_KEY kube-controller-manager.kubeconfig $K8S_ADMIN_USER@${instance}:/var/lib/kubernetes/
    popd

    cat <<EOF4 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "cat >/etc/systemd/system/kube-controller-manager.service"
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=${K8S_SERVICE_CLUSTER_IP_RANGE} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF4

  done
} # configure_controller_manager()


configure_scheduler() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    cat <<EOF5 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	sudo mkdir -p /etc/kubernetes/config
	sudo chown $K8S_ADMIN_USER /etc/kubernetes/config
EOF5

    pushd $K8S_PKI_DIR
    scp -i $K8S_ADMIN_SSH_KEY kube-scheduler.kubeconfig $K8S_ADMIN_USER@${instance}:/var/lib/kubernetes/
    popd

    cat <<EOF6 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "cat >/etc/kubernetes/config/kube-scheduler.yaml"
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF6

    cat <<EOF7 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance} "cat >/etc/systemd/system/kube-scheduler.service"
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF7

  done
}

start_controller_services() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    cat <<EOF8 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	sudo systemctl daemon-reload
	sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
	sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
EOF8
  done
}

main "$@"
