# pw.config.test.forge.sh — fixture config for forge-routing tests (point PW_CONFIG_FILE here).
# Maps the harness's forge-plausible repo host to the OTHER CLI, so an exact PW_FORGE_HOSTS entry
# must steer exec/monitor to `gh` instead of the auto-detected `glab`.
PW_PROVIDERS=(kilo claude cursor)
PW_FORGE_HOSTS=(gitlab.example.com=github)
