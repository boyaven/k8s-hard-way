#!/bin/bash

# generate an encryption key and an encryption config suitable for encrypting Kubernetes Secrets.
#
# from: https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/06-data-encryption-keys.md

source ./k8s-cluster.config

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

echo "Generating encryption key & provisioning to controller nodes..."
cat > $K8S_PKI_DIR/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

for ((i=0;i<K8S_CONTROLLER_COUNT;i++)) do
  instance=${K8S_CONTROLLER[$i]}
  scp -i $K8S_ADMIN_SSH_KEY $K8S_PKI_DIR/encryption-config.yaml $K8S_ADMIN_NAME@${instance}:/var/lib/kubernetes
done
