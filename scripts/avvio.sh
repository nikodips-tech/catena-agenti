#!/usr/bin/env bash
# Avvio della catena, senza Claude: controlla chi e cosa, mette in coda, fa il preflight e
# riparte dal punto giusto (docs/flusso.md). Lo chiama il wrapper del progetto per:
#   EVENTO=etichetta   `auto` messa su una issue (CHI = chi l'ha messa)
#   EVENTO=commento    un commento del proprietario su una issue con `turn-human`
#   EVENTO=dispatch    la coda, il guardiano o un avvio a mano
#   EVENTO=etichetta con ETICHETTA=retrospective-approved: i consigli della retrospettiva (applica)
# Variabili: ISSUE, EVENTO, CHI, ETICHETTA, PROPRIETARIO, più quelle di preflight.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR"

rifiuta() { pf_etichetta_togli "$ISSUE" "$E_AUTO"; pf_commenta_testo "$ISSUE" "$1"; exit 0; }

# Consigli della retrospettiva approvati: solo il proprietario, serve una retrospettiva; si
# applica anche a issue chiusa, quindi prima di ogni altro controllo
if [ "$EVENTO" = etichetta ] && [ "${ETICHETTA:-}" = "$E_RETRO_OK" ]; then
  if [ "$CHI" != "$PROPRIETARIO" ]; then
    pf_etichetta_togli "$ISSUE" "$E_RETRO_OK"
    pf_commenta_testo "$ISSUE" "\`$E_RETRO_OK\` vale solo se la mette il proprietario del repository."
    exit 0
  fi
  if [ -z "$(commento_con_titolo "$ISSUE" "$T_RETRO")" ]; then
    pf_etichetta_togli "$ISSUE" "$E_RETRO_OK"
    pf_commenta_testo "$ISSUE" "Non c'è nessuna retrospettiva da applicare su questa issue."
    exit 0
  fi
  pf_etichetta_togli "$ISSUE" "$E_RETRO,$E_RETRO_OK"
  passo applica "$ISSUE"
  exit 0
fi

etichette=$(pf_issue_etichette "$ISSUE")
tipo=$(tipo_issue "$etichette")

case "$EVENTO" in
  etichetta) [ "$CHI" = "$PROPRIETARIO" ] || rifiuta "\`auto\` vale solo se la mette il proprietario del repository." ;;
  commento)
    # Una risposta quando la palla è sua: solo del proprietario, solo con `turn-human`
    [ "$CHI" = "$PROPRIETARIO" ] || exit 0
    ha "$etichette" "$E_TURN_HUMAN" || exit 0 ;;
  dispatch) ;;
  *) errore "evento sconosciuto: $EVENTO"; exit 2 ;;
esac

! ha "$etichette" "$E_SOTTOTASK" || rifiuta "\`auto\` va messa sull'issue principale, non su un sotto-task."
[ -n "$tipo" ] || rifiuta "La catena gestisce solo issue con etichetta \`$E_TASK\` o \`$E_HOTFIX\`."
[ "$(pf_issue_stato "$ISSUE")" = OPEN ] || exit 0
# Già unita e in attesa del rilascio (chiudi_issue: produzione): la catena ha finito
! ha "$etichette" "$E_IN_DEVELOP" || rifiuta "L'issue è già in develop e si chiude con il rilascio. Per una correzione apri una issue nuova."

# Già in corso: un secondo avvio (coda e pr-chiusa insieme, `auto` rimessa per sbaglio) non fa
# niente. Il guardiano toglie il turno prima di chiamare l'avvio, così la ripresa passa.
if in_corso "$etichette"; then
  pf_etichetta_togli "$ISSUE" "$E_AUTO"
  [ "$EVENTO" != etichetta ] || pf_commenta_testo "$ISSUE" "La catena è già al lavoro su questa issue."
  exit 0
fi

ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")

