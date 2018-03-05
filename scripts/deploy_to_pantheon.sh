#!/bin/bash

cd scripts
source functions.sh

echo -e "\n${txtgrn}Pushing the master branch to Github Upstream ${txtrst}"
prepare_pantheon_folder
rsync_repos

cd $HOME/pantheon
git add -A --force .
git commit -m "Circle CI build $CIRCLE_BUILD_NUM by $CIRCLE_USERNAME" -m "$COMMIT_MESSAGE"
git push -u origin master --force
