#!/bin/bash
#-------------------------------------------------------------------------------
set -o allexport
source vars/default
set +o allexport
#-------------------------------------------------------------------------------
wait_for_url() {
    local url=$1
    local prefix=${2:-}
    local wait=${3:-1}
    local times=${4:-30}

    which curl >/dev/null || {
    exit 1
    }

    local i
    for i in $(seq 1 $times); do
        local out
        if out=$(curl -gfs $url 2>/dev/null); then
            status "On try ${i}, ${prefix}: ${out}"
            return 0
        fi
        sleep ${wait}
    done
    error_exit "Timed out waiting for ${prefix} to answer at ${url}; tried ${times} waiting ${wait} between each"
    return 1
}
#-------------------------------------------------------------------------------
wait_for_apiserver() {
    local server=$1
    local kubeconfig=$2
    local prefix=${3:-}
    local wait=${4:-1}
    local times=${5:-30}

    which curl >/dev/null || {
    exit 1
    }

    local i
    for i in $(seq 1 $times); do
        local out
        if out=$(${KUBECTL} --kubeconfig=$kubeconfig --server=$server cluster-info 2>/dev/null); then
            status "On try ${i}, ${prefix}: ${out}"
            return 0
        fi
        sleep ${wait}
    done
    error_exit "Timed out waiting for ${prefix} to answer at ${server}; tried ${times} waiting ${wait} between each"
    return 1
}
#-------------------------------------------------------------------------------
# Generate kubeconfig file used for Kubelet & user

# TODO: these really should be 2 different kubeconfig's per best-practices -
# need to alter make-ca-cert.sh to generate 2 different copies
render_kubeconfig(){
    echo "=> Rendering kubectl kubeconfig file..."
    $TEMPLATES_DIR/create-kubeconfig.yaml.sh
}
#-------------------------------------------------------------------------------
# Generate k8s component manifests from their respective templates

render_addons() {
    echo "=> Rendering addons..."

    # dns
    $ADDONS_DIR/dns/create-skydns-rc.yaml.sh
    $ADDONS_DIR/dns/create-skydns-svc.yaml.sh
}
#-------------------------------------------------------------------------------
# Generate certs & k8s config for TLS

