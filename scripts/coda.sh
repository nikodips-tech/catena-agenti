#!/usr/bin/env bash
# La coda: se nessuna issue principale è `in-corso`, avvia la più vecchia con `auto`
# (task o hotfix, non sotto-task). La chiamano unione, pr-chiusa e guardiano.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"

in_corso=$(pf_issue_aperte_con "$E_IN_CORSO" | jq -r --arg s "$E_SOTTOTASK" '[.[] | select(.etichette | index($s) | not)] | length')
[ "$in_corso" -eq 0 ] || { log "coda: la #$(pf_issue_aperte_con "$E_IN_CORSO" | jq -r '.[0].numero') è ancora in corso"; exit 0; }

prossima=$(pf_issue_aperte_con "$E_AUTO" | jq -r --arg s "$E_SOTTOTASK" --arg t "$E_TASK" --arg h "$E_HOTFIX" \
  '[.[] | select((.etichette | index($s) | not) and ((.etichette | index($t)) or (.etichette | index($h))))] | sort_by(.numero) | first | .numero // empty')
if [ -n "$prossima" ]; then
  log "coda: parte la #$prossima"
  pf_passo_avvia avvio "$prossima"
fi
