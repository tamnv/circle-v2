#!/bin/bash

comment=""
file=""
line=0

generate_post_data() {
  cat <<EOF
{
  "body": $comment,
  "commit_id": "${CIRCLE_SHA1}",
  "path": "${file}",
  "position": $line
}
EOF
}

# PHPCS_RESULT="$(phpcs --standard=Drupal --extensions=php,module,inc,install,test,profile,theme,css,info,txt,md web/modules web/themes/ --ignore=web/modules/contrib --ignore=web/themes/custom/spcs/pattern-lab --ignore=web/themes/custom/spcs/README.md --ignore=web/themes/custom/spcs/css --ignore=web/themes/contrib)"

echo "${PHPCS_RESULT}"

STR_ERROR="ERROR"

if echo "$PHPCS_RESULT" | grep -q "$STR_ERROR"; then
  if [ -z "${CI_PULL_REQUEST+1}" ]
  then
    exit 0
  fi

  PR_NUMBER=${CI_PULL_REQUEST##*/}

  # PHPCS_CSV="$(phpcs --standard=Drupal --extensions=php,module,inc,install,test,profile,theme,css,info,txt,md web/modules/custom web/themes/ --ignore=web/modules/contrib --report=csv --ignore=web/themes/custom/spcs/pattern-lab --ignore=web/themes/custom/spcs/README.md --ignore=web/themes/custom/spcs/css --ignore=web/themes/contrib)"
  CURRENT_DIR=$(pwd)
  POST_URL="https://api.github.com/repos/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/pulls/$PR_NUMBER/comments"
  while IFS=',' read -r f1 f2 f3 f4 f5 f6 f7 f8; do
    if [ "File" == "$f1"  ]; then
      continue
    fi

    temp="${f1%\"}"
    temp="${temp#\"}"
    file="${temp#$CURRENT_DIR/}"

    comment=$f5
    line=$f2

    curl -H "Authorization: token ${GIT_TOKEN}" --request POST --data "$(generate_post_data)" $POST_URL
  done <<< "$PHPCS_CSV"
  exit 1
fi
