#!/bin/bash

cat > ${LOCAL_MANIFESTS_DIR}/kube-proxy.yaml << EOF
 apiVersion: v1
 kind: Pod
 metadata:
   name: ${PROXY_POD_NAME}
   namespace: kube-system
 spec:
   hostNetwork: true
   containers:
     - name: ${PROXY_POD_NAME}
       image: ${HYPERKUBE_IMAGE_REPO}:${HYPERKUBE_VERSION}
       command:
         - /hyperkube
         - proxy
         - --conntrack-max=0
         - --kubeconfig=${CERT_DIR}/kubeconfig
         - --master=https://${PRIVATE_MASTER_HOST}
       securityContext:
         privileged: true
       volumeMounts:
         - name: ssl-certs-kubernetes
           mountPath: ${CERT_DIR}
           readOnly: true
         - name: ssl-certs-host
           mountPath: /etc/ssl/certs
           readOnly: true
   volumes:
   - name: ssl-certs-kubernetes
     hostPath:
       path: ${CERT_DIR}
   - name: ssl-certs-host
     hostPath:
       path: /usr/share/ca-certificates
EOF
