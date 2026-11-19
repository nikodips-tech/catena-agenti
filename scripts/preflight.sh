#!/usr/bin/env bash
# Controllo iniziale della catena, senza Claude: tutto ciò che in passato si scopriva a metà
# corsa (segreto mancante, App non installata, environment assente, etichette, configurazione)
# si verifica qui, in un colpo, e si riferisce con un elenco preciso. Ciò che si può
# sistemare da soli (le etichette) si sistema.
#
# Uso: preflight.sh            → stampa i problemi, esce con 1 se ce ne sono
#      preflight.sh etichette  → crea solo le etichette mancanti (anche dalla migrazione)
# Variabili: CLAUDE_TOKEN_PRESENTE (true|false, dal workflow), APP_OK (si|no, dal workflow).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"

# nome colore descrizione
etichette_catena() {
  cat <<'FINE'
task	0E8A16	Lavoro normale, va verso develop
hotfix	B60205	Correzione urgente, parte da master
sotto-task	C5DEF5	Sub-issue creata dalla catena
auto	5319E7	Avvia la catena: la mette solo il proprietario
in-corso	FBCA04	Gli agenti ci stanno lavorando
domanda	D93F0B	Serve una risposta del proprietario
bloccato	000000	Errore di infrastruttura o tetto superato: serve una mano
unione-automatica	1D76DB	A controlli verdi la pull request si unisce da sola
FINE
}

crea_etichette() {
  local esistenti nome colore descrizione create=""
  esistenti=$(pf_etichette_repo)
  while IFS=$'\t' read -r nome colore descrizione; do
    grep -qxF -- "$nome" <<< "$esistenti" && continue
    pf_etichetta_crea "$nome" "$colore" "$descrizione" && create="$create $nome"
  done < <(etichette_catena)
  [ -z "$create" ] || log "etichette create:$create"
}

if [ "${1:-}" = etichette ]; then crea_etichette; exit 0; fi

problemi=()
crea_etichette || problemi+=("Non riesco a creare le etichette della catena (serve issues: write)")

[ "${CLAUDE_TOKEN_PRESENTE:-false}" = true ] || problemi+=("Manca il segreto \`CLAUDE_CODE_OAUTH_TOKEN\` nel repository")
[ "${APP_OK:-no}" = si ] || problemi+=("Il token della App \`dipstech-agenti\` non si ottiene: controlla l'environment \`agenti\` (variabile \`AGENTI_CLIENT_ID\`, segreto \`AGENTI_APP_KEY\`, policy dei rami che ammette \`$RAMO_SVILUPPO\`) e che la App sia installata sul repository")
pf_environment_esiste agenti || problemi+=("Manca l'environment \`agenti\`")

if [ ! -f "$CONFIG" ]; then
  problemi+=("Manca \`.catena.yml\` nella radice di \`$RAMO_SVILUPPO\` (docs/configurazione.md)")
else
  [ -n "$(cfg lint)$(cfg tipi)$(cfg test)" ] || problemi+=("\`.catena.yml\` non configura nessun controllo (lint, tipi, test)")
fi

if [ "$PIATTAFORMA" = github ]; then
  ci=$(cfg ci_nome CI)
  grep -lE "^name:[[:space:]]*['\"]?$ci['\"]?[[:space:]]*$" "$REPO_DIR"/.github/workflows/*.yml > /dev/null 2>&1 \
    || problemi+=("Nessun workflow in \`.github/workflows\` si chiama \`$ci\` (chiave \`ci_nome\` di .catena.yml): l'unione non saprebbe quando la CI finisce")
  obbligatori=$(pf_controlli_obbligatori "$RAMO_SVILUPPO" | paste -sd, - || true)
  log "controlli obbligatori su $RAMO_SVILUPPO: ${obbligatori:-nessuno}"
fi

if [ "${#problemi[@]}" -gt 0 ]; then
  printf -- '- %s\n' "${problemi[@]}"
  exit 1
fi
echo "preflight: OK"
