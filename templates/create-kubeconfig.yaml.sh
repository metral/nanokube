#!/bin/bash

cat > ${CERT_DIR}/kubeconfig << EOF
apiVersion: v1
kind: Config
clusters:
- name: nanokube-cluster
  cluster:
    certificate-authority: ${CERT_DIR}/ca.pem
    server: https://${PRIVATE_MASTER_LB_HOST}
contexts:
- context:
    cluster: nanokube-cluster
    user: nanokube-admin
    namespace: default
  name: nanokube-context
users:
- name: nanokube-admin
  user:
    client-certificate: ${CERT_DIR}/kubecfg.pem
    client-key: ${CERT_DIR}/kubecfg-key.pem
current-context: nanokube-context
EOF
