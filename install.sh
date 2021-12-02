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
  sudo apt install build-essential procps curl file git -y
  ;;
esac

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

case "$OSTYPE" in
drawin*)
  # Mac OSX
  ;;
linux-gnu)
  # GNU/Linux
  export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
  ;;
esac

brew install ansible-lint --force

ansible-galaxy collection install community.general
ansible-playbook "$DIR"/site.yml
