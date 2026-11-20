#!/usr/bin/env bash
# Test di scripts/guardia.sh: casi consentiti (uscita 0) e bloccati (uscita 2).
# Uso: bash plugin/hooks/test.sh   (da qualunque cartella; serve Git Bash o Linux)
set -u
qui=$(cd "$(dirname "$0")" && pwd)
guardia="$qui/../scripts/guardia.sh"

ok=0; ko=0

# gh finto: risponde alle domande dell'hook (base e URL della PR, nome del repo) senza GitHub.
# "prod" o la PR 200: master di livegest (produzione); "rel" o la PR 100: master di r (non di
# produzione); "sconosciuta" o 999: errore; altrimenti develop. repo view: il nome della cartella.
finto=$(mktemp -d)
trap 'rm -rf "$finto"' EXIT
mkdir -p "$finto/livegest" "$finto/altro"
cat > "$finto/gh" <<'GH'
#!/usr/bin/env bash
case " $* " in
  *' repo view '*) basename "$PWD" ;;
  *sconosciuta*|*999*) exit 1 ;;
  *prod*|*' 200 '*|*/200' '*|*pulls/200*) echo "master https://github.com/o/livegest/pull/200" ;;
  *rel*|*' 100 '*|*/100' '*|*pulls/100*) echo "master https://github.com/o/r/pull/100" ;;
  *) echo "develop https://github.com/o/r/pull/12" ;;
esac
GH
chmod +x "$finto/gh"
export PATH="$finto:$PATH"

# Costruisce il JSON dell'hook con gli escape giusti per " e \ .
json() {
  local c
  c=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '{"session_id":"t","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s","description":"test"}}' "${CWD:-/tmp}" "${TOOL:-Bash}" "$c"
}

prova() {
  local atteso=$1 comando=$2 esito msg
  msg=$(json "$comando" | bash "$guardia" 2>&1 >/dev/null)
  esito=$?
  if [ "$esito" -eq "$atteso" ]; then
    ok=$((ok + 1)); printf 'OK   (%s) %s\n' "$esito" "$comando"
  else
    ko=$((ko + 1)); printf 'FAIL (atteso %s, avuto %s) %s\n     %s\n' "$atteso" "$esito" "$comando" "$msg"
  fi
}
# prod: lo stesso, con il comando lanciato nella cartella di un repo di produzione (livegest)
prod() { CWD="$finto/livegest" prova "$@"; }

