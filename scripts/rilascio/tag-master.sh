#!/usr/bin/env bash
# Fine di una release o di un hotfix (niente Claude): quello
# che dal PC fa `git flow release finish`. A ogni push su master, se il commit è il merge di
# una PR da release/x.y.z o da un hotfix (hotfix/x.y.z dal PC, hotfix/issue-N della catena:
# l'ultimo tag più uno sulla patch):
# - crea il tag x.y.z (il suo push, fatto con l'App, fa partire il rilascio del progetto);
# - chiude le issue citate nei commit della versione (Closes, Fixes, Resolves o Refs #N) e
#   toglie loro `in-develop`;
# - riporta master in develop con una PR (develop è protetto) e ne chiede il merge automatico;
# - cancella il ramo della release o dell'hotfix.
# Le release finite dal PC con git flow arrivano con il loro tag e senza PR: si saltano.
# Variabili: REPO_DIR (checkout completo con il token dell'App), GH_TOKEN (App), GH_REPO, COMMIT,
# APP_NOME (lo slug dell'App, per l'autore del tag).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"
cd "$REPO_DIR" || exit 1
riepilogo=${GITHUB_STEP_SUMMARY:-/dev/null}

ramo=$(gh api "repos/$GH_REPO/commits/$COMMIT/pulls" \
  --jq "[.[] | select(.merged_at != null and .base.ref == \"$RAMO_PRODUZIONE\")][0].head.ref // empty")
case "$ramo" in
  release/*|hotfix/*) ;;
  *) echo "Il commit non viene da una release o da un hotfix: niente da fare." >> "$riepilogo"; exit 0 ;;
esac
versione=${ramo#*/}
git fetch -q --tags origin '+refs/heads/*:refs/remotes/origin/*'
# Gli hotfix della catena (hotfix/issue-N) non hanno il numero: l'ultimo tag più uno sulla
# patch, saltando quelli che ci sono già. La release aperta, se aveva preso lo stesso numero,
# si rinumera da sola (la release riparte dopo questo workflow)
if [[ "$ramo" =~ ^hotfix/issue- ]]; then
  tag=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)
  ultimo=$(sort -V <<< "$tag" | tail -1)
  IFS=. read -r ma mi pa <<< "${ultimo:-0.0.0}"
  versione="$ma.$mi.$((pa + 1))"
  while grep -qxF "$versione" <<< "$tag"; do IFS=. read -r ma mi pa <<< "$versione"; versione="$ma.$mi.$((pa + 1))"; done
fi
[[ "$versione" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { errore "versione non valida nel ramo: $ramo"; exit 1; }
echo "### $ramo → tag $versione" >> "$riepilogo"
# Una release unita con squash (o rebase) ha un solo genitore: i commit di develop non
# risultano in master e la release successiva li ripeterebbe. Si va avanti, ma si avvisa
storia=""
if [[ "$ramo" == release/* ]] && [ "$(git rev-list --parents -n 1 "$COMMIT" | wc -w)" -lt 3 ]; then
  storia="$ramo è entrata in \`$RAMO_PRODUZIONE\` senza merge commit (squash o rebase): i commit di \`$RAMO_SVILUPPO\` non risultano in \`$RAMO_PRODUZIONE\` e la prossima release li ripeterebbe. Serve una PR da \`$RAMO_SVILUPPO\` (o da un ramo non \`release/*\`) verso \`$RAMO_PRODUZIONE\` unita con merge commit, e nel ruleset di \`$RAMO_PRODUZIONE\` solo il merge (docs/rilascio.md della catena)."
  avviso "$storia"
  printf '\n> [!WARNING]\n> %s\n\n' "$storia" >> "$riepilogo"
fi

git config user.name "${APP_NOME:-catena-agenti}[bot]"
git config user.email "${APP_NOME:-catena-agenti}[bot]@users.noreply.github.com"
# Il tag x.y.z precedente, per le issue della versione (prima del tag nuovo)
prima=$(git tag -l --merged "$COMMIT" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
if git rev-parse -q --verify "refs/tags/$versione" > /dev/null; then
  # Tag già creato sullo stesso commit: è un re-run, si va avanti
  [ "$(git rev-parse "$versione^{commit}")" = "$COMMIT" ] || { errore "il tag $versione esiste già su un altro commit"; exit 1; }
  echo "tag $versione già presente su $COMMIT: proseguo"
  prima=$(git tag -l --merged "$COMMIT^" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
else
  git tag -a "$versione" -m "$versione" "$COMMIT"
  git push origin "refs/tags/$versione"
fi

# Le issue della versione
numeri=$(git log --format='%B' "${prima:+$prima..}$COMMIT" \
  | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?) +#[0-9]+' | grep -oE '[0-9]+$' | sort -un || true)
for n in $numeri; do
  [ "$(gh issue view "$n" -R "$GH_REPO" --json state -q .state 2> /dev/null || true)" = OPEN ] || continue
  gh issue edit "$n" -R "$GH_REPO" --remove-label "$E_IN_DEVELOP" > /dev/null 2>&1 || true
  gh issue close "$n" -R "$GH_REPO" --comment "In produzione con la versione $versione."
  echo "chiusa #$n"
done

# master in develop
if git merge-base --is-ancestor "$COMMIT" "origin/$RAMO_SVILUPPO"; then
  echo "$RAMO_SVILUPPO ha già $RAMO_PRODUZIONE"
else
  pr=$(gh pr list -R "$GH_REPO" --head "$RAMO_PRODUZIONE" --base "$RAMO_SVILUPPO" --state open --json number --jq '.[0].number // empty')
  if [ -z "$pr" ]; then
    pr=$(gh pr create -R "$GH_REPO" --head "$RAMO_PRODUZIONE" --base "$RAMO_SVILUPPO" \
      --title "Riporta $versione in $RAMO_SVILUPPO" \
      --body "Riporto automatico di \`$RAMO_PRODUZIONE\` in \`$RAMO_SVILUPPO\` dopo il tag $versione." | grep -oE '[0-9]+$')
  fi
  # Merge commit, come git flow. Con file di CODEOWNERS GitHub chiede la revisione al proprietario
  gh pr merge "$pr" -R "$GH_REPO" --merge --auto || avviso "non riesco a chiedere il merge automatico di #$pr: va unita a mano"
  [ -z "$storia" ] || gh pr comment "$pr" -R "$GH_REPO" --body "> [!WARNING]"$'\n'"> $storia" > /dev/null || true
fi

git push origin --delete "$ramo" || echo "ramo $ramo già cancellato"
