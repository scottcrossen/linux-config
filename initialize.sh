#!/bin/bash

SCRIPT_DIR="${BASH_SOURCE%/*}"

git config --global user.name "Scott Crossen"
git config --global user.email "scottcrossen42@gmail.com"

cp -r "$SCRIPT_DIR"/home ~
chmod +x ~/.bashrc.d
chmod +x ~/.bashrc

# TODO: Install minikube
cp "$SCRIPT_DIR"/systemd/minikube.service /lib/systemd/system/minikube.service
systemctl daemon-reload
