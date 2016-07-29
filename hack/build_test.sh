#!/bin/bash
set -e

source lib/init.sh

# test traditional/binary install
echo "--------------------------------------------"
trap traditional_install_cleanup ERR
traditional_install
#TODO test DNS is working via kubectl
if [ $? -eq 0 ]; then
  traditional_install_cleanup "false"
fi

# test self hosted install
echo "--------------------------------------------"
trap self_hosted_install_cleanup ERR
self_hosted_install
#TODO test DNS is working via kubectl
if [ $? -eq 0 ]; then
  self_hosted_install_cleanup "false"
fi
