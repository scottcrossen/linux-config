#!/bin/bash

SCRIPT_DIR="${BASH_SOURCE%/*}"

# Install chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install ./google-chrome-stable_current_amd64.deb

# Install git
apt install git
git config --global user.name "Scott Crossen"
git config --global user.email "scottcrossen42@gmail.com"

# Install bashrc
cp -r "$SCRIPT_DIR"/home ~
chmod +x ~/.bashrc.d
chmod +x ~/.bashrc

# TODO: Install minikube
cp "$SCRIPT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
systemctl daemon-reload
