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

if [ -z "$USER" ] || [ -z "$USER_FULLNAME" ] || [ -z "$USER_EMAIL" ]; then
  echo "Usage is: $0 <user> \"<first name> <last name>\" <email>"
  exit 1
fi

if [[ $(uname -m) = x86_64 ]]; then
  ARCH="amd64"
else
  echo "Unknown architecture \"$(uname -m)\""
  exit 1
fi

HEADLESS=false
HAS_RUBY=false
for EXTRA_ARG in "${@:4}"; do
  if [ "$EXTRA_ARG" = "--headless" ]; then
    HEADLESS=true
  elif [ "$EXTRA_ARG" = "--has_ruby" ]; then
    HAS_RUBY=trie
  else
    echo "Unknown argument $EXTRA_ARG"
    exit 1
  fi
done

function replace_with_user_details {
  ALL_FILES_IN_DIR=($(find ${1:-"."} -type f))
  for FILE in "${ALL_FILES_IN_DIR[@]}"; do
    # TODO: IF no interface then it needs to be removed
    sudo sed -i "s/###ETHERNET_INTERFACE###/$ETHERNET_INTERFACE/g" "$FILE"
    sudo sed -i "s/###WIFI_INTERFACE###/$WIFI_INTERFACE/g" "$FILE"
    sudo sed -i "s/###USER_EMAIL###/$USER_EMAIL/g" "$FILE"
    sudo sed -i "s/###USER_FULLNAME###/$USER_FULLNAME/g" "$FILE"
    sudo sed -i "s/###USER###/$USER/g" "$FILE"
    if [ -z "$ETHERNET_INTERFACE" ]; then
      sudo sed -i "s/###HAS_ETHERNET###.*$//g" "$FILE"
    else
      sudo sed -i "s/###HAS_ETHERNET###//g" "$FILE"
    fi
    if [ -z "$WIFI_INTERFACE" ]; then
      sudo sed -i "s/###HAS_WIFI###.*$//g" "$FILE"
    else
      sudo sed -i "s/###HAS_WIFI###//g" "$FILE"
    fi
  done
}

echo "Creating user $USER"
sudo useradd -m $USER > /dev/null 2> /dev/null
sudo usermod -aG video $USER > /dev/null 2> /dev/null
groupadd libvert > /dev/null 2> /dev/null
groupadd chrome-remote-desktop > /dev/null 2> /dev/null
sudo usermod -aG libvert $USER > /dev/null 2> /dev/null
sudo usermod -aG sudo $USER > /dev/null 2> /dev/null
sudo usermod -aG chrome-remote-desktop $USER > /dev/null 2> /dev/null
if [ "$(sudo passwd --status "$USER" | awk '{print $2}')" != "P" ]; then
  echo "Setting user password"
  sudo passwd "$USER"
fi

echo "Copying and chowning files"
mkdir -p linux-config
ARTIFACT_DIR="$(pwd)"/linx-config
sudo cp -r "$SCRIPT_DIR" "$ARTIFACT_DIR"
sudo chown -R "$USER" "$ARTIFACT_DIR"
replace_with_user_details "$ARTIFACT_DIR"

echo "Copying dotfiles"
sudo cp -r "$ARTIFACT_DIR"/home/. ./home/
sudo cp -r ./home/. /home/"$USER"/
sudo chmod +x -R /home/"$USER"/.bashrc.d
sudo chmod +x /home/"$USER"/.bashrc
sudo chmod +x /home/"$USER"/.xprofile

echo "Copying udev files"
sudo cp -r "$ARTIFACT_DIR"/udev/. /etc/udev/rules.d
sudo udevadm control --reload-rules && udevadm trigger

echo "Copying scripts"
sudo cp -r "$ARTIFACT_DIR"/scripts/. /usr/local/bin

echo "Copying cron jobs"
sudo cp -r "$ARTIFACT_DIR"/cron.d/. /etc/cron.d
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
  xfce4-terminal \
  jq > /dev/null

if [ "$HEADLESS" != "true" ]; then
  sudo apt-get -qq install -y lightdm  > /dev/null
fi

echo "Installing Google Chrome"
curl -sSLo google-chrome-stable_current_$ARCH.deb https://dl.google.com/linux/direct/google-chrome-stable_current_$ARCH.deb
sudo apt-get -qq install -y ./google-chrome-stable_current_$ARCH.deb > /dev/null

echo "Installing Git"
sudo apt-get -qq install git > /dev/null
if [ ! -f /home/"$USER"/.ssh/id_rsa ]; then
  echo "Creating ssh key"
  sudo su -c "ssh-keygen -f /home/$USER/.ssh/id_rsa -q -N ''" "$USER"
  echo "TODO: Remember to add public ssh key to GitHub/BitBucket"
fi

