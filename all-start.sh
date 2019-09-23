#!/bin/bash

#
# stop and start etcd servers on all controller nodes
#

source ./k8s-cluster.config

main() {
  start_etcd_service
  start_controller_services
}

start_etcd_service() {
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$instance "sudo systemctl enable etcd; sudo systemctl start etcd" &

  done

  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    cat <<EOF3 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$instance
      sudo ETCDCTL_API=3 etcdctl member list \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem
EOF3
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
