#!/usr/bin/env bash
# Esito del developer (token in scrittura, niente Claude).
# - Controlli verdi: un solo commit "feat: #<n>" (o "fix:" per gli hotfix) che assorbe i
#   tentativi precedenti (wip:), con nel corpo le note del developer e i test della base
#   toccati; push, sotto-task chiuso, passo dopo (prossimo sotto-task, revisione, oppure
#   chiusura in corsia diretta e nelle riparazioni, a meno che abbia toccato test della base:
#   allora la revisione).
# - Controlli rossi: il lavoro parziale resta sul ramo come "wip: #<n> tentativo k", così il
#   tentativo dopo corregge invece di rifare. Al fallimento di MAX_TENTATIVI escalation al
#   team leader (una volta), poi `bloccato`. Subito, se la raccolta ha ripristinato test
#   bloccati dal revisore.
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
# token, i test bloccati si ricalcolano dall'issue e la patch si controlla
if [ "$diretto" = 1 ]; then : > "$TMP_BASE/bloccati.txt"; else test_bloccati "$(pf_issue_corpo "$SOTTOTASK")" | sort -u > "$TMP_BASE/bloccati.txt"; fi
if [ -s "$ESITO_DIR/patch.diff" ]; then git apply --index "$ESITO_DIR/patch.diff"; fi
vietati=$(file_vietati "$base" "$TMP_BASE/bloccati.txt")
if [ -n "$vietati" ]; then
  git reset -q --hard
  bloccato "patch scartata: tocca file che la raccolta avrebbe dovuto rimettere com'erano (file protetti, e2e o test bloccati dal revisore). Va guardato il job agente:"$'\n\n```\n'"$vietati"$'\n```'
fi

# Test della base toccati e note del developer: vanno nei commenti e nel commit, il revisore li legge
note=""; [ ! -f "$ESITO_DIR/note.md" ] || note=$(tronca 3000 < "$ESITO_DIR/note.md")
calcola_extra() {
  toccati_base=$(test_base_toccati "$base" HEAD); extra=""
  [ -z "$toccati_base" ] || extra+=$'Test della base modificati (M) o cancellati (D):\n```\n'"$(tr '\t' ' ' <<< "$toccati_base")"$'\n```\n'
  [ -z "$note" ] || extra+=$'\nNote del developer:\n'"$note"$'\n'
}
calcola_extra

if [ "$stato" != ok ]; then
  { printf 'Tentativo %s di %s fallito: %s (%s)\n' "$TENTATIVO" "$MAX_TENTATIVI" "$motivo" "$cons"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; [ -z "$extra" ] || { echo; echo "$extra"; }; } | pf_issue_commenta "$SOTTOTASK" -
  # Il lavoro parziale resta sul ramo: il tentativo dopo lo corregge
  if [ -s "$ESITO_DIR/patch.diff" ]; then
    git commit -q -m "wip: #$SOTTOTASK tentativo $TENTATIVO"
    pf_push "$ramo"
  fi
  printf '%s' "$messaggio" > "$TMP_BASE/nota.txt"
  # Rosso con test della base ripristinati: il tentativo dopo rifarebbe la stessa modifica,
  # quindi si salta subito al team leader, che decide se tenerli bloccati o sbloccarli
  ripristinati=$(paste -sd, "$ESITO_DIR/test-ripristinati.txt" 2> /dev/null || true)
  # Dipendenze dichiarate che non si aggiungono: un altro tentativo darebbe lo stesso errore
  dip_ko=""; [ ! -s "$ESITO_DIR/dipendenze-fallite.md" ] || dip_ko=si
  if [ "$TENTATIVO" -lt "$MAX_TENTATIVI" ] && [ -z "$ripristinati" ] && [ -z "$dip_ko" ]; then
    pf_passo_avvia developer "$ISSUE" "$SOTTOTASK" "$((TENTATIVO + 1))" "$TMP_BASE/nota.txt"
    exit 0
  fi
  if [ -n "$ripristinati" ]; then perche="ha toccato test bloccati dal revisore ($ripristinati)"
  elif [ -n "$dip_ko" ]; then perche="non ha potuto aggiungere le dipendenze dichiarate"
  else perche="è fallito $MAX_TENTATIVI volte"; fi
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

# Le dipendenze dichiarate (dall'issue, con il token): nel corpo del commit, le leggono revisore e PR
dipendenze=""
if dipendenze_attive; then
  if [ "$diretto" = 1 ]; then dipendenze=$(commento_con_titolo "$ISSUE" "$T_SPECIFICA" | dipendenze_righe); else dipendenze=$(pf_issue_corpo "$SOTTOTASK" | dipendenze_righe); fi
fi

# Verde: un solo commit che assorbe i tentativi precedenti. Il corpo porta note e test della
# base toccati: il revisore li ritrova nel log
primo_wip=$(git log --reverse --format='%H %s' "origin/$base..HEAD" | grep -E " wip: #$SOTTOTASK " | sed -n 1p | cut -d' ' -f1 || true)
forza=()
if [ -n "$primo_wip" ]; then git reset -q --soft "$primo_wip^"; forza=(--force); fi
# Dopo l'assorbimento i test toccati si contano da prima dei wip: anche quelli dei tentativi falliti
[ -z "$primo_wip" ] || calcola_extra
{ echo "$pref: #$SOTTOTASK"
  if [ -n "$toccati_base" ]; then printf '\nTest della base modificati (M) o cancellati (D):\n%s\n' "$(tr '\t' ' ' <<< "$toccati_base")"; fi
  if [ -n "$note" ]; then printf '\nNote del developer:\n%s\n' "$note"; fi
  if [ -n "$dipendenze" ]; then printf '\n%s\n' "$dipendenze"; fi
} > "$TMP_BASE/commit.txt"
git commit -q --allow-empty -F "$TMP_BASE/commit.txt"
pf_push "${forza[@]}" "$ramo"

if [ "$diretto" = 1 ]; then
  { printf 'Developer: fatto in %s tentativo/i (%s). ' "$TENTATIVO" "$cons"
    if [ -n "$toccati_base" ]; then echo "Ha toccato test della base: parte la revisione."; else echo "Parte la chiusura."; fi
    [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; [ -z "$extra" ] || { echo; echo "$extra"; }; } | pf_issue_commenta "$ISSUE" -
  if [ -n "$toccati_base" ]; then pf_passo_avvia revisore "$ISSUE"; else pf_passo_avvia chiusura "$ISSUE"; fi
  exit 0
fi

pf_etichetta_togli "$SOTTOTASK" "$E_IN_CORSO"
{ printf 'Fatto sul ramo `%s` in %s tentativo/i (%s).\n' "$ramo" "$TENTATIVO" "$cons"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; [ -z "$extra" ] || { echo; echo "$extra"; }; } > "$TMP_BASE/chiusura.md"
pf_issue_chiudi "$SOTTOTASK" "$(cat "$TMP_BASE/chiusura.md")"

prossimo=$(pf_sottoissue_aperte "$ISSUE" | sed -n 1p)
if [ -n "$prossimo" ]; then
  pf_passo_avvia developer "$ISSUE" "$prossimo" 1
else
  pf_commenta_testo "$ISSUE" "Sotto-task finiti sul ramo \`$ramo\`: parte la revisione."
  pf_passo_avvia revisore "$ISSUE"
fi
