#!/bin/bash
#author scottcrossen

source <(kubectl completion bash)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

alias kubectx='kubectl ctx'
alias kubens='kubectl ns'
alias kubelogin='kubectl oidc-login'
alias krew='kubectl krew'
