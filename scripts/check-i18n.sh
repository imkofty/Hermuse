#!/bin/bash
# check-i18n.sh — CI check: every i18n key used in this repo must be
# translated in ALL six languages (en, id, ms, vi, hi, ja), validated
# SEPARATELY per runtime:
#
#   - Bash runtime: keys used via the bash helper in *.sh must be
#     defined in lib/i18n.sh for every language (bash `case` branches:
#     en) / ms) / vi) / hi) / ja) / *) where the *) branch is Indonesian,
#     the default).
#   - JS runtime: keys used via the JS helper in *.mjs must be defined
#     in lib/i18n.mjs for every language (the STRINGS object).
#
# The two definition sets are never merged: a key missing from one
# runtime cannot be covered by the other runtime's definitions.
#
# Value integrity is also enforced per runtime: for every defined key,
# in every language, the value must be non-empty and contain the same
# number of %s placeholders as the English (en) reference value of the
# same runtime. (Literal command/path/URL equality is NOT checked —
# some examples are intentionally localized.)
#
# Usage is scanned statically (there is no dynamic key usage in this
# repo — verified 2026-10-12).
#
# Exit 0: every used key is fully translated in its own runtime and
# all values pass integrity. Keys defined but never used are warnings.
# Exit 1: at least one failure (each is listed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LANGS="en id ms vi hi ja"

# --- values per language in lib/i18n.sh ---
# Prints one line per definition: key <TAB> %s-count <TAB> empty(0|1)
vals_sh() { # $1 = en|id|ms|vi|hi
  awk -v lang="$1" '
    /^[[:space:]]*en\)[[:space:]]*$/ { cur="en"; next }
    /^[[:space:]]*ms\)[[:space:]]*$/ { cur="ms"; next }
    /^[[:space:]]*vi\)[[:space:]]*$/ { cur="vi"; next }
    /^[[:space:]]*hi\)[[:space:]]*$/ { cur="hi"; next }
    /^[[:space:]]*ja\)[[:space:]]*$/ { cur="ja"; next }
    /^[[:space:]]*\*\)[[:space:]]*$/ { cur="id"; next }
    cur==lang && /^[[:space:]]*[a-z][a-z_0-9]*\)[[:space:]]*fmt=/ {
      line = $0
      k = line; sub(/^[[:space:]]*/, "", k); sub(/\).*$/, "", k)
      v = line; sub(/^.*fmt="/, "", v); sub(/"[[:space:]]*;;[[:space:]]*$/, "", v)
      n = gsub(/%s/, "%s", v)
      print k "\t" n "\t" (v == "" ? 1 : 0)
    }
  ' lib/i18n.sh | sort -u
}

