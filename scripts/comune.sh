#!/usr/bin/env bash
# Funzioni comuni degli script della catena. Si carica con `source`, non si esegue.
#
# Variabili d'ambiente attese (tutte con un predefinito ragionevole):
#   CATENA        cartella della catena (questo repository, in checkout)
#   REPO_DIR      checkout del progetto su cui si lavora
#   PIATTAFORMA   github (predefinito) | gitlab …: sceglie piattaforme/<nome>/adattatore.sh
#   ESITO_DIR     cartella scambiata tra il job agente e il job esito (artifact)
#   CONTESTO      cartella dei file dati che riceve Claude (fuori dal repo)
#   LOG_DIR       log completi dei controlli (fuori dal repo)
#
# Lo stato della catena vive sulle issue, in commenti che cominciano con un titolo fisso
# (docs/specifica.md, sezione «Stati»). I titoli stanno qui, in un posto solo.

CATENA=${CATENA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
REPO_DIR=${REPO_DIR:-$PWD}
PIATTAFORMA=${PIATTAFORMA:-github}
TMP_BASE=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
ESITO_DIR=${ESITO_DIR:-$TMP_BASE/esito}
CONTESTO=${CONTESTO:-$TMP_BASE/contesto}
LOG_DIR=${LOG_DIR:-$TMP_BASE/catena-log}
CONFIG=${CATENA_CONFIG:-$REPO_DIR/.catena.yml}

# Titoli dei commenti che fanno da stato
T_SPECIFICA="## Specifica"
T_DOMANDA="## Domanda"
T_REV_OK="## Revisione: approvata"
T_REV_SOTTOTASK="## Revisione: sottotask aggiunti"
T_REV_RIMOSSI="## Revisione: file rimossi"
T_REV_RISERVE="## Revisione: con riserve"
T_ESCALATION="## Escalation"
T_RIPARAZIONE="## Riparazione"
T_PR_PRONTA="## Pull request pronta"

# Etichette
E_TASK=task; E_HOTFIX=hotfix; E_SOTTOTASK=sotto-task; E_AUTO=auto
E_IN_CORSO=in-corso; E_DOMANDA=domanda; E_BLOCCATO=bloccato; E_UNIONE=unione-automatica

# Tetti
MAX_TENTATIVI=3        # tentativi del developer per sottotask
MAX_GIRI_REVISIONE=2   # giri di revisione prima delle riserve
MAX_ESCALATION=1       # escalation al team leader per sottotask
MAX_RIPARAZIONI=1      # riparazioni dopo una CI rossa

# ---------------------------------------------------------------- configurazione
# cfg <chiave> [predefinito]: un valore da .catena.yml (file piatto, una chiave per riga)
cfg() {
  local v=""
  if [ -f "$CONFIG" ]; then
    v=$(sed -n "s/^$1:[[:space:]]*//p" "$CONFIG" | head -1 | sed -E 's/[[:space:]]+#.*$//; s/^"(.*)"$/\1/; s/[[:space:]]+$//')
  fi
  printf '%s' "${v:-${2:-}}"
}

RAMO_SVILUPPO=$(cfg ramo_sviluppo develop)
RAMO_PRODUZIONE=$(cfg ramo_produzione master)
RE_TEST=$(cfg file_test '\.(test|spec)\.[^/]+$')
RE_E2E=$(cfg file_e2e '(^|/)(e2e|e2e-screenshots)/|playwright\.config|\.e2e\.')
# File che nessun agente può toccare: catena, istruzioni di Claude, segreti, più quelli del progetto
RE_PROTETTI='^(\.github/|\.gitlab-ci|\.gitlab/|\.claude/)|(^|/)CLAUDE\.md$|(^|/)\.catena\.yml$|(^|/)\.env($|\.(?!example$))'
[ -z "$(cfg file_protetti)" ] || RE_PROTETTI="$RE_PROTETTI|$(cfg file_protetti)"
RE_DOCS=$(cfg docs '^docs/|^README\.md$')
WORKFLOW_CATENA=$(cfg workflow_catena catena.yml)

# ---------------------------------------------------------------- utilità
avviso() { echo "::warning::$*" >&2; }
errore() { echo "::error::$*" >&2; }
log() { echo "[catena] $*" >&2; }

# ha <lista separata da spazi> <voce>
ha() { [[ " $1 " == *" $2 "* ]]; }

# tronca <n caratteri>: legge da stdin, taglia e segnala il taglio
tronca() { awk -v n="$1" '{ s = s $0 "\n" } END { if (length(s) > n) printf "%s\n[… troncato]\n", substr(s, 1, n); else printf "%s", s }'; }

# json_valido <file> <espressione jq che deve essere vera>
json_valido() { [ -f "$1" ] && jq -e "$2" "$1" > /dev/null 2>&1; }

# consumo <claude.json>: una riga con turni, costo e durata dell'esecuzione di Claude
consumo() {
  [ -f "$1" ] || { echo "consumo non disponibile"; return; }
  jq -r '"\(.num_turns // "?") turni, \((.total_cost_usd // 0) * 100 | round / 100) USD, \(((.duration_ms // 0) / 60000) | floor) min"' "$1" 2> /dev/null || echo "consumo non leggibile"
}

# riga_esecuzione: la riga finale dei commenti con il link all'esecuzione
riga_esecuzione() { printf '\n\nEsecuzione: %s\n' "$(pf_url_esecuzione)"; }

# ---------------------------------------------------------------- issue e rami
# tipo_issue <etichette>: task | hotfix | vuoto
tipo_issue() { if ha "$1" "$E_HOTFIX"; then echo hotfix; elif ha "$1" "$E_TASK"; then echo task; fi; }

# base_di <tipo>: il ramo da cui parte e in cui torna il lavoro
base_di() { if [ "$1" = hotfix ]; then echo "$RAMO_PRODUZIONE"; else echo "$RAMO_SVILUPPO"; fi; }

# ramo_di <issue> <tipo>: issue-<n>, oppure hotfix/issue-<n>
ramo_di() { if [ "$2" = hotfix ]; then echo "hotfix/issue-$1"; else echo "issue-$1"; fi; }

# issue_da_ramo <ramo>: il numero, o vuoto se il ramo non è della catena
issue_da_ramo() { if [[ "$1" =~ ^(hotfix/)?issue-([0-9]+)$ ]]; then echo "${BASH_REMATCH[2]}"; fi; }

# prefisso_di <tipo>: il prefisso del commit squash richiesto dal workflow di release
prefisso_di() { if [ "$1" = hotfix ]; then cfg prefisso_hotfix fix; else cfg prefisso_task feat; fi; }

# titolo_squash <titolo> <tipo> [issue]: "feat: titolo (#n)", senza raddoppiare un prefisso già presente
titolo_squash() {
  local titolo=$1 pref; pref=$(prefisso_di "$2")
  [[ "$titolo" =~ ^[a-z]+(\([^\)]*\))?!?:\  ]] || titolo="$pref: $titolo"
  if [ -n "${3:-}" ]; then echo "$titolo (#$3)"; else echo "$titolo"; fi
}

