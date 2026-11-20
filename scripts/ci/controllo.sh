#!/usr/bin/env bash
# CI, un controllo (lint | tipi | test | test-db) con controlli.sh: gli stessi comandi e lo
# stesso container che usa il developer della catena. Un controllo non configurato in
# .catena.yml passa subito (il nome del check resta, come vuole il ruleset). In caso di
# errore stampa il log completo, che nella CI non costa token.
# Uso: controllo.sh <controllo>. Variabili: CODICE (si | no, dal job cambi).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"
cd "$REPO_DIR" || exit 1
c=$1
riepilogo=${GITHUB_STEP_SUMMARY:-/dev/null}

case "$c" in
  lint|tipi|test) chiave=$c ;;
  test-db) chiave=test_db ;;
  *) errore "controllo sconosciuto: $c"; exit 2 ;;
esac
if [ "${CODICE:-si}" != si ]; then echo "$c: saltato (solo documentazione)" | tee -a "$riepilogo"; exit 0; fi
if [ -z "$(cfg "$chiave")" ]; then echo "$c: non configurato in .catena.yml" | tee -a "$riepilogo"; exit 0; fi

bash "$CATENA/scripts/controlli.sh" install || { cat "$LOG_DIR/install.log" 2> /dev/null; exit 1; }
if bash "$CATENA/scripts/controlli.sh" "$c"; then exit 0; fi
echo "::group::Log completo di $c"; cat "$LOG_DIR/$c.log" 2> /dev/null; cat "$LOG_DIR/db.log" 2> /dev/null; echo "::endgroup::"
exit 1
