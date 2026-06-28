#!/usr/bin/env bash
# Regenerate docs/content.md and docs/core.md from the in-game changelog
# (src/lua/GUIBetaBalanceChangelogData.lua). Run from anywhere.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$script_dir/gen-changelog.py"
