#!/usr/bin/env bash
# Chiusura (niente Claude): apre la pull request dal ramo dell'issue alla base, con l'App
# (APP_TOKEN), così la CI parte da sola; se la PR c'è già, un commit vuoto dell'App la fa
# ripartire. Etichette: il tipo (task/hotfix) e, quando la catena può unire da sola,
# `unione-automatica`: ogni task, anche con le riserve del revisore (che restano scritte nel
# corpo della PR e nel commento). Non si unisce da sola solo un hotfix: l'unione in master
# è del proprietario. Con RETROSPETTIVA=true: la PR dei consigli approvati, che non si unisce da sola.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"

# Consigli della retrospettiva: PR dal ramo retrospettiva/issue-n alla base di sviluppo, senza
# etichette e senza `unione-automatica`: la unisce il proprietario dopo averla letta
if [ "${RETROSPETTIVA:-false}" = true ]; then
  ramo=$(ramo_retro "$ISSUE"); base=$RAMO_SVILUPPO
  pr=$(pf_pr_aperta "$ramo" "$base" | jq -r '.numero // empty')
  if [ -z "$pr" ]; then
    { printf 'Consigli della retrospettiva di #%s, approvati dal proprietario:\n\n' "$ISSUE"
      commento_con_titolo "$ISSUE" "$T_RETRO" | tronca 4000
      printf '\nNon si unisce da sola: la unisci tu dopo averla letta.\n\nAperta dalla catena di agenti.\n'; } > "$TMP_BASE/corpo.md"
    pr=$(pf_pr_apri "$ramo" "$base" "chore: retrospettiva di #$ISSUE" "$TMP_BASE/corpo.md")
  else
    # I push del token di Actions non fanno partire la CI: un commit vuoto dell'App sì
    ramo_checkout "$ramo" "$base"
    GIT_NOME="${APP_NOME:-catena-agenti}[bot]" GIT_EMAIL="${APP_NOME:-catena-agenti}[bot]@users.noreply.github.com" git_identita
    git commit -q --allow-empty -m "ci: rilancia i controlli"
    pf_push "$ramo"
  fi
  pf_commenta_testo "$ISSUE" "$T_PR_PRONTA"$'\n\n'"Retrospettiva: #$pr verso \`$base\`. Non si unisce da sola: la unisci tu dopo averla letta."
  exit 0
fi
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")
specifica=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA"); corsia=$(corsia_di "$specifica")

approvata=$(conta_commenti "$ISSUE" "$T_REV_OK"); riserve=$(conta_commenti "$ISSUE" "$T_REV_RISERVE")
revisione="nessuna (corsia diretta: garantisce la CI)"
[ "$riserve" -eq 0 ] || revisione="con riserve"
[ "$approvata" -eq 0 ] || revisione="approvata"
con_riserve=no; [ "$revisione" != "con riserve" ] || con_riserve=si
unione_automatica=si
[ "$tipo" = task ] || unione_automatica=no

pr=$(pf_pr_aperta "$ramo" "$base" | jq -r '.numero // empty')
if [ -z "$pr" ]; then
  titolo=$(pf_issue_titolo "$ISSUE")
  sotto=$(pf_sottoissue "$ISSUE" | jq -r '.[] | "- #\(.numero) \(.titolo)"')
  { printf '%s\n\nCorsia: %s\nRevisione: %s\n' "$(riferimento_issue "$ISSUE" "$base")" "$corsia" "$revisione"
    [ -z "$sotto" ] || printf '\nSotto-task:\n\n%s\n' "$sotto"
    if [ "$con_riserve" = si ]; then printf '\nRiserve del revisore:\n\n%s\n' "$(commento_con_titolo "$ISSUE" "$T_REV_RISERVE" | tronca 4000)"; fi
    printf '\nAperta dalla catena di agenti.\n'; } > "$TMP_BASE/corpo.md"
  pr=$(pf_pr_apri "$ramo" "$base" "$titolo" "$TMP_BASE/corpo.md")
else
  # I push del token di Actions non fanno partire la CI: un commit vuoto dell'App sì
  ramo_checkout "$ramo" "$base"
  GIT_NOME="${APP_NOME:-catena-agenti}[bot]" GIT_EMAIL="${APP_NOME:-catena-agenti}[bot]@users.noreply.github.com" git_identita
  git commit -q --allow-empty -m "ci: rilancia i controlli"
  pf_push "$ramo"
fi

pf_pr_etichetta_aggiungi "$pr" "$tipo"
if [ "$unione_automatica" = si ]; then pf_pr_etichetta_aggiungi "$pr" "$E_UNIONE"; else pf_pr_etichetta_togli "$pr" "$E_UNIONE"; fi

testo="$T_PR_PRONTA"$'\n\n'"#$pr verso \`$base\`. "
case "$tipo-$unione_automatica" in
  task-si) if [ "$con_riserve" = si ]; then testo+="A controlli verdi si unisce da sola, con le riserve del revisore: guardale prima del passaggio in master."; else testo+="A controlli verdi si unisce da sola."; fi ;;
  hotfix-*) testo+="È un hotfix: l'unione in \`$base\` la fai tu, dopo i controlli." ;;
  *) testo+="Non si unisce da sola: l'unione spetta a te." ;;
esac
pf_commenta_testo "$ISSUE" "$testo"
