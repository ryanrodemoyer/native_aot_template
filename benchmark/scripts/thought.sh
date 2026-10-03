#!/usr/bin/env bash
# Appends a timestamped, hash-chained entry to submission/THOUGHTS.md.
# Benchmark agents MUST use this script (or thought.ps1) for every THOUGHTS.md entry.
# Each entry records the SHA-256 of the file as it was before the append, so hand edits break the chain.
set -euo pipefail

CATEGORIES="start plan decision attempt failure fix pivot ci note end"

usage() {
  cat >&2 <<EOF
Usage:
  benchmark/scripts/thought.sh <category> <message...>
  printf 'multi-line\nmessage\n' | benchmark/scripts/thought.sh <category> -
  benchmark/scripts/thought.sh --verify

Categories: $CATEGORIES
EOF
  exit 2
}

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -c1-16; else shasum -a 256 | cut -c1-16; fi
}

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: run this inside your submission worktree" >&2; exit 1; }
file="$root/submission/THOUGHTS.md"
header_re='^## [0-9TZ:-]+ \| [a-z]+ \| HEAD [0-9a-z]+ \| chain ([0-9a-f]{16})$'

verify() {
  [ -f "$file" ] || { echo "error: $file not found" >&2; exit 1; }
  local tmp n=0 bad=0 line
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ $header_re ]]; then
      n=$((n + 1))
      if [ "$(sha < "$tmp")" != "${BASH_REMATCH[1]}" ]; then
        echo "BROKEN chain at entry $n: $line" >&2
        bad=1
      fi
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  if [ "$bad" -eq 0 ]; then echo "OK: $n entries, chain intact"; else exit 1; fi
}

[ $# -ge 1 ] || usage
if [ "$1" = "--verify" ]; then verify; exit 0; fi
[ $# -ge 2 ] || usage

category=$1; shift
case " $CATEGORIES " in *" $category "*) ;; *) echo "error: unknown category '$category'" >&2; usage ;; esac

if [ "$1" = "-" ]; then message=$(cat); else message="$*"; fi
message=$(printf '%s' "$message" | tr -d '\r' | sed 's/^#/\\#/')
[ -n "${message//[[:space:]]/}" ] || { echo "error: empty message" >&2; exit 2; }

mkdir -p "$(dirname "$file")"
if [ ! -f "$file" ]; then
  printf '# THOUGHTS\n\nAppend-only log written by `benchmark/scripts/thought.sh`. Do not edit by hand.\n\n' > "$file"
fi
if [ "$category" = "start" ] && grep -Eq '^## .* \| start \| ' "$file"; then
  echo "error: a 'start' entry already exists" >&2; exit 2
fi

chain=$(sha < "$file")
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
head=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo none)
printf '## %s | %s | HEAD %s | chain %s\n\n%s\n\n' "$ts" "$category" "$head" "$chain" "$message" >> "$file"
echo "logged [$ts] $category"
