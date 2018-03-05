#!/bin/bash

generate_post_data()
{
  cat <<EOF
{
  "body": "${GIT_MESSAGE_TEXT}"
}
EOF
}

send_git_message() {
  curl -H "Authorization: token ${GIT_TOKEN}" -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" $GITHUB_API_URL/issues/$PR_NUMBER/comments
}

prepare_slack_notification() {
if [ -n "${SLACK_HOOK_URL+1}" ]
then
  echo -e "\n${txtylw}Create/Update the secret Webhook URL into a file called secrets.json ${txtrst}"
  echo "{\"slack_url\": \"$SLACK_HOOK_URL\", \"slack_channel\": \"$SLACK_CHANNEL\", \"always_show_text\": \"1\"}" > secrets.json
fi
}

prepare_variables() {

  BUILD_DIR=$(pwd)
  txtred='\033[0;91m' # Red
  txtgrn='\033[0;32m' # Green
  txtylw='\033[1;33m' # Yellow
  txtrst='\033[0m' # Text reset.

  COMMIT_MESSAGE="$(git log -1 --pretty=%B)"
  GITHUB_API_URL="https://api.github.com/repos/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME"
  PANTHEON_SITE_NAME=`git log --format=%B -n 1 | grep -Po ':(\w+):' | awk -F ':' '{print $2}'`
  GIT_MESSAGE_TEXT="";
  # Get the evironment from which to clone the multidev.
  if [ -z "${PANTHEON_FROM_ENV+1}" ]; then
    PANTHEON_FROM_ENV="dev"
  fi
}

check_if_correct_site_name() {
  CORRECT_SITENAME=0
  for name in $PANTHEON_SITE_NAMES
  do
    if [ $name == $PANTHEON_SITE_NAME ]; then
      CORRECT_SITENAME=1
    fi
  done

  if [ $CORRECT_SITENAME == 0 ]; then
    GIT_MESSAGE_TEXT='The sitename is wither missing or is not part of the PANTHEON_SITE_NAMES variable'
    send_git_message
    exit 0
  fi
}

log_into_terminus() {
  echo -e "\n${txtylw}Logging into Terminus ${txtrst}"
  terminus auth:login --machine-token=$PANTHEON_MACHINE_TOKEN
}

prepare_pantheon_folder() {
  cd $HOME

  # Prepare pantheon repo folder.
  if [ ! -d "$HOME/pantheon" ]; then
    git clone "https://$GIT_TOKEN@github.com/$CIRCLE_PROJECT_USERNAME/scu" pantheon
  fi

  cd $HOME/pantheon
  git fetch
  git pull origin master
}

prepare_git_settings() {
  cd $HOME/pantheon
  # Add pantheon upstream as remote upstream
  PANTHEON_UPSTREAM="$pantheon_site_name-upstream"
  PANTHEON_GIT_URL="$(terminus connection:info $pantheon_site_name.$PANTHEON_FROM_ENV --field=git_url)"
  git remote add $PANTHEON_UPSTREAM $PANTHEON_GIT_URL
  git fetch --quiet $PANTHEON_UPSTREAM

  git branch --quiet -D $normalize_branch
  git checkout --quiet -b $normalize_branch $PANTHEON_UPSTREAM/master
}

rsync_repos() {
  # Remove all changeable files from pantheon repo
  echo -e "\n${txtylw}Prepare upstream repo for multidev${txtrst}"
  cd $HOME/pantheon
  if [ -d "$HOME/pantheon/web" ]
  then
    # Remove it without folder sites.
    find web -maxdepth 1 ! -name web ! -name sites | xargs rm -rf
  fi

  rm -rf $HOME/pantheon/config
  rm -rf $HOME/pantheon/vendor
  rm -f $HOME/pantheon/pantheon.yml
  rm -f $HOME/pantheon/composer.json
  rm -f $HOME/pantheon/composer.lock

  mkdir -p vendor
  mkdir -p config

  rm -rf $CIRCLE_WORKING_DIRECTORY/web/sites/default/files
  rm -f $HOME/pantheon/web/sites/default/settings.local.php
  rm -f $CIRCLE_WORKING_DIRECTORY/web/sites/default/settings.local.php

  rsync -ar $CIRCLE_WORKING_DIRECTORY/web/ $HOME/pantheon/web/
  rsync -ar $CIRCLE_WORKING_DIRECTORY/vendor/ $HOME/pantheon/vendor/
  rsync -ar $CIRCLE_WORKING_DIRECTORY/config/ $HOME/pantheon/config/

  cp $CIRCLE_WORKING_DIRECTORY/pantheon.yml .
  cp $CIRCLE_WORKING_DIRECTORY/composer.* .
}

