#!/usr/bin/env bash
# La cache delle dipendenze (chiavi `cache` e `cache_chiave` di .catena.yml), per i passi
# actions/cache della CI e del developer: in $GITHUB_OUTPUT `percorsi` (assoluti, uno per riga),
# `chiave` (prefisso + hash dei file di `cache_chiave`) e `prefisso` (per le restore-keys).
# Senza `cache` non scrive niente e i passi della cache si saltano.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"
cd "$REPO_DIR" || exit 1
uscita=${GITHUB_OUTPUT:-/dev/stdout}

percorsi=$(cfg cache)
[ -n "$percorsi" ] || exit 0
cartella=$(cfg cartella .)

prefisso="catena-${RUNNER_OS:-Linux}-$(printf '%s' "$percorsi" | sha256sum | cut -c1-8)-"
hash=$(for f in $(cfg cache_chiave); do
  if [ -f "$cartella/$f" ]; then sha256sum "$cartella/$f"; else echo "manca $f"; fi
done | sha256sum | cut -c1-16)

{
  echo "percorsi<<FINE"
  for p in $percorsi; do echo "$REPO_DIR/$cartella/$p"; done
  echo "FINE"
  echo "chiave=$prefisso$hash"
  echo "prefisso=$prefisso"
} >> "$uscita"
