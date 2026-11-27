#!/usr/bin/env bash
# Il guardiano (a orario, niente Claude): se nessuna esecuzione della catena è attiva e una
# issue è in corso (un `turn-*` diverso da turn-human) da troppo senza novità (un workflow morto
# per timeout o per un errore di GitHub), la fa ripartire dal punto giusto, leggendo lo stato dai
# commenti e dal ramo. Se non c'è niente in corso, avvia la coda.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
soglia=$(cfg guardiano_minuti 90)

attive=$(( $(pf_esecuzioni_attive) - 1 ))   # meno questa
[ "$attive" -le 0 ] || { log "guardiano: $attive esecuzioni attive, non tocco niente"; exit 0; }

adesso=$(date -u +%s)
ferme=$(issue_in_corso | jq -r --argjson adesso "$adesso" --argjson soglia "$soglia" \
  '[.[] | select(($adesso - (.aggiornata | fromdateiso8601)) / 60 > $soglia)] | sort_by(.numero) | .[].numero')
if [ -n "$ferme" ]; then
  issue=$(head -1 <<< "$ferme")
  pf_commenta_testo "$issue" "Ripresa automatica: nessuna esecuzione attiva e nessuna novità da più di $soglia minuti."
  # Senza turno l'avvio non la scambia per un doppio avvio e riparte dal punto giusto
  turno "$issue" ""
  passo avvio "$issue"
  exit 0
fi
bash "$CATENA/scripts/coda.sh"
