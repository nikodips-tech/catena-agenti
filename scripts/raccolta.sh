#!/usr/bin/env bash
# Dopo Claude, senza Claude: raccoglie ciò che l'agente ha cambiato nel checkout e lo giudica.
# I file protetti si rimettono com'erano (avviso, non blocco); i file fuori ambito del ruolo
# si scartano; per il developer si formatta e si eseguono i controlli. Il risultato va in
# $ESITO_DIR (artifact) per il job esito: stato, messaggio.md, motivo.txt, avvisi.md,
# patch.diff, file.txt, esito.json.
# Uso: raccolta.sh <ruolo>. Variabili: INIZIO (commit di partenza), BASE, RAMO, SOTTOTASK, ISSUE.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
ruolo=$1
cd "$REPO_DIR"
mkdir -p "$ESITO_DIR" "$LOG_DIR"
: > "$ESITO_DIR/avvisi.md"
uscita=$(cat "$ESITO_DIR/claude-exit" 2> /dev/null || echo "?")
[ -f esito.json ] && mv esito.json "$ESITO_DIR/esito.json"
[ -f note-developer.md ] && mv note-developer.md "$ESITO_DIR/note.md"
[ -f domanda-developer.md ] && mv domanda-developer.md "$ESITO_DIR/domanda.md"

avviso_file() { # <titolo> <elenco>
  [ -n "$2" ] || return 0
  printf '%s:\n```\n%s\n```\n\n' "$1" "$2" >> "$ESITO_DIR/avvisi.md"
}
# ripristina_da <commit> <file…>: come in quel commit (o cancellati se lì non c'erano)
ripristina_da() {
  local f da=$1; shift
  for f in "$@"; do
    if git cat-file -e "$da:$f" 2> /dev/null; then git checkout -q "$da" -- "$f"; else git rm -q --cached -- "$f" > /dev/null 2>&1 || true; rm -f -- "$f"; fi
  done
}
# ripristina <file…>: come al commit di partenza
ripristina() { ripristina_da "$INIZIO" "$@"; }
# fotografa: indice, elenco dei file e patch rispetto al commit di partenza
fotografa() {
  git add -A -- . ":!esito.json" > /dev/null 2>&1 || true
  git diff --cached --name-status --no-renames "$INIZIO" > "$ESITO_DIR/stato-file.txt"
  cut -f2- "$ESITO_DIR/stato-file.txt" > "$ESITO_DIR/file.txt"
  git diff --cached --binary --no-renames "$INIZIO" > "$ESITO_DIR/patch.diff"
}
stato() { echo "$1" > "$ESITO_DIR/stato"; }

# File protetti: mai un blocco, si rimettono com'erano e si avvisa (non per `applica`: i consigli approvati
# toccano CLAUDE.md, .claude/, .catena.yml, e lo scarto lo fa il suo caso più sotto)
if [ "$ruolo" != applica ]; then avviso_file "File protetti toccati e ripristinati" "$(ripristina_protetti "$BASE")"; fi
fotografa