echo "Configuring screen mirroring"
git clone https://github.com/schlomo/automirror.git -q > /dev/null
sudo mkdir -p /home/"$USER"/.screenlayout
sudo mv automirror/automirror.sh /home/"$USER"/.screenlayout/automirror.sh
sudo chmod +x /home/"$USER"/.screenlayout/*

echo "Installing Docker"
curl -sSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2> /dev/null
sudo add-apt-repository \
  "deb [arch=$ARCH] https://download.docker.com/linux/$(lsb_release -is | awk '{print tolower($0)}') \
  $(lsb_release -cs) \
  stable"
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y docker-ce docker-ce-cli containerd.io > /dev/null
sudo usermod -aG docker $USER

echo "Installing docker compose"
# Personally, I think docker compose is stupid. However, some repositories think we need it for some reason.
sudo curl -sSL "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "Installing Kubernetes"
curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - > /dev/null 2> /dev/null
if [ ! -f /etc/apt/sources.list.d/kubernetes.list ] || ! grep -q "xenial" /etc/apt/sources.list.d/kubernetes.list; then
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list > /dev/null
fi
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y kubectl > /dev/null
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz"
tar zxvf krew.tar.gz > /dev/null
sudo -H -u "$USER" bash -c 'KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/')" && \
sudo "$KREW" install krew > /dev/null 2> /dev/null && \
sudo "$KREW" install ctx > /dev/null 2> /dev/null && \
sudo "$KREW" install ns > /dev/null 2> /dev/null && \
sudo "$KREW" install oidc-login > /dev/null 2> /dev/null'

echo "Installing Minikube"
curl -sSLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$ARCH \
  && chmod +x minikube
mkdir -p /usr/local/bin/
sudo install minikube /usr/local/bin/
sudo cp "$ARTIFACT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
sudo systemctl daemon-reload
sudo systemctl enable minikube.service

echo "Installing Helm"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh > /dev/null

echo "Installing HashiCorp Vault"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - > /dev/null 2> /dev/null
sudo apt-add-repository --yes --update "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y vault > /dev/null

echo "Installing I3"
if [ "$HEADLESS" != "true" ]; then
  sudo apt-get -qq install i3
else
  sudo DEBIAN_FRONTEND=noninteractive apt install --assume-yes -qq i3 desktop-base
fi
sudo update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/i3 60
if [ "$HEADLESS" != "true" ]; then
  sudo dpkg-reconfigure lightdm
fi
sudo cp "$ARTIFACT_DIR"/systemd/lock.service /lib/systemd/system/lock.service

echo "Installing Visual Studio Code"
if [ ! -f /etc/apt/sources.list.d/vscode.list ] && ! grep -q "vscode" /etc/apt/sources.list; then
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - > /dev/null 2> /dev/null
  sudo add-apt-repository "deb [arch=$ARCH] https://packages.microsoft.com/repos/vscode stable main"
  sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y code > /dev/null
  sudo rm /etc/apt/sources.list.d/vscode.list
fi

echo "Installing Chrome Remote Desktop"
curl -sSLO https://dl.google.com/linux/direct/chrome-remote-desktop_current_$ARCH.deb
sudo dpkg --install chrome-remote-desktop_current_$ARCH.deb > /dev/null
sudo apt-get -qq install --assume-yes --fix-broken
sudo touch /etc/chrome-remote-desktop-session
sudo bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'
if [ "$HEADLES" = "true" ]; then
  sudo systemctl disable lightdm.service
fi
echo "TODO: Remember to add this computer to chrome remote desktop list at https://remotedesktop.google.com/headless"

echo "Installing Golang"
VERSION_REGEX='\"version\":\s*\"([^"]*)\"'
[[ $(curl -sSL 'https://golang.org/dl/?mode=json') =~ $VERSION_REGEX ]]
CURRENT_VERSION="${BASH_REMATCH[1]}"
curl -sSLO https://dl.google.com/go/$CURRENT_VERSION.linux-$ARCH.tar.gz
sudo tar -C /usr/local -xzf $CURRENT_VERSION.linux-$ARCH.tar.gz

echo "Installing Rust"
curl -sSL --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sed 's/main "$@"/main "$@" -y > \/dev\/null 2> \/dev\/null/g' | sh > /dev/null

echo "Installing Ansible"
if ! grep -q "ansible" /etc/apt/sources.list; then
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
  sudo add-apt-repository "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main"
  sudo apt-get -qq update > /dev/null
fi
sudo apt-get -qq install -y ansible

echo "Installing Yubikey"
if [ -z "$(sudo apt-cache search yubikey-manager)" ]; then
  sudo apt-add-repository --yes --update ppa:yubico/stable
  sudo apt-get -qq update > /dev/null
fi
sudo apt-get -qq install -y yubikey-manager libpam-yubico
if [ -z "$(sudo apt-cache search yubico-piv-tool)" ]; then
  # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=926551
  curl -sSlO http://http.us.debian.org/debian/pool/main/y/yubico-piv-tool/libykpiv2_2.1.1-3_amd64.deb
  sudo dpkg -i --force-depends libykpiv2_2.1.1-3_amd64.deb  > /dev/null
  curl -sSLO http://http.us.debian.org/debian/pool/main/y/yubico-piv-tool/yubico-piv-tool_2.1.1-3_amd64.deb
  sudo dpkg -i --force-depends yubico-piv-tool_2.1.1-3_amd64.deb  > /dev/null
fi
sudo apt-get -qq install -y yubico-piv-tool

echo "Installing Protobuf"
sudo apt-get -qq install -y protobuf-compiler

echo "Installing Javascript"
if [ ! -d /home/"$USER"/.nvm ]; then
  sudo mkdir -p /home/"$USER"/.nvm
  sudo git clone https://github.com/nvm-sh/nvm.git /home/"$USER"/.nvm -q
fi

echo "Installing Terraform"
if [ ! -d /home/"$USER"/.tfenv ]; then
  sudo mkdir -p /home/"$USER"/.tfenv
  sudo git clone https://github.com/tfutils/tfenv.git /home/"$USER"/.tfenv -q
  sudo ln -s /home/"$USER"/.tfenv/bin/* /usr/local/bin
fi

if [ "$HAS_RUBY" = "true" ]; then
  echo "Installing Ruby"
  gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB > /dev/null 2> /dev/null
  curl -sSL https://get.rvm.io  | sed 's/rvm_install "$@"/rvm_install "$@" > \/dev\/null 2> \/dev\/null/g' | bash -s stable --ruby > /dev/null
  source /usr/local/rvm/scripts/rvm
  rvm rvmrc warning ignore allGemfiles
fi

echo "Chowning home directory to $USER"
sudo chown -R "$USER" /home/"$USER"

