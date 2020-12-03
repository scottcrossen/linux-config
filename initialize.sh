#!/bin/bash
#author scottcrossen

echo "Setting script variables"
SCRIPT_DIR="$(pwd)"/"${BASH_SOURCE%/*}"
TEMP_DIR=$(mktemp -d)
USER=${1:-$USER}
USER_FULLNAME=$2
USER_EMAIL=$3
ARCH=""
ETHERNET_INTERFACE=$(ip link show | grep -o 'en[^: ]\+')
WIFI_INTERFACE=$(ip link show | grep -o 'wlp[^: ]\+')
cd $TEMP_DIR

if [ -z "$USER" ] || [ -z "$FULL_NAME" ] || [ -z "$USER_EMAIL" ]; then
  echo "Usage is: $0 <user> \"<first name> <last name>\" <email>"
  exit 1
fi

if [[ $(uname -m) = x86_64 ]]; then
  ARCH="amd64"
else 
  echo "Unknown architecture \"$(uname -m)\""
  exit 1
fi

function replaceWithUserDetails {
  ALL_FILES_IN_DIR=($(find ${1:-"."}))
  for FILE in "${ALL_FILES_IN_DIR[@]}"; do
    sed -i "s/###ETHERNET_INTERFACE###/$ETHERNET_INTERFACE/g" "$FILE"
    sed -i "s/###WIFI_INTERFACE###/$WIFI_INTERFACE/g" "$FILE"
    sed -i "s/###USER_EMAIL###/$USER_EMAIL/g" "$FILE"
    sed -i "s/###USER_FULLNAME###/$USER_FULLNAME/g" "$FILE"
    sed -i "s/###USER###/$USER/g" "$FILE"
  done
}

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
replaceWithUserDetails ~
sudo chmod +x -R ~/.bashrc.d
sudo chmod +x ~/.bashrc
sudo chmod +x ~/.xprofile

echo "Copying udev files"
sudo cp -r "$SCRIPT_DIR"/udev/. /etc/udev/rules.d
sudo replaceWithUserDetails /etc/udev/rules.d
sudo udevadm control --reload-rules && udevadm trigger

echo "Copying scripts"
sudo cp -r "$SCRIPT_DIR"/scripts/. /usr/local/bin
sudo replaceWithUserDetails /usr/local/bin

echo "Copying cron jobs"
sudo cp -r "$SCRIPT_DIR"/cron.d/. /etc/cron.d
sudo replaceWithUserDetails /etc/cron.d
sudo systemctl restart cron

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
  brightnessctl \
  jq \
  lightdm  > /dev/null

echo "Installing Google Chrome"
curl -sSLo google-chrome-stable_current_$ARCH.deb https://dl.google.com/linux/direct/google-chrome-stable_current_$ARCH.deb
sudo apt-get -qq install -y ./google-chrome-stable_current_$ARCH.deb > /dev/null

echo "Installing Git"
sudo apt-get -qq install git > /dev/null
git config --global user.name "$USER_FULLNAME"
git config --global user.email "$USER_EMAIL"
git config --global url."ssh://git@stash.teslamotors.com:7999/".insteadOf "https://stash.teslamotors.com/scm/"
git config --global url."git@stash.teslamotors.com:7999".insteadOf "https://stash.teslamotors.com/"
git config --global url."git@github.com:".insteadOf "https://github.com/"
git config --global core.editor "vim"
ssh-keygen -f ~/.ssh/id_rsa -q -N ""
ssh-add ~/.ssh/id_rsa
echo "TODO: Remember to add public ssh key to GitHub/BitBucket"

echo "Configuring screen mirroring"
git clone https://github.com/schlomo/automirror.git
mkdir -p ~/.screenlayout
mv automirror/automirror.sh ./screenlayout/automirror.sh
sudo chmod +x ~/.screenlayout/*

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

echo "Installing docker compose"
# Personally, I think docker compose is stupid. However, some repositories think we need it for some reason.
sudo curl -sSL "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "Installing Kubernetes"
curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - > /dev/null 2> /dev/null
if ! grep -q "xenial" /etc/apt/sources.list.d/kubernetes.list; then
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list > /dev/null
fi
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y kubectl > /dev/null
cd "$(mktemp -d)" &&
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz" &&
tar zxvf krew.tar.gz &&
KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/')" &&
"$KREW" install krew
"$KREW" install ctx
"$KREW" install ns
"$KREW" install oidc-login

echo "Installing Minikube"
sudo adduser $USER libvirt
curl -sSLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$ARCH \
  && chmod +x minikube
mkdir -p /usr/local/bin/
sudo install minikube /usr/local/bin/
# TODO: systemd files need to have their username re-mapped to the current.
sudo cp "$SCRIPT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
sudo replaceWithUserDetails /lib/systemd/system/minikube.service
sudo systemctl daemon-reload
sudo systemctl enable minikube.service

echo "Installing HashiCorp Vault (for Kubernetes secrets)"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository --yes --update "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y vault

echo "Installing I3"
sudo apt-get -qq install i3
sudo update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/i3 60
sudo dpkg-reconfigure lightdm
sudo cp "$SCRIPT_DIR"/systemd/lock.service /lib/systemd/system/lock.service
sudo replaceWithUserDetails /lib/systemd/system/lock.service

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

echo "Installing Ansible"
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y ansible

echo "Installing Yubikey"
sudo apt-add-repository --yes --update ppa:yubico/stable
sudo apt-get -qq update > /dev/null
sudo apt-get install yubikey-manager libpam-yubico
sudo apt-get install -y yubico-piv-tool

echo "Installing Protobuf"
sudo apt-get -qq install -y protobuf-compiler

echo "Installing Javascript"
mkdir ~/.nvm && cd ~/.nvm && git clone https://github.com/nvm-sh/nvm.git . && cd -

# echo "Installing Ruby"
# Stuff
# rvm rvmrc warning ignore allGemfiles