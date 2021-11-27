#!/usr/bin/env bash
set -e

DIR=$(cd "$(dirname "$0")" && pwd)

case "$OSTYPE" in
drawin*)
  # Mac OSX
  ;;
linux-gnu)
  # GNU/Linux
  sudo apt update
  sudo apt upgrade -y
  sudo apt install python3-pip python-is-python3 -y
  ;;
esac

pip3 install "ansible-lint[community,yamllint]"

export PATH="$HOME/.local/bin:$PATH"

ansible-galaxy collection install community.general
ansible-playbook "$DIR"/site.yml
