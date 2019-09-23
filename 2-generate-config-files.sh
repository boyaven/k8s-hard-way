#!/bin/bash

# generate Kubernetes configuration files, also known as kubeconfigs, which enable Kubernetes clients 
# to locate and authenticate to the Kubernetes API Servers
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/05-kubernetes-configuration-files.md

source ./k8s-cluster.config

main() {
    pushd $K8S_PKI_DIR
    generate_worker_config_files
    generate_kube_proxy_config_file
    generate_kube_controller_config_file
    generate_kube_scheduler_config_file
    generate_kube_admin_config_file
    provision_worker_config_files
}

generate_worker_config_files() {
    echo "Generating worker config files..."
    for ((i=0;i<K8S_WORKER_COUNT;i++)) do
      instance=${K8S_WORKER[$i]}

      kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=ca.pem \
        --embed-certs=true \
        --server=https://${KUBERNETES_MASTER_IP_ADDRESS}:6443 \
        --kubeconfig=${instance}.kubeconfig

      kubectl config set-credentials system:node:${instance} \
        --client-certificate=${instance}.pem \
        --client-key=${instance}-key.pem \
        --embed-certs=true \
        --kubeconfig=${instance}.kubeconfig

      kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:node:${instance} \
        --kubeconfig=${instance}.kubeconfig

      kubectl config use-context default --kubeconfig=${instance}.kubeconfig
    done
}

generate_kube_proxy_config_file() {
  echo "Generating kube proxy config file..."
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}

generate_kube_controller_config_file() {
  echo "Generating kube controller config file..."
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem \
    --client-key=kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}

generate_kube_scheduler_config_file() {
  echo "Generating kube scheduler config file..."
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem \
    --client-key=kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}

generate_kube_admin_config_file() {
  echo "Generating kube admin config file..."
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

provision_worker_config_files() {
    echo "Provisioning worker config files..."
    for ((i=0;i<K8S_WORKER_COUNT;i++)) do
      instance=${K8S_WORKER[$i]}
      scp -i $K8S_ADMIN_SSH_KEY ${instance}.kubeconfig kube-proxy.kubeconfig $K8S_ADMIN_USER@${instance}:~/
    done
}
main "$@"
