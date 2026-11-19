#!/usr/bin/env bash
# Formattazione, lint, tipi e test del progetto con i comandi di .catena.yml, nello stesso
# container della CI. Output corto, perché finisce nel contesto del developer e costa token a
# ogni turno: per ogni controllo nome e OK/FALLITO e, se fallisce, al massimo 30 righe di errore
# più il percorso del log completo (in LOG_DIR, fuori dal repo, caricato come artifact).
#
# Uso: controlli.sh install | formatta <file…> | lint | tipi | test | test-db | tutto
# Chiavi lette da .catena.yml: docs/configurazione.md.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR"
mkdir -p "$LOG_DIR"

CARTELLA=$(cfg cartella .)
CONTAINER=$(cfg container)
RETE=$(cfg container_rete host)
OPZIONI=$(cfg container_opzioni)

# esegui <comando shell>: nella cartella del progetto, nel container se configurato
esegui() {
  if [ -n "$CONTAINER" ]; then
    # shellcheck disable=SC2086
    docker run --rm --network "$RETE" -e NO_COLOR=1 -e FORCE_COLOR=0 -e CI=1 $OPZIONI \
      -v "$PWD/$CARTELLA:/lavoro" -w /lavoro "$CONTAINER" sh -c "$1"
  else
    (cd "$CARTELLA" && NO_COLOR=1 FORCE_COLOR=0 CI=1 sh -c "$1")
  fi
}

# controlla <nome> <comando>: log completo su file, a video l'esito
controlla() {
  local nome=$1 comando=$2 log="$LOG_DIR/$1.log" righe
  if [ -z "$comando" ]; then echo "$nome: saltato (non configurato)"; return 0; fi
  if esegui "$comando" > "$log" 2>&1; then echo "$nome: OK"; return 0; fi
  echo "$nome: FALLITO"
  righe=$(grep -E -i "$(cfg filtro_errori '^/lavoro/|error|fail|✖|×|❯|\[warn\]|expected|received')" "$log" | head -n 30 || true)
  [ -n "$righe" ] || righe=$(tail -n 30 "$log")
  echo "$righe" | cut -c1-300
  echo "Log completo: $log"
  return 1
}

installa() {
  local comando segno; comando=$(cfg installa); segno=$(cfg installato_se)
  [ -n "$comando" ] || { echo "install: saltato (non configurato)"; return 0; }
  if [ -n "$segno" ] && [ -e "$CARTELLA/$segno" ] && [ -z "${CATENA_REINSTALLA:-}" ]; then echo "install: già fatto"; return 0; fi
  if esegui "$comando" > "$LOG_DIR/install.log" 2>&1; then echo "install: OK"; return 0; fi
  echo "install: FALLITO"; tail -n 30 "$LOG_DIR/install.log"; echo "Log completo: $LOG_DIR/install.log"
  return 1
}

# Test con database: il servizio lo accende e spegne il runner (db_avvia, db_ferma), i test
# girano nel container sulla rete host
test_db() {
  local comando; comando=$(cfg test_db)
  [ -n "$comando" ] || { echo "test-db: saltato (non configurato)"; return 0; }
  local avvia ferma esito=0; avvia=$(cfg db_avvia); ferma=$(cfg db_ferma)
  if [ -n "$avvia" ]; then sh -c "$avvia" > "$LOG_DIR/db.log" 2>&1 || { echo "test-db: FALLITO (il database non parte)"; tail -n 30 "$LOG_DIR/db.log"; return 1; }; fi
  controlla test-db "$comando" || esito=1
  if [ -n "$ferma" ]; then sh -c "$ferma" >> "$LOG_DIR/db.log" 2>&1 || true; fi
  return $esito
}

# formatta <file…>: percorsi dalla radice del repo; il formattatore e i fix del linter sui
# file che li riguardano (formatta_file, formatta_codice_file), nella cartella del progetto
formatta() {
  local comando codice re_tutti re_codice tutti="" lista_codice="" f rel
  comando=$(cfg formatta); codice=$(cfg formatta_codice)
  re_tutti=$(cfg formatta_file '\.(js|mjs|cjs|ts|tsx|vue|svelte|json|css|scss|md|yml|yaml)$')
  re_codice=$(cfg formatta_codice_file '\.(js|mjs|cjs|ts|tsx|vue|svelte)$')
  [ -n "$comando$codice" ] || return 0
  for f in "$@"; do
    [ -f "$f" ] || continue
    if [ "$CARTELLA" = . ]; then rel=$f; else [[ "$f" == "$CARTELLA"/* ]] || continue; rel=${f#"$CARTELLA"/}; fi
    if grep -qE "$re_tutti" <<< "$rel"; then tutti="$tutti '$rel'"; fi
    if grep -qE "$re_codice" <<< "$rel"; then lista_codice="$lista_codice '$rel'"; fi
  done
  {
    [ -z "$comando" ] || [ -z "$tutti" ] || esegui "${comando//\{file\}/$tutti}" || true
    [ -z "$codice" ] || [ -z "$lista_codice" ] || esegui "${codice//\{file\}/$lista_codice}" || true
  } > "$LOG_DIR/formatta.log" 2>&1
  echo "formatta: fatto"
}

case "${1:-}" in
  install) installa ;;
  formatta) shift; formatta "$@" ;;
  lint) controlla lint "$(cfg lint)" ;;
  tipi) controlla tipi "$(cfg tipi)" ;;
  test) controlla test "$(cfg test)" ;;
  test-db) test_db ;;
  tutto)
    # Tutti, anche se uno fallisce: l'esito è fallito se ne fallisce uno
    ko=0
    controlla lint "$(cfg lint)" || ko=1
    controlla tipi "$(cfg tipi)" || ko=1
    controlla test "$(cfg test)" || ko=1
    test_db || ko=1
    exit $ko ;;
  *) echo "uso: controlli.sh install | formatta <file…> | lint | tipi | test | test-db | tutto" >&2; exit 2 ;;
esac
