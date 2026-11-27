#!/usr/bin/env bash
# Esito del revisore (token in scrittura, niente Claude): approva (→ editor), aggiunge
# sotto-task, rimuove file o fa ripristinare test della base (al massimo MAX_GIRI_REVISIONE
# giri), oppure, finiti i giri, "con riserve": la catena va avanti fino alla pull request,
# che si unisce comunque da sola in develop con le riserve scritte (le guarda chi passa in
# master). I test ripristinati si bloccano per i sotto-task che seguono.
# Un esito.json mancante o non valido si ritenta una volta, poi la palla al proprietario (`turn-human`).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
f="$ESITO_DIR/esito.json"
cons=$(cat "$ESITO_DIR/consumo.txt" 2> /dev/null || echo "consumo non disponibile")
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")

bloccato() {
  printf 'Catena, revisione: %s\n\nPer ripartire rispondi con un commento o rimetti `auto`.%s' "$1" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  fermo "$ISSUE"
  exit 0
}
non_valido() {
  local marca="Revisore: risultato non valido"
  if [ "$(conta_commenti "$ISSUE" "$marca")" -lt 1 ]; then
    pf_commenta_testo "$ISSUE" "$marca ($1), riprovo una volta. $cons"
    passo revisore "$ISSUE"
    exit 0
  fi
  bloccato "risultato non valido anche al secondo tentativo ($1)."
}

