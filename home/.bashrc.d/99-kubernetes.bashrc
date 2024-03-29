#!/bin/bash
#author scottcrossen

source <(kubectl completion bash)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

alias kubectx='kubectl ctx'
alias kubens='kubectl ns'
alias kubelogin='kubectl oidc-login'
alias krew='kubectl krew'

if ls $HOME/.kube/*.config.yml > /dev/null 2> /dev/null; then
    export KUBECONFIG=$HOME/.kube/config:$(ls -A1 $HOME/.kube/*.config.yml | tr '\n' :)
fi

function inspect-cert-secret {
    kubectl get secret $1 -o jsonpath='{.data}' | jq -r '.["tls.crt"]' | base64 -d | openssl x509 -text -noout
}
