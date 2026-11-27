#!/usr/bin/env bash
# Adattatore GitHub: tutto ciò che la catena chiede alla piattaforma passa da queste funzioni.
# Un'altra piattaforma si aggiunge scrivendo un file con le stesse funzioni (docs/portabilita.md).
#
# Serve `gh` autenticato (GH_TOKEN) e GH_REPO=<proprietario>/<repo>.
# Le funzioni segnate (App) usano il token dell'App della catena in APP_TOKEN: pull request,
# merge e push fatti con il token di Actions non fanno partire gli altri workflow (CI, release).
# Il token dell'App però non legge le issue: le issue si leggono sempre con il token di Actions.

pf_proprietario() { echo "${GITHUB_REPOSITORY_OWNER:-${GH_REPO%%/*}}"; }
pf_url_esecuzione() { echo "${GITHUB_SERVER_URL:-https://github.com}/$GH_REPO/actions/runs/${GITHUB_RUN_ID:-0}"; }
con_app() { GH_TOKEN="${APP_TOKEN:?manca APP_TOKEN}" "$@"; }

# ---------------------------------------------------------------- issue
pf_issue_titolo() { gh issue view "$1" --json title --jq .title; }
pf_issue_corpo() { gh issue view "$1" --json body --jq .body; }
pf_issue_stato() { gh issue view "$1" --json state --jq .state; }            # OPEN | CLOSED
pf_issue_etichette() { gh issue view "$1" --json labels --jq '[.labels[].name] | join(" ")'; }
pf_issue_aggiornata() { gh issue view "$1" --json updatedAt --jq .updatedAt; } # ISO 8601
# JSON [{autore, corpo}], in ordine di tempo
pf_issue_commenti() { gh issue view "$1" --json comments --jq '[.comments[] | {autore: .author.login, corpo: .body}]'; }
# pf_issue_commenta <issue> <file | ->
pf_issue_commenta() { if [ "$2" = - ]; then gh issue comment "$1" --body-file -; else gh issue comment "$1" --body-file "$2"; fi; }
pf_commenta_testo() { gh issue comment "$1" --body "$2"; }
# etichette separate da virgola; togliere un'etichetta che non c'è non è un errore
pf_etichetta_aggiungi() { gh issue edit "$1" --add-label "$2" > /dev/null; }
pf_etichetta_togli() { local e; for e in ${2//,/ }; do gh issue edit "$1" --remove-label "$e" > /dev/null 2>&1 || true; done; }
pf_issue_chiudi() { if [ -n "${2:-}" ]; then gh issue close "$1" --reason completed --comment "$2"; else gh issue close "$1" --reason completed; fi; }
# pf_issue_crea <titolo> <file corpo> <etichette csv> → numero
pf_issue_crea() { gh issue create --title "$1" --body-file "$2" --label "$3" | sed -E 's#.*/##'; }
pf_sottoissue_collega() { # <padre> <figlio>
  local id; id=$(gh api "repos/$GH_REPO/issues/$2" --jq .id)
  gh api -X POST "repos/$GH_REPO/issues/$1/sub_issues" -F sub_issue_id="$id" > /dev/null
}
# JSON [{numero, stato (open|closed), titolo}]
pf_sottoissue() { gh api "repos/$GH_REPO/issues/$1/sub_issues" --jq '[.[] | {numero: .number, stato: .state, titolo: .title}]'; }
pf_sottoissue_aperte() { pf_sottoissue "$1" | jq -r '.[] | select(.stato == "open") | .numero'; }
# pf_issue_aperte_con <etichette csv (tutte)>: JSON [{numero, etichette[], aggiornata}]
pf_issue_aperte_con() {
  gh issue list --state open --label "$1" --limit 100 --json number,labels,updatedAt \
    --jq '[.[] | {numero: .number, etichette: [.labels[].name], aggiornata: .updatedAt}]'
}
# pf_issue_aperte: tutte le issue aperte, stesso JSON di pf_issue_aperte_con
pf_issue_aperte() {
  gh issue list --state open --limit 200 --json number,labels,updatedAt \
    --jq '[.[] | {numero: .number, etichette: [.labels[].name], aggiornata: .updatedAt}]'
}

# ---------------------------------------------------------------- passi della catena
# pf_passo_avvia <passo> <issue> [sottotask] [tentativo] [file nota]: il wrapper catena.yml del progetto
pf_passo_avvia() {
  local nota=""
  if [ -n "${5:-}" ] && [ -f "$5" ]; then nota=$(tronca 3000 < "$5"); fi
  gh workflow run "$WORKFLOW_CATENA" --ref "$RAMO_SVILUPPO" \
    -f passo="$1" -f issue="$2" -f sottotask="${3:-}" -f tentativo="${4:-1}" -f nota="$nota"
}
pf_workflow_avvia() { gh workflow run "$@"; }
# Quante esecuzioni del workflow della catena sono in corso o in coda (compresa quella corrente)
pf_esecuzioni_attive() {
  local n=0 s k
  for s in in_progress queued waiting requested pending; do
    k=$(gh run list --workflow "$WORKFLOW_CATENA" --status "$s" --limit 50 --json databaseId --jq length 2> /dev/null || echo 0)
    n=$((n + k))
  done
  echo "$n"
}

# ---------------------------------------------------------------- rami e pull request
pf_ramo_esiste() { gh api "repos/$GH_REPO/branches/$1" --silent > /dev/null 2>&1; }
pf_ramo_cancella() { gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$1" > /dev/null 2>&1 || true; }
# push del ramo corrente: con l'App se APP_TOKEN c'è (fa partire la CI), altrimenti col token di Actions
pf_push() {
  if [ -n "${APP_TOKEN:-}" ]; then
    git -C "$REPO_DIR" push "https://x-access-token:${APP_TOKEN}@github.com/$GH_REPO.git" "$@"
  else
    git -C "$REPO_DIR" push origin "$@"
  fi
}
# pf_pr_aperta <ramo> <base>: JSON {numero, sha, etichette[]} o vuoto
pf_pr_aperta() {
  gh pr list --head "$1" --base "$2" --state open --json number,headRefOid,labels \
    --jq '.[0] | select(. != null) | {numero: .number, sha: .headRefOid, etichette: [.labels[].name]}'
}
# pf_pr_apri <ramo> <base> <titolo> <file corpo> [etichette csv] → numero   (App)
pf_pr_apri() {
  if [ -n "${5:-}" ]; then
    con_app gh pr create --base "$2" --head "$1" --title "$3" --body-file "$4" --label "$5" | sed -E 's#.*/##'
  else
    con_app gh pr create --base "$2" --head "$1" --title "$3" --body-file "$4" | sed -E 's#.*/##'
  fi
}
pf_pr_etichetta_aggiungi() { gh pr edit "$1" --add-label "$2" > /dev/null; }
pf_pr_etichetta_togli() { gh pr edit "$1" --remove-label "$2" > /dev/null 2>&1 || true; }
pf_pr_commenta() { gh pr comment "$1" --body "$2"; }
# pf_pr_unisci <pr> <squash|merge> <soggetto> [corpo del commit] (App)
pf_pr_unisci() {
  if [ -n "${4:-}" ]; then con_app gh pr merge "$1" "--$2" --delete-branch --subject "$3" --body "$4"
  else con_app gh pr merge "$1" "--$2" --delete-branch --subject "$3"; fi
}
# JSON {numero, titolo, corpo, etichette[], ramo, base, stato, unita}
pf_pr_json() {
  gh pr view "$1" --json number,title,body,labels,headRefName,baseRefName,state,mergedAt \
    --jq '{numero: .number, titolo: .title, corpo: .body, etichette: [.labels[].name], ramo: .headRefName, base: .baseRefName, stato: .state, unita: (.mergedAt != null)}'
}

# ---------------------------------------------------------------- CI
pf_ci_falliti() { gh run view "$1" --json jobs --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "- \(.name): \(.url)"'; }
pf_ci_log_falliti() { gh run view "$1" --log-failed 2> /dev/null | tail -c 6000 || true; }

# ---------------------------------------------------------------- repository
pf_etichetta_crea() { gh label create "$1" --color "$2" --description "$3" --force > /dev/null; }
pf_etichette_repo() { gh label list --limit 200 --json name --jq '.[].name'; }
pf_controlli_obbligatori() { gh api "repos/$GH_REPO/rules/branches/$1" --jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | unique | .[]' 2> /dev/null || true; }
pf_environment_esiste() { gh api "repos/$GH_REPO/environments/$1" --silent > /dev/null 2>&1; }
# I rami ammessi dalla policy di un environment, uno per riga (vuoto se la policy non è per rami)
pf_environment_rami() { gh api "repos/$GH_REPO/environments/$1/deployment-branch-policies" --jq '.branch_policies[].name' 2> /dev/null || true; }
# true se il repository ha l'auto-merge abilitato. Il campo lo vedono solo gli amministratori:
# con il token di Actions risponde vuoto, quindi serve all'installazione, non al preflight
pf_auto_merge() { gh api "repos/$GH_REPO" --jq '.allow_auto_merge // empty' 2> /dev/null || true; }
# pf_variabile <nome>: il valore o vuoto. Nei workflow da VARIABILI (toJSON(vars)): il token di
# Actions non ha il permesso di leggere le variabili con l'API e le troverebbe tutte vuote
pf_variabile() {
  if [ -n "${VARIABILI:-}" ]; then
    jq -r --arg n "$1" '.[$n] // empty' <<< "$VARIABILI"
  else
    gh variable get "$1" 2> /dev/null || true
  fi
}
