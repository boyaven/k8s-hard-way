#!/bin/bash

# Provision an external load balancer to front the Kubernetes API Servers.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/08-bootstrapping-kubernetes-controllers.md#the-kubernetes-frontend-load-balancer

source ./k8s-cluster.config

# Since this cluster is not running in the cloud, we need to install haproxy
# on a node and configure it with SSL Pass-Through to the controller nodes.

# install haproxy, which starts automagically, so stop it
ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$K8S_MASTER_HOSTNAME "sudo apt-get install -y haproxy; sudo systemctl stop haproxy"

# kill any running instance
haproxy_pid=$(ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$K8S_MASTER_HOSTNAME "ps -aux | grep haproxy | grep -v grep | awk '{print \$2}'")
if [[ "$haproxy_pid" != "" ]]; then
  ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$K8S_MASTER_HOSTNAME "sudo kill -9 $haproxy_pid"
fi

# create haproxy.cfg file
cat <<EOF | ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$K8S_MASTER_HOSTNAME "sudo cat >haproxy.cfg"
global
	maxconn 256
	external-check

defaults
	timeout connect 5s
	timeout client 50s
	timeout server 50s

frontend f_kubernetes_api_server
	bind *:6443
	mode tcp
	default_backend b_kubernetes_api_server

# HTTP backend info - don't verify w/ cert
backend b_kubernetes_api_server
	mode tcp
	balance static-rr
	default-server inter 5s fall 3 rise 2
        option ssl-hello-chk
	 server ${K8S_CONTROLLER[0]} ${K8S_CONTROLLER[0]}:6443 check
	 server ${K8S_CONTROLLER[1]} ${K8S_CONTROLLER[1]}:6443 check
	 server ${K8S_CONTROLLER[2]} ${K8S_CONTROLLER[2]}:6443 check
EOF

# start load balancer and verify all ok
ssh -i $K8S_ADMIN_SSH_KEY $K8S_ADMIN_USER@$K8S_MASTER_HOSTNAME "sudo haproxy -D -f haproxy.cfg"
if [[ "$(curl -ks https://$K8S_MASTER_HOSTNAME:6443/healthz)" != "ok" ]]; then
  echo "Load balancer not functioning correctly"
  exit -1
fi
echo
curl --cacert $K8S_PKI_DIR/ca.pem https://$KUBERNETES_PUBLIC_ADDRESS:6443/version
echo
echo "Load balancer functioning correctly"