echo "--- git push: consentiti"
prova 0 'git status'
prova 0 'git push origin develop'
prova 0 'git push origin develop:verifica/3'
prova 0 'git push -u origin feature/F-012'
prova 0 'git push -u origin riordino/fase-6'
prova 0 'git push origin HEAD:verifica/12'
prova 0 'git push origin develop:refs/heads/verifica/4'
prova 0 'git -C D:/repos/x push origin develop'
prova 0 'git push origin --delete feature/F-012'
prova 0 'git push origin :riordino/fase-1'
prova 0 'git push origin release/1.2.0'
prova 0 'cd app && npm test && git push origin develop'
echo "--- git push: bloccati"
prova 2 'git push'
prova 2 'git push origin'
prova 2 'git push origin HEAD'
prova 2 'git push origin master'
prova 2 'git push origin main'
prova 2 'git push origin develop:master'
prova 2 'git push origin HEAD:refs/heads/master'
prova 2 'git push --tags'
prova 2 'git push origin --tags'
prova 2 'git push --follow-tags origin develop'
prova 2 'git push origin 1.2.3'
prova 2 'git push origin v1.2.3'
prova 2 'git push origin refs/tags/1.2.3'
prova 2 'git push --force origin verifica/3'
prova 2 'git push -f origin verifica/3'
prova 2 'git push origin develop --force'
prova 2 'git push --force-with-lease origin feature/x'
prova 2 'git push origin +develop'
prova 2 'git push origin :develop'
prova 2 'git push origin :master'
prova 2 'git push origin --delete develop'
prova 2 'git push origin --delete master'
prova 2 'git push --mirror origin'
prova 2 'npm test && git push origin master'
echo "--- gh api"
prova 0 'gh api repos/o/r/environments/production'
prova 0 'gh api repos/o/r/rulesets'
prova 0 'gh api repos/o/r/rulesets/123'
prova 0 'gh api repos/o/r/pulls/3'
prova 2 'gh api repos/o/r/actions/runs/1/pending_deployments'
prova 2 'gh api -X POST repos/o/r/actions/runs/1/pending_deployments -f state=approved'
prova 2 'gh api repos/o/r/environments/production/deployment_protection_rules'
prova 2 'gh api -X PUT repos/o/r/environments/production --input x.json'
prova 2 'gh api --method PATCH repos/o/r/environments/production'
prova 2 'gh api -X DELETE repos/o/r/environments/staging'
prova 2 'gh api -X PUT repos/o/r/rulesets/123 --input r.json'
prova 2 'gh api repos/o/r/rulesets -f name=x'
echo "--- merge: consentiti (develop, o master di un repo non di produzione)"
prova 0 'gh pr merge 200 --merge'
prova 0 'gh pr merge 999 --merge'
prova 0 'gh pr merge prod/release --merge'
prova 0 'gh api -X PUT repos/o/r/pulls/999/merge'
prova 0 'gh api repos/o/r/merges --input m.json'
prod 0 'gh pr merge 12 --merge'
prova 0 'gh pr merge 12 --merge'
prova 0 'gh pr merge 12 --merge --delete-branch'
prova 0 'gh pr merge feature/x --merge -R o/r'
prova 0 'gh pr merge https://github.com/o/r/pull/12 --merge'
prova 0 'gh pr merge 12 --merge -b "testo con 200 parole"'
prova 0 'cd /tmp && gh pr merge 12 --merge'
prova 0 'gh pr merge 100 --merge'
prova 0 'gh pr merge release/1.2.0 --merge --delete-branch'
prova 0 'gh pr merge https://github.com/o/r/pull/100'
prova 0 'gh pr view 200'
prova 0 'gh api repos/o/livegest/pulls/200/merge'
prova 0 'gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=merge'
prova 0 'gh api -X PUT repos/o/r/pulls/100/merge'
prova 0 'gh api -X POST repos/o/r/merges -f base=develop -f head=feature/x'
prova 0 'gh api -X POST repos/o/claude-config/merges -f base=master -f head=develop'
prova 0 "cd $finto/altro && gh api -X POST repos/{owner}/{repo}/merges -f base=master -f head=x"
echo "--- merge: bloccati (master di un repo di produzione, o destinazione sconosciuta)"
prod 2 'gh pr merge 200 --merge'
prod 2 'gh pr merge prod/release --merge'
prova 2 'gh pr merge https://github.com/o/livegest/pull/200'
prova 2 'gh pr merge 200 --merge -R o/livegest'
prod 2 'gh pr merge 200 --auto --merge'
prod 2 'gh pr merge 999 --merge'
prova 2 'cd /cartella/che/non/esiste && gh pr merge 12 --merge'
prod 2 'npm test && gh pr merge 200 --merge'
prova 2 'gh api -X PUT repos/o/livegest/pulls/200/merge'
prova 2 'gh api --method PUT /repos/o/livegest/pulls/200/merge -f merge_method=squash'
prova 2 'gh api -X PUT repos/o/livegest/pulls/12/merge'
prova 2 'gh api -X POST repos/o/livegest/merges -f base=master -f head=develop'
prova 2 'gh api repos/o/FantaFormula1/merges -f head=develop -f base=main'
prova 2 'gh api repos/o/livegest/merges --input m.json'
prova 2 "cd $finto/livegest && gh api -X POST repos/{owner}/{repo}/merges -f base=master -f head=x"
prova 2 'gh api graphql -f query="mutation{mergePullRequest(input:{pullRequestId:\"X\"}){clientMutationId}}"'
prova 2 'gh api graphql -f query="mutation{enablePullRequestAutoMerge(input:{pullRequestId:\"X\"}){clientMutationId}}"'
echo "--- comandi annidati"
prova 0 'out=$(gh pr merge 12 --merge 2>&1)'
prova 0 'case "$st" in CLEAN*) gh pr merge 12 --merge ;; esac'
prova 0 'ls *.md'
prod 2 'out=$(gh pr merge 200 --merge 2>&1)'
prod 2 'echo `gh pr merge 200 --merge`'
prod 2 'case "$st" in CLEAN*) gh pr merge 200 --merge ;; esac'
prod 2 'if true; then gh pr merge 200 --merge; fi'
prova 2 'for n in 1; do gh pr merge $n --merge; done'
prova 2 'echo 12 | xargs gh pr merge --merge'
prova 2 'echo 12 | xargs -n1 gh pr merge --merge'
echo "--- PowerShell"
TOOL=PowerShell prova 2 'git push --force origin feature/x'
TOOL=PowerShell prova 2 'git status; git push origin master'
TOOL=PowerShell prova 2 'ssh deploy@vps'
TOOL=PowerShell prova 0 'git push origin feature/x'
TOOL=Read prova 0 'git push --force origin x'
prova 2 'x=$(git push origin master)'
prova 2 'if true; then git push origin master; fi'
prova 2 '! ssh host'
echo "--- ssh e docker"
prova 0 'echo ssh'
prova 0 'ssh-keygen -t ed25519 -f /tmp/k'
prova 0 'gh pr create --title "ssh test"'
prova 0 'docker compose down'
prova 0 'docker compose up -d'
prova 0 'docker compose -f a.yml down'
prova 0 'grep -rn "docker compose down -v" docs/'
prova 2 'ssh deploy@vps'
prova 2 'scp a.txt deploy@vps:/tmp/'
prova 2 'sftp deploy@vps'
prova 2 'cd x && ssh host'
prova 2 'npm test; ssh host'
prova 2 'docker compose down -v'
prova 2 'docker compose down --volumes'
prova 2 'docker compose down --remove-orphans'
prova 2 'docker-compose down -v'
prova 2 'docker compose -f a.yml down -v'

echo
echo "Totale: $ok ok, $ko falliti"
[ "$ko" -eq 0 ]
