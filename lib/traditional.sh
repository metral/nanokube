#!/bin/bash
#-------------------------------------------------------------------------------
set -o allexport
source vars/default
set +o allexport
#-------------------------------------------------------------------------------
# Pre-Setup
pre_setup() {
    echo "=> Running pre-setup..."

    # install deps
    ./install_deps.sh

    # setup filesystem requirements
    mkdir -p ${CERT_DIR}

    # Pull down hyperkube binary
    curl -s -o ${HYPERKUBE} ${HYPERKUBE_BIN_SOURCE}
    chmod +x ${HYPERKUBE}

    # Pull down kubectl binary
    curl -s -o ${KUBECTL} ${KUBECTL_BIN_SOURCE}
    chmod +x ${KUBECTL}

    get_flannel
}
#-------------------------------------------------------------------------------
# Launch kube-apiserver

start_apiserver() {
    echo "=> Starting - Master - kube-apiserver..."

    # run kube-apiserver as binary
    MASTER_APISERVER_LOG="/tmp/master-apiserver.log"
    ${HYPERKUBE} apiserver \
        --advertise-address=${PRIVATE_MASTER_HOST} \
        --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota \
        --client-ca-file=${CERT_DIR}/ca.pem \
        --etcd-servers=$ETCD_SERVERS \
        --bind-address=${PRIVATE_MASTER_HOST} \
        --runtime-config=extensions/v1beta1/thirdpartyresources=true \
        --service-cluster-ip-range=${SERVICE_CIDR} \
        --secure-port=443 \
        --tls-cert-file=${CERT_DIR}/apiserver.pem \
        --tls-private-key-file=${CERT_DIR}/apiserver-key.pem > ${MASTER_APISERVER_LOG} 2>&1 &
    MASTER_APISERVER_PID=$!

    # Wait for kube-apiserver to come up before launching the rest of the
    # components.
    echo "=> Waiting for apiserver to come up..."
    wait_for_apiserver "${MASTER_HOST}" "${CERT_DIR}/admin-kubeconfig" "apiserver: " 1 20 || exit 1
}
#-------------------------------------------------------------------------------
# Stop kube-apiserver

stop_apiserver() {
    echo "=> Stopping - Master - kube-apiserver..."
    ## Check if the kube-apiserver is still running
    [[ -n "${MASTER_APISERVER_PID-}" ]] && MASTER_APISERVER_PIDS=$(pgrep -P ${MASTER_APISERVER_PID} ; ps -o pid= -p ${MASTER_APISERVER_PID})
    [[ -n "${MASTER_APISERVER_PIDS-}" ]] && kill_pid ${MASTER_APISERVER_PIDS}
}
#-------------------------------------------------------------------------------
# Launch kube-controller-manager

start_controller_manager() {
    echo "=> Starting - Master - kube-controller-manager..."

    # run kube-controller-manager as binary
    MASTER_CTRLRMGR_LOG="/tmp/master-controller-manager.log"
    ${HYPERKUBE} controller-manager \
        --cluster-cidr=${PODS_CIDR} \
        --master=http://127.0.0.1:8080 \
        --root-ca-file=${CERT_DIR}/ca.pem \
        --service-account-private-key-file=${CERT_DIR}/apiserver-key.pem \
        --service-cluster-ip-range=${SERVICE_CIDR} > ${MASTER_CTRLRMGR_LOG} 2>&1 &
    MASTER_CTRLRMGR_PID=$!
}
#-------------------------------------------------------------------------------
# Stop kube-controller-manager

stop_controller_manager() {
    echo "=> Stopping - Master - kube-controller-manager..."
    ## Check if the controller-manager is still running
    [[ -n "${MASTER_CTRLRMGR_PID-}" ]] && MASTER_CTRLRMGR_PIDS=$(pgrep -P ${MASTER_CTRLRMGR_PID} ; ps -o pid= -p ${MASTER_CTRLRMGR_PID})
    [[ -n "${MASTER_CTRLRMGR_PIDS-}" ]] && kill_pid ${MASTER_CTRLRMGR_PIDS}
}
#-------------------------------------------------------------------------------
# Launch kube-scheduler

start_scheduler() {
    echo "=> Starting - Master - kube-scheduler..."

    # run kube-scheduler as binary
    MASTER_SCHEDULER_LOG="/tmp/master-scheduler.log"
    ${HYPERKUBE} scheduler \
        --master=http://127.0.0.1:8080 > ${MASTER_SCHEDULER_LOG} 2>&1 &
    MASTER_SCHEDULER_PID=$!
}
#-------------------------------------------------------------------------------
# Stop kube-scheduler

