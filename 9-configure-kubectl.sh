#!/bin/bash

# Generate a kubeconfig file for the kubectl command line utility based on the admin user credentials.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/10-configuring-kubectl.md

source ./k8s-cluster.config

main() {
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=${K8S_PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

  kubectl config set-credentials admin \
    --client-certificate=${K8S_PKI_DIR}/admin.pem \
    --client-key=${K8S_PKI_DIR}/admin-key.pem

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

  kubectl config use-context kubernetes-the-hard-way

  # Verifications
  kubectl get componentstatuses
  kubectl get nodes
}

main "$@"
