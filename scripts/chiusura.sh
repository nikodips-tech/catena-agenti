#!/usr/bin/env bash
# Chiusura (niente Claude): apre la pull request dal ramo dell'issue alla base, con l'App
# (APP_TOKEN), così la CI parte da sola; se la PR c'è già, un commit vuoto dell'App la fa
# ripartire. Etichette: il tipo (task/hotfix) e, quando la catena può unire da sola,
# `unione-automatica`. Non si unisce da sola: un hotfix (l'unione in master è del proprietario)
# e una revisione con riserve.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
ramo=$(ramo_di "$ISSUE" "$tipo"); base=$(base_di "$tipo")
specifica=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA"); corsia=$(corsia_di "$specifica")

approvata=$(conta_commenti "$ISSUE" "$T_REV_OK"); riserve=$(conta_commenti "$ISSUE" "$T_REV_RISERVE")
revisione="nessuna (corsia diretta: garantisce la CI)"
[ "$riserve" -eq 0 ] || revisione="con riserve"
[ "$approvata" -eq 0 ] || revisione="approvata"
unione_automatica=si
[ "$tipo" = task ] || unione_automatica=no
[ "$riserve" -eq 0 ] || [ "$approvata" -gt 0 ] || unione_automatica=no

pr=$(pf_pr_aperta "$ramo" "$base" | jq -r '.numero // empty')
if [ -z "$pr" ]; then
  titolo=$(pf_issue_titolo "$ISSUE")
  sotto=$(pf_sottoissue "$ISSUE" | jq -r '.[] | "- #\(.numero) \(.titolo)"')
  { printf 'Closes #%s\n\nCorsia: %s\nRevisione: %s\n' "$ISSUE" "$corsia" "$revisione"
    [ -z "$sotto" ] || printf '\nSotto-task:\n\n%s\n' "$sotto"
    printf '\nAperta dalla catena di agenti.\n'; } > "$TMP_BASE/corpo.md"
  pr=$(pf_pr_apri "$ramo" "$base" "$titolo" "$TMP_BASE/corpo.md")
else
  # I push del token di Actions non fanno partire la CI: un commit vuoto dell'App sì
  ramo_checkout "$ramo" "$base"
  GIT_NOME=dipstech-agenti GIT_EMAIL=dipstech-agenti@users.noreply.github.com git_identita
  git commit -q --allow-empty -m "ci: rilancia i controlli"
  pf_push "$ramo"
fi

pf_pr_etichetta_aggiungi "$pr" "$tipo"
if [ "$unione_automatica" = si ]; then pf_pr_etichetta_aggiungi "$pr" "$E_UNIONE"; else pf_pr_etichetta_togli "$pr" "$E_UNIONE"; fi

testo="$T_PR_PRONTA"$'\n\n'"#$pr verso \`$base\`. "
case "$tipo-$unione_automatica" in
  task-si) testo+="A controlli verdi si unisce da sola." ;;
  hotfix-*) testo+="È un hotfix: l'unione in \`$base\` la fai tu, dopo i controlli." ;;
  *) testo+="La revisione non ha approvato: unirla o chiuderla spetta a te." ;;
esac
pf_commenta_testo "$ISSUE" "$testo"
if [ "$unione_automatica" = no ] && [ "$tipo" = task ]; then pf_etichetta_aggiungi "$ISSUE" "$E_DOMANDA"; fi