generate_certs() {
    echo "=> Generating certs..."
    /usr/sbin/groupadd -f -r kube-cert > /dev/null 2>&1
    ./make-ca-cert.sh IP:$PRIVATE_MASTER_HOST,IP:$APISERVER_SERVICE_IP,IP:127.0.0.1,DNS:localhost,DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc
}
#-------------------------------------------------------------------------------
kill_pid(){
    kill "$1" >/dev/null 2>&1 || :
    wait "$1" >/dev/null 2>&1 || :
}
#-------------------------------------------------------------------------------
cleanup_docker_container() {
    local container_name=$1
    local cidfile=$2
    if [[ -e $cidfile ]]; then
        rm -f $cidfile
    fi

    docker kill $container_name > /dev/null 2>&1 || :
    docker rm -f $container_name > /dev/null 2>&1 || :
}
#-------------------------------------------------------------------------------
cleanup_all_containers(){
  echo "=> Cleaning any remaining Docker containers..."

  # Check if the k8s component pods are still running
  K8S_POD_NAMES=$(docker ps -a --format '{{.Names}}' | grep "k8s")
  while read -r pod_ctr_name;do
    cleanup_docker_container ${pod_ctr_name}
  done <<< "${K8S_POD_NAMES}"
}
#-------------------------------------------------------------------------------
cleanup_k8s(){
  echo "=> Cleaning k8s resources..."

  # Check if the k8s resources still exist & delete
  ${KUBECTL} --kubeconfig=${CERT_DIR}/kubeconfig --server=https://${PRIVATE_MASTER_HOST} delete --namespace=default deployments,rc,rs,pods,svc,ing,secrets,configmaps --all --grace-period=0
}
#-------------------------------------------------------------------------------
# check k8s component statuses
check_component_statuses(){
    echo "=> k8s component statuses:"
    while true;
    do
        out=$(${KUBECTL} --kubeconfig=${CERT_DIR}/kubeconfig --server=https://${PRIVATE_MASTER_HOST} get cs | grep "Unhealthy" | wc -l)
        if [[ $out == 0 ]]; then
            echo "`${KUBECTL} --kubeconfig=${CERT_DIR}/kubeconfig --server=https://${PRIVATE_MASTER_HOST} get cs`"
            return 0
        fi
        sleep 1;
    done
}
#-------------------------------------------------------------------------------
# Print a status line.  Formatted to show up in a stream of output.
status() {
    timestamp=$(date +"[%m%d %H:%M:%S]")
    echo "+++ $timestamp $1"
    shift
    for message; do
        echo "    $message"
    done
}
#-------------------------------------------------------------------------------
# Log an error but keep going.  Don't dump the stack or exit.
error() {
    timestamp=$(date +"[%m%d %H:%M:%S]")
    echo "!!! $timestamp ${1-}" >&2
    shift
    for message; do
        echo "    $message" >&2
    done
}
#-------------------------------------------------------------------------------
# Print out the stack trace
#
# Args:
#   $1 The number of stack frames to skip when printing.
stack() {
    local stack_skip=${1:-0}
    stack_skip=$((stack_skip + 1))
    if [[ ${#FUNCNAME[@]} -gt $stack_skip ]]; then
        echo "Call stack:" >&2
        local i
        for ((i=1 ; i <= ${#FUNCNAME[@]} - $stack_skip ; i++))
        do
            local frame_no=$((i - 1 + stack_skip))
            local
            source_file=${BASH_SOURCE[$frame_no]}
            local
            source_lineno=${BASH_LINENO[$((frame_no
            - 1))]}
            local
            funcname=${FUNCNAME[$frame_no]}
            echo "  $i:
            ${source_file}:${source_lineno}
            ${funcname}(...)"
            >&2
        done
    fi
}
#-------------------------------------------------------------------------------
# Log an error and exit.
# Args:
#   $1 Message to log with the error
#   $2 The error code to return
#   $3 The number of stack frames to skip when printing.
error_exit() {
    local message="${1:-}"
    local code="${2:-1}"
    local stack_skip="${3:-0}"
    stack_skip=$((stack_skip + 1))

    local source_file=${BASH_SOURCE[$stack_skip]}
    local source_line=${BASH_LINENO[$((stack_skip - 1))]}
    echo "!!! Error in ${source_file}:${source_line}" >&2
    [[ -z ${1-} ]] || {
    echo "  ${1}" >&2
    }

    stack $stack_skip

    echo "Exiting with status ${code}" >&2
    exit "${code}"
}
#-------------------------------------------------------------------------------
# Launch etcd

start_etcd() {
    echo "=> Starting etcd..."

    # Pull Docker image
    $DOCKER pull quay.io/coreos/etcd:$ETCD_VERSION

    # Start etcd as container
    ETCD_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    ETCD_CIDFILE="/tmp/etcd.cid"
    ETCD_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t test-etcd.XXXXXX)
    $DOCKER run -d \
        --restart=always \
        -v $CA_CERTS:/etc/ssl/certs \
        -v $ETCD_DIR:$ETCD_DIR \
        -p $ETCD_CLIENT_PORT:$ETCD_CLIENT_PORT -p $ETCD_PEER_PORT:$ETCD_PEER_PORT \
        --cidfile=$ETCD_CIDFILE \
        --name $ETCD_NAME $ETCD_IMAGE \
        -name $ETCD_NAME \
        -data-dir $ETCD_DIR \
        -advertise-client-urls http://$ETCD_HOST:$ETCD_CLIENT_PORT \
        -listen-client-urls http://0.0.0.0:$ETCD_CLIENT_PORT \
        -initial-advertise-peer-urls http://$ETCD_HOST:$ETCD_PEER_PORT \
        -listen-peer-urls http://0.0.0.0:$ETCD_PEER_PORT \
        -initial-cluster-token $ETCD_TOKEN \
        -initial-cluster $ETCD_NAME=http://$ETCD_HOST:$ETCD_PEER_PORT \
        -initial-cluster-state new

    echo "==> Waiting for etcd to come up..."
    wait_for_url "http://$ETCD_HOST:$ETCD_CLIENT_PORT/v2/machines" "etcd: " 0.25 80
    curl -fs -X PUT "http://$ETCD_HOST:$ETCD_CLIENT_PORT/v2/keys/_test"
}
#-------------------------------------------------------------------------------
# Stop etcd

stop_etcd(){
    echo "=> Stopping etcd..."

    # Check if the etcd is still running
    [[ -n "${ETCD_CIDFILE-}" ]] && cleanup_docker_container $ETCD_NAME $ETCD_CIDFILE
    rm -rf "${ETCD_DIR}"
    rm -rf "${ETCD_CIDFILE}"
}
#-------------------------------------------------------------------------------
get_flannel(){
  # Pull down flannel binary
  wget --quiet https://github.com/coreos/flannel/releases/download/v${FLANNEL_VERSION}/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz -O /tmp/flannel.tar.gz
  pushd /tmp > /dev/null
  tar xzf /tmp/flannel.tar.gz
  cp -r flannel*/flanneld ${FLANNEL}
  popd > /dev/null
  chmod +x ${FLANNEL}
}
#-------------------------------------------------------------------------------
# Launch flannel

config_flannel_opts(){
  echo "Configuring flannel options..."

  mkdir -p /run/flannel

  cat > /etc/default/flannel << EOF
FLANNELD_IFACE=${MASTER_PRIVATE_IF}
FLANNELD_ETCD_ENDPOINTS=http://${ETCD_HOST}:${ETCD_CLIENT_PORT}
EOF

  ln -sf /etc/default/flannel /run/flannel/options.env
}

init_flannel(){
  echo "Waiting for etcd..."
  while true
  do
    # TODO - line should be: IFS=',' read -ra ES <<< "<all etcd endpoints>"
    IFS=',' read -ra ES <<< "${ETCD_HOST}:${ETCD_CLIENT_PORT}"
    for etcd_host in "${ES[@]}"; do
      echo "Trying: $etcd_host"
      if [ -n "$(curl --silent "$etcd_host/v2/machines")" ]; then
        local ACTIVE_ETCD_HOST=$etcd_host
        break
      fi
      sleep 1
    done
    if [ -n "$ACTIVE_ETCD_HOST" ]; then
      break
    fi
  done
  RES=$(curl --silent -X PUT -d "value={\"Network\":\"$PODS_CIDR\",\"Backend\":{\"Type\":\"vxlan\"}}" "$ACTIVE_ETCD_HOST/v2/keys/coreos.com/network/config?prevExist=false")
  if [ -z "$(echo $RES | grep '"action":"create"')" ] && [ -z "$(echo $RES | grep 'Key already exists')" ]; then
    echo "Unexpected error configuring flannel pod network: $RES"
  fi
}

setup_flannel(){
  echo "=> Setting up flannel..."
  config_flannel_opts
  init_flannel
}
#-------------------------------------------------------------------------------
start_flannel(){
  echo "=> Starting flannel..."

  FLANNEL_LOG="/tmp/flannel.log"
  ${FLANNEL} > ${FLANNEL_LOG} 2>&1 &
  FLANNEL_PID=$!
}
#-------------------------------------------------------------------------------
# Stop flannel

stop_flannel(){
  echo "=> Stopping flannel..."

  # Check if the flannel is still running
  [[ -n "${FLANNEL_PID-}" ]] && FLANNEL_PIDS=$(pgrep -P ${FLANNEL_PID} ; ps -o pid= -p ${FLANNEL_PID})
  [[ -n "${FLANNEL_PIDS-}" ]] && kill_pid ${FLANNEL_PIDS}

  [ -e /etc/default/flannel ] && rm -rf /etc/default/flannel
  [ -e /run/flannel ] && rm -rf /run/flannel
  [ -d /sys/class/net/flannel.1 ] && ip link set flannel.1 down && ip link delete flannel.1
}
#-------------------------------------------------------------------------------
# Reconfigure Docker to use the flannel interface as the bridge with an MTU

reconfig_docker(){
  echo "=> Reconfiguring Docker to use flannel..."

  local i
  local times=15
  local wait=1
  for i in $(seq 1 $times); do
    if [ -f ${FLANNEL_ENV} ]; then
      source ${FLANNEL_ENV}

      cp -r ${DOCKER_DEFAULT} /tmp/ > /dev/null 2>&1
      cat >> ${DOCKER_DEFAULT} << EOF
DOCKER_OPTS="--bip=${FLANNEL_SUBNET} --mtu=${FLANNEL_MTU}"
EOF

      service docker restart

      echo "==> Waiting for etcd to come up..."
      wait_for_url "http://${ETCD_HOST}:${ETCD_CLIENT_PORT}/v2/machines" "etcd: " 0.25 80

      return 0
    fi
    sleep ${wait}
  done
  error_exit "Timed out waiting for Docker to reconfigure; tried ${times} waiting ${wait} between each"
  return 1
}
#-------------------------------------------------------------------------------
# Reset Docker to not use flannel

reset_docker(){
  echo "=> Resetting Docker..."

  cp -r /tmp/docker ${DOCKER_DEFAULT}
  service docker restart
}
#-------------------------------------------------------------------------------
# Launch kube_dns in k8s

start_kube_dns(){
  echo "=> Starting dns..."

  ${KUBECTL} \
    --kubeconfig="${CERT_DIR}/kubeconfig" \
    --server=https://${PRIVATE_MASTER_HOST} \
    apply -f ${ADDONS_DIR}/dns -R
}
#-------------------------------------------------------------------------------
# Stop kube-dns Pods

stop_kube_dns(){
  echo "=> Stopping dns..."

  ${KUBECTL} \
    --kubeconfig="${CERT_DIR}/kubeconfig" \
    --server=https://${PRIVATE_MASTER_HOST} \
    delete -f ${ADDONS_DIR}/dns -R || :
}
#-------------------------------------------------------------------------------
# Launch addons

start_addons() {
  echo "=> Starting addons..."

  # dns
  start_kube_dns
}
#-------------------------------------------------------------------------------
# Stop addons

stop_addons() {
  echo "=> Stopping addons..."

  # dns
  stop_kube_dns
}
#-------------------------------------------------------------------------------
self_hosted_install(){
  echo "=> Starting nanokube (self-hosted)..."

  source vars/self-hosted
  source lib/self-hosted.sh

  ./lib/self-hosted-init.sh

  pre_setup
  generate_certs
  render_kubeconfig
  render_manifests
  render_addons
  start_etcd      # runs as a Docker container
  setup_flannel
  start_flannel     # runs as a binary
  reconfig_docker
  start_sys_hosted_kubelet "kubelet-master-node"    # runs as a privileged Docker container
  start_master
  check_component_statuses
  start_node
  check_nodes
  start_addons
}
#-------------------------------------------------------------------------------
self_hosted_install_cleanup() {
  echo "=> Cleaning up before exiting..."

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

  echo "Cleanup done."

  local exit_requested=${1:-"true"}
  if [ "$exit_requested" == "true" ]; then
    exit 0
  fi
}
#-------------------------------------------------------------------------------
traditional_install() {
  echo "=> Starting nanokube (traditional/binary)..."

  source lib/traditional.sh

  pre_setup
  generate_certs
  render_kubeconfig
  render_addons
  start_etcd      # runs as a Docker container
  setup_flannel
  start_flannel     # runs as a binary
  reconfig_docker
  start_master
  check_component_statuses
  start_node
  check_nodes
  start_addons
}
#-------------------------------------------------------------------------------
traditional_install_cleanup() {
  echo "=> Cleaning up before exiting..."

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

  echo "Cleanup done."

  local exit_requested=${1:-"true"}
  if [ "$exit_requested" == "true" ]; then
    exit 0
  fi
}
#-------------------------------------------------------------------------------
