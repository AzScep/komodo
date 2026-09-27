#!/bin/bash
#
# Tests for komodo-age-decrypt. Needs age, age-keygen, base64, jq, and the
# docker compose plugin (only to parse files; no daemon). Run it inside the Periphery
# image, or anywhere with those tools:
#
#   bin/periphery/tests/komodo-age-decrypt.test.sh [path-to-komodo-age-decrypt]

set -uo pipefail

DECRYPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/komodo-age-decrypt}"
CANARY="canary-7f3e9a1c-do-not-print"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
failures=0
tests=0

age-keygen -o "$T/server.key" 2> /dev/null
chmod 600 "$T/server.key"
RECIPIENT="$(age-keygen -y "$T/server.key")"
age-keygen -o "$T/other.key" 2> /dev/null
OTHER="$(age-keygen -y "$T/other.key")"
export KOMODO_AGE_IDENTITY="$T/server.key"

# seal <value> [recipient]: the base64 age ciphertext of the exact bytes.
seal() {
  printf '%s' "$1" | age -r "${2:-$RECIPIENT}" | base64 -w0
}

pass() { tests=$((tests + 1)); echo "ok - $1"; }
bad() { tests=$((tests + 1)); failures=$((failures + 1)); echo "not ok - $1"; }

# run <dir>: runs the script on <dir>/.env into <dir>/secrets.env, keeping
# stdout, stderr, and the exit code, and checks the canary never shows.
run() {
  (cd "$1" && "$DECRYPT" .env secrets.env > "$1/stdout" 2> "$1/stderr")
  code=$?
  if grep -q -- "$CANARY" "$1/stdout" "$1/stderr"; then
    bad "$(basename "$1"): output printed a secret value"
  fi
  return $code
}

# refused <name> <env-content> <expected stderr fragment>
refused() {
  local dir="$T/$1"
  mkdir -p "$dir"
  printf '%s' "$2" > "$dir/.env"
  printf "PREVIOUS='kept'\n" > "$dir/secrets.env"
  if run "$dir"; then
    bad "$1: exited 0"
  elif ! grep -q -- "$3" "$dir/stderr"; then
    bad "$1: stderr lacks '$3': $(cat "$dir/stderr")"
  elif [ "$(cat "$dir/secrets.env")" != "PREVIOUS='kept'" ]; then
    bad "$1: previous secrets.env was changed"
  elif [ -n "$(find "$dir" -name '.komodo-age-decrypt.*')" ]; then
    bad "$1: left a temporary file"
  else
    pass "$1 is refused and leaves the previous file"
  fi
}

# --- Decrypts every secret and writes values compose reads back exactly.

dir="$T/happy"
mkdir -p "$dir"
declare -A values=(
  [PLAIN]="$CANARY"
  [DOLLARS]="a\$b \${HOME} \$\$ \$(id)-$CANARY"
  [QUOTES]="say \"hi\" \\n \\\\ back\\slash #not-a-comment = x"
  [SPACES]="  leading and trailing  "
  [EMPTY]=""
  [UNICODE]="pässwörd-日本"
)
{
  echo "# settings"
  echo "LOG_LEVEL=info"
  for name in "${!values[@]}"; do echo "AGE_$name=$(seal "${values[$name]}")"; done
} > "$dir/.env"
if run "$dir"; then
  pass "happy: exits 0"
else
  bad "happy: exited non-zero: $(cat "$dir/stderr")"
fi
mode="$(stat -c '%a' "$dir/secrets.env" 2> /dev/null)"
if [ "$mode" = 600 ]; then pass "happy: secrets.env has mode 600"; else bad "happy: secrets.env mode is $mode"; fi
for name in "${!values[@]}"; do
  grep -qx "decrypted $name" "$dir/stdout" || bad "happy: stdout does not name $name"
done
grep -q LOG_LEVEL "$dir/secrets.env" && bad "happy: a plain setting was copied into secrets.env"

