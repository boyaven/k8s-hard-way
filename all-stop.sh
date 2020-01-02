#!/bin/bash

#
# stop servers on all nodes
#

source ./k8s-cluster.config

main() {
  stop_worker_services
  stop_controller_services
  stop_etcd_service
  sleep 3
}

stop_etcd_service() {
  echo "Stopping etcd services..."
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$instance "sudo systemctl disable etcd; sudo systemctl stop etcd" &

  done
}

stop_controller_services() {
  echo "Stopping controller services..."
  for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
    instance=${K8S_CONTROLLER[$i]}

    cat <<EOF1 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
        sudo systemctl disable kube-apiserver kube-controller-manager kube-scheduler
        sudo systemctl stop kube-apiserver kube-controller-manager kube-scheduler
EOF1
  done
}

stop_worker_services() {
  echo "Stopping worker services..."
  for ((i=0;i<K8S_WORKER_COUNT;i++)) do
    instance=${K8S_WORKER[$i]}

    cat <<EOF2 | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@${instance}
	sudo systemctl disable containerd kubelet kube-proxy
	sudo systemctl stop containerd kubelet kube-proxy
EOF2
  done
}

main "$@"
