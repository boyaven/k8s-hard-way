#!/bin/bash

# Provision PKI Infrastructure using CloudFlare's PKI toolkit, cfssl, then use it to bootstrap 
# a Certificate Authority, and generate TLS certificates for the following components: 
#   etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, and kube-proxy.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md

source ./k8s-cluster.config

main() {
    rm -rf $K8S_PKI_DIR
    mkdir -p $K8S_PKI_DIR
    pushd $K8S_PKI_DIR
    generate_ca
    generate_admin_cert
    generate_worker_certs
    generate_controller_manager_cert
    generate_kube_proxy_client_cert
    generate_scheduler_client_cert
    generate_api_server_cert
    generate_service_account_key_pair
}

generate_ca() {
    echo "Generating root cert..."
    cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

    cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF

    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

generate_admin_cert() {

    echo "Generating admin cert..."
    cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      admin-csr.json | cfssljson -bare admin
}

generate_worker_certs() {
    echo "Generating worker node certs..."
    for ((i=0;i<K8S_WORKER_COUNT;i++)) do
      instance=${K8S_WORKER[$i]}
      ip_addr=${K8S_WORKER_IP_ADDR[$i]}

        cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Austin",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Texas"
    }
  ]
}
EOF

        cfssl gencert \
          -ca=ca.pem \
          -ca-key=ca-key.pem \
          -config=ca-config.json \
          -hostname=${instance},${ip_addr} \
          -profile=kubernetes \
          ${instance}-csr.json | cfssljson -bare ${instance}

    done
}

generate_controller_manager_cert() {
    echo "Generating controller manager cert..."
    cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Austin",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes The Hard Way",
      "ST": "Texas"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
}

generate_kube_proxy_client_cert() {
    echo "Generating kube proxy client cert..."
    cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      kube-proxy-csr.json | cfssljson -bare kube-proxy
}

generate_scheduler_client_cert() {
    echo "Generating scheduler client cert..."
    cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Austin",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way",
      "ST": "Texas"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      kube-scheduler-csr.json | cfssljson -bare kube-scheduler
}

generate_api_server_cert() {
    echo "Generating API server cert..."
    KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local

    cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Austin",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Texas"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=${KUBERNETES_MASTER_IP_ADDRESS},${K8S_CONTROLLER_IP_ADDR[0]},${K8S_CONTROLLER_IP_ADDR[1]},${K8S_CONTROLLER_IP_ADDR[2]},127.0.0.1,${KUBERNETES_HOSTNAMES} \
      -profile=kubernetes \
      kubernetes-csr.json | cfssljson -bare kubernetes
  --initial-cluster ${K8S_CONTROLLER[0]}=https://
}

generate_service_account_key_pair() {
    echo "Generating service account key pair..."
    cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Austin",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Texas"
    }
  ]
}
EOF

    cfssl gencert \
     -ca=ca.pem \
     -ca-key=ca-key.pem \
     -config=ca-config.json \
     -profile=kubernetes \
     service-account-csr.json | cfssljson -bare service-account
}

main "$@"
