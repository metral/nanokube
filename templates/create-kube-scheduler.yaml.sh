#!/bin/bash

cat > ${LOCAL_MANIFESTS_DIR}/kube-scheduler.yaml << EOF
 apiVersion: v1
 kind: Pod
 metadata:
   name: ${SCHEDULER_POD_NAME}
   namespace: kube-system
 spec:
   hostNetwork: true
   containers:
     - name: ${SCHEDULER_POD_NAME}
       image: ${HYPERKUBE_IMAGE_REPO}:${KUBERNETES_VERSION}
       command:
         - /hyperkube
         - scheduler
         - --master=http://127.0.0.1:8080
       livenessProbe:
         httpGet:
           host: 127.0.0.1
           path: /healthz
           port: 10251
         initialDelaySeconds: 15
         timeoutSeconds: 1
EOF
