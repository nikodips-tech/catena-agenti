#!/usr/bin/env bash
# Developer, prima di Claude e con la rete: aggiunge le dipendenze che il team leader ha
# dichiarato nel sotto-task (righe "Dipendenze nuove:" e "Dipendenze di sviluppo nuove:", in
# corsia diretta nella specifica) con i comandi `dipendenze` e `dipendenze_sviluppo` di
# .catena.yml, poi reinstalla. Claude trova manifest e lock aggiornati e i pacchetti
# installati; il lock non lo scrive mai lui (raccolta.sh lo rimette come qui).
# Se non riesce: $ESITO_DIR/dipendenze-fallite.md e `esito=ko`, il tentativo fallisce senza
# far partire Claude.
# Uso: dipendenze.sh. Variabili: ISSUE, SOTTOTASK.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR" || exit 1
mkdir -p "$ESITO_DIR" "$LOG_DIR"
uscita=${GITHUB_OUTPUT:-/dev/null}

if [ "$SOTTOTASK" = "$ISSUE" ]; then testo=$(cat "$CONTESTO/specifica.md"); else testo=$(cat "$CONTESTO/sottotask.md"); fi

fallito() {
  git reset -q --hard; git clean -fdq
  printf 'dipendenze: FALLITO\n\n%s\n' "$1" | tee "$ESITO_DIR/dipendenze-fallite.md"
  echo "esito=ko" >> "$uscita"
  exit 0
}

aggiunte=""
aggiungi() { # <chiave del comando> <prefisso della riga>
  local comando p pacchetti
  mapfile -t pacchetti < <(elenco_riga "$testo" "$2")
  [ "${#pacchetti[@]}" -gt 0 ] || return 0
  comando=$(cfg "$1")
  [ -n "$comando" ] || fallito "Il sotto-task dichiara \"$2: ${pacchetti[*]}\", ma in .catena.yml manca \`$1\`."
  for p in "${pacchetti[@]}"; do grep -qP -- "$RE_PACCHETTO" <<< "$p" || fallito "Nome di pacchetto non valido: $p"; done
  esegui "$comando ${pacchetti[*]}" > "$LOG_DIR/dipendenze.log" 2>&1 \
    || fallito "\`$comando ${pacchetti[*]}\`:"$'\n'"$(tail -n 30 "$LOG_DIR/dipendenze.log")"
  aggiunte+="$2: ${pacchetti[*]}"$'\n'
}
aggiungi dipendenze "$T_DIP"
aggiungi dipendenze_sviluppo "$T_DIP_SVILUPPO"
aggiungi dipendenze_togli "$T_DIP_TOGLI"
[ -n "$aggiunte" ] || exit 0

# Nel container i file li riscrive root: tornano del runner, così Claude può ancora modificarli
contenitore=$(cfg container)
if [ -n "$contenitore" ]; then
  mapfile -t cambiati < <(git ls-files -m -o --exclude-standard)
  [ "${#cambiati[@]}" -eq 0 ] || docker run --rm -v "$REPO_DIR:/r" -w /r "$contenitore" chown "$(id -u):$(id -g)" -- "${cambiati[@]}"
fi
CATENA_REINSTALLA=1 bash "$CATENA/scripts/controlli.sh" install > "$LOG_DIR/dipendenze-install.log" 2>&1 \
  || fallito "$(tail -n 30 "$LOG_DIR/dipendenze-install.log")"

# Un commit locale (mai spinto) segna il lock giusto: raccolta.sh ci rimette quelli toccati.
# La patch del tentativo si calcola da INIZIO, quindi manifest e lock entrano nel commit
git_identita
git add -A -- . && git commit -q --allow-empty -m "dipendenze: #$SOTTOTASK"
echo "DOPO_DIPENDENZE=$(git rev-parse HEAD)" >> "${GITHUB_ENV:-/dev/null}"

printf '%s' "$aggiunte" > "$CONTESTO/dipendenze.txt"
echo "- $CONTESTO/dipendenze.txt: le dipendenze aggiunte (o tolte) per questo sotto-task, già nel manifest e nel lock e installate: usale; le dipendenze nel manifest e il lock non si toccano" >> "$CONTESTO/descrizione.md"
printf 'dipendenze: aggiunte\n%s' "$aggiunte"
