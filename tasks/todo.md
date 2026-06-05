- [x] Add a non-invasive running-process preflight to PowerShell and Bash scripts.
- [x] Update README and tutorial docs so beginners understand the new warning.
- [x] Run syntax and repository checks.
- [x] Ask whether to close Codex Desktop when it is detected running.
- [x] Update docs for the optional close prompt.
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
