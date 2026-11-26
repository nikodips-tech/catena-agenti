#!/usr/bin/env bash
# Prepara i dati che riceve l'agente, in file fuori dal repo ($CONTESTO), e li descrive in
# $CONTESTO/descrizione.md (una riga per file: finisce nel prompt). Claude riceve solo questo,
# non legge le issue da sé: così il job può avere un token in sola lettura e i commenti
# dell'issue non possono cambiare le istruzioni.
# Uso: contesto.sh <ruolo>. Variabili: ISSUE, SOTTOTASK, TENTATIVO, NOTA, RAMO, BASE, PROPRIETARIO.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR"
ruolo=$1
mkdir -p "$CONTESTO"; : > "$CONTESTO/descrizione.md"

descrivi() { echo "- $CONTESTO/$1: $2" >> "$CONTESTO/descrizione.md"; }
# limita <byte>: taglia i file grandi (un diff enorme costa token e non si legge comunque)
# head chiude la pipe dopo n byte: senza `cat` il comando a monte prende SIGPIPE e con
# pipefail lo script esce con 141
limita() { head -c "$1"; cat > /dev/null; }

specifica() {
  commento_con_titolo "$ISSUE" "$T_SPECIFICA" > "$CONTESTO/specifica.md"
  [ -s "$CONTESTO/specifica.md" ] || { errore "specifica mancante sull'issue #$ISSUE"; exit 1; }
  descrivi specifica.md "la specifica dell'issue principale #$ISSUE"
}
issue_md() {
  { echo "# $(pf_issue_titolo "$ISSUE")"; echo; pf_issue_corpo "$ISSUE"; } > "$CONTESTO/issue.md"
  descrivi issue.md "titolo e testo dell'issue #$ISSUE: dice cosa vuole chi la scrive"
}
sottotask_md() {
  { echo "# $(pf_issue_titolo "$SOTTOTASK")"; echo; pf_issue_corpo "$SOTTOTASK"; } > "$CONTESTO/sottotask.md"
  descrivi sottotask.md "titolo e testo del sotto-task #$SOTTOTASK"
}
nota_md() {
  [ -n "${NOTA:-}" ] || return 0
  printf '%s\n' "$NOTA" > "$CONTESTO/$1"
  descrivi "$1" "$2"
}
differenze() {
  git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
  git diff "origin/$BASE...HEAD" | limita 200000 > "$CONTESTO/differenze.diff"
  descrivi differenze.diff "le differenze tra $BASE e il ramo $RAMO (tutto il lavoro fatto)"
}

