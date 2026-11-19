#!/usr/bin/env bash
# Rimuove dal ramo (già in checkout) i file indicati dal revisore, ma solo se sono stati
# aggiunti sul ramo e non esistono nella base; gli altri si ignorano. Non fa commit.
# Stampa "rimosso: <file>" e "ignorato: <file> (<motivo>)".
# Uso: BASE=<ramo base> rimuovi-file.sh <file…>   (percorsi dalla radice del repo)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR"
base=${BASE:-$RAMO_SVILUPPO}

aggiunti=$(git diff --diff-filter=A --name-only --no-renames "origin/$base...HEAD")
for f in "$@"; do
  if [[ "$f" == /* || "$f" == *..* ]] || grep -qP "$RE_PROTETTI" <<< "$f"; then
    echo "ignorato: $f (percorso non ammesso)"
  elif git cat-file -e "origin/$base:$f" 2> /dev/null; then
    echo "ignorato: $f (esiste già in $base)"
  elif ! grep -qxF -- "$f" <<< "$aggiunti" || [ ! -f "$f" ]; then
    echo "ignorato: $f (non aggiunto sul ramo)"
  else
    git rm -q -- "$f" && echo "rimosso: $f"
  fi
done
