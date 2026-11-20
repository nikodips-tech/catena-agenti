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
limita() { head -c "$1"; }

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
      # Escalation: il sotto-task è fallito tre volte
      specifica; sottotask_md
      nota_md errore.log "le ultime righe dell'errore dell'ultimo tentativo del developer"
      git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
      if git show-ref -q --verify "refs/remotes/origin/$RAMO"; then
        git diff "origin/$BASE...origin/$RAMO" | limita 150000 > "$CONTESTO/lavoro.diff"
        descrivi lavoro.diff "tutto il lavoro sul ramo $RAMO rispetto a $BASE, compresi i test del sotto-task e i tentativi del developer (commit wip:)"
      fi
      { echo "Il sotto-task #$SOTTOTASK è fallito. Sei chiamato in escalation: decidi se il test è sbagliato,"
        echo "se il sotto-task va riformulato in pezzi più piccoli o se serve davvero una persona (docs/specifica.md, Escalation)."
        echo "Se l'errore dice che sono stati ripristinati test della base, l'escalation è arrivata subito: il developer"
        echo "li ha modificati senza permesso. Se il sotto-task richiede davvero di cambiarli, riformula indicandoli in"
        echo "test_modificabili; se non serve, riformula spiegando nella descrizione che vanno lasciati com'erano."
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
    # I test già presenti nella base non si toccano: l'elenco di quelli che il ramo ha aggiunto
    git diff --diff-filter=A --name-only --no-renames "origin/$BASE...HEAD" | grep -P "$RE_TEST" | sort -u > "$CONTESTO/test-del-ramo.txt" || true
    descrivi test-del-ramo.txt "i file di test aggiunti su questo ramo dai sotto-task precedenti (puoi modificarli)"
    # I test della base modificabili: quelli che il team leader autorizza nel sotto-task (in
    # corsia diretta e nelle riparazioni, nella specifica) e quelli già modificati sul ramo,
    # che la raccolta di un passo precedente ha lasciato passare. raccolta.sh legge questo file
    if [ "$SOTTOTASK" = "$ISSUE" ]; then autorizzati=$(cat "$CONTESTO/specifica.md"); else autorizzati=$(cat "$CONTESTO/sottotask.md"); fi
    { test_modificabili "$autorizzati"
      git diff --diff-filter=M --name-only --no-renames "origin/$BASE...HEAD" | grep -P "$RE_TEST" || true
    } | sort -u > "$CONTESTO/test-modificabili.txt"
    descrivi test-modificabili.txt "i test che esistono già in $BASE e che puoi modificare (non cancellare); tutti gli altri test di $BASE non si toccano"
    nota_md errore.txt "le ultime righe dell'errore del tentativo precedente, o i controlli falliti della CI da riparare"
    wip=$(git log --format=%s "origin/$BASE..HEAD" 2> /dev/null | grep -E "^wip: #$SOTTOTASK " | head -1 || true)
    if [ -n "$wip" ]; then
      git log --format= --name-only --grep="^wip: #$SOTTOTASK " "origin/$BASE..HEAD" | grep -v '^$' | sort -u > "$CONTESTO/lavoro-precedente.txt"
      descrivi lavoro-precedente.txt "i file che il tentativo precedente ha già cambiato: il suo lavoro è già nel checkout, correggilo invece di rifarlo"
    fi ;;
  revisore)
    specifica; differenze
    git diff --diff-filter=A --name-only --no-renames "origin/$BASE...HEAD" | grep -P "$RE_TEST" | sort -u > "$CONTESTO/test-developer.txt" || true
    descrivi test-developer.txt "i file di test aggiunti sul ramo dal developer (vuoto se nessuno)"
    git diff --diff-filter=M --name-only --no-renames "origin/$BASE...HEAD" | grep -P "$RE_TEST" | sort -u > "$CONTESTO/test-modificati.txt" || true
    descrivi test-modificati.txt "i test che esistono già in $BASE e che il developer ha modificato con il permesso del team leader (vuoto se nessuno): controlla che non siano stati indeboliti"
    pf_issue_commenti "$ISSUE" | jq -r '[.[] | select(.corpo | startswith("## Revisione")) | .corpo] | join("\n\n---\n\n")' > "$CONTESTO/revisioni-precedenti.md"
    descrivi revisioni-precedenti.md "le tue revisioni precedenti su questa issue (vuoto al primo giro): non ripetere richieste già fatte" ;;
  editor)
    specifica; differenze ;;
  *) errore "ruolo sconosciuto: $ruolo"; exit 2 ;;
esac
