#!/bin/bash
#-------------------------------------------------------------------------------
set -o allexport
source vars/default
source vars/self-hosted
set +o allexport
#-------------------------------------------------------------------------------
# Generate k8s component manifests from their respective templates

render_manifests() {
    echo "=> Rendering manifests..."
    $TEMPLATES_DIR/create-kube-apiserver.yaml.sh
    $TEMPLATES_DIR/create-kube-controller-manager.yaml.sh
    $TEMPLATES_DIR/create-kube-scheduler.yaml.sh
    $TEMPLATES_DIR/create-kube-proxy.yaml.sh
}
#-------------------------------------------------------------------------------
# Pre-Setup
pre_setup() {
    echo "=> Running pre-setup..."

    # install deps
    ./install_deps.sh

    # setup filesystem requirements
    mkdir -p $CERT_DIR
    mkdir -p $MANIFESTS_DIR

    # Pull down Docker images
    # Hyperkube: each Pod will use this image to instantiate a k8s component in a
    # Pod depending on the role, Master or Node: apiserver, controller-manager, scheduler or kube-proxy
    $DOCKER pull $HYPERKUBE_IMAGE_REPO:$HYPERKUBE_VERSION

    # Pull down kubectl binary
    curl -s -o ${KUBECTL} ${KUBECTL_BIN_SOURCE}
    chmod +x ${KUBECTL}

    get_flannel
}
#-------------------------------------------------------------------------------
# Launch kube-apisever as Pod via system-hosted

start_apiserver() {
    echo "=> Starting - Master - kube-apiserver..."
    cp -f $LOCAL_MANIFESTS_DIR/kube-apiserver.yaml $MANIFESTS_DIR/ > /dev/null 2>&1

    # Wait for kube-apiserver to come up before launching the rest of the
    # components.
    echo "=> Waiting for apiserver to come up..."
    wait_for_apiserver "https://${PRIVATE_MASTER_HOST}" "${CERT_DIR}/kubeconfig" "apiserver: " 1 20 || exit 1
}
#-------------------------------------------------------------------------------
# Stop kube-apisever Pod

stop_apiserver() {
    echo "=> Stopping - Master - kube-apiserver..."
    rm -rf $MANIFESTS_DIR/kube-apiserver.yaml
}
#-------------------------------------------------------------------------------
# Launch kube-controller-manager as Pod via system-hosted Kubelet

start_controller_manager() {
    echo "=> Starting - Master - kube-controller-manager..."
    cp -f $LOCAL_MANIFESTS_DIR/kube-controller-manager.yaml $MANIFESTS_DIR/ > /dev/null 2>&1
}
#-------------------------------------------------------------------------------
# Stop kube-controller-manager Pod

stop_controller_manager() {
    echo "=> Stopping - Master - kube-controller-manager..."
    rm -rf $MANIFESTS_DIR/kube-controller-manager.yaml
}
#-------------------------------------------------------------------------------
# Launch kube-scheduler Pod

start_scheduler() {
    echo "=> Starting - Master - kube-scheduler..."
    cp -f $LOCAL_MANIFESTS_DIR/kube-scheduler.yaml $MANIFESTS_DIR/ > /dev/null 2>&1
}
#-------------------------------------------------------------------------------
# Stop kube-scheduler Pod

stop_scheduler() {
    echo "=> Stopping - Master - kube-scheduler..."
    rm -rf $MANIFESTS_DIR/kube-scheduler.yaml
}
#-------------------------------------------------------------------------------
# Launch Kubelet as a system-hosted, privileged container

start_sys_hosted_kubelet() {
    KUBELET_NAME=${1:-"kubelet"}
    echo "=> Starting - Master/Node - system-hosted Kubelet for '$KUBELET_NAME'..."

    HOSTNAME_OVERRIDE="127.0.0.1"
    KUBELET_MASTER_CIDFILE="/tmp/${KUBELET_NAME}.cid"
    KUBELET_MASTER_LOG="/tmp/${KUBELET_NAME}.log"

    $DOCKER run -d \
      --volume=${MANIFESTS_DIR}:${MANIFESTS_DIR} \
      --volume=/:/rootfs:ro \
      --volume=/sys:/sys:rw \
      --volume=/var/run:/var/run:rw \
      --volume=/var/lib/docker/:/var/lib/docker:rw \
      --volume=/var/lib/kubelet/:/var/lib/kubelet:rw,shared \
      --net=host \
      --pid=host \
      --privileged=true \
      --cidfile=${KUBELET_MASTER_CIDFILE} \
      --name ${KUBELET_NAME} \
      ${HYPERKUBE_IMAGE_REPO}:${HYPERKUBE_VERSION} \
      /hyperkube kubelet \
        --allow_privileged=true \
        --api-servers=http://127.0.0.1:8080 \
        --cluster-dns=${DNS_SERVICE_IP} \
        --cluster-domain=${DNS_DOMAIN} \
        --config=${MANIFESTS_DIR} \
        --hostname-override=${HOSTNAME_OVERRIDE} \
        --v=2
}
#-------------------------------------------------------------------------------
# Stop system-hosted Kubelet

stop_sys_hosted_kubelet() {
    echo "=> Stopping - Master/Node - system-hosted Kubelet..."
    # Check if the kubelet's are still running
    KUBELET_NAMES=$(docker ps -a --format '{{.Names}}' | grep "kubelet")
    while read -r kubelet_name; do
      local kubelet_cidfile="/tmp/$kubelet_name.cid"
      [[ -n "$kubelet_cidfile" ]] && cleanup_docker_container $kubelet_name $kubelet_cidfile
      rm -rf $kubelet_cidfile
    done <<< "${KUBELET_NAMES}"
}
#-------------------------------------------------------------------------------
# Launch kube-proxy as Pod via self-hosted Kubelet

start_proxy() {
    echo "=> Starting -  Node  - kube-proxy..."
    cp -f $LOCAL_MANIFESTS_DIR/kube-proxy.yaml $MANIFESTS_DIR/ > /dev/null 2>&1
}
#-------------------------------------------------------------------------------
# Stop kube-proxy Pod

stop_proxy() {
    echo "=> Stopping -  Node  - kube-proxy..."
    rm -rf $MANIFESTS_DIR/kube-proxy.yaml
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
    start_proxy
}
#-------------------------------------------------------------------------------
# Stop the k8s Node

stop_node(){
    stop_proxy
}
#-------------------------------------------------------------------------------
# check k8s node health
check_nodes(){
    echo "=> k8s nodes:"
    while true;
    do
        kubelet=$(${KUBECTL} --kubeconfig=${CERT_DIR}/kubeconfig --server=https://${PRIVATE_MASTER_HOST} get no | grep "NotReady" | wc -l)
        proxy_pod_name=$(docker ps --format '{{.Names}}' | grep "k8s_kube-proxy")
        if [[ $kubelet == 0 ]] && [ -n "$proxy_pod_name" ]; then
            echo "`${KUBECTL} --kubeconfig=${CERT_DIR}/kubeconfig --server=https://${PRIVATE_MASTER_HOST} get no`"
            return 0
        fi
        sleep 1;
    done
}
#-------------------------------------------------------------------------------
