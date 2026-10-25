# shellcheck shell=bash
# pw.config.test.readiness.sh — fixture config for draft-readiness cases. The harness forge host
# must be registered explicitly (its path shape is GitLab, so the forge value must stay gitlab).
PW_PROVIDERS=(kilo)
PW_FORGE_HOSTS=(gitlab.example.com=gitlab)