case "$ruolo" in
  team-leader)
    issue_md
    pf_issue_commenti "$ISSUE" | jq -r --arg o "$PROPRIETARIO" '[.[] | select(.autore == $o) | .corpo] | join("\n\n---\n\n")' > "$CONTESTO/risposte.md"
    descrivi risposte.md "i commenti del proprietario sull'issue, cioè le risposte alle tue domande (vuoto se nessuno)"
    if [ -n "${SOTTOTASK:-}" ]; then
      # Escalation: il sotto-task è fallito o ha toccato test bloccati
      specifica; sottotask_md
      nota_md errore.log "le ultime righe dell'errore dell'ultimo tentativo del developer"
      git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
      if git show-ref -q --verify "refs/remotes/origin/$RAMO"; then
        git diff "origin/$BASE...origin/$RAMO" | limita 150000 > "$CONTESTO/lavoro.diff"
        descrivi lavoro.diff "tutto il lavoro sul ramo $RAMO rispetto a $BASE, compresi i test del sotto-task e i tentativi del developer (commit wip:)"
      fi
      { echo "Il sotto-task #$SOTTOTASK è fallito $MAX_TENTATIVI volte, oppure subito perché il developer ha toccato test"
        echo "bloccati dal revisore. Sei chiamato in escalation: decidi se il test è sbagliato, se il sotto-task va"
        echo "riformulato in pezzi più piccoli o se serve davvero una persona (docs/specifica.md, Escalation)."
        echo "Se l'errore dice che sono stati ripristinati test bloccati, decidi se tenerli bloccati (mettili in"
        echo "test_bloccati dei sotto-task nuovi) o sbloccarli (omettili e spiega nella descrizione come vanno cambiati)."
      } > "$CONTESTO/escalation.md"
      descrivi escalation.md "perché sei stato chiamato"
    fi ;;
  developer)
    specifica
    if [ "$SOTTOTASK" = "$ISSUE" ]; then
      # Corsia diretta o riparazione: il lavoro è l'issue stessa, test compresi
      issue_md
      cp "$CONTESTO/issue.md" "$CONTESTO/sottotask.md"
      descrivi sottotask.md "il lavoro da fare è l'issue stessa (corsia diretta): scrivi codice e test"
    else
      sottotask_md
    fi
    # I test della base che il revisore ha fatto ripristinare: li legge anche raccolta.sh.
    # In corsia diretta e nelle riparazioni il sotto-task è l'issue: nessun test bloccato
    if [ "$SOTTOTASK" = "$ISSUE" ]; then : > "$CONTESTO/test-bloccati.txt"; else test_bloccati "$(cat "$CONTESTO/sottotask.md")" | sort -u > "$CONTESTO/test-bloccati.txt"; fi
    descrivi test-bloccati.txt "i test della base che il revisore ha fatto ripristinare: non toccarli, fai passare il codice (vuoto se nessuno)"
    nota_md errore.txt "le ultime righe dell'errore del tentativo precedente, o i controlli falliti della CI da riparare"
    wip=$(git log --format=%s "origin/$BASE..HEAD" 2> /dev/null | grep -E "^wip: #$SOTTOTASK " | sed -n 1p || true)
    if [ -n "$wip" ]; then
      git log --format= --name-only --grep="^wip: #$SOTTOTASK " "origin/$BASE..HEAD" | grep -v '^$' | sort -u > "$CONTESTO/lavoro-precedente.txt"
      descrivi lavoro-precedente.txt "i file che il tentativo precedente ha già cambiato: il suo lavoro è già nel checkout, correggilo invece di rifarlo"
    fi ;;
  revisore)
    specifica; differenze
    git diff --diff-filter=A --name-only --no-renames "origin/$BASE...HEAD" | grep -P "$RE_TEST" | sort -u > "$CONTESTO/test-developer.txt" || true
    descrivi test-developer.txt "i file di test aggiunti sul ramo dal developer (vuoto se nessuno)"
    # Test della base modificati (M) o cancellati (D) sul ramo
    git diff --name-status --no-renames --diff-filter=MD "origin/$BASE...HEAD" | while IFS=$'\t' read -r st f; do
      if grep -qP -- "$RE_TEST" <<< "$f"; then printf '%s\t%s\n' "$st" "$f"; fi
    done > "$CONTESTO/test-base-toccati.txt"
    descrivi test-base-toccati.txt "i test della base modificati (M) o cancellati (D) dal developer (vuoto se nessuno): giudica se il cambiamento è giustificato"
    # Le note stanno nel corpo dei commit del developer (esito-developer.sh)
    for c in $(git log --reverse --format=%H "origin/$BASE..HEAD"); do
      corpo=$(git show -s --format=%b "$c")
      if [ -n "$corpo" ]; then printf '%s\n%s\n\n' "$(git show -s --format=%s "$c")" "$corpo"; fi
    done > "$CONTESTO/note-developer.md"
    descrivi note-developer.md "le note del developer sui sotto-task: perché ha toccato test della base o fatto scelte particolari (vuoto se nessuna)"
    # Le dipendenze nuove le scrive esito-developer.sh nel corpo dei commit (righe dell'issue)
    git log --format=%b "origin/$BASE..HEAD" | dipendenze_righe > "$CONTESTO/dipendenze.txt"
    descrivi dipendenze.txt "le dipendenze nuove aggiunte sul ramo (vuoto se nessuna): giudicale"
    pf_issue_commenti "$ISSUE" | jq -r '[.[] | select(.corpo | startswith("## Revisione")) | .corpo] | join("\n\n---\n\n")' > "$CONTESTO/revisioni-precedenti.md"
    descrivi revisioni-precedenti.md "le tue revisioni precedenti su questa issue (vuoto al primo giro): non ripetere richieste già fatte" ;;
  editor)
    specifica; differenze ;;
  *) errore "ruolo sconosciuto: $ruolo"; exit 2 ;;
esac
