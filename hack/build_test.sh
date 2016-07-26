#!/bin/bash

source lib/init.sh

# test self hosted install
self_hosted_install
#test dns working with kubectl
# cleanup
source vars/self-hosted
source lib/self-hosted.sh
cleanup_k8s
stop_addons
stop_master
stop_node
stop_sys_hosted_kubelet
stop_etcd
stop_flannel
cleanup_all_containers
reset_docker
rm -rf /etc/kubernetes

# test traditional/binary install
traditional_install
#test dns working with kubectl
# cleanup
source lib/traditional.sh
cleanup_k8s
stop_addons
stop_master
stop_node
stop_etcd
stop_flannel
cleanup_all_containers
reset_docker
rm -rf /etc/kubernetes
