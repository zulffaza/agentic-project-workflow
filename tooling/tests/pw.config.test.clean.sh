# shellcheck shell=bash
# pw.config.test.clean.sh — the hermetic "clean machine" global config.
# Deliberately assigns NOTHING: sourcing it is equivalent to a missing pw.config.sh
# (all bundle defaults apply, no providers enabled by config, no role cells). The
# harness exports it as the PW_CONFIG_FILE default so fixture builds and case runs
# never read the maintainer's real pw.config.sh — live global cells need not resolve
# against the fixture shim catalogs (machine-independence rule, docs/testing.md).
# Cases pinning a specific config keep it: an explicitly exported PW_CONFIG_FILE wins.
