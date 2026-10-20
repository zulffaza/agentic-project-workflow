# pw.config.test.forge.sh — fixture config for forge-routing tests (point PW_CONFIG_FILE here).
# Maps the harness's forge-plausible repo host to the OTHER CLI, so an exact PW_FORGE_HOSTS entry
# must steer exec/monitor to `gh` instead of the auto-detected `glab`.
PW_PROVIDERS=(kilo claude cursor)
# gitlab.example.com is mapped to the OTHER CLI so the override is observable; github.example.com
# models an enterprise GitHub host that must resolve to gh with explicit repository identity.
PW_FORGE_HOSTS=(gitlab.example.com=github github.example.com=github)
