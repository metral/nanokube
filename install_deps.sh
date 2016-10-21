#!/bin/bash

# install APT pkgs'
apt-get update > /dev/null && \
  apt-get install -y \
    curl > /dev/null
