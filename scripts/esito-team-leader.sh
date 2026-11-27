#!/usr/bin/env bash
# Esito del team leader (token in scrittura, niente Claude). Due casi:
# - specifica (SOTTOTASK vuoto): pubblica "## Specifica" con la corsia; corsia diretta → developer
#   sull'issue; corsia completa → crea le sub-issue e avvia la prima; domanda → `turn-human`.
# - escalation (SOTTOTASK pieno): il sotto-task è fallito MAX_TENTATIVI volte, o subito se ha
#   toccato test bloccati dal revisore; il team leader decide
#   riformula | bloccato (docs/specifica.md, Escalation).
# - domanda del developer (SOTTOTASK pieno con una domanda aperta): risposta | domanda | riformula.
# Un esito.json mancante o non valido si ritenta una volta, poi la palla al proprietario (`turn-human`).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
f="$ESITO_DIR/esito.json"
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")
avvisi=$(cat "$ESITO_DIR/avvisi.md" 2> /dev/null || true)
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")

bloccato() {
  printf 'Catena, team leader: %s\n\nPer ripartire rispondi con un commento o rimetti `auto`.%s' "$1" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  fermo "$ISSUE" "${SOTTOTASK:-}"
  exit 0
}
# Un risultato assente o malformato: un secondo tentativo, poi basta
non_valido() {
  local marca="Team leader: risultato non valido"
  if [ "$(conta_commenti "$ISSUE" "$marca")" -lt 1 ]; then
    pf_commenta_testo "$ISSUE" "$marca ($1), riprovo una volta. $cons"
    passo team-leader "$ISSUE" "${SOTTOTASK:-}" 1 "$CONTESTO_NOTA_FILE"
    exit 0
  fi
  bloccato "risultato non valido anche al secondo tentativo ($1)."
}
# crea_sottotask <file esito> <chiave jq>: le sub-issue, in ordine; stampa i numeri
crea_sottotask() {
  local n i titolo numero
  n=$(jq "$2 | length" "$1")
  for i in $(seq 0 $((n - 1))); do
    jq -r "$2[$i].descrizione" "$1" > "$TMP_BASE/corpo.md"
    printf '\nSotto-task di #%s.\n' "$ISSUE" >> "$TMP_BASE/corpo.md"
    righe_sottotask "$1" "$2[$i]" >> "$TMP_BASE/corpo.md"
    titolo=$(jq -r "$2[$i].titolo" "$1")
    numero=$(pf_issue_crea "$titolo" "$TMP_BASE/corpo.md" "$E_SOTTOTASK")
    pf_sottoissue_collega "$ISSUE" "$numero"
    echo "$numero"
  done
}
CONTESTO_NOTA_FILE="$TMP_BASE/nota-escalation.txt"; printf '%s' "${NOTA:-}" > "$CONTESTO_NOTA_FILE"

[ -f "$f" ] || non_valido "esito.json non trovato"

