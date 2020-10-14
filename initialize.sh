#!/bin/bash

echo "Setting script variables"
SCRIPT_DIR="$(pwd)"/"${BASH_SOURCE%/*}"
TEMP_DIR=$(mktemp -d)
USER=scottcrossen
cd $TEMP_DIR
ARCH=""
if [[ $(uname -m) = x86_64 ]]; then
  ARCH="amd64"
else 
  echo "Unknown architecture \"$(uname -m)\""
  exit
fi

echo "Creating user and switching over"
sudo useradd -m $USER
sudo usermod -aG video $USER
sudo usermod -aG libvert $USER
sudo usermod -aG sudo $USER
sudo su - $USER
echo "Setting user password"
passwd

echo "Copying dotfiles"
cp -r "$SCRIPT_DIR"/home/. ~
sudo chmod +x ~/.bashrc.d
sudo chmod +x ~/.bashrc
ETHERNET_INTERFACE=$(ip link show | grep -o 'en[^: ]\+')
sed -i "s/#####/$ETHERNET_INTERFACE/g" ~/.config/i3status/config

echo "Copying udev files"
sudo cp -r "$SCRIPT_DIR"/udev/. /etc/udev/rules.d
sudo udevadm control --reload-rules && udevadm trigger

echo "Copying scripts"
sudo cp -r "$SCRIPT_DIR"/scripts/. /usr/local/bin

echo "Installing basic packages"
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y \
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
  python3-psutil \
  arandr \
  brightnessctl > /dev/null

echo "Installing Google Chrome"
curl -sSLo google-chrome-stable_current_$ARCH.deb https://dl.google.com/linux/direct/google-chrome-stable_current_$ARCH.deb
sudo apt-get -qq install -y ./google-chrome-stable_current_$ARCH.deb > /dev/null

echo "Installing Git"
sudo apt-get -qq install git > /dev/null
git config --global user.name "Scott Crossen"
git config --global user.email "scottcrossen42@gmail.com"
git config --global url."ssh://git@stash.teslamotors.com:7999/".insteadOf "https://stash.teslamotors.com/scm/"
git config --global url."git@stash.teslamotors.com:7999".insteadOf "https://stash.teslamotors.com/"
git config --global core.editor "vim"
ssh-keygen -f ~/.ssh/id_rsa -q -N ""
ssh-add ~/.ssh/id_rsa
echo "TODO: Remember to add public ssh key to GitHub"

echo "Installing Docker"
curl -sSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2> /dev/null
sudo add-apt-repository \
  "deb [arch=$ARCH] https://download.docker.com/linux/$(lsb_release -is | awk '{print tolower($0)}') \
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
curl -sSLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$ARCH \
  && chmod +x minikube
mkdir -p /usr/local/bin/
sudo install minikube /usr/local/bin/
# TODO: systemd files need to have their username re-mapped to the current.
sudo cp "$SCRIPT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
sudo systemctl daemon-reload
sudo systemctl enable minikube.service

echo "Installing I3"
sudo apt-get -qq install i3
sudo update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/i3 60

echo "Installing Visual Studio Code"
# curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - > /dev/null 2> /dev/null
# sudo add-apt-repository "deb [arch=$ARCH] https://packages.microsoft.com/repos/vscode stable main"
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y code > /dev/null

echo "Installing Chrome Remote Desktop"
curl -sSLO https://dl.google.com/linux/direct/chrome-remote-desktop_current_$ARCH.deb
sudo dpkg --install chrome-remote-desktop_current_$ARCH.deb > /dev/null
sudo apt-get -qq install --assume-yes --fix-broken
sudo touch /etc/chrome-remote-desktop-session
sudo bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'
echo "TODO: Remember to add this computer to chrome remote desktop list"

echo "Installing Golang"
VERSION_REGEX='\"version\":\s*\"([^"]*)\"'
[[ $(curl -sSL 'https://golang.org/dl/?mode=json') =~ $VERSION_REGEX ]]
CURRENT_VERSION="${BASH_REMATCH[1]}"
curl -sSLO https://dl.google.com/go/$CURRENT_VERSION.linux-$ARCH.tar.gz
tar -C /usr/local -xzf $CURRENT_VERSION.linux-$ARCH.tar.gz

echo "Installing Rust"
curl -sSL --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

echo "Install Ansible"
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y ansible
