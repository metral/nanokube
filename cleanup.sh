#!/bin/bash

# cleanup k8s resources
kubectl delete --namespace=default deployments,rc,rs,pods,svc,ing,secrets,configmaps --all --grace-period=0

# reset Docker
cp /tmp/docker.bak /etc/default/docker
service docker restart
docker ps -a | awk '{print $1}' | grep -v CONTAINER | xargs docker rm -f
