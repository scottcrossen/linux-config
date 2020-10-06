#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

SCRIPT_DIR="${BASH_SOURCE%/*}"
mkdir -p "$SCRIPT_DIR"/tmp
cd "$SCRIPT_DIR"/tmp

apt update
apt update && apt install -y \
    apt-transport-https \
    gnupg2 \
    curl \
    vim \
    ca-certificates \
    gnupg-agent \
    software-properties-common \
    qemu-system \
    libvirt-clients \
    libvirt-daemon-system

# Install chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt install -y ./google-chrome-stable_current_amd64.deb

# Install git
apt install git
git config --global user.name "Scott Crossen"
git config --global user.email "scottcrossen42@gmail.com"
ssh-keygen -f ~/.ssh/id_rsa -q -N ""
ssh-add ~/.ssh/id_rsa
# TODO: automate adding id_rsa to GitHub

# Install bashrc
cp -r "$SCRIPT_DIR"/home/. ~
chmod +x ~/.bashrc.d
chmod +x ~/.bashrc

# Install docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"
apt update && apt install -y docker-ce docker-ce-cli containerd.io
usermod -aG docker $USER && newgrp docker

# Install Kubernetes
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
apt update && apt install -y kubectl

# Install minikube
adduser $USER libvirt
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && chmod +x minikube
mkdir -p /usr/local/bin/
install minikube /usr/local/bin/
cp "$SCRIPT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
systemctl daemon-reload

# Install i3
apt install i3
update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/i3 60
