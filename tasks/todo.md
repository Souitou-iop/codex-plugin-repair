- [x] Add a non-invasive running-process preflight to PowerShell and Bash scripts.
- [x] Update README and tutorial docs so beginners understand the new warning.
- [x] Run syntax and repository checks.

## Review

- Added a non-invasive running-process warning before config/cache repair.
- Updated beginner-facing docs and release command links for v0.3.12.
- Verified Bash syntax, Bash cancel path, Bash mock repair path, and `git diff --check`.
- PowerShell AST validation needs GitHub Actions because `pwsh` is not installed on this Mac.
