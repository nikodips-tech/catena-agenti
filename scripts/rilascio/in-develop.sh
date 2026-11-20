#!/usr/bin/env bash
# Issue entrate in develop (niente Claude), da in-develop.yml: quando una PR entra in develop,
# le issue citate nella descrizione o nei commit (Closes, Fixes, Resolves o Refs #N) ricevono un
# commento e l'etichetta `in-develop`. Restano aperte: le chiude tag-master al rilascio.
# Si saltano il riporto di master in develop (porta issue già in produzione) e i rami della
# catena (issue-N): per quelli lo fa già l'unione (chiudi_issue: produzione).
# develop è il ramo predefinito: con "Closes #N" GitHub chiuderebbe l'issue da solo, per questo
# nelle PR verso develop si scrive "Refs #N".
# Variabili: GH_TOKEN, GH_REPO, PR, RAMO (head della PR).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"

[ "$RAMO" != "$RAMO_PRODUZIONE" ] || { log "riporto di $RAMO_PRODUZIONE: niente da fare"; exit 0; }
[ -z "$(issue_da_ramo "$RAMO")" ] || { log "ramo della catena: le issue le segue l'unione"; exit 0; }

testo=$(gh pr view "$PR" -R "$GH_REPO" --json body,commits \
  -q '.body + "\n" + ([.commits[] | .messageHeadline + "\n" + .messageBody] | join("\n"))')
numeri=$(grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?) +#[0-9]+' <<< "$testo" | grep -oE '[0-9]+$' | sort -un || true)
[ -z "$numeri" ] || gh label create "$E_IN_DEVELOP" -R "$GH_REPO" --color 0075CA \
  --description "In develop: si chiude quando va in produzione" > /dev/null 2>&1 || true
for n in $numeri; do
  [ "$(gh issue view "$n" -R "$GH_REPO" --json state -q .state 2> /dev/null || true)" = OPEN ] || continue
  gh issue edit "$n" -R "$GH_REPO" --add-label "$E_IN_DEVELOP" > /dev/null
  gh issue comment "$n" -R "$GH_REPO" --body \
    "Entrata in $RAMO_SVILUPPO con la pull request #$PR: va in produzione con la prossima release. Se qualcosa non va, scrivilo qui."
  echo "in develop: #$n"
done
