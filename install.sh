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
for dir in lib rules targets skills agents hooks; do
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

# CI and code-owner templates: src/templates/github/X -> .softwary/templates/X.
# They are only offered here; the setup skill places them under .github/.
for f in $(cd "$pkg/src/templates/github" && find . -type f | sort); do
	f=${f#./}
	plan="$plan
src/templates/github/$f .softwary/templates/$f"
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
	# Replace by rename: a running ./softwary keeps reading its old file.
	cp "$pkg/$src" "$target/$dest.new" || exit 1
	mv -f "$target/$dest.new" "$target/$dest" || exit 1
done
chmod +x "$target/softwary" "$target/.softwary/bin/softwary"
for h in "$target"/.softwary/hooks/*; do
	[ -f "$h" ] && chmod +x "$h"
done
for c in $owned; do
	if [ ! -e "$target/.softwary/config/$c" ]; then
		mkdir -p "$target/.softwary/config"
		cp "$pkg/src/templates/$c" "$target/.softwary/config/$c"
	fi
done

# Git hooks: point core.hooksPath at the managed hooks, unless that would
# displace another hook setup (then `doctor` reports it).
hooks_path=.softwary/hooks
set_hooks_path() {
	top=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null) || top=
	if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$target" ]; then
		printf 'hooks: not a git repository root; core.hooksPath not set\n'
		return 0
	fi
	current=$(git -C "$target" config --get core.hooksPath 2>/dev/null) || current=
	if [ "$current" = "$hooks_path" ]; then
		printf 'hooks: core.hooksPath already %s\n' "$hooks_path"
		return 0
	fi
	if [ -n "$current" ]; then
		printf "hooks: core.hooksPath is '%s'; kept\n" "$current"
		return 0
	fi
	shown=$(cd "$target" && git rev-parse --git-path hooks)
	case $shown in
	/*) dir=$shown ;;
	*) dir=$target/$shown ;;
	esac
	for h in "$dir"/*; do
		[ -f "$h" ] || continue
		case ${h##*/} in
		*.sample) ;;
		*)
			printf 'hooks: %s/%s is not a sample; kept\n' "$shown" "${h##*/}"
			return 0
			;;
		esac
	done
	git -C "$target" config core.hooksPath "$hooks_path"
	printf 'hooks: core.hooksPath set to %s\n' "$hooks_path"
}
set_hooks_path

printf 'Done. Next: set .softwary/config/commands.conf, tools.conf and risk.conf, write architecture/model/system.calm.json (start from .softwary/templates/), run ./softwary sync, then ./softwary doctor\n'
