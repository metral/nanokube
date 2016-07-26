#!/bin/bash
#-------------------------------------------------------------------------------
source lib/init.sh
#-------------------------------------------------------------------------------
function usage () {
   cat <<EOF
Usage: $0 [-s] [-t]
   -s   create a self-hosted k8s cluster, using k8s Pods
   -t   create a traditional k8s cluster, using binaries
EOF
   exit 0
}

if [ ! "`whoami`" = "root" ]
then
    echo "Please run as root."
    exit 1
fi

while getopts ":st" opt; do
  case "${opt}" in
    s)
      trap self_hosted_install_cleanup EXIT
      self_hosted_install
      ;;
    t)
      trap traditional_install_cleanup EXIT
      traditional_install
      ;;
  esac
done
if [ $OPTIND -eq 1 ]; then
  usage
fi
shift $((OPTIND-1));

# sleep infinitely
echo "=> k8s component processes:"
echo "`ps aux | grep --color=always hyperkube | grep -v grep`"
echo ""
echo "=> Kubernetes cluster has started. When done, press CTRL+C to tear down, or background the process & terminate later."
while true; do sleep 1; done
#-------------------------------------------------------------------------------