prepare_multidev_environment() {
  cd $HOME/pantheon
  # Get a list of all environments
  PANTHEON_ENVS="$(terminus multidev:list $pantheon_site_name --format=list --field=Name)"

  # Check if we are NOT on the branch deploy
  if [ -n "$CI_PULL_REQUEST" ]
  then
    # Get PR number
    PR_NUMBER=${CI_PULL_REQUEST##*/}

    # Multidev name is the pull request
    normalize_branch="pr$PR_NUMBER"

    MULTIDEV_FOUND=0
    echo -e "\n${txtylw}Checking for the multidev environment ${normalize_branch} via Terminus ${txtrst}"
    while read -r line; do
        if [[ "${line}" == "${normalize_branch}" ]]
        then
          MULTIDEV_FOUND=1
        fi
    done <<< "$PANTHEON_ENVS"

    # If the multidev for this branch is found
    if [[ "$MULTIDEV_FOUND" -eq 1 ]]
    then
      # Send a message
      echo -e "\n${txtylw}Multidev found! ${txtrst}"
    else
      # otherwise, create the multidev branch
      echo -e "\n${txtylw}Multidev not found, creating the multidev branch ${normalize_branch} via Terminus ${txtrst}"
      terminus multidev:create $pantheon_site_name.$PANTHEON_FROM_ENV $normalize_branch
      git fetch
    fi
  fi
}

push_code_to_environment() {
  cd $HOME/pantheon
  git add -A --force .

  echo -e "\n${txtylw}Show what will be committed.${txtrst}"
  echo -e "\n${txtgrn}"
  git commit -m "Circle CI build $CIRCLE_BUILD_NUM by $CIRCLE_USERNAME" -m "$COMMIT_MESSAGE"
  echo -e "\n${txtrst}"

  echo -e "\n${txtgrn}Pushing the ${normalize_branch} branch to Pantheon ${txtrst}"
  git push -u $PANTHEON_UPSTREAM $normalize_branch --force
  ENV_URL=$(terminus env:view --print ${pantheon_site_name}.${normalize_branch})

  # Visit image functionality.
  PANTHEON_SITE_NAME=`php -r "print strtoupper(\"${pantheon_site_name}\");"`
  VISIT="_VISIT_IMAGE"
  temp=$PANTHEON_SITE_NAME$VISIT

  VISIT_IMAGE=${!temp}
  if [ -z $VISIT_IMAGE ]; then
    VISIT_IMAGE=$DEFAULT_VISIT_IMAGE
  fi
  GIT_MESSAGE_TEXT="$GIT_MESSAGE_TEXT \n [![Visit Site]($VISIT_IMAGE)](${ENV_URL})"
}

multidev_environment_cleanup() {
  echo -e "\n${txtylw}Cleaning up multidevs from closed pull requests...${txtrst}"
  cd $CIRCLE_WORKING_DIRECTORY
  while read -r b; do
    if [[ $b =~ ^pr[0-9]+ ]]
    then
      PR_NUMBER_TO_CLEAN=${b#pr}
    else
      echo -e "\n${txtylw}NOT deleting the multidev '$b' since it was created manually ${txtrst}"
      continue
    fi
    echo -e "\n${txtylw}Analyzing the multidev: $b...${txtrst}"
    PR_RESPONSE="$(curl --write-out %{http_code} --silent --output /dev/null $GITHUB_API_URL/pulls/$PR_NUMBER_TO_CLEAN?access_token=$GIT_TOKEN)"
    if [ $PR_RESPONSE -eq 200 ]
    then
      PR_STATE="$(curl $GITHUB_API_URL/pulls/$PR_NUMBER_TO_CLEAN?access_token=$GIT_TOKEN | jq -r '.state')"
      if [ "open" == "$PR_STATE"  ]
      then
        echo -e "\n${txtylw}NOT deleting the multidev '$b' since the pull request is still open ${txtrst}"
      else
        echo -e "\n${txtred}Deleting the multidev for closed pull request #$PR_NUMBER_TO_CLEAN...${txtrst}"
        terminus multidev:delete $pantheon_site_name.$b --delete-branch --yes
      fi
    else
      echo -e "\n${txtred}Invalid pull request number: $PR_NUMBER_TO_CLEAN...${txtrst}"
    fi
  done <<< "$PANTHEON_ENVS"
}

pantheon_folder_cleanup() {
  cd $HOME
  rm -rf pantheon
  prepare_pantheon_folder
}
