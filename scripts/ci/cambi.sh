#!/usr/bin/env bash
# CI, job `cambi`: cosa c'è da controllare, per gli altri job (in $GITHUB_OUTPUT).
# - codice: si | no. Una pull request che cambia solo documentazione (chiave `docs`) non
#   esegue lint, tipi, test e build: i passi si saltano e i controlli finiscono verdi.
# - immagini: la matrice JSON delle immagini da costruire, da `immagini`
#   ("<servizio>=<dockerfile> …") o da `dockerfile` (servizio: la cartella del Dockerfile);
#   [] se il progetto non ha immagini.
# Variabili: EVENTO, BASE (la base della PR).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"
cd "$REPO_DIR" || exit 1
uscita=${GITHUB_OUTPUT:-/dev/stdout}
riepilogo=${GITHUB_STEP_SUMMARY:-/dev/null}

codice=si
if [ "${EVENTO:-}" = pull_request ] && [ -n "${BASE:-}" ]; then
  cambiati=$(git diff --name-only "origin/$BASE...HEAD")
  if [ -n "$cambiati" ] && ! grep -qvP -- "$RE_DOCS" <<< "$cambiati"; then
    codice=no
    echo "Solo documentazione: niente lint, tipi, test e build." >> "$riepilogo"
  fi
fi

immagini=$(cfg immagini)
dockerfile=$(cfg dockerfile)
if [ -z "$immagini" ] && [ -n "$dockerfile" ]; then
  cartella=$(dirname "$dockerfile")
  servizio=$(basename "$cartella"); [ "$cartella" != . ] || servizio=app
  immagini="$servizio=$dockerfile"
fi
matrice="[]"
for voce in $immagini; do
  [[ "$voce" =~ ^[a-z0-9-]+=[A-Za-z0-9._/-]+$ ]] || { errore ".catena.yml: immagine non valida «$voce» (<servizio>=<dockerfile>)"; exit 1; }
  servizio=${voce%%=*}; file=${voce#*=}
  [ -f "$file" ] || { errore ".catena.yml: il Dockerfile $file non esiste"; exit 1; }
  matrice=$(jq -c --arg s "$servizio" --arg f "$file" --arg c "$(dirname "$file")" '. + [{servizio: $s, file: $f, context: $c}]' <<< "$matrice")
done

{ echo "codice=$codice"; echo "immagini=$matrice"; } >> "$uscita"
