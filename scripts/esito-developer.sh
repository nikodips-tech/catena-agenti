#!/usr/bin/env bash
# Esito del developer (token in scrittura, niente Claude).
# - Controlli verdi: un solo commit "feat: #<n>" (o "fix:" per gli hotfix) che assorbe i
#   tentativi precedenti (wip:), push, sotto-task chiuso, passo dopo (prossimo sotto-task,
#   revisione, oppure chiusura in corsia diretta e nelle riparazioni).
# - Controlli rossi: il lavoro parziale resta sul ramo come "wip: #<n> tentativo k", così il
#   tentativo dopo corregge invece di rifare. Al terzo fallimento escalation al team leader
#   (una volta), poi `bloccato`. Subito, se la raccolta ha ripristinato test della base.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
stato=$(cat "$ESITO_DIR/stato" 2> /dev/null || echo mancante)
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")
avvisi=$(cat "$ESITO_DIR/avvisi.md" 2> /dev/null || true)
messaggio=$(cat "$ESITO_DIR/messaggio.md" 2> /dev/null || echo "il developer non ha prodotto un risultato")
motivo=$(head -n 1 "$ESITO_DIR/motivo.txt" 2> /dev/null | cut -c1-250 || true); [ -n "$motivo" ] || motivo="nessun risultato dal developer"
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo"); pref=$(prefisso_di "$tipo")
diretto=0; [ "$SOTTOTASK" != "$ISSUE" ] || diretto=1

bloccato() {
  printf 'Catena, sotto-task #%s: %s%s' "$SOTTOTASK" "$1" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  [ "$diretto" = 1 ] || pf_etichetta_togli "$SOTTOTASK" "$E_IN_CORSO"
  pf_etichetta_togli "$ISSUE" "$E_IN_CORSO"; pf_etichetta_aggiungi "$ISSUE" "$E_BLOCCATO"
  exit 0
}

ramo_checkout "$ramo" "$base"
git_identita
# La raccolta gira nel job di Claude e legge file che Claude può scrivere: qui, con il
# token, i test della base modificabili si ricalcolano dall'issue e la patch si controlla
if [ "$diretto" = 1 ]; then autorizzati=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA"); else autorizzati=$(pf_issue_corpo "$SOTTOTASK"); fi
{ test_modificabili "$autorizzati"
  git diff --diff-filter=M --name-only --no-renames "origin/$base...HEAD" | grep -P "$RE_TEST" || true
} | sort -u > "$TMP_BASE/permessi.txt"
if [ -s "$ESITO_DIR/patch.diff" ]; then git apply --index "$ESITO_DIR/patch.diff"; fi
vietati=$(file_vietati "$base" "$TMP_BASE/permessi.txt")
if [ -n "$vietati" ]; then
  git reset -q --hard
  bloccato "patch scartata: tocca file che la raccolta avrebbe dovuto rimettere com'erano (file protetti, e2e o test della base senza permesso). Va guardato il job agente:"$'\n\n```\n'"$vietati"$'\n```'
fi

if [ "$stato" != ok ]; then
  { printf 'Tentativo %s di %s fallito: %s (%s)\n' "$TENTATIVO" "$MAX_TENTATIVI" "$motivo" "$cons"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } | pf_issue_commenta "$SOTTOTASK" -
  # Il lavoro parziale resta sul ramo: il tentativo dopo lo corregge
  if [ -s "$ESITO_DIR/patch.diff" ]; then
    git commit -q -m "wip: #$SOTTOTASK tentativo $TENTATIVO"
    pf_push "$ramo"
  fi
  printf '%s' "$messaggio" > "$TMP_BASE/nota.txt"
  # Rosso con test della base ripristinati: il tentativo dopo rifarebbe la stessa modifica,
  # quindi si salta subito al team leader, che può autorizzarla (test_modificabili)
  ripristinati=$(paste -sd, "$ESITO_DIR/test-ripristinati.txt" 2> /dev/null || true)
  if [ "$TENTATIVO" -lt "$MAX_TENTATIVI" ] && [ -z "$ripristinati" ]; then
    pf_passo_avvia developer "$ISSUE" "$SOTTOTASK" "$((TENTATIVO + 1))" "$TMP_BASE/nota.txt"
    exit 0
  fi
  if [ -n "$ripristinati" ]; then perche="ha modificato test della base senza permesso ($ripristinati)"; else perche="è fallito $MAX_TENTATIVI volte"; fi
  # Riparazione di una CI rossa: niente escalation (riformulare a PR aperta riscriverebbe il
  # ramo), una sola riparazione e poi `bloccato` (docs/specifica.md, Scala di escalation)
  if [ "$diretto" = 1 ] && [ "$(conta_commenti "$ISSUE" "$T_RIPARAZIONE")" -gt 0 ]; then
    bloccato "la riparazione della CI rossa $perche. Ultimo errore:"$'\n\n```\n'"$(tail -c 2500 <<< "$messaggio")"$'\n```'
  fi
  if [ "$(conta_commenti "$SOTTOTASK" "$T_ESCALATION")" -lt "$MAX_ESCALATION" ]; then
    pf_commenta_testo "$ISSUE" "Il sotto-task #$SOTTOTASK $perche: chiedo al team leader (escalation)."
    pf_passo_avvia team-leader "$ISSUE" "$SOTTOTASK" 1 "$TMP_BASE/nota.txt"
    exit 0
  fi
  bloccato "$perche anche dopo l'escalation. Ultimo errore:"$'\n\n```\n'"$(tail -c 2500 <<< "$messaggio")"$'\n```'
fi

# Verde: un solo commit che assorbe i tentativi precedenti
primo_wip=$(git log --reverse --format='%H %s' "origin/$base..HEAD" | grep -E " wip: #$SOTTOTASK " | head -1 | cut -d' ' -f1 || true)
forza=()
if [ -n "$primo_wip" ]; then git reset -q --soft "$primo_wip^"; forza=(--force); fi
git commit -q --allow-empty -m "$pref: #$SOTTOTASK"
pf_push "${forza[@]}" "$ramo"

if [ "$diretto" = 1 ]; then
  { printf 'Developer: fatto in %s tentativo/i (%s). Parte la chiusura.\n' "$TENTATIVO" "$cons"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } | pf_issue_commenta "$ISSUE" -
  pf_passo_avvia chiusura "$ISSUE"
  exit 0
fi

pf_etichetta_togli "$SOTTOTASK" "$E_IN_CORSO"
{ printf 'Fatto sul ramo `%s` in %s tentativo/i (%s).\n' "$ramo" "$TENTATIVO" "$cons"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } > "$TMP_BASE/chiusura.md"
pf_issue_chiudi "$SOTTOTASK" "$(cat "$TMP_BASE/chiusura.md")"

prossimo=$(pf_sottoissue_aperte "$ISSUE" | head -1)
if [ -n "$prossimo" ]; then
  pf_passo_avvia developer "$ISSUE" "$prossimo" 1
else
  pf_commenta_testo "$ISSUE" "Sotto-task finiti sul ramo \`$ramo\`: parte la revisione."
  pf_passo_avvia revisore "$ISSUE"
fi
