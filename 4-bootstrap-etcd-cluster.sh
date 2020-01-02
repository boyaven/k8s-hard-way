#!/bin/bash

#
# bootstrap a three node etcd cluster and configure it for high availability and secure remote access.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/07-bootstrapping-etcd.md

source ./k8s-cluster.config

main() {
#  download_and_install_etcd
  install_etcd_service_def
  start_etcd_service
}

download_and_install_etcd() {

  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    echo "Downloading etcd tarfile & installing..."
    cat <<EOF1 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$instance
      wget -q https://github.com/etcd-io/etcd/releases/download/v3.4.0/etcd-v3.4.0-linux-amd64.tar.gz
      tar -xvzf etcd-v3.4.0-linux-amd64.tar.gz >& /dev/null
      sudo mv etcd-v3.4.0-linux-amd64/etcd* /usr/local/bin/
      sudo mkdir -p /etc/etcd /var/lib/etcd
      sudo chown $K8S_ADMIN_USER /etc/etcd /var/lib/etcd /etc/systemd/system/
EOF1

  done
}

install_etcd_service_def() {
  echo "Copying over service description..."
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}
    ip_addr=${K8S_CONTROLLER_IP_ADDR[$i]}

    echo "Copying over service description..."
    cat <<EOF2 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$instance "sudo cat >/etc/systemd/system/etcd.service"
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${instance} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${ip_addr}:2380 \\
  --listen-peer-urls https://${ip_addr}:2380 \\
  --listen-client-urls https://${ip_addr}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${ip_addr}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${K8S_CONTROLLER[0]}=https://${K8S_CONTROLLER_IP_ADDR[0]}:2380,${K8S_CONTROLLER[1]}=https://${K8S_CONTROLLER_IP_ADDR[1]}:2380,${K8S_CONTROLLER[2]}=https://${K8S_CONTROLLER_IP_ADDR[2]}:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2

    echo "Copying over certs..."
    pushd $K8S_PKI_DIR
      sudo scp -i $K8S_ADMIN_SSH_KEY ca.pem kubernetes-key.pem kubernetes.pem $K8S_ADMIN_USER@$instance:/etc/etcd/
    popd

  done

}

start_etcd_service() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    echo
    echo "Starting etcd service on $instance..."
    cat <<EOF3 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$instance &
      sudo systemctl stop etcd
      sudo systemctl daemon-reload
      sudo systemctl enable etcd
      sudo systemctl start etcd

      sudo ETCDCTL_API=3 etcdctl member list \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem
EOF3

  done
}

main "$@"
