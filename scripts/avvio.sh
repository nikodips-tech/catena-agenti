#!/usr/bin/env bash
# Avvio della catena, senza Claude: controlla chi e cosa, mette in coda, fa il preflight e
# riparte dal punto giusto (docs/flusso.md). Lo chiama il wrapper del progetto per:
#   EVENTO=etichetta   `auto` messa su una issue (CHI = chi l'ha messa)
#   EVENTO=commento    un commento del proprietario su una issue con `domanda`
#   EVENTO=dispatch    la coda, il guardiano o un avvio a mano
# Variabili: ISSUE, EVENTO, CHI, PROPRIETARIO, più quelle di preflight.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR"

rifiuta() { pf_etichetta_togli "$ISSUE" "$E_AUTO"; pf_commenta_testo "$ISSUE" "$1"; exit 0; }

etichette=$(pf_issue_etichette "$ISSUE")
tipo=$(tipo_issue "$etichette")

case "$EVENTO" in
  etichetta) [ "$CHI" = "$PROPRIETARIO" ] || rifiuta "\`auto\` vale solo se la mette il proprietario del repository." ;;
  commento)
    # Una risposta a una domanda: solo del proprietario, solo con `domanda`
    [ "$CHI" = "$PROPRIETARIO" ] || exit 0
    ha "$etichette" "$E_DOMANDA" || exit 0 ;;
  dispatch) ;;
  *) errore "evento sconosciuto: $EVENTO"; exit 2 ;;
esac

! ha "$etichette" "$E_SOTTOTASK" || rifiuta "\`auto\` va messa sull'issue principale, non su un sotto-task."
[ -n "$tipo" ] || rifiuta "La catena gestisce solo issue con etichetta \`$E_TASK\` o \`$E_HOTFIX\`."
[ "$(pf_issue_stato "$ISSUE")" = OPEN ] || exit 0
# Già unita e in attesa del rilascio (chiudi_issue: produzione): la catena ha finito
! ha "$etichette" "$E_IN_DEVELOP" || rifiuta "L'issue è già in develop e si chiude con il rilascio. Per una correzione apri una issue nuova."

# Già in corso: un secondo avvio (coda e pr-chiusa insieme, `auto` rimessa per sbaglio) non fa
# niente. Il guardiano toglie `in-corso` prima di chiamare l'avvio, così la ripresa passa.
if ha "$etichette" "$E_IN_CORSO"; then
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
altra=$(pf_issue_aperte_con "$E_IN_CORSO" | jq -r --argjson io "$ISSUE" --arg s "$E_SOTTOTASK" \
  '[.[] | select(.numero != $io and (.etichette | index($s) | not))] | sort_by(.numero) | first | .numero // empty')
if [ -n "$altra" ]; then
  ultimo=$(pf_issue_commenti "$ISSUE" | jq -r 'last | .corpo // ""')
  [[ "$ultimo" == "In coda"* ]] || pf_commenta_testo "$ISSUE" "In coda: parte quando finisce la #$altra."
  exit 0
fi

# Preflight: se manca qualcosa di infrastruttura, l'elenco preciso e `bloccato`
if ! problemi=$(bash "$CATENA/scripts/preflight.sh"); then
  pf_etichetta_togli "$ISSUE" "$E_AUTO,$E_IN_CORSO"
  pf_etichetta_aggiungi "$ISSUE" "$E_BLOCCATO"
  printf 'Catena, controllo iniziale: manca qualcosa che richiede le tue mani.\n\n%s\n\nSistemato, rimetti `%s`.%s' "$problemi" "$E_AUTO" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  exit 0
fi

pf_etichetta_togli "$ISSUE" "$E_AUTO,$E_DOMANDA,$E_BLOCCATO"
pf_etichetta_aggiungi "$ISSUE" "$E_IN_CORSO"

# Ripartenza dal punto giusto, leggendo lo stato dai commenti e dal ramo
specifica=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA")
if [ -z "$specifica" ]; then
  pf_passo_avvia team-leader "$ISSUE"
  exit 0
fi

git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
pref=$(prefisso_di "$tipo")

if [ "$(corsia_di "$specifica")" = diretta ]; then
  # Corsia diretta: il developer lavora sull'issue stessa, poi la chiusura
  if commit_sul_ramo "$ramo" "$pref: #$ISSUE" "$base"; then
    pf_passo_avvia chiusura "$ISSUE"
  else
    pf_passo_avvia developer "$ISSUE" "$ISSUE" 1
  fi
  exit 0
fi

prima=$(pf_sottoissue_aperte "$ISSUE" | sed -n 1p)
if [ -n "$prima" ]; then
  pf_passo_avvia developer "$ISSUE" "$prima" 1
elif pf_ramo_esiste "$ramo"; then
  # Sotto-task finiti: revisione, oppure chiusura se la revisione c'è già stata
  if [ "$(conta_commenti "$ISSUE" "$T_REV_OK" "$T_REV_RISERVE")" -gt 0 ]; then
    pf_passo_avvia chiusura "$ISSUE"
  else
    pf_passo_avvia revisore "$ISSUE"
  fi
else
  # Specifica senza sotto-task aperti e senza ramo: si rifà la specifica
  pf_commenta_testo "$ISSUE" "Specifica presente ma nessun sotto-task aperto e nessun ramo: rifaccio la specifica."
  pf_passo_avvia team-leader "$ISSUE"
fi
