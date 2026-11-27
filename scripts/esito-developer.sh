#!/usr/bin/env bash
# Esito del developer (token in scrittura, niente Claude).
# - Controlli verdi: un solo commit "feat: #<n>" (o "fix:" per gli hotfix) che assorbe i
#   tentativi precedenti (wip:), con nel corpo le note del developer e i test della base
#   toccati; push, sotto-task chiuso, passo dopo (prossimo sotto-task, revisione, oppure
#   chiusura in corsia diretta e nelle riparazioni, a meno che abbia toccato test della base:
#   allora la revisione).
# - Controlli rossi: il lavoro parziale resta sul ramo come "wip: #<n> tentativo k", così il
#   tentativo dopo corregge invece di rifare. Al fallimento di MAX_TENTATIVI escalation al
#   team leader (una volta), poi `turn-human`. Subito, se la raccolta ha ripristinato test
#   bloccati dal revisore.
# - Domanda (stato `domanda`): il developer chiede al team leader; la patch resta come "wip: #<n>
#   domanda", la domanda va sul sotto-task, risponde il team leader (al massimo MAX_DOMANDE).
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
  printf 'Catena, sotto-task #%s: %s\n\nPer ripartire rispondi con un commento o rimetti `auto`.%s' "$SOTTOTASK" "$1" "$(riga_esecuzione)" | pf_issue_commenta "$ISSUE" -
  fermo "$ISSUE" "$SOTTOTASK"
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

# Il developer chiede al team leader: la patch resta sul ramo (wip:), la domanda sul sotto-task,
# poi risponde il team leader. Oltre MAX_DOMANDE è un tentativo fallito come gli altri
if [ "$stato" = domanda ]; then
  domanda=$(tronca 4000 < "$ESITO_DIR/domanda.md")
  if [ "$(conta_commenti "$SOTTOTASK" "$T_DOMANDA_DEV")" -lt "$MAX_DOMANDE" ]; then
    if [ -s "$ESITO_DIR/patch.diff" ]; then
      git commit -q -m "wip: #$SOTTOTASK domanda"
      pf_push "$ramo"
    fi
    { echo "$T_DOMANDA_DEV"; echo; echo "Tentativo: $TENTATIVO"; echo; echo "$domanda"; echo; echo "_${cons}_"; } | pf_issue_commenta "$SOTTOTASK" -
    [ "$diretto" = 1 ] || pf_commenta_testo "$ISSUE" "Il developer chiede al team leader sul sotto-task #$SOTTOTASK."
    passo team-leader "$ISSUE" "$SOTTOTASK" "$TENTATIVO"
    exit 0
  fi
  stato=fallito; messaggio=$domanda; motivo="domanda oltre il limite di $MAX_DOMANDE"
fi

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
  if [ "$TENTATIVO" -lt "$MAX_TENTATIVI" ] && [ -z "$ripristinati" ]; then
    passo developer "$ISSUE" "$SOTTOTASK" "$((TENTATIVO + 1))" "$TMP_BASE/nota.txt"
    exit 0
  fi
  if [ -n "$ripristinati" ]; then perche="ha toccato test bloccati dal revisore ($ripristinati)"
  else perche="è fallito $MAX_TENTATIVI volte"; fi
  # Riparazione di una CI rossa: niente escalation (riformulare a PR aperta riscriverebbe il
  # ramo), una sola riparazione e poi `turn-human` (docs/specifica.md, Scala di escalation)
  if [ "$diretto" = 1 ] && [ "$(conta_commenti "$ISSUE" "$T_RIPARAZIONE")" -gt 0 ]; then
    bloccato "la riparazione della CI rossa $perche. Ultimo errore:"$'\n\n```\n'"$(tail -c 2500 <<< "$messaggio")"$'\n```'
  fi
  if [ "$(conta_commenti "$SOTTOTASK" "$T_ESCALATION")" -lt "$MAX_ESCALATION" ]; then
    pf_commenta_testo "$ISSUE" "Il sotto-task #$SOTTOTASK $perche: chiedo al team leader (escalation)."
    passo team-leader "$ISSUE" "$SOTTOTASK" 1 "$TMP_BASE/nota.txt"
    exit 0
  fi
  bloccato "$perche anche dopo l'escalation. Ultimo errore:"$'\n\n```\n'"$(tail -c 2500 <<< "$messaggio")"$'\n```'
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
} > "$TMP_BASE/commit.txt"
git commit -q --allow-empty -F "$TMP_BASE/commit.txt"
pf_push "${forza[@]}" "$ramo"

if [ "$diretto" = 1 ]; then
  { printf 'Developer: fatto in %s tentativo/i (%s). ' "$TENTATIVO" "$cons"
    if [ -n "$toccati_base" ]; then echo "Ha toccato test della base: parte la revisione."; else echo "Parte la chiusura."; fi
    [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; [ -z "$extra" ] || { echo; echo "$extra"; }; } | pf_issue_commenta "$ISSUE" -
  if [ -n "$toccati_base" ]; then passo revisore "$ISSUE"; else passo chiusura "$ISSUE"; fi
  exit 0
fi

turno "$SOTTOTASK" ""
{ printf 'Fatto sul ramo `%s` in %s tentativo/i (%s).\n' "$ramo" "$TENTATIVO" "$cons"; [ -z "$avvisi" ] || { echo; echo "$avvisi"; }; [ -z "$extra" ] || { echo; echo "$extra"; }; } > "$TMP_BASE/chiusura.md"
pf_issue_chiudi "$SOTTOTASK" "$(cat "$TMP_BASE/chiusura.md")"

prossimo=$(pf_sottoissue_aperte "$ISSUE" | sed -n 1p)
if [ -n "$prossimo" ]; then
  passo developer "$ISSUE" "$prossimo" 1
else
  pf_commenta_testo "$ISSUE" "Sotto-task finiti sul ramo \`$ramo\`: parte la revisione."
  passo revisore "$ISSUE"
fi
