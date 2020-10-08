#!/bin/bash

# TODO: Cleanup stdout on most of this

echo "Setting script variables"
SCRIPT_DIR="${BASH_SOURCE%/*}"
mkdir -p "$SCRIPT_DIR"/tmp
cd "$SCRIPT_DIR"/tmp
SCRIPT_DIR="$SCRIPT_DIR"/..

echo "Copying dotfiles"
cp -r "$SCRIPT_DIR"/home/. ~
sudo chmod +x ~/.bashrc.d
sudo chmod +x ~/.bashrc

echo "Installing basic packages"
sudo apt-get -qq update > /dev/null
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y \
    apt-transport-https \
    gnupg2 \
    curl \
    vim \
    ca-certificates \
    gnupg-agent \
    software-properties-common \
    qemu-system \
    libvirt-clients \
    libvirt-daemon-system \
    xvfb \
    xbase-clients \
    python3-psutil > /dev/null

echo "Installing Google Chrome"
curl -sSLo google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt-get -qq install -y ./google-chrome-stable_current_amd64.deb > /dev/null

echo "Installing Git"
sudo apt-get -qq install git > /dev/null
git config --global user.name "Scott Crossen"
git config --global user.email "scottcrossen42@gmail.com"
ssh-keygen -f ~/.ssh/id_rsa -q -N ""
ssh-add ~/.ssh/id_rsa
echo "TODO: Remember to add public ssh key to GitHub"

echo "Installing Docker"
curl -sSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2> /dev/null
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y docker-ce docker-ce-cli containerd.io > /dev/null
sudo usermod -aG docker $USER
echo "Logging into docker"
docker login

echo "Installing Kubernetes"
curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - > /dev/null 2> /dev/null
if ! grep -q "xenial" /etc/apt/sources.list.d/kubernetes.list; then
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list > /dev/null
fi
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y kubectl > /dev/null

echo "Installing Minikube"
sudo adduser $USER libvirt
curl -sSLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && chmod +x minikube
mkdir -p /usr/local/bin/
sudo install minikube /usr/local/bin/
sudo cp "$SCRIPT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
sudo systemctl daemon-reload

echo "Installing I3"
sudo apt-get -qq install i3
sudo update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/i3 60

echo "Installing Visual Studio Code"
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - > /dev/null 2> /dev/null
sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y code > /dev/null

echo "Installing Chrome Remote Desktop"
curl -sSLo chrome-remote-desktop_current_amd64.deb https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
sudo dpkg --install chrome-remote-desktop_current_amd64.deb > /dev/null
sudo apt-get -qq install --assume-yes --fix-broken
sudo touch /etc/chrome-remote-desktop-session
sudo echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session
echo "TODO: Remember to add this computer to chrome remote desktop list"
