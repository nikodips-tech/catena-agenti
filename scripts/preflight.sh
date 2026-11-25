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
  [ "$CHIUDI_ISSUE" != produzione ] || printf '%s\t0075CA\tIn develop: si chiude quando va in produzione\n' "$E_IN_DEVELOP"
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
[ "${APP_OK:-no}" = si ] || problemi+=("Il token della App della catena non si ottiene: controlla l'environment \`agenti\` (variabile \`AGENTI_CLIENT_ID\`, segreto \`AGENTI_APP_KEY\`, policy dei rami che ammette \`$RAMO_SVILUPPO\`) e che la App sia installata sul repository")
if pf_environment_esiste agenti; then
  # La policy dei rami deve ammettere sviluppo (catena, release) e produzione (tag-master).
  # Se il token di Actions non può leggere la policy (elenco vuoto), non si giudica: lo
  # verifica l'installazione, con l'account del proprietario
  rami=$(pf_environment_rami agenti)
  if [ -n "$rami" ]; then
    for r in "$RAMO_SVILUPPO" "$RAMO_PRODUZIONE"; do
      grep -qxF -- "$r" <<< "$rami" || problemi+=("La policy dei rami dell'environment \`agenti\` non ammette \`$r\` (docs/permessi.md)")
    done
  else
    log "policy dei rami di agenti non leggibile con questo token: non la controllo"
  fi
else
  problemi+=("Manca l'environment \`agenti\`")
fi
# L'auto-merge del repository (riporto di produzione in sviluppo) non si controlla qui: il
# campo è visibile solo agli amministratori. Lo verifica l'installazione (prompt/installazione.md)

if [ ! -f "$CONFIG" ]; then
  problemi+=("Manca \`.catena.yml\` nella radice di \`$RAMO_SVILUPPO\` (docs/configurazione.md)")
else
  [ -n "$(cfg lint)$(cfg tipi)$(cfg test)" ] || problemi+=("\`.catena.yml\` non configura nessun controllo (lint, tipi, test)")
  # La cache sta nel checkout: se git non la ignora, la raccolta la committa
  for p in $(cfg cache); do
    git -C "$REPO_DIR" check-ignore -q "$(cfg cartella .)/$p/x" \
      || problemi+=("La cartella di cache \`$p\` (chiave \`cache\`) non è in \`.gitignore\`")
  done
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