# commento_con_titolo <issue> <titolo>: il corpo dell'ultimo commento che comincia così (vuoto se nessuno)
commento_con_titolo() { pf_issue_commenti "$1" | jq -r --arg t "$2" '[.[] | select(.corpo | startswith($t))] | last | .corpo // ""'; }

# conta_commenti <issue> <titolo...>: quanti commenti cominciano con uno dei titoli
conta_commenti() {
  local issue=$1; shift
  pf_issue_commenti "$issue" | jq -r --args '[.[] | select(.corpo as $c | $ARGS.positional | any(. as $t | $c | startswith($t)))] | length' "$@"
}

# corsia_di <specifica>: diretta | completa (la riga "Corsia: diretta" nella specifica)
corsia_di() { if grep -qiE '^Corsia:[[:space:]]*diretta' <<< "$1"; then echo diretta; else echo completa; fi; }

# senza_test <corpo sottotask>: vero se il corpo ha la riga "Test: no"
senza_test() { tr -d '\r' <<< "$1" | grep -qx 'Test: no'; }

# test_modificabili <testo>: i test della base che il team leader permette di modificare (la
# riga "Test modificabili: a, b" del sotto-task o della specifica), uno per riga
test_modificabili() {
  tr -d '\r' <<< "$1" | sed -n 's/^Test modificabili:[[:space:]]*//p' | tr ',' '\n' \
    | sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//' | grep -v '^$' || true
}

