#!/usr/bin/env bash
# Unione (niente Claude): quando la CI finisce su un ramo con una pull request aperta che ha
# `unione-automatica`, verde → squash con il prefisso giusto, ramo cancellato, issue chiusa
# (o `in-develop` fino al rilascio, con chiudi_issue: produzione);
# rossa → una riparazione del developer (una volta), poi `turn-human`. Vale per le PR della
# catena (rami issue-*) e per quelle aperte in corsia diretta da una sessione locale, se hanno
# l'etichetta. Alla fine avvia la coda.
# Variabili: RAMO, SHA, ESITO (success|failure|…), RUN_CI, APP_TOKEN.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
[ "$ESITO" != cancelled ] || exit 0

issue=$(issue_da_ramo "$RAMO")
pr=""
for base in "$RAMO_SVILUPPO" "$RAMO_PRODUZIONE"; do
  pr=$(pf_pr_aperta "$RAMO" "$base"); [ -z "$pr" ] || break
done
[ -n "$pr" ] || { log "nessuna pull request aperta per $RAMO"; exit 0; }
[ "$(jq -r .sha <<< "$pr")" = "$SHA" ] || { log "la CI è di un commit superato"; exit 0; }
numero=$(jq -r .numero <<< "$pr"); etichette_pr=$(jq -r '.etichette | join(" ")' <<< "$pr")
ha "$etichette_pr" "$E_UNIONE" || { log "la PR #$numero non ha $E_UNIONE: non tocco niente"; bash "$CATENA/scripts/coda.sh"; exit 0; }
# In master non si unisce mai da soli: l'unione è l'OK del proprietario al rilascio
[ "$base" != "$RAMO_PRODUZIONE" ] || { log "la PR #$numero va in $base: la unisce il proprietario"; bash "$CATENA/scripts/coda.sh"; exit 0; }

tipo=task
if ha "$etichette_pr" "$E_HOTFIX" || [ "$base" = "$RAMO_PRODUZIONE" ]; then tipo=hotfix; fi

bloccato() {
  if [ -n "$issue" ]; then
    printf 'Catena, unione: %s\n\nPer ripartire rispondi con un commento o rimetti `auto`.%s' "$1" "$(riga_esecuzione)" | pf_issue_commenta "$issue" -
    fermo "$issue"
  else
    pf_pr_commenta "$numero" "Catena, unione: $1"
  fi
}

if [ "$ESITO" = success ]; then
  titolo=$(pf_pr_json "$numero" | jq -r .titolo)
  soggetto=$(titolo_squash "$titolo" "$tipo" "$issue")
  # Il riferimento all'issue nel messaggio dello squash: lo cerca il rilascio per chiuderla
  corpo=""; [ -z "$issue" ] || corpo=$(riferimento_issue "$issue" "$base")
  # Squash: si unisce solo in develop. Se un giorno anche in master, lì serve "merge"
  # (docs/rilascio.md)
  if pf_pr_unisci "$numero" squash "$soggetto" "$corpo"; then
    dove="Unita in \`$base\`"
    variabile=$(cfg staging_variabile); workflow_staging=$(cfg staging_workflow)
    if [ -n "$variabile" ] && [ "$base" = "$RAMO_SVILUPPO" ]; then
      if [ "$(pf_variabile "$variabile")" = "$(cfg staging_valore si)" ]; then
        dove+=": è in staging"
      elif [ -n "$workflow_staging" ]; then
        # shellcheck disable=SC2086
        pf_workflow_avvia "$workflow_staging" --ref "$RAMO_SVILUPPO" $(cfg staging_avvio) && dove+=": parte lo staging"
      fi
    fi
    [ -z "$issue" ] || issue_unita "$issue" "$base" "$dove."
  else
    bloccato "i controlli sono verdi ma non riesco a unire la pull request #$numero."
  fi
else
  falliti=$(pf_ci_falliti "$RUN_CI"); [ -n "$falliti" ] || falliti="- (esito: $ESITO)"
  riparazioni=0; [ -z "$issue" ] || riparazioni=$(conta_commenti "$issue" "$T_RIPARAZIONE")
  if [ -n "$issue" ] && [ "$riparazioni" -lt "$MAX_RIPARAZIONI" ]; then
    printf '%s %s\n\nLa CI della pull request #%s è rossa:\n\n%s\n\nParte il developer per ripararla.\n' "$T_RIPARAZIONE" "$((riparazioni + 1))" "$numero" "$falliti" | pf_issue_commenta "$issue" -
    { echo "La CI della pull request è rossa. Job falliti:"; echo "$falliti"; echo; echo "Ultime righe dei log:"; pf_ci_log_falliti "$RUN_CI"; } > "$TMP_BASE/nota.txt"
    passo developer "$issue" "$issue" 1 "$TMP_BASE/nota.txt"
    exit 0
  fi
  bloccato "i controlli della pull request #$numero non passano."$'\n\n'"$falliti"
fi

bash "$CATENA/scripts/coda.sh"
