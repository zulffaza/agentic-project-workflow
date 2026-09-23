# shellcheck shell=bash
# pw.config.test.noscope.sh — fixture config with the API-provider axis UNSET (empty array):
# every catalog line is in scope (the "no filtering" fallback rule).
PW_PROVIDERS=(kilo claude cursor)
PW_KILO_API_PROVIDERS=()
