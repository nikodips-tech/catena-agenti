#!/usr/bin/env bash
# Esito della retrospettiva (token in scrittura, niente Claude): pubblica "## Retrospettiva" con
# i consigli sull'issue (chiusa o in-develop). Un esito.json mancante o non valido si ritenta una
# volta, poi solo un commento d'errore: niente turni, l'issue è finita. L'etichetta
# `retrospective` c'è solo se ci sono consigli per il progetto: il proprietario li approva con
# `retrospective-approved` (avvio.sh) e parte `applica`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
f="$ESITO_DIR/esito.json"
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")

non_valido() {
  local marca="Retrospettiva: risultato non valido"
  if [ "$(conta_commenti "$ISSUE" "$marca")" -lt 1 ]; then
    pf_commenta_testo "$ISSUE" "$marca ($1), riprovo una volta. $cons"
    passo retrospettiva "$ISSUE"
  else
    pf_commenta_testo "$ISSUE" "$marca anche al secondo tentativo ($1): niente retrospettiva per questa issue."
  fi
  exit 0
}

[ -f "$f" ] || non_valido "esito.json non trovato"
json_valido "$f" '(.riassunto | type) == "string"
  and ((.progetto // []) | type) == "array"
  and all((.progetto // [])[]; (.consiglio | type) == "string" and (.consiglio | length) > 0 and (.file | type) == "string" and (.file | length) > 0)
  and ((.catena // []) | type) == "array"
  and all((.catena // [])[]; type == "string" and length > 0)' \
  || non_valido "formato non previsto: servono riassunto, progetto [{consiglio, file}] e catena [testo]"

n_progetto=$(jq '(.progetto // []) | length' "$f"); n_catena=$(jq '(.catena // []) | length' "$f")
if [ "$n_progetto" -eq 0 ] && [ "$n_catena" -eq 0 ]; then
  printf '%s\n\nNiente da proporre.\n\n_%s_\n' "$T_RETRO" "$cons" | pf_issue_commenta "$ISSUE" -
  exit 0
fi

{
  echo "$T_RETRO"; echo
  jq -r '.riassunto' "$f"; echo
  if [ "$n_progetto" -gt 0 ]; then
    echo "### Consigli per questo progetto"; echo
    jq -r '(.progetto // []) | to_entries[] | "\(.key + 1). \(.value.consiglio) (file: `\(.value.file)`)"' "$f"; echo
  fi
  if [ "$n_catena" -gt 0 ]; then
    echo "### Consigli per la catena di agenti"; echo
    echo "Da riportare a mano nel repository della catena: la catena non apre issue altrove."; echo
    jq -r '(.catena // []) | to_entries[] | "\(.key + 1). \(.value)"' "$f"; echo
  fi
  if [ "$n_progetto" -gt 0 ]; then
    echo "Per applicare i consigli del progetto metti \`$E_RETRO_OK\`. Se ne vuoi solo alcuni o diversi, scrivilo prima in un commento: chi li applica lo legge. Per scartarli togli \`$E_RETRO\`. Se non fai niente non succede niente."; echo
  fi
  echo "_${cons}_"
} | pf_issue_commenta "$ISSUE" -
if [ "$n_progetto" -gt 0 ]; then pf_etichetta_aggiungi "$ISSUE" "$E_RETRO"; fi