# righe_sottotask <file esito> <elemento jq>: le righe di servizio in fondo al corpo di un
# sotto-task. `== false` e non `// true`: per jq `false // true` vale true
righe_sottotask() {
  local tm
  [ "$(jq -r "$2.test == false" "$1")" != true ] || printf '\nTest: no\n'
  tm=$(jq -r "($2.test_modificabili // []) | join(\", \")" "$1")
  [ -z "$tm" ] || printf '\nTest modificabili: %s\n' "$tm"
}

# Validazione jq di un elenco di sotto-task (team leader e revisore)
SOTTOTASK_VALIDI='all(.[]; (.titolo | type) == "string" and (.titolo | length) > 0 and (.descrizione | type) == "string"
  and ((.test // true) | type) == "boolean"
  and ((.test_modificabili // []) | type) == "array" and all((.test_modificabili // [])[]; type == "string" and length > 0))'

# ---------------------------------------------------------------- git
git_identita() {
  git -C "$REPO_DIR" config user.name "${GIT_NOME:-catena-agenti[bot]}"
  git -C "$REPO_DIR" config user.email "${GIT_EMAIL:-catena-agenti@users.noreply.github.com}"
}

# ramo_checkout <ramo> <base>: il ramo remoto se esiste, altrimenti nuovo dalla base
ramo_checkout() {
  cd "$REPO_DIR"
  git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
  if git show-ref -q --verify "refs/remotes/origin/$1"; then
    git checkout -q -B "$1" "origin/$1"
  else
    git checkout -q -B "$1" "origin/$2"
  fi
}

# commit_sul_ramo <ramo> <soggetto> <base>: il ramo remoto ha un commit con quel soggetto esatto?
commit_sul_ramo() {
  cd "$REPO_DIR"
  git show-ref -q --verify "refs/remotes/origin/$1" || return 1
  git log --format=%s "origin/$3..origin/$1" | grep -qxF -- "$2"
}

# commit_prima_di <ramo> <issue o sottotask> <base>: il commit del ramo prima del primo commit
# che riguarda quel numero (wip:, feat:, fix: #n); vuoto se non ce n'è nessuno
commit_prima_di() {
  cd "$REPO_DIR"
  local primo
  primo=$(git log --reverse --format='%H %s' "origin/$3..origin/$1" | grep -E " (wip|feat|fix|chore): #$2( |$)" | head -1 | cut -d' ' -f1)
  [ -n "$primo" ] && git rev-parse "$primo^"
}

# ripristina_protetti <base>: nel checkout corrente rimette come nella base i file protetti
# toccati (o li cancella se nuovi). Stampa l'elenco dei file ripristinati, uno per riga.
ripristina_protetti() {
  cd "$REPO_DIR"
  local f
  git add -A -- . ":!esito.json" > /dev/null 2>&1 || true
  git diff --cached --name-only --no-renames | grep -P "$RE_PROTETTI" | while read -r f; do
    if git cat-file -e "origin/$1:$f" 2> /dev/null; then
      git checkout -q "origin/$1" -- "$f"
    else
      git rm -q --cached -- "$f" > /dev/null 2>&1 || true
      rm -f -- "$f"
    fi
    echo "$f"
  done
}

# ---------------------------------------------------------------- adattatore della piattaforma
# shellcheck source=../piattaforme/github/adattatore.sh
source "$CATENA/piattaforme/$PIATTAFORMA/adattatore.sh"
