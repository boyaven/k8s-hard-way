#!/bin/bash

# install the command line utilities required to complete this tutorial: 
#   cfssl, cfssljson, and kubectl.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-client-tools.md

echo "Installing cfssl..."
wget -q \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/linux/cfssl \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/linux/cfssljson
chmod +x cfssl cfssljson
sudo mv cfssl cfssljson /usr/local/bin/
cfssljson --version
echo

echo "Installing kubectl..."
sudo rm -f /usr/local/bin/kubectl
wget -q https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
