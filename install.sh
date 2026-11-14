#!/bin/sh
# Installs softwary into a repository.
# Usage: sh install.sh <repo>
#
# Lists every file it will write, then writes them, only inside <repo>.
# Managed files are overwritten; existing project-owned config files are kept.
set -eu

pkg=$(cd "$(dirname "$0")" && pwd -P)

if [ $# -ne 1 ]; then
	printf 'usage: sh install.sh <repo>\n' >&2
	exit 2
fi
if [ ! -d "$1" ]; then
	printf 'install: %s is not an existing directory\n' "$1" >&2
	exit 2
fi
target=$(cd "$1" && pwd -P)
version=$(cat "$pkg/VERSION")
# Project-owned files: written once, never overwritten.
owned="commands.conf tools.conf risk.conf"

# Pairs of "source destination", destination relative to the target.
plan="src/templates/softwary softwary
VERSION .softwary/VERSION
src/templates/gitignore .softwary/.gitignore
src/bin/softwary .softwary/bin/softwary"
# Managed trees: every file under these src/ directories is installed.
for dir in lib rules targets skills agents; do
	[ -d "$pkg/src/$dir" ] || continue
	files=$(cd "$pkg/src" && find "$dir" -type f | sort)
	for f in $files; do
		plan="$plan
src/$f .softwary/$f"
	done
done
# Artifact templates: src/templates/artifacts/X -> .softwary/templates/X.
for f in $(cd "$pkg/src/templates/artifacts" && find . -type f | sort); do
	f=${f#./}
	plan="$plan
src/templates/artifacts/$f .softwary/templates/$f"
done

printf 'softwary %s: installing into %s\n' "$version" "$target"
printf 'Files to write:\n'
printf '%s\n' "$plan" | while read -r _src dest; do
	printf '  %s\n' "$dest"
done
for c in $owned; do
	if [ -e "$target/.softwary/config/$c" ]; then
		printf '  .softwary/config/%s (exists, kept)\n' "$c"
	else
		printf '  .softwary/config/%s\n' "$c"
	fi
done

printf 'Writing...\n'
printf '%s\n' "$plan" | while read -r src dest; do
	mkdir -p "$target/$(dirname "$dest")"
	cp "$pkg/$src" "$target/$dest"
done
chmod +x "$target/softwary" "$target/.softwary/bin/softwary"
for c in $owned; do
	if [ ! -e "$target/.softwary/config/$c" ]; then
		mkdir -p "$target/.softwary/config"
		cp "$pkg/src/templates/$c" "$target/.softwary/config/$c"
	fi
done

printf 'Done. Next: set .softwary/config/commands.conf, tools.conf and risk.conf, write architecture/model/system.calm.json (start from .softwary/templates/), run ./softwary sync, then ./softwary doctor\n'
