#!/bin/bash

if [ ! -d "$HOME/coder" ]
then
  # Clone Code Sniffer if it doesn't exist
  echo -e "Installing Coder Sniffer...\n"
  git clone --branch 8.x-2.x http://git.drupal.org/project/coder.git ~/coder
  cd "$HOME/coder"
  composer install
  cd -
else
  # Otherwise make sure Code Sniffer is up to date
  cd "$HOME/coder"
  git pull
  composer install
  cd -
fi

echo 'export PATH=$HOME/coder/vendor/bin:$PATH' >> $BASH_ENV

phpcs --config-set installed_paths ~/coder/coder_sniffer