case "$ruolo" in
  team-leader|revisore|retrospettiva)
    # Non devono toccare file: se lo fanno, le modifiche si ignorano
    avviso_file "File modificati e ignorati (il ruolo non modifica il repo)" "$(cat "$ESITO_DIR/file.txt")"
    if [ -f "$ESITO_DIR/esito.json" ]; then stato ok; else stato mancante; echo "esito.json non trovato (uscita di Claude: $uscita)" > "$ESITO_DIR/messaggio.md"; fi ;;

  developer)
    e2e=$(grep -P "$RE_E2E" "$ESITO_DIR/file.txt" || true)
    if [ -n "$e2e" ]; then mapfile -t f <<< "$e2e"; ripristina "${f[@]}"; avviso_file "Test e2e toccati e ripristinati" "$e2e"; fi
    # I test della base si possono modificare e cancellare (il revisore li giudica). Si
    # ripristinano solo quelli che il revisore ha bloccato (test-bloccati.txt, contesto.sh)
    bloccati="$CONTESTO/test-bloccati.txt"; [ -f "$bloccati" ] || : > "$bloccati"
    toccati=""
    while IFS= read -r f; do
      [ -n "$f" ] && grep -qxF -- "$f" "$bloccati" && toccati+="$f"$'\n'
    done < "$ESITO_DIR/file.txt"
    toccati=${toccati%$'\n'}
    if [ -n "$toccati" ]; then
      mapfile -t f <<< "$toccati"; ripristina "${f[@]}"
      avviso_file "Test bloccati dal revisore toccati e ripristinati" "$toccati"
    fi
    # Per esito-developer.sh: se i controlli falliscono, l'escalation parte subito
    printf '%s' "$toccati" > "$ESITO_DIR/test-ripristinati.txt"
    fotografa
    # Una domanda al team leader: il lavoro fatto resta (patch), niente formattazione né controlli
    if [ -s "$ESITO_DIR/domanda.md" ]; then
      stato domanda
      consumo "$ESITO_DIR/claude.json" > "$ESITO_DIR/consumo.txt"
      log "developer: domanda al team leader, $(cat "$ESITO_DIR/consumo.txt")"
      exit 0
    fi
    # Formattazione di tutto ciò che cambia rispetto alla base, test compresi
    mapfile -t cambiati < <(git diff --cached --name-only --diff-filter=d --no-renames "origin/$BASE" || true)
    [ "${#cambiati[@]}" -eq 0 ] || bash "$CATENA/scripts/controlli.sh" formatta "${cambiati[@]}" > /dev/null 2>&1 || true
    fotografa
    # Manifest o lock cambiati: `aggiorna` riallinea il lock al manifest (anche se il developer
    # se n'è dimenticato o l'ha scritto a mano). Con la rete e nel container dei controlli
    aggiorna_ko=""
    if [ -n "$(cfg aggiorna)" ] && grep -qP -- "$RE_MANIFEST|$RE_LOCK" "$ESITO_DIR/file.txt"; then
      if bash "$CATENA/scripts/controlli.sh" aggiorna > "$LOG_DIR/aggiorna-raccolta.log" 2>&1; then fotografa; else aggiorna_ko=1; fi
    fi
    if [ -n "$aggiorna_ko" ]; then
      stato fallito
      tail -c 4000 "$LOG_DIR/aggiorna-raccolta.log" > "$ESITO_DIR/messaggio.md"
      echo "aggiornamento delle dipendenze fallito" > "$ESITO_DIR/motivo.txt"
    elif [ ! -s "$ESITO_DIR/file.txt" ] && [ -z "$(git log --format=%s "origin/$BASE..HEAD" | grep -E "^wip: #$SOTTOTASK " || true)" ]; then
      stato fallito
      echo "il developer non ha modificato nessun file (uscita di Claude: $uscita)" | tee "$ESITO_DIR/messaggio.md" > "$ESITO_DIR/motivo.txt"
    # `if` e non `$?`: la shell di Actions esce al primo errore e lo stato non verrebbe scritto
    elif CATENA_REINSTALLA=1 bash "$CATENA/scripts/controlli.sh" tutto > "$LOG_DIR/controlli.log" 2>&1; then
      stato ok
    else
      stato fallito
      { [ -z "$toccati" ] || printf 'Avevi toccato test bloccati dal revisore (%s): sono stati ripristinati.\n\n' "$(paste -sd, - <<< "$toccati")"
        tail -c 4000 "$LOG_DIR/controlli.log"; } > "$ESITO_DIR/messaggio.md"
      riga=$(grep -m1 -E ': FALLITO' "$LOG_DIR/controlli.log" || tail -n 1 "$LOG_DIR/controlli.log")
      echo "controlli falliti: $riga" > "$ESITO_DIR/motivo.txt"
    fi
    cp "$LOG_DIR/controlli.log" "$ESITO_DIR/controlli.log" 2> /dev/null || true ;;

  editor)
    fuori=$(grep -vE "$RE_DOCS" "$ESITO_DIR/file.txt" || true)
    if [ -n "$fuori" ]; then mapfile -t f <<< "$fuori"; ripristina "${f[@]}"; avviso_file "File fuori da docs/ e README scartati" "$fuori"; fi
    fotografa
    if [ -s "$ESITO_DIR/file.txt" ]; then stato ok; else stato vuoto; fi ;;

  applica)
    # Solo i file dei consigli (RE_APPLICA); mai .github/ né .env: il resto si scarta con un avviso
    fuori=$({ grep -vP "$RE_APPLICA" "$ESITO_DIR/file.txt"; grep -P '^\.github/|(^|/)\.env' "$ESITO_DIR/file.txt"; } | sort -u || true)
    if [ -n "$fuori" ]; then mapfile -t f <<< "$fuori"; ripristina "${f[@]}"; avviso_file "File fuori dall'ambito della retrospettiva scartati" "$fuori"; fi
    fotografa
    if [ -s "$ESITO_DIR/file.txt" ]; then stato ok; else stato vuoto; fi ;;

  *) errore "ruolo sconosciuto: $ruolo"; exit 2 ;;
esac

consumo "$ESITO_DIR/claude.json" > "$ESITO_DIR/consumo.txt"
log "$ruolo: stato $(cat "$ESITO_DIR/stato"), $(cat "$ESITO_DIR/consumo.txt")"
exit 0