# ------------------------------------------------------------------ specifica
if [ -z "${SOTTOTASK:-}" ]; then
  json_valido "$f" '(.domanda == null or (.domanda | type) == "string")
    and (((.domanda // "") != "") or
         ((.specifica | type) == "string" and (.specifica | length) > 0
          and ((.corsia // "completa") | IN("diretta", "completa"))
          and ((.corsia // "completa") == "diretta" or ((.sottotask | type) == "array" and (.sottotask | length) > 0 and (.sottotask | '"$SOTTOTASK_VALIDI"')))))' \
    || non_valido "formato non previsto: servono domanda, oppure specifica, corsia e sottotask"

  domanda=$(jq -r '.domanda // ""' "$f")
  if [ -n "$domanda" ]; then
    printf '%s\n\n%s\n\nRispondi con un commento: la catena riparte da sola.\n' "$T_DOMANDA" "$domanda" | pf_issue_commenta "$ISSUE" -
    fermo "$ISSUE"
    exit 0
  fi

  corsia=$(jq -r '.corsia // "completa"' "$f")
  { echo "$T_SPECIFICA"; echo; echo "Corsia: $corsia"; echo; jq -r '.specifica' "$f"; echo; echo "_${cons}_"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; } | pf_issue_commenta "$ISSUE" -

  if [ "$corsia" = diretta ]; then
    pf_commenta_testo "$ISSUE" "Corsia diretta: parte il developer, codice e test insieme, poi la pull request."
    passo developer "$ISSUE" "$ISSUE" 1
    exit 0
  fi
  # Su file e non in pipe con head: con pipefail il secondo echo darebbe "Broken pipe"
  crea_sottotask "$f" '.sottotask' > "$TMP_BASE/sottotask.txt"; prima=$(head -1 "$TMP_BASE/sottotask.txt")
  pf_commenta_testo "$ISSUE" "Specifica pronta. Parte il primo sotto-task (#$prima)."
  passo developer "$ISSUE" "$prima" 1
  exit 0
fi

# ------------------------------------------------------------------ escalation o domanda del developer
# Con una domanda del developer aperta sul sotto-task si risponde; altrimenti è un'escalation
SOTTOTASK_RIFORMULA='(.azione != "riformula" or ((.sottotask | type) == "array" and (.sottotask | length) > 0 and (.sottotask | '"$SOTTOTASK_VALIDI"')))'
if domanda_aperta "$SOTTOTASK"; then
  json_valido "$f" '(.azione | IN("risposta", "domanda", "riformula")) and ((.nota // "") | type) == "string"
    and (.azione != "risposta" or ((.risposta | type) == "string" and (.risposta | length) > 0))
    and (.azione != "domanda" or ((.domanda | type) == "string" and (.domanda | length) > 0))
    and '"$SOTTOTASK_RIFORMULA" \
    || non_valido "formato non previsto: servono azione (risposta | domanda | riformula) e il suo testo (risposta, domanda o sottotask)"
  azione=$(jq -r '.azione' "$f")
  if [ "$azione" = risposta ]; then
    # Il developer riparte con lo stesso tentativo della domanda
    tentativo=$(commento_con_titolo "$SOTTOTASK" "$T_DOMANDA_DEV" | tr -d '\r' | sed -n 's/^Tentativo:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | sed -n 1p)
    printf '%s\n\n%s\n\n_%s_\n' "$T_RISPOSTA" "$(jq -r '.risposta' "$f")" "$cons" | pf_issue_commenta "$SOTTOTASK" -
    passo developer "$ISSUE" "$SOTTOTASK" "${tentativo:-1}"
    exit 0
  fi
  if [ "$azione" = domanda ]; then
    printf '%s\n\nIl developer, sul sotto-task #%s, ha bisogno di una scelta tua:\n\n%s\n\nRispondi con un commento: la catena riparte da sola.\n' "$T_DOMANDA" "$SOTTOTASK" "$(jq -r '.domanda' "$f")" | pf_issue_commenta "$ISSUE" -
    fermo "$ISSUE" "$SOTTOTASK"
    exit 0
  fi
  nota=$(jq -r '.nota // ""' "$f")
else
  json_valido "$f" '(.azione | IN("riformula", "bloccato")) and (.nota | type) == "string" and '"$SOTTOTASK_RIFORMULA" \
    || non_valido "formato non previsto: servono azione (riformula | bloccato), nota e, per riformula, sottotask"
  azione=$(jq -r '.azione' "$f"); nota=$(jq -r '.nota' "$f")
fi
printf '%s\n\n%s: %s\n\n_%s_\n' "$T_ESCALATION" "$azione" "$nota" "$cons" | pf_issue_commenta "$SOTTOTASK" -

if [ "$azione" = bloccato ]; then
  # Il lavoro resta sul ramo (commit wip:) perché una persona lo guardi
  bloccato "il sotto-task #$SOTTOTASK è fallito e il team leader chiede una mano:"$'\n\n'"$nota"$'\n\n'"Il lavoro parziale è sul ramo \`$ramo\`."
fi

# Si tolgono dal ramo i tentativi del sotto-task: si riparte puliti
cd "$REPO_DIR"
git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
prima_di=$(commit_prima_di "$ramo" "$SOTTOTASK" "$base" || true)
if [ -n "$prima_di" ]; then
  ramo_checkout "$ramo" "$base"
  git reset -q --hard "$prima_di"
  pf_push --force "$ramo"
fi

# riformula: il sotto-task si chiude, al suo posto quelli nuovi. In corsia diretta il
# "sotto-task" è l'issue principale: resta aperta, i nuovi sono sue sub-issue
if [ "$SOTTOTASK" != "$ISSUE" ]; then
  turno "$SOTTOTASK" ""
  pf_issue_chiudi "$SOTTOTASK" "Riformulato dal team leader in sotto-task più piccoli."
fi
crea_sottotask "$f" '.sottotask' > "$TMP_BASE/sottotask.txt"; prima=$(head -1 "$TMP_BASE/sottotask.txt")
# In corsia diretta la riformulazione porta nella corsia completa: lo dice una nuova specifica
specifica=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA")
if [ "$(corsia_di "$specifica")" = diretta ]; then
  { echo "$T_SPECIFICA"; echo; echo "Corsia: completa"; echo; sed -E '1,/^Corsia:/d' <<<"$specifica"; } | pf_issue_commenta "$ISSUE" -
fi
pf_commenta_testo "$ISSUE" "Escalation sul sotto-task #$SOTTOTASK: riformulato. Riparte dal sotto-task #$prima."
passo developer "$ISSUE" "$prima" 1
