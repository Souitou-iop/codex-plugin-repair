- [x] Add a non-invasive running-process preflight to PowerShell and Bash scripts.
- [x] Update README and tutorial docs so beginners understand the new warning.
- [x] Run syntax and repository checks.
- [x] Ask whether to close Codex Desktop when it is detected running.
- [x] Update docs for the optional close prompt.
- [x] Move the Codex Desktop close prompt before the repair confirmation.
- [x] Change README one-line commands to track the latest `main` scripts.
- [x] Diagnose post-update case where previously downloaded plugins still ask to download again.
- [x] Expand repair targets from enabled-only plugins to configured and already-cached plugins.
- [ ] Run local checks and publish the next release.

## Review

- Added a non-invasive running-process warning before config/cache repair.
- Updated beginner-facing docs and release command links for v0.3.12.
- Verified Bash syntax, Bash cancel path, Bash mock repair path, and `git diff --check`.
- PowerShell AST validation needs GitHub Actions because `pwsh` is not installed on this Mac.

## Review v0.3.13 draft

- Added a second confirmation prompt when Codex Desktop is detected running.
- The script attempts to close Codex Desktop only after `y` or `yes`; other plugin processes remain warning-only.
- `CODEX_PLUGIN_REPAIR_YES=1` does not close Codex Desktop unless `CODEX_PLUGIN_REPAIR_CLOSE_CODEX_DESKTOP=1` is also set.
- Updated README/tutorial command links to v0.3.13.

## Review v0.3.14 draft

- Moved the running Codex Desktop prompt before the repair explanation and confirmation.
- The close prompt now explains that closing Codex Desktop is recommended, but continuing is allowed if the user restarts Codex Desktop after repair.
- README one-line commands now use `main` raw links so they automatically fetch the latest script.

## Review v0.3.15 draft

- Fixed macOS Bash process detection so running Codex Desktop is detected by the app binary path instead of `pgrep -x Codex`.
- Updated macOS Chrome native host verification commands to use `Resources/cua_node/bin/node`, matching the June 24 Codex Desktop layout.
- Confirmed the June 24 update symptom locally: config still enabled bundled plugins, while cache needed refresh to browser/chrome 26.616.81150 and computer-use 1.0.829.

## Review v0.3.16 draft

- Found a second June 24 update symptom: plugins that were present in config as disabled or only existed in local cache could still ask to download again.
- Changed repair scope to refresh configured plugins and already-cached plugins without enabling disabled plugins.
- Kept the final failure check limited to `enabled=true` plugins so disabled plugins do not fail the run.
