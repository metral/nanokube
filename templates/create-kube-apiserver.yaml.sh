#!/bin/bash

cat > ${LOCAL_MANIFESTS_DIR}/kube-apiserver.yaml << EOF
 apiVersion: v1
 kind: Pod
 metadata:
   name: $APISERVER_POD_NAME
   namespace: kube-system
 spec:
   hostNetwork: true
   containers:
     - name: $APISERVER_POD_NAME
       image: ${HYPERKUBE_IMAGE_REPO}:${KUBERNETES_VERSION}
       command:
         - /hyperkube
         - apiserver
         - --advertise-address=${PRIVATE_MASTER_HOST}
         - --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota
         - --client-ca-file=${CERT_DIR}/ca.pem
         - --etcd-servers=$ETCD_SERVERS
         - --bind-address=${PRIVATE_MASTER_HOST}
         - --runtime-config=extensions/v1beta1/thirdpartyresources=true
         - --service-cluster-ip-range=${SERVICE_CIDR}
         - --secure-port=443
         - --tls-cert-file=${CERT_DIR}/apiserver.pem
         - --tls-private-key-file=${CERT_DIR}/apiserver-key.pem
       ports:
         - containerPort: 443
           hostPort: 443
           name: https
         - containerPort: 8080
           hostPort: 8080
           name: local
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
