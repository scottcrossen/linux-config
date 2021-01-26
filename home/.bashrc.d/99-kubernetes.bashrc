#!/bin/bash
#author scottcrossen

if minikube -p minikube docker-env | grep -q "To fix this" || minikube -p minikube docker-env | grep -q "minikube start"; then
  echo "Minikube not started"
else
  eval "$(minikube -p minikube docker-env)"
fi

source <(kubectl completion bash)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

alias kubectx='kubectl ctx'
alias kubens='kubectl ns'
alias kubelogin='kubectl oidc-login'
alias krew='kubectl krew'
