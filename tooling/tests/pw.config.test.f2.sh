# shellcheck shell=bash
# pw.config.test.f2.sh — fixture config for the project-doctor F2 walk: the ONLY enabled
# Agent Provider is the fixture's own `kilotest`, so produced-by / pin-membership checks
# validate against a deterministic list (F2 fixtures pin everything to kilotest/test-model).
PW_PROVIDERS=(kilotest)
PW_KILO_API_PROVIDERS=()
