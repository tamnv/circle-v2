#!/bin/bash

cd scripts
source functions.sh

pantheon_site_name="${CIRCLE_STAGE/-multidev/}"

prepare_variables
log_into_terminus
prepare_pantheon_folder
prepare_multidev_environment
prepare_git_settings
rsync_repos
prepare_slack_notification
push_code_to_environment
multidev_environment_cleanup
send_git_message
