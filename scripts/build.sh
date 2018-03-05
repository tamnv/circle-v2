#!/bin/bash

BUILD_DIR=$(pwd)
JSON=composer.json
EXE=composer

txtred='\033[0;91m' # Red
txtgrn='\033[0;32m' # Green
txtylw='\033[1;33m' # Yellow
txtrst='\033[0m' # Text reset.

# CI options
export COMPOSER_DISCARD_CHANGES=1
export COMPOSER_NO_INTERACTION=1

if [ ! -f "$JSON" ]
then
  echo ${txtred}Error: No $JSON found ${txtrst}
  exit 1
fi

FOUND=`which $EXE`
COMPOSER_PARMS="--no-ansi --no-dev --no-interaction --optimize-autoloader --no-progress --prefer-dist"

# Install Composer dependencies
echo -e "\n${txtylw}Invoking: $FOUND install $COMPOSER_PARMS ${txtrst}"
$FOUND install $COMPOSER_PARMS
$FOUND prepare-for-pantheon

# generate styleguide from pattern lab
for dir in $(find $BUILD_DIR/web/themes/custom/ -maxdepth 1 -type d); do
  if [ -d "$dir/pattern-lab" ]
  then
    cd "$dir/pattern-lab"
    M | $FOUND install --no-dev
    php core/console --generate

    echo -e "\n${txtylw}Delete vendor ${txtrst}"
    rm -rf vendor
  fi
done