cat > "$dir/compose.yml" << 'EOF'
services:
  app:
    image: busybox
    env_file: [secrets.env]
    environment:
      FROM_INTERPOLATION: ${DOLLARS}
EOF
if (cd "$dir" && docker compose --env-file secrets.env -f compose.yml config --format json > config.json 2> config.err); then
  pass "happy: docker compose parses secrets.env"
  # compose config prints a compose file, so each literal $ comes out as $$.
  changed=0
  for name in "${!values[@]}" FROM_INTERPOLATION; do
    if [ "$name" = FROM_INTERPOLATION ]; then expected="${values[DOLLARS]}"; else expected="${values[$name]}"; fi
    got="$(jq -j --arg n "$name" '.services.app.environment[$n]' "$dir/config.json")"
    got="${got//\$\$/\$}"
    [ "$got" = "$expected" ] || { bad "happy: compose read $name back changed"; changed=1; }
  done
  [ "$changed" -eq 0 ] && pass "happy: compose reads every value back exactly"
else
  bad "happy: docker compose config failed: $(cat "$dir/config.err")"
fi

# --- No secrets still writes an empty file, so compose --env-file finds it.

dir="$T/none"
mkdir -p "$dir"
printf 'LOG_LEVEL=info\n' > "$dir/.env"
if run "$dir" && [ -f "$dir/secrets.env" ] && [ ! -s "$dir/secrets.env" ]; then
  pass "none: writes an empty secrets.env"
else
  bad "none: $(cat "$dir/stderr")"
fi

# --- A redeploy replaces the kept file.

dir="$T/redeploy"
mkdir -p "$dir"
printf "OLD='value'\n" > "$dir/secrets.env"
printf 'AGE_NEW=%s\n' "$(seal new)" > "$dir/.env"
if run "$dir" && [ "$(cat "$dir/secrets.env")" = "NEW='new'" ]; then
  pass "redeploy: replaces the previous secrets.env"
else
  bad "redeploy: $(cat "$dir/stderr")"
fi

# --- Every failure is refused, prints no value, and leaves no partial file.

good="AGE_GOOD=$(seal "$CANARY")"
refused wrong-key "$good
AGE_OTHER=$(seal "$CANARY" "$OTHER")
" "secret OTHER: age could not decrypt it"
refused bad-base64 "$good
AGE_BROKEN=not*base64!
" "secret BROKEN: ciphertext is not valid base64"
refused not-age "$good
AGE_BROKEN=$(printf '%s' "$CANARY" | base64 -w0)
" "secret BROKEN: age could not decrypt it"
refused empty-ciphertext "AGE_BROKEN=
" "secret BROKEN has no ciphertext"
refused multi-line "$good
AGE_LINES=$(seal "first-$CANARY
second")
" "secret LINES contains a line break"
refused trailing-newline "AGE_LINES=$(seal "$CANARY
")
" "secret LINES contains a line break"
refused carriage-return "AGE_CR=$(seal "$CANARY"$'\r'x)
" "secret CR contains a line break"
refused nul "AGE_NUL=$(printf 'a\000%s' "$CANARY" | age -r "$RECIPIENT" | base64 -w0)
" "secret NUL contains a line break or control character"
refused single-quote "AGE_QUOTE=$(seal "it's-$CANARY")
" "secret QUOTE contains a single quote"
refused lower-case "AGE_lower=$(seal "$CANARY")
" "secret name AGE_lower is not upper-case"
refused no-equals "AGE_BROKEN
" "line starting AGE_ has no '='"
refused duplicate "$good
$good
" "secret GOOD is listed twice"
refused shadowed "GOOD=plain
$good
" "secret GOOD is also set as a plain setting"

chmod 644 "$T/server.key"
refused open-identity "$good
" "readable by group or others"
chmod 600 "$T/server.key"
KOMODO_AGE_IDENTITY="$T/missing.key" refused missing-identity "$good
" "cannot read age identity"

echo "$tests checks, $failures failed"
[ "$failures" -eq 0 ]