stop_scheduler() {
    echo "=> Stopping - Master - kube-scheduler..."

    ## Check if the kube-scheduler is still running
    [[ -n "${MASTER_SCHEDULER_PID-}" ]] && MASTER_SCHEDULER_PIDS=$(pgrep -P ${MASTER_SCHEDULER_PID} ; ps -o pid= -p ${MASTER_SCHEDULER_PID})
    [[ -n "${MASTER_SCHEDULER_PIDS-}" ]] && kill_pid ${MASTER_SCHEDULER_PIDS}
}
#-------------------------------------------------------------------------------
# Launch kubelet

start_kubelet() {
    echo "=> Starting -  Node  - kubelet..."

    # run kubelet as binary
    HOSTNAME_OVERRIDE=${PRIVATE_NODE_HOST:-127.0.0.1}
    NODE_KUBELET_LOG="/tmp/node-kubelet.log"
    ${HYPERKUBE} kubelet \
        --api-servers=${MASTER_HOST} \
        --cluster-dns=${DNS_SERVICE_IP} \
        --cluster-domain=${DNS_DOMAIN} \
        --hostname-override=${HOSTNAME_OVERRIDE} \
        --kubeconfig=${CERT_DIR}/node-kubeconfig > ${NODE_KUBELET_LOG} 2>&1 &
    NODE_KUBELET_PID=$!
}
#-------------------------------------------------------------------------------
# Stop kubelet

stop_kubelet() {
    echo "=> Stopping -  Node  - kubelet..."
    ## Check if the kubelet is still running
    [[ -n "${NODE_KUBELET_PID-}" ]] && NODE_KUBELET_PIDS=$(pgrep -P ${NODE_KUBELET_PID} ; ps -o pid= -p ${NODE_KUBELET_PID})
    [[ -n "${NODE_KUBELET_PIDS-}" ]] && kill -9 ${NODE_KUBELET_PIDS}
}
#-------------------------------------------------------------------------------
# Launch kube-proxy

start_proxy() {
    echo "=> Starting -  Node  - kube-proxy..."

    # run kube-proxy as binary
    NODE_KUBE_PROXY_LOG="/tmp/node-kube-proxy.log"
    ${HYPERKUBE} proxy \
        --conntrack-max=0 \
        --kubeconfig=${CERT_DIR}/node-kubeconfig \
        --master=${MASTER_HOST} > ${NODE_KUBE_PROXY_LOG} 2>&1 &
    NODE_KUBE_PROXY_PID=$!
}
#-------------------------------------------------------------------------------
# Stop kube-proxy

stop_proxy() {
    echo "=> Stopping -  Node  - kube-proxy..."
    ## Check if the kube-proxy is still running
    [[ -n "${NODE_KUBE_PROXY_PID-}" ]] && NODE_KUBE_PROXY_PIDS=$(pgrep -P ${NODE_KUBE_PROXY_PID} ; ps -o pid= -p ${NODE_KUBE_PROXY_PID})
    [[ -n "${NODE_KUBE_PROXY_PIDS-}" ]] && kill_pid ${NODE_KUBE_PROXY_PIDS}
}
#-------------------------------------------------------------------------------
# Fake podmaster selecting this host to be cluster leader and start the
# controller-manager & scheduler

start_podmaster(){
  start_controller_manager
  start_scheduler
}
#-------------------------------------------------------------------------------
# Fake podmaster selecting this host to be cluster leader and stop the
# controller-manager & scheduler

stop_podmaster(){
  stop_controller_manager
  stop_scheduler
}
#-------------------------------------------------------------------------------
# Launch the k8s Master

start_master(){
    start_apiserver
    start_podmaster
}
#-------------------------------------------------------------------------------
# Stop the k8s Master

stop_master(){
    stop_apiserver
    stop_podmaster
}
#-------------------------------------------------------------------------------
# Launch the k8s Node

start_node(){
    start_kubelet
    start_proxy
}
#-------------------------------------------------------------------------------
# Stop the k8s Node

stop_node(){
    stop_kubelet
    stop_proxy
}
#-------------------------------------------------------------------------------
# check k8s node health
check_nodes(){
    echo "=> k8s nodes:"
    while true;
    do
        kubelet=$(${KUBECTL} --kubeconfig=${CERT_DIR}/admin-kubeconfig --server=${MASTER_HOST} get no | grep "NotReady" | wc -l)
        proxy=$(ps aux | grep "hyperkube proxy" | grep -v grep)
        if [[ $kubelet == 0 ]] && [ -n "$proxy" ]; then
            sleep 7 # TODO fix this hack
            echo "`${KUBECTL} --kubeconfig=${CERT_DIR}/admin-kubeconfig --server=${MASTER_HOST} get no`"
            return 0
        fi
        sleep 1;
    done
}
#-------------------------------------------------------------------------------
