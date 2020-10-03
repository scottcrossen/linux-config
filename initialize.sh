#!/bin/bash

SCRIPT_DIR="${BASH_SOURCE%/*}"

git config --global user.name "Scott Crossen"
git config --global user.email "scottcrossen42@gmail.com"

cp -r "$SCRIPT_DIR"/home ~
chmod +x ~/.bashrc.d
chmod +x ~/.bashrc
