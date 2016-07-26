#!/bin/bash

# backup Docker defaults
cp /etc/default/docker /tmp/docker.bak

# remount /var/lib/kubelet as shared to be able to access from within other # Pods
umount -l $(mount | grep /var/lib/kubelet | awk '{print $3}') > /dev/null 2>&1
sleep 2;
rm -rf /var/lib/kubelet/
mkdir -p /var/lib/kubelet;
mount --bind /var/lib/kubelet /var/lib/kubelet
mount --make-shared /var/lib/kubelet
