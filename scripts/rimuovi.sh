#!/usr/bin/env bash
# Cancella dal checkout i file che il sotto-task chiede di togliere. Lo usa il developer
# (Claude non ha `rm`): solo file normali dentro il repo, mai file protetti o e2e. I test
# della base si possono cancellare: la raccolta li lascia nella patch e il revisore li giudica.
# Non fa commit: la cancellazione entra nella patch, controllata come ogni altra modifica.
# Stampa "rimosso: <file>" e "ignorato: <file> (<motivo>)".
# Uso: rimuovi.sh <file…>   (percorsi dalla radice del repo)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR" || exit 1
radice=$(pwd -P)

[ "$#" -gt 0 ] || { echo "uso: rimuovi.sh <file…>" >&2; exit 2; }
for f in "$@"; do
  # Percorsi puliti e relativi: niente assoluti, `..`, `.`, `//` né la cartella .git
  if [[ -z "$f" || "$f" == /* || "$f" == *..* || "/$f/" == */./* || "$f" == *//* || "/$f/" == */.git/* ]]; then
    echo "ignorato: $f (percorso non ammesso)"
  elif grep -qP -- "$RE_PROTETTI" <<< "$f"; then
    echo "ignorato: $f (file protetto)"
  elif grep -qP -- "$RE_E2E" <<< "$f"; then
    echo "ignorato: $f (test e2e)"
  elif [ ! -e "$f" ] && [ ! -L "$f" ]; then
    echo "ignorato: $f (non esiste)"
  elif [ -L "$f" ] || [ ! -f "$f" ]; then
    echo "ignorato: $f (non è un file normale)"
  elif ! cartella=$(cd "$(dirname -- "$f")" 2> /dev/null && pwd -P) || [[ "$cartella" != "$radice" && "$cartella" != "$radice"/* ]]; then
    echo "ignorato: $f (fuori dal repo)"
  else
    rm -f -- "$f" && echo "rimosso: $f"
  fi
done
exit 0
