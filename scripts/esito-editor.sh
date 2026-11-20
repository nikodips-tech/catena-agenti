#!/usr/bin/env bash
# Esito dell'editor (token in scrittura, niente Claude): commit "docs: #<issue>" se ha scritto
# qualcosa dentro docs/ e README; il resto è già stato scartato dalla raccolta. Poi la chiusura,
# sempre: l'editor non ferma mai la catena.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
stato=$(cat "$ESITO_DIR/stato" 2> /dev/null || echo mancante)
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")
avvisi=$(cat "$ESITO_DIR/avvisi.md" 2> /dev/null || true)
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")

if [ "$stato" = ok ]; then
  ramo_checkout "$ramo" "$base"
  git apply --index "$ESITO_DIR/patch.diff"
  # La raccolta gira nel job di Claude: qui si ricontrolla che la patch resti in docs/
  cambiati=$(git diff --cached --name-only --no-renames HEAD)
  fuori=$({ grep -vP "$RE_DOCS" <<< "$cambiati"; grep -P "$RE_PROTETTI" <<< "$cambiati"; } | grep -v '^$' | sort -u || true)
  if [ -n "$fuori" ]; then
    git reset -q --hard
    testo="Editor: patch scartata, tocca file fuori dalla documentazione (va guardato il job agente):"$'\n```\n'"$fuori"$'\n```'
  else
    git_identita
    git commit -q -m "docs: #$ISSUE"
    pf_push "$ramo"
    testo="Editor: documentazione aggiornata ($cons)."
  fi
else
  testo="Editor: niente da aggiornare ($cons)."
fi
{ echo "$testo"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } | pf_issue_commenta "$ISSUE" -
pf_passo_avvia chiusura "$ISSUE"
