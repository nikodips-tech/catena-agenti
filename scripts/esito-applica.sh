#!/usr/bin/env bash
# Esito di applica (token in scrittura, niente Claude): i consigli approvati della retrospettiva
# diventano un commit "chore: retrospettiva di #<n>" sul ramo retrospettiva/issue-<n>, poi la
# chiusura apre la PR (che non si unisce da sola). La raccolta ha già scartato i file fuori
# ambito; qui si ricontrolla, perché gira nel job di Claude.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
stato=$(cat "$ESITO_DIR/stato" 2> /dev/null || echo mancante)
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")
avvisi=$(cat "$ESITO_DIR/avvisi.md" 2> /dev/null || true)
ramo=$(ramo_retro "$ISSUE"); base=$RAMO_SVILUPPO

if [ "$stato" != ok ]; then
  { echo "Retrospettiva: nessuna modifica da applicare ($cons)."; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } | pf_issue_commenta "$ISSUE" -
  exit 0
fi

ramo_checkout "$ramo" "$base"
git apply --index "$ESITO_DIR/patch.diff"
cambiati=$(git diff --cached --name-only --no-renames HEAD)
fuori=$({ grep -vP "$RE_APPLICA" <<< "$cambiati"; grep -P '^\.github/|(^|/)\.env' <<< "$cambiati"; } | grep -v '^$' | sort -u || true)
if [ -n "$fuori" ]; then
  git reset -q --hard
  pf_commenta_testo "$ISSUE" "Retrospettiva: patch scartata, tocca file fuori dall'ambito (va guardato il job agente):"$'\n```\n'"$fuori"$'\n```'
  exit 0
fi
git_identita
git commit -q -m "chore: retrospettiva di #$ISSUE"
pf_push "$ramo"
{ echo "Retrospettiva: consigli applicati sul ramo \`$ramo\` ($cons)."; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } | pf_issue_commenta "$ISSUE" -
passo chiusura-retrospettiva "$ISSUE"
