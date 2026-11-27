#!/usr/bin/env bash
# Una pull request della catena chiusa da una persona (unita a mano, o chiusa senza unione):
# si fa ordine sull'issue, si cancella il ramo e si avvia la coda. Senza questo passo
# il turno resterebbe per sempre e la coda si fermerebbe.
# Variabili: PR, RAMO, BASE, UNITA (true|false).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
issue=$(issue_da_ramo "$RAMO")

if [ -n "$issue" ]; then
  if [ "$UNITA" = true ]; then
    # Unita dall'unione automatica: ha già fatto lei. Unita a mano: come l'unione
    ultimo=$(pf_issue_commenti "$issue" | jq -r 'last | .corpo // ""')
    [[ "$ultimo" == "Unita in"* ]] || issue_unita "$issue" "$BASE" "Unita in \`$BASE\` dalla pull request #$PR."
    pf_ramo_cancella "$RAMO"
  else
    pf_commenta_testo "$issue" "La pull request #$PR è stata chiusa senza unione: la catena si ferma qui. Il ramo \`$RAMO\` resta; per ripartire rimetti \`$E_AUTO\`."
  fi
  turno "$issue" ""
fi
bash "$CATENA/scripts/coda.sh"
