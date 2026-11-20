#!/usr/bin/env bash
# CI, job `migrazioni`: le istruzioni distruttive nelle migrazioni nuove (chiave
# `migrazioni` di .catena.yml: in un hotfix bloccano, altrove si elencano) e i test
# indeboliti (spenti: bloccano; tolti: si segnalano), sui file di test di `file_test`.
# Variabili: BASE (la base della PR), RAMO (il ramo della PR).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"
cd "$REPO_DIR" || exit 1
riepilogo=${GITHUB_STEP_SUMMARY:-/dev/null}
base=origin/${BASE:-$RAMO_SVILUPPO}
esito=0

cartella=$(cfg migrazioni)
if [ -z "$cartella" ]; then
  echo "Nessuna cartella di migrazioni in .catena.yml." >> "$riepilogo"
else
  # Se lo script si rompe il controllo è rosso: meglio un falso allarme che un DROP non visto
  if ! trovate=$(bash "$CATENA/scripts/ci/migrazioni-distruttive.sh" "$base" HEAD "$cartella"); then
    errore "non riesco a leggere le migrazioni tra $base e HEAD"; exit 1
  fi
  if [ -z "$trovate" ]; then
    echo "Nessuna migrazione distruttiva." >> "$riepilogo"
  else
    { echo "### Migrazioni distruttive"; echo '```'; echo "$trovate"; echo '```'; } >> "$riepilogo"
    echo "$trovate"
    if [[ "${RAMO:-}" == hotfix/* ]]; then errore "un hotfix può contenere solo migrazioni additive"; esito=1; fi
  fi
fi

bash "$CATENA/scripts/ci/test-indeboliti.sh" "$base" HEAD "$RE_TEST" || esito=1
exit $esito