[ -f "$f" ] || non_valido "esito.json non trovato"
json_valido "$f" '(.approvato | type) == "boolean" and (.nota | type) == "string"
  and (.approvato or
       (((.sottotask // []) | type) == "array" and ((.rimuovi // []) | type) == "array"
        and ((.ripristina // []) | type) == "array"
        and (((.sottotask // []) | length) + ((.rimuovi // []) | length) + ((.ripristina // []) | length)) > 0
        and ((.sottotask // []) | '"$SOTTOTASK_VALIDI"')
        and all((.rimuovi // [])[]; type == "string" and length > 0)
        and all((.ripristina // [])[]; type == "string" and length > 0)
        and (((.ripristina // []) | length) == 0 or ((.sottotask // []) | length) > 0)))' \
  || non_valido "formato non previsto: approvato, nota, sottotask, rimuovi, ripristina (con ripristina serve almeno un sottotask)"

nota=$(jq -r '.nota' "$f")
# Proposte per le regole del progetto (.claude/rules): le decide il proprietario, la catena
# le riporta soltanto. Si accodano alla nota, qualunque sia l'esito
proposte=$(jq -r '(.proposte // []) | map(select(type == "string" and length > 0)) | map("- " + .) | join("\n")' "$f" 2> /dev/null || true)
[ -z "$proposte" ] || nota+=$'\n\n'"**Proposte per le regole del progetto** (\`.claude/rules/\`, decidi tu):"$'\n'"$proposte"

if [ "$(jq -r '.approvato' "$f")" = true ]; then
  printf '%s\n\n%s\n\n_%s_\n' "$T_REV_OK" "$nota" "$cons" | pf_issue_commenta "$ISSUE" -
  passo editor "$ISSUE"
  exit 0
fi

giri=$(conta_commenti "$ISSUE" "$T_REV_SOTTOTASK" "$T_REV_RIMOSSI")
SEGUITO_RISERVE="La pull request va avanti comunque: a CI verde si unisce da sola (in master e per gli hotfix la unisce il proprietario). Le riserve restano qui e nella PR: da guardare prima del passaggio in master."
if [ "$giri" -ge "$MAX_GIRI_REVISIONE" ]; then
  # Non si blocca: la pull request si apre e si unisce, con le riserve scritte
  printf '%s\n\nDopo %s giri la revisione non approva. %s\n\n%s\n\n_%s_\n' \
    "$T_REV_RISERVE" "$giri" "$SEGUITO_RISERVE" "$nota" "$cons" | pf_issue_commenta "$ISSUE" -
  passo editor "$ISSUE"
  exit 0
fi

# File da rimuovere (solo quelli aggiunti sul ramo e assenti dalla base) e test da ripristinare
rapporto=""; rimossi=0; ripristinati=0; push=0
mapfile -t da_rimuovere < <(jq -r '(.rimuovi // [])[]' "$f")
mapfile -t da_ripristinare < <(jq -r '(.ripristina // [])[]' "$f")
if [ "${#da_rimuovere[@]}" -gt 0 ] || [ "${#da_ripristinare[@]}" -gt 0 ]; then
  ramo_checkout "$ramo" "$base"
  git_identita
fi
if [ "${#da_rimuovere[@]}" -gt 0 ]; then
  rapporto=$(BASE="$base" bash "$CATENA/scripts/rimuovi-file.sh" "${da_rimuovere[@]}")
  rimossi=$(grep -c '^rimosso: ' <<< "$rapporto" || true)
  if [ "$rimossi" -gt 0 ]; then
    git commit -q -m "chore: #$ISSUE rimozione file estranei"
    push=1
  fi
  rapporto=$'\n\nFile da rimuovere:\n```\n'"$rapporto"$'\n```'
fi
echo '[]' > "$TMP_BASE/ripristinati.json"
if [ "${#da_ripristinare[@]}" -gt 0 ]; then
  rip=""
  for t in "${da_ripristinare[@]}"; do
    if [[ "$t" == /* || "$t" == *..* ]]; then rip+="ignorato: $t (percorso non ammesso)"$'\n'
    elif ! grep -qP -- "$RE_TEST" <<< "$t"; then rip+="ignorato: $t (non è un test)"$'\n'
    elif grep -qP -- "$RE_PROTETTI|$RE_E2E" <<< "$t"; then rip+="ignorato: $t (file protetto o e2e)"$'\n'
    elif ! git cat-file -e "origin/$base:$t" 2> /dev/null; then rip+="ignorato: $t (non esiste in $base)"$'\n'
    else
      git checkout -q "origin/$base" -- "$t"
      rip+="ripristinato: $t"$'\n'
      ripristinati=$((ripristinati + 1))
      jq --arg t "$t" '. + [$t] | unique' "$TMP_BASE/ripristinati.json" > "$TMP_BASE/rip2.json" && mv "$TMP_BASE/rip2.json" "$TMP_BASE/ripristinati.json"
    fi
  done
  if [ "$ripristinati" -gt 0 ] && ! git diff --cached --quiet; then
    git commit -q -m "chore: #$ISSUE ripristino test"
    push=1
  fi
  rapporto+=$'\n\nTest da ripristinare:\n```\n'"${rip%$'\n'}"$'\n```'
fi
[ "$push" -eq 0 ] || pf_push "$ramo"

n=$(jq '(.sottotask // []) | length' "$f")
if [ "$n" -eq 0 ]; then
  # Solo rimozioni: la revisione riparte (vale come giro)
  if [ "$rimossi" -eq 0 ]; then
    printf '%s\n\nI file indicati non si possono rimuovere (non aggiunti sul ramo o già nella base): proseguo con riserve. %s\n\n%s%s\n' "$T_REV_RISERVE" "$SEGUITO_RISERVE" "$nota" "$rapporto" | pf_issue_commenta "$ISSUE" -
    passo editor "$ISSUE"
    exit 0
  fi
  printf '%s\n\n%s%s\n\n_%s_\n' "$T_REV_RIMOSSI" "$nota" "$rapporto" "$cons" | pf_issue_commenta "$ISSUE" -
  passo revisore "$ISSUE"
  exit 0
fi

# I test ripristinati sono bloccati per ogni sotto-task nuovo
jq --slurpfile r "$TMP_BASE/ripristinati.json" '.sottotask |= map(.test_bloccati = (((.test_bloccati // []) + $r[0]) | unique))' "$f" > "$TMP_BASE/esito-bloccati.json"
for i in $(seq 0 $((n - 1))); do
  jq -r ".sottotask[$i].descrizione" "$TMP_BASE/esito-bloccati.json" > "$TMP_BASE/corpo.md"
  printf '\nSotto-task di #%s (revisione, giro %s).\n' "$ISSUE" "$((giri + 1))" >> "$TMP_BASE/corpo.md"
  righe_sottotask "$TMP_BASE/esito-bloccati.json" ".sottotask[$i]" >> "$TMP_BASE/corpo.md"
  numero=$(pf_issue_crea "$(jq -r ".sottotask[$i].titolo" "$f")" "$TMP_BASE/corpo.md" "$E_SOTTOTASK")
  pf_sottoissue_collega "$ISSUE" "$numero"
done
prima=$(pf_sottoissue_aperte "$ISSUE" | sed -n 1p)
printf '%s\n\n%s%s\n\nRiparte dal sotto-task #%s.\n\n_%s_\n' "$T_REV_SOTTOTASK" "$nota" "$rapporto" "$prima" "$cons" | pf_issue_commenta "$ISSUE" -
passo developer "$ISSUE" "$prima" 1
