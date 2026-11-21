#!/usr/bin/env bash
# Esito del revisore (token in scrittura, niente Claude): approva (→ editor), aggiunge
# sotto-task o rimuove file (al massimo MAX_GIRI_REVISIONE giri), oppure, finiti i giri,
# "con riserve": la catena va avanti fino alla pull request, che però non si unisce da sola.
# Un esito.json mancante o non valido si ritenta una volta, poi `bloccato`.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
f="$ESITO_DIR/esito.json"
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")

bloccato() {
  printf 'Catena, revisione: %s%s' "$1" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  pf_etichetta_togli "$ISSUE" "$E_IN_CORSO"; pf_etichetta_aggiungi "$ISSUE" "$E_BLOCCATO"
  exit 0
}
non_valido() {
  local marca="Revisore: risultato non valido"
  if [ "$(conta_commenti "$ISSUE" "$marca")" -lt 1 ]; then
    pf_commenta_testo "$ISSUE" "$marca ($1), riprovo una volta. $cons"
    pf_passo_avvia revisore "$ISSUE"
    exit 0
  fi
  bloccato "risultato non valido anche al secondo tentativo ($1)."
}

[ -f "$f" ] || non_valido "esito.json non trovato"
json_valido "$f" '(.approvato | type) == "boolean" and (.nota | type) == "string"
  and (.approvato or
       (((.sottotask // []) | type) == "array" and ((.rimuovi // []) | type) == "array"
        and (((.sottotask // []) | length) + ((.rimuovi // []) | length)) > 0
        and ((.sottotask // []) | '"$SOTTOTASK_VALIDI"')
        and all((.rimuovi // [])[]; type == "string" and length > 0)))' \
  || non_valido "formato non previsto: approvato, nota, sottotask, rimuovi"

nota=$(jq -r '.nota' "$f")
# Proposte per le regole del progetto (.claude/rules): le decide il proprietario, la catena
# le riporta soltanto. Si accodano alla nota, qualunque sia l'esito
proposte=$(jq -r '(.proposte // []) | map(select(type == "string" and length > 0)) | map("- " + .) | join("\n")' "$f" 2> /dev/null || true)
[ -z "$proposte" ] || nota+=$'\n\n'"**Proposte per le regole del progetto** (\`.claude/rules/\`, decidi tu):"$'\n'"$proposte"

if [ "$(jq -r '.approvato' "$f")" = true ]; then
  printf '%s\n\n%s\n\n_%s_\n' "$T_REV_OK" "$nota" "$cons" | pf_issue_commenta "$ISSUE" -
  pf_passo_avvia editor "$ISSUE"
  exit 0
fi

giri=$(conta_commenti "$ISSUE" "$T_REV_SOTTOTASK" "$T_REV_RIMOSSI")
if [ "$giri" -ge "$MAX_GIRI_REVISIONE" ]; then
  # Non si blocca: la pull request si apre comunque, ma la unisce il proprietario
  printf '%s\n\nDopo %s giri la revisione non approva. La catena apre la pull request, che non si unirà da sola: decidi tu.\n\n%s\n\n_%s_\n' \
    "$T_REV_RISERVE" "$giri" "$nota" "$cons" | pf_issue_commenta "$ISSUE" -
  pf_passo_avvia editor "$ISSUE"
  exit 0
fi

# File da rimuovere: solo quelli aggiunti sul ramo e assenti dalla base
rapporto=""; rimossi=0
mapfile -t da_rimuovere < <(jq -r '(.rimuovi // [])[]' "$f")
if [ "${#da_rimuovere[@]}" -gt 0 ]; then
  ramo_checkout "$ramo" "$base"
  rapporto=$(BASE="$base" bash "$CATENA/scripts/rimuovi-file.sh" "${da_rimuovere[@]}")
  rimossi=$(grep -c '^rimosso: ' <<< "$rapporto" || true)
  if [ "$rimossi" -gt 0 ]; then
    git_identita
    git commit -q -m "chore: #$ISSUE rimozione file estranei"
    pf_push "$ramo"
  fi
  rapporto=$'\n\nFile da rimuovere:\n```\n'"$rapporto"$'\n```'
fi

n=$(jq '(.sottotask // []) | length' "$f")
if [ "$n" -eq 0 ]; then
  # Solo rimozioni: la revisione riparte (vale come giro)
  if [ "$rimossi" -eq 0 ]; then
    printf '%s\n\nI file indicati non si possono rimuovere (non aggiunti sul ramo o già nella base): proseguo con riserve.\n\n%s%s\n' "$T_REV_RISERVE" "$nota" "$rapporto" | pf_issue_commenta "$ISSUE" -
    pf_passo_avvia editor "$ISSUE"
    exit 0
  fi
  printf '%s\n\n%s%s\n\n_%s_\n' "$T_REV_RIMOSSI" "$nota" "$rapporto" "$cons" | pf_issue_commenta "$ISSUE" -
  pf_passo_avvia revisore "$ISSUE"
  exit 0
fi

for i in $(seq 0 $((n - 1))); do
  jq -r ".sottotask[$i].descrizione" "$f" > "$TMP_BASE/corpo.md"
  printf '\nSotto-task di #%s (revisione, giro %s).\n' "$ISSUE" "$((giri + 1))" >> "$TMP_BASE/corpo.md"
  righe_sottotask "$f" ".sottotask[$i]" >> "$TMP_BASE/corpo.md"
  numero=$(pf_issue_crea "$(jq -r ".sottotask[$i].titolo" "$f")" "$TMP_BASE/corpo.md" "$E_SOTTOTASK")
  pf_sottoissue_collega "$ISSUE" "$numero"
done
prima=$(pf_sottoissue_aperte "$ISSUE" | sed -n 1p)
printf '%s\n\n%s%s\n\nRiparte dal sotto-task #%s.\n\n_%s_\n' "$T_REV_SOTTOTASK" "$nota" "$rapporto" "$prima" "$cons" | pf_issue_commenta "$ISSUE" -
pf_passo_avvia developer "$ISSUE" "$prima" 1
