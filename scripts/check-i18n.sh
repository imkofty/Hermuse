#!/bin/bash
# check-i18n.sh — CI check: every i18n key used in this repo must be
# translated in ALL five languages (en, id, ms, vi, hi).
#
# Definitions come from lib/i18n.sh (bash `case` branches: en) / ms) /
# vi) / hi) / *) where the *) branch is Indonesian, the default) and
# from lib/i18n.mjs (the STRINGS = { en: {...}, ms: {...}, id: {...},
# vi: {...}, hi: {...} } object).
# Usage is scanned statically: `t <keyname>` in *.sh, `t("<keyname>")` in *.mjs
# (there is no dynamic key usage in this repo — verified 2026-10-12).
#
# Exit 0: every used key is fully translated. Keys that are defined but
# never used are warnings only.
# Exit 1: at least one used key is missing a translation (listed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LANGS="en id ms vi hi"

# --- keys defined per language in lib/i18n.sh ---
def_sh() { # $1 = en|id|ms|vi|hi
  awk -v lang="$1" '
    /^[[:space:]]*en\)[[:space:]]*$/ { cur="en"; next }
    /^[[:space:]]*ms\)[[:space:]]*$/ { cur="ms"; next }
    /^[[:space:]]*vi\)[[:space:]]*$/ { cur="vi"; next }
    /^[[:space:]]*hi\)[[:space:]]*$/ { cur="hi"; next }
    /^[[:space:]]*\*\)[[:space:]]*$/ { cur="id"; next }
    cur==lang && /^[[:space:]]*[a-z][a-z_0-9]*\)[[:space:]]*fmt=/ {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/\).*$/, "", line)
      print line
    }
  ' lib/i18n.sh | sort -u
}

# --- keys defined per language in lib/i18n.mjs ---
# Handles both the repo's multi-line style and single-line blocks.
def_mjs() { # $1 = en|id|ms|vi|hi
  awk -v lang="$1" '
    function emit_inline(s,   n, parts, i, k, rest) {
      n = split(s, parts, ",")
      for (i = 1; i <= n; i++) {
        if (match(parts[i], /[a-z][a-z_0-9]*/)) {
          k = substr(parts[i], RSTART, RLENGTH)
          rest = substr(parts[i], RSTART + RLENGTH)
          if (rest ~ /^[[:space:]]*:/) print k
        }
      }
    }
    /^[[:space:]]*(en|ms|id|vi|hi)[[:space:]]*:[[:space:]]*\{/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*:.*$/, "", line)
      cur = line
      rest = $0
      sub(/^[^{]*\{/, "", rest)
      if (rest ~ /\}/) { sub(/\}[^}]*$/, "", rest); single = 1 } else { single = 0 }
      if (cur == lang) emit_inline(rest)
      if (single) cur = ""
      next
    }
    /^[[:space:]]*\}[;,]?[[:space:]]*$/ { cur = ""; next }
    cur == lang && /^[[:space:]]*[a-z][a-z_0-9]*[[:space:]]*:/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*:.*$/, "", line)
      print line
    }
  ' lib/i18n.mjs | sort -u
}

# --- keys used via t() in shell scripts (excluding the helpers and this checker itself) ---
used_sh() {
  grep -rhoE --include='*.sh' --exclude='i18n.sh' --exclude='check-i18n.sh' --exclude-dir='.git' \
    -e '\bt[[:space:]]+[a-z][a-z_0-9]*' . 2>/dev/null \
    | sed -E 's/^t[[:space:]]+//' | sort -u || true
}

# --- keys used via t("key") in node scripts (excluding the helper itself) ---
used_mjs() {
  grep -rhoE --include='*.mjs' --exclude='i18n.mjs' --exclude-dir='.git' \
    -e '\bt\(["'"'"'][a-z][a-z_0-9]*["'"'"']' . 2>/dev/null \
    | sed -E 's/^t\(["'"'"']//; s/["'"'"']$//' | sort -u || true
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for l in $LANGS; do
  { def_sh "$l"; def_mjs "$l"; } | sort -u > "$tmpdir/def_$l"
done
{ used_sh; used_mjs; } | sort -u | grep -v '^$' > "$tmpdir/used" || true

echo "i18n check: $(wc -l < "$tmpdir/used") keys used;"
for l in $LANGS; do
  echo "  defined [$l]: $(wc -l < "$tmpdir/def_$l") keys"
done

fail=0
while read -r key; do
  missing=""
  for l in $LANGS; do
    grep -qx "$key" "$tmpdir/def_$l" 2>/dev/null || missing="$missing $l"
  done
  if [ -n "$missing" ]; then
    echo "FAIL: key '$key' missing translation for:$missing"
    fail=1
  fi
done < "$tmpdir/used"

# defined-but-unused keys are warnings only — never fail the check
{ cat "$tmpdir"/def_*; } | sort -u > "$tmpdir/def_all"
while read -r key; do
  grep -qx "$key" "$tmpdir/used" 2>/dev/null \
    || echo "warn: key '$key' defined but never used"
done < "$tmpdir/def_all"

if [ "$fail" -eq 1 ]; then
  echo "i18n check FAILED" >&2
  exit 1
fi
echo "i18n check OK"