# --- values per language in lib/i18n.mjs ---
# Same output shape as vals_sh. Handles both the repo's multi-line
# style and single-line blocks (values may contain commas).
vals_mjs() { # $1 = en|id|ms|vi|hi
  awk -v lang="$1" '
    function emit_inline(s,   rest, k, v, n) {
      rest = s
      while (match(rest, /[a-z][a-z_0-9]*[[:space:]]*:[[:space:]]*"/)) {
        k = substr(rest, RSTART, RLENGTH)
        sub(/[[:space:]]*:.*$/, "", k)
        rest = substr(rest, RSTART + RLENGTH)
        if (match(rest, /"/)) { v = substr(rest, 1, RSTART - 1); rest = substr(rest, RSTART + 1) }
        else { v = rest; rest = "" }
        n = gsub(/%s/, "%s", v)
        print k "\t" n "\t" (v == "" ? 1 : 0)
      }
    }
    /^[[:space:]]*(en|ms|id|vi|hi|ja)[[:space:]]*:[[:space:]]*\{/ {
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
      k = line; sub(/^[[:space:]]*/, "", k); sub(/[[:space:]]*:.*$/, "", k)
      v = line; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
      n = gsub(/%s/, "%s", v)
      print k "\t" n "\t" (v == "" ? 1 : 0)
    }
  ' lib/i18n.mjs | sort -u
}

# --- keys used via the bash helper in shell scripts (excluding the
# helper and this checker itself) ---
used_sh() {
  grep -rhoE --include='*.sh' --exclude='i18n.sh' --exclude='check-i18n.sh' --exclude-dir='.git' \
    -e '\bt[[:space:]]+[a-z][a-z_0-9]*' . 2>/dev/null \
    | sed -E 's/^t[[:space:]]+//' | sort -u || true
}

# --- keys used via the JS helper in node scripts (excluding the
# helper itself) ---
used_mjs() {
  grep -rhoE --include='*.mjs' --exclude='i18n.mjs' --exclude-dir='.git' \
    -e '\bt\(["'"'"'][a-z][a-z_0-9]*["'"'"']' . 2>/dev/null \
    | sed -E 's/^t\(["'"'"']//; s/["'"'"']$//' | sort -u || true
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for l in $LANGS; do
  vals_sh  "$l" > "$tmpdir/sh_vals_$l"
  vals_mjs "$l" > "$tmpdir/mjs_vals_$l"
  cut -f1 "$tmpdir/sh_vals_$l"  | sort -u > "$tmpdir/sh_def_$l"
  cut -f1 "$tmpdir/mjs_vals_$l" | sort -u > "$tmpdir/mjs_def_$l"
done
used_sh  | grep -v '^$' > "$tmpdir/used_sh"  || true
used_mjs | grep -v '^$' > "$tmpdir/used_mjs" || true

fail=0

# validate one runtime: $1 = label (sh|mjs), $2 = definition source file
validate() {
  local rt="$1" src="$2"
  local usedf="$tmpdir/used_$rt"
  local counts=""
  local l key missing
  for l in $LANGS; do
    counts="$counts $l=$(wc -l < "$tmpdir/${rt}_def_$l")"
  done
  echo "i18n check [$rt] $src: $(wc -l < "$usedf") keys used; defined:$counts"

  # 1) every key used by this runtime must be defined in THIS runtime,
  #    in every language
  while read -r key; do
    missing=""
    for l in $LANGS; do
      grep -qx "$key" "$tmpdir/${rt}_def_$l" 2>/dev/null || missing="$missing $l"
    done
    if [ -n "$missing" ]; then
      echo "FAIL [$rt]: key '$key' missing translation for:$missing"
      fail=1
    fi
  done < "$usedf"

  # 2) value integrity per language vs the en reference of this runtime:
  #    non-empty, same number of %s placeholders
  for l in $LANGS; do
    awk -F'\t' -v rt="$rt" -v lang="$l" '
      NR == FNR { ref[$1] = $2; next }
      $3 == 1 { printf "FAIL [%s]: key '\''%s'\'' [%s] has an empty value\n", rt, $1, lang; bad = 1; next }
      ($1 in ref) && $2 != ref[$1] {
        printf "FAIL [%s]: key '\''%s'\'' [%s] has %d %%s placeholder(s), en has %d\n", rt, $1, lang, $2, ref[$1]
        bad = 1
      }
      END { exit (bad ? 1 : 0) }
    ' "$tmpdir/${rt}_vals_en" "$tmpdir/${rt}_vals_$l" || fail=1
  done
}

echo "i18n check: per-runtime validation, languages: $LANGS"
validate sh  lib/i18n.sh
validate mjs lib/i18n.mjs

# defined-but-unused keys (across both runtimes) are warnings only
{ cat "$tmpdir"/sh_def_* "$tmpdir"/mjs_def_*; } | sort -u > "$tmpdir/def_all"
{ cat "$tmpdir/used_sh" "$tmpdir/used_mjs"; } | sort -u > "$tmpdir/used_all"
while read -r key; do
  grep -qx "$key" "$tmpdir/used_all" 2>/dev/null \
    || echo "warn: key '$key' defined but never used"
done < "$tmpdir/def_all"

if [ "$fail" -eq 1 ]; then
  echo "i18n check FAILED" >&2
  exit 1
fi
echo "i18n check OK"
