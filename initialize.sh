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
BLUE='\033[0;34m'
NC='\033[0m'
cd $TEMP_DIR

if [ -z "$USER" ] || [ -z "$USER_FULLNAME" ] || [ -z "$USER_EMAIL" ]; then
  echo -e "${BLUE}Usage is: $0 <user> \"<first name> <last name>\" <email>$NC"
  exit 1
fi

if [[ $(uname -m) = x86_64 ]]; then
  ARCH="amd64"
else
  echo -e "${BLUE}Unknown architecture \"$(uname -m)\"$NC"
  exit 1
fi

HEADLESS=false
HAS_RUBY=false
for EXTRA_ARG in "${@:4}"; do
  if [ "$EXTRA_ARG" = "--headless" ]; then
    HEADLESS=true
  elif [ "$EXTRA_ARG" = "--has_ruby" ]; then
    HAS_RUBY=true
  else
    echo -e "${BLUE}Unknown argument $EXTRA_ARG$NC"
    exit 1
  fi
done

function replace_with_user_details {
  ALL_FILES_IN_DIR=($(find ${1:-"."} -type f))
  for FILE in "${ALL_FILES_IN_DIR[@]}"; do
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

echo -e "${BLUE}Creating user $USER$NC"
sudo useradd -m $USER > /dev/null 2> /dev/null
sudo usermod -aG video $USER > /dev/null 2> /dev/null
groupadd libvert > /dev/null 2> /dev/null
groupadd chrome-remote-desktop > /dev/null 2> /dev/null
sudo usermod -aG libvert $USER > /dev/null 2> /dev/null
sudo usermod -aG sudo $USER > /dev/null 2> /dev/null
sudo usermod -aG chrome-remote-desktop $USER > /dev/null 2> /dev/null
if [ "$(sudo passwd --status "$USER" | awk '{print $2}')" != "P" ]; then
  echo -e "${BLUE}Setting user password$NC"
  sudo passwd "$USER"
fi

echo -e "${BLUE}Setting timezone$NC"
sudo timedatectl set-timezone America/Los_Angeles

echo -e "${BLUE}Copying and chowning files$NC"
mkdir -p linux-config
ARTIFACT_DIR="$(pwd)"/linx-config
sudo cp -r "$SCRIPT_DIR" "$ARTIFACT_DIR"
sudo chown -R "$USER" "$ARTIFACT_DIR"
replace_with_user_details "$ARTIFACT_DIR"

echo -e "${BLUE}Copying dotfiles$NC"
sudo cp -r "$ARTIFACT_DIR"/home/. ./home/
sudo cp -r ./home/. /home/"$USER"/
sudo chmod +x -R /home/"$USER"/.bashrc.d
sudo chmod +x /home/"$USER"/.bashrc
sudo chmod +x /home/"$USER"/.xprofile
# The ssh key has not been added yet. We need to use https for everything
sudo rm /home/"$USER"/.gitconfig

echo -e "${BLUE}Copying udev files$NC"
sudo cp -r "$ARTIFACT_DIR"/udev/. /etc/udev/rules.d
sudo udevadm control --reload-rules && sudo udevadm trigger

echo -e "${BLUE}Copying scripts$NC"
sudo cp -r "$ARTIFACT_DIR"/scripts/. /usr/local/bin

echo -e "${BLUE}Copying cron jobs$NC"
sudo cp -r "$ARTIFACT_DIR"/cron.d/. /etc/cron.d
sudo systemctl restart cron

echo -e "${BLUE}Installing basic packages$NC"
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y \
  apt-transport-https \
  gnupg \
  gnupg2 \
  curl \
  cmake \
  libssl-dev \
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
  fzf \
  dnsutils \
  unzip \
  inotify-tools \
  make \
  libnss3-tools \
  build-essential \
  jq > /dev/null

if [ "$HEADLESS" != "true" ]; then
  sudo apt-get -qq install -y lightdm  > /dev/null
fi

echo -e "${BLUE}Installing Google Chrome$NC"
curl -sSLo google-chrome-stable_current_$ARCH.deb https://dl.google.com/linux/direct/google-chrome-stable_current_$ARCH.deb
sudo apt-get -qq install -y ./google-chrome-stable_current_$ARCH.deb > /dev/null

echo -e "${BLUE}Installing Git$NC"
sudo apt-get -qq install git > /dev/null
if [ ! -f /home/"$USER"/.ssh/id_rsa ]; then
  echo "Creating ssh key"
  sudo su -c "ssh-keygen -f /home/$USER/.ssh/id_rsa -q -N ''" "$USER"
  echo "TODO: Remember to add public ssh key to GitHub/BitBucket"
fi

echo -e "${BLUE}Configuring screen mirroring$NC"
git clone https://github.com/schlomo/automirror.git -q > /dev/null
sudo mkdir -p /home/"$USER"/.screenlayout
sudo mv automirror/automirror.sh /home/"$USER"/.screenlayout/automirror.sh
sudo chmod +x /home/"$USER"/.screenlayout/*

echo -e "${BLUE}Installing Docker$NC"
curl -sSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2> /dev/null
sudo add-apt-repository \
  "deb [arch=$ARCH] https://download.docker.com/linux/$(lsb_release -is | awk '{print tolower($0)}') \
  $(lsb_release -cs) \
  stable"
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y docker-ce docker-ce-cli containerd.io > /dev/null
sudo usermod -aG docker $USER

echo -e "${BLUE}Installing docker compose$NC"
# Personally, I think docker compose is stupid. However, some repositories think we need it for some reason.
sudo curl -sSL "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo -e "${BLUE}Installing Kubernetes$NC"
curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - > /dev/null 2> /dev/null
if [ ! -f /etc/apt/sources.list.d/kubernetes.list ] || ! grep -q "xenial" /etc/apt/sources.list.d/kubernetes.list; then
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list > /dev/null
fi
sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y kubectl > /dev/null

echo -e "${BLUE}Installing concourse fly CLI"
curl -sSL https://api.github.com/repos/concourse/concourse/releases/latest | grep "browser_download_url.*fly.*$(uname -s | tr '[:upper:]' '[:lower:]')-$ARCH.tgz\"" | cut -d : -f 2,3 | tr -d "\" " | xargs curl -sSLo fly.tgz
sudo tar -C /usr/local/bin -zxvf fly.tgz > /dev/null

echo -e "${BLUE}Installing Minikube$NC"
curl -sSLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$ARCH \
  && chmod +x minikube
mkdir -p /usr/local/bin/
sudo install minikube /usr/local/bin/
# sudo cp "$ARTIFACT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
# sudo systemctl daemon-reload
# sudo systemctl enable minikube.service

echo -e "${BLUE}Installing sops$NC"
curl -sSL https://api.github.com/repos/mozilla/sops/releases/latest  | grep "browser_download_url.*$(uname -s | tr '[:upper:]' '[:lower:]')"  | cut -d : -f 2,3 | tr -d "\" " | xargs curl -sSLo sops
sudo chmod +x sops
sudo install sops /usr/local/bin/

echo -e "${BLUE}Installing Helm$NC"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
sudo chmod 700 get_helm.sh
./get_helm.sh > /dev/null
curl -sSL https://api.github.com/repos/roboll/helmfile/releases/latest | grep "browser_download_url.*$(uname -s | tr '[:upper:]' '[:lower:]')_$ARCH" | cut -d : -f 2,3 | tr -d "\" " | xargs curl -sSLo helmfile
sudo chmod +x helmfile
sudo install helmfile /usr/local/bin/
sudo -H -u "$USER" bash -c 'helm plugin install https://github.com/databus23/helm-diff > /dev/null 2> /dev/null'
sudo -H -u "$USER" bash -c 'helm plugin install https://github.com/jkroepke/helm-secrets > /dev/null 2> /dev/null'

echo -e "${BLUE}Installing HashiCorp Vault$NC"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - > /dev/null 2> /dev/null
sudo apt-add-repository --yes --update "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y vault > /dev/null

echo -e "${BLUE}Installing I3$NC"
if [ "$HEADLESS" != "true" ]; then
  sudo apt-get -qq install -y i3
else
  sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y i3 desktop-base
fi
sudo update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/i3 60
if [ "$HEADLESS" != "true" ]; then
  sudo dpkg-reconfigure lightdm
fi
sudo cp "$ARTIFACT_DIR"/systemd/lock.service /lib/systemd/system/lock.service
sudo systemctl daemon-reload
sudo systemctl start lock.service

echo -e "${BLUE}Installing Visual Studio Code$NC"
if [ ! -f /etc/apt/sources.list.d/vscode.list ] && ! grep -q "vscode" /etc/apt/sources.list; then
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - > /dev/null 2> /dev/null
  sudo add-apt-repository "deb [arch=$ARCH] https://packages.microsoft.com/repos/vscode stable main"
  sudo apt-get -qq update > /dev/null && sudo apt-get -qq install -y code > /dev/null
  sudo rm /etc/apt/sources.list.d/vscode.list
fi

echo -e "${BLUE}Installing Chrome Remote Desktop$NC"
curl -sSLO https://dl.google.com/linux/direct/chrome-remote-desktop_current_$ARCH.deb
sudo dpkg --install chrome-remote-desktop_current_$ARCH.deb > /dev/null
sudo apt-get -qq install --assume-yes --fix-broken
sudo touch /etc/chrome-remote-desktop-session
sudo bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'
if [ "$HEADLES" = "true" ]; then
  sudo systemctl disable lightdm.service
fi
echo "TODO: Remember to add this computer to chrome remote desktop list at https://remotedesktop.google.com/headless"

echo -e "${BLUE}Installing Golang$NC"
VERSION_REGEX='\"version\":\s*\"([^"]*)\"'
[[ $(curl -sSL 'https://golang.org/dl/?mode=json') =~ $VERSION_REGEX ]]
CURRENT_VERSION="${BASH_REMATCH[1]}"
curl -sSLO https://dl.google.com/go/$CURRENT_VERSION.linux-$ARCH.tar.gz
sudo tar -C /usr/local -xzf $CURRENT_VERSION.linux-$ARCH.tar.gz

echo -e "${BLUE}Installing Rust$NC"
sudo -H -u "$USER" bash -c 'curl -sSL --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sed "s/main "$@"/main "$@" -y > \/dev\/null 2> \/dev\/null/g" | sh > /dev/null'
sudo -H -u "$USER" bash -c "/home/$USER/.cargo/bin/rustup install stable"

echo -e "${BLUE}Installing Ansible$NC"
if ! grep -q "ansible" /etc/apt/sources.list; then
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
  sudo add-apt-repository "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main"
  sudo apt-get -qq update > /dev/null
fi
sudo apt-get -qq install -y ansible

echo -e "${BLUE}Installing Yubikey$NC"
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

echo -e "${BLUE}Installing Protobuf$NC"
sudo apt-get -qq install -y protobuf-compiler

echo -e "${BLUE}Installing Terraform$NC"
if [ ! -d /home/"$USER"/.tfenv ]; then
  sudo mkdir -p /home/"$USER"/.tfenv
  sudo git clone https://github.com/tfutils/tfenv.git /home/"$USER"/.tfenv -q
  sudo ln -s /home/"$USER"/.tfenv/bin/* /usr/local/bin
fi

if [ "$HAS_RUBY" = "true" ]; then
  echo -e "${BLUE}Installing Ruby$NC"
  gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB > /dev/null 2> /dev/null
  curl -sSL https://get.rvm.io  | sed 's/rvm_install "$@"/rvm_install "$@" > \/dev\/null 2> \/dev\/null/g' | bash -s stable --ruby > /dev/null
  source /usr/local/rvm/scripts/rvm
  rvm rvmrc warning ignore allGemfiles
fi

echo -e "${BLUE}Installing gcloud$NC"

if [ ! -f /etc/apt/sources.list.d/google-cloud-sdk.list ]; then
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
fi
sudo apt-get update && sudo apt-get install google-cloud-sdk

echo -e "${BLUE}Chowning home directory to $USER$NC"
sudo chown -R "$USER" /home/"$USER"

echo -e "${BLUE}Installing Javascript$NC"
if [ ! -d /home/"$USER"/.nvm ]; then
  sudo mkdir -p /home/"$USER"/.nvm
  sudo git clone https://github.com/nvm-sh/nvm.git /home/"$USER"/.nvm -q
  sudo chown -R "$USER" /home/"$USER"/.nvm
  sudo -H -u "$USER" bash -c "source /home/$USER/.nvm/nvm.sh && \
  nvm install --lts && \
  nvm use --lts && \
  npm install --global yarn"
fi

echo -e "${BLUE}Installing krew$NC"
sudo -H -u "$USER" bash -c 'cd "$(mktemp -d)" && export PATH="${PATH}:${HOME}/.krew/bin" && \
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz" && \
tar zxvf krew.tar.gz && KREW=./krew-"$(uname | tr "[:upper:]" "[:lower:]")"_"$(uname -m | sed -e "s/x86_64/amd64/" -e "s/arm.*$/arm/")" && \
"$KREW" install krew && \
"$KREW" install ctx && \
"$KREW" install ns && \
"$KREW" install oidc-login'

echo -e "${BLUE}Adding .gitconfig$NC"
sudo cp -r "$ARTIFACT_DIR"/home/.gitconfig /home/"$USER"/.gitconfig
sudo chown "$USER" /home/"$USER"/.gitconfig

echo -e "${BLUE}Finished$NC"
