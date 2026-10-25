# shellcheck shell=bash
# pw.config.test.sh — fixture config for provider-scope tests (point PW_CONFIG_FILE here).
# Mirrors the nested-BYOK migration case: the gateway is reachable ONLY through the
# `kilo/alibaba-token-plan` prefix — `kilo` alone and `command_code` are out of scope.
PW_PROVIDERS=(kilo claude cursor)
PW_KILO_API_PROVIDERS=(kilo/alibaba-token-plan)
# Fixture forge host (path shape is GitLab, so the exact entry must stay gitlab).
PW_FORGE_HOSTS=(gitlab.example.com=gitlab)
