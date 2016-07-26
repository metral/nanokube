#!/bin/bash

cat > ${LOCAL_MANIFESTS_DIR}/kube-controller-manager.yaml << EOF
 apiVersion: v1
 kind: Pod
 metadata:
   name: $CTRLR_MGR_POD_NAME
   namespace: kube-system
 spec:
   hostNetwork: true
   containers:
     - name: $CTRLR_MGR_POD_NAME
       image: ${HYPERKUBE_IMAGE_REPO}:${HYPERKUBE_VERSION}
       command:
         - /hyperkube
         - controller-manager
         - --cluster-cidr=${PODS_CIDR}
         - --master=http://127.0.0.1:8080
         - --root-ca-file=${CERT_DIR}/ca.pem
         - --service-account-private-key-file=${CERT_DIR}/apiserver-key.pem
         - --service-cluster-ip-range=${SERVICE_CIDR}
       livenessProbe:
         httpGet:
           host: 127.0.0.1
           path: /healthz
           port: 10252
         initialDelaySeconds: 15
         timeoutSeconds: 1
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
