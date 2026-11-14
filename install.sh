#!/bin/sh
# Installs softwary into a repository.
# Usage: sh install.sh <repo>
#
# Lists every file it will write, then writes them, only inside <repo>.
# Managed files are overwritten; an existing commands.conf is kept.
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
conf=.softwary/config/commands.conf

# Pairs of "source destination", destination relative to the target.
plan="src/templates/softwary softwary
VERSION .softwary/VERSION
src/templates/gitignore .softwary/.gitignore
src/bin/softwary .softwary/bin/softwary"
for lib in "$pkg"/src/lib/*.sh; do
	name=${lib##*/}
	plan="$plan
src/lib/$name .softwary/lib/$name"
done

printf 'softwary %s: installing into %s\n' "$version" "$target"
printf 'Files to write:\n'
printf '%s\n' "$plan" | while read -r _src dest; do
	printf '  %s\n' "$dest"
done
if [ -e "$target/$conf" ]; then
	printf '  %s (exists, kept)\n' "$conf"
else
	printf '  %s\n' "$conf"
fi

printf 'Writing...\n'
printf '%s\n' "$plan" | while read -r src dest; do
	mkdir -p "$target/$(dirname "$dest")"
	cp "$pkg/$src" "$target/$dest"
done
chmod +x "$target/softwary" "$target/.softwary/bin/softwary"
if [ ! -e "$target/$conf" ]; then
	mkdir -p "$target/.softwary/config"
	cp "$pkg/src/templates/commands.conf" "$target/$conf"
fi

printf 'Done. Next: set the commands in %s, then run ./softwary doctor\n' "$conf"
