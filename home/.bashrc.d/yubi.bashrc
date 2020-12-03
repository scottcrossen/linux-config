#!/bin/bash
#author scottcrossen

alias fixyubi="ssh-add -e /usr/lib/libykcs11.so > /dev/null 2>&1; ssh-add -s /usr/lib/libykcs11.so"

if ! ssh-add -L | grep -q " PIV "; then
    echo "Yubikey not add added to ssh-agent"
    fixyubi
fi