# Con una pull request aperta non si riparte: decide il proprietario (unirla o chiuderla)
pr=$(pf_pr_aperta "$ramo" "$base" | jq -r '.numero // empty')
if [ -n "$pr" ]; then
  pf_etichetta_togli "$ISSUE" "$E_AUTO"
  pf_commenta_testo "$ISSUE" "La pull request #$pr è aperta: la catena non riparte finché non viene unita o chiusa."
  exit 0
fi

# Una sola catena alla volta: i sotto-task non contano. L'issue resta con `auto`, la coda la troverà
altra=$(issue_in_corso | jq -r --argjson io "$ISSUE" '[.[] | select(.numero != $io)] | sort_by(.numero) | first | .numero // empty')
if [ -n "$altra" ]; then
  ultimo=$(pf_issue_commenti "$ISSUE" | jq -r 'last | .corpo // ""')
  [[ "$ultimo" == "In coda"* ]] || pf_commenta_testo "$ISSUE" "In coda: parte quando finisce la #$altra."
  exit 0
fi

# Preflight: se manca qualcosa di infrastruttura, l'elenco preciso e la palla al proprietario
if ! problemi=$(bash "$CATENA/scripts/preflight.sh"); then
  pf_etichetta_togli "$ISSUE" "$E_AUTO"
  fermo "$ISSUE"
  printf 'Catena, controllo iniziale: manca qualcosa che richiede le tue mani.\n\n%s\n\nSistemato, rispondi con un commento o rimetti `%s`.%s' "$problemi" "$E_AUTO" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  exit 0
fi

# Si parte: il turno giusto lo mette `passo`
pf_etichetta_togli "$ISSUE" "$E_AUTO,$E_TURN_HUMAN"

# Ripartenza dal punto giusto, leggendo lo stato dai commenti e dal ramo
specifica=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA")
if [ -z "$specifica" ]; then
  passo team-leader "$ISSUE"
  exit 0
fi

# Il developer ripartirebbe, ma se ha una domanda senza risposta tocca al team leader
avvia_developer() {
  if domanda_aperta "$1"; then passo team-leader "$ISSUE" "$1"; else passo developer "$ISSUE" "$1" 1; fi
}

git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
pref=$(prefisso_di "$tipo")

prima=$(pf_sottoissue_aperte "$ISSUE" | sed -n 1p)

if [ "$(corsia_di "$specifica")" = diretta ]; then
  # Corsia diretta: il developer lavora sull'issue stessa
  if ! commit_sul_ramo "$ramo" "$pref: #$ISSUE" "$base"; then
    avvia_developer "$ISSUE"
    exit 0
  fi
  # Lavoro finito: di norma la chiusura. Si prosegue come nella corsia completa se ci sono
  # sotto-task aperti (revisore), o se il ramo tocca test della base e nessuno l'ha rivisto
  tocca_test=$(git diff --name-status --no-renames --diff-filter=MD "origin/$base...origin/$ramo" | while IFS=$'\t' read -r st f; do
    if grep -qP -- "$RE_TEST" <<< "$f"; then echo "$f"; fi
  done)
  if [ -z "$prima" ] && { [ -z "$tocca_test" ] || [ "$(conta_commenti "$ISSUE" "$T_REV_OK" "$T_REV_RISERVE")" -gt 0 ]; }; then
    passo chiusura "$ISSUE"
    exit 0
  fi
fi

if [ -n "$prima" ]; then
  avvia_developer "$prima"
elif pf_ramo_esiste "$ramo"; then
  # Sotto-task finiti: revisione, oppure chiusura se la revisione c'è già stata
  if [ "$(conta_commenti "$ISSUE" "$T_REV_OK" "$T_REV_RISERVE")" -gt 0 ]; then
    passo chiusura "$ISSUE"
  else
    passo revisore "$ISSUE"
  fi
else
  # Specifica senza sotto-task aperti e senza ramo: si rifà la specifica
  pf_commenta_testo "$ISSUE" "Specifica presente ma nessun sotto-task aperto e nessun ramo: rifaccio la specifica."
  passo team-leader "$ISSUE"
fi
