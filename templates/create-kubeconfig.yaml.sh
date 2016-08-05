#!/bin/bash

k8s_user=$1

cat > ${CERT_DIR}/$k8s_user-kubeconfig << EOF
apiVersion: v1
kind: Config
clusters:
- name: nanokube-cluster
  cluster:
    certificate-authority: ${CERT_DIR}/ca.pem
    server: ${MASTER_HOST}
contexts:
- context:
    cluster: nanokube-cluster
    user: $k8s_user
    namespace: default
  name: nanokube-context
users:
- name: $k8s_user
  user:
    client-certificate: ${CERT_DIR}/${k8s_user}.pem
    client-key: ${CERT_DIR}/${k8s_user}-key.pem
current-context: nanokube-context
EOF
