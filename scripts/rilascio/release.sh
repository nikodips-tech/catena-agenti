#!/usr/bin/env bash
# La release (niente Claude). A ogni push su develop, o a mano:
# con commit feat o fix non ancora in master crea release/x.y.z dalla testa di develop e la
# pull request verso master, con le note fatte dai commit; se una release è già aperta la
# porta alla testa di develop (o la rinumera, se cambia la versione). Dopo un tag-master
# (EVENTO=workflow_run) rimette in pari solo una release già aperta: stessi commit, numero
# nuovo. Il numero: feat → minor, fix → patch, "!" o BREAKING CHANGE → major. In cima alla PR
# le migrazioni distruttive (chiave `migrazioni`) e le issue `in-develop` con un commento di
# una persona senza risposta. Il merge resta del proprietario: è il suo OK al rilascio.
# Variabili: REPO_DIR (checkout di develop, completo), GH_TOKEN (App), GH_REPO, EVENTO,
# PROPRIETARIO.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../comune.sh"
cd "$REPO_DIR" || exit 1
riepilogo=${GITHUB_STEP_SUMMARY:-/dev/null}
git fetch -q --tags origin '+refs/heads/*:refs/remotes/origin/*'

aperta=""
for b in $(git branch -r --list 'origin/release/*' | sed 's|^ *origin/||'); do
  if git show-ref -q --verify "refs/tags/${b#release/}"; then
    avviso "$b ha già il suo tag: è rilasciata, non la tocco"
  elif [ -n "$aperta" ]; then
    errore "più di una release aperta: $aperta e $b"; exit 1
  else
    aperta=$b
  fi
done

# A ogni push e a mano si parte dalla testa di develop; dopo un tag-master si rimette in pari
# solo la release già aperta, con i suoi commit e un numero nuovo
if [ "${EVENTO:-}" = workflow_run ]; then
  [ -n "$aperta" ] || { echo "Nessuna release aperta: niente da rimettere in pari." >> "$riepilogo"; exit 0; }
  origine="origin/$aperta"
else
  origine="origin/$RAMO_SVILUPPO"
fi
# Gli stessi file di master (dopo il riporto, o dopo una release unita con squash): niente
# da rilasciare, qualunque cosa dicano i commit
if git diff --quiet "origin/$RAMO_PRODUZIONE" "$origine"; then
  echo "Nessuna differenza tra $RAMO_PRODUZIONE e $origine: niente da rilasciare." >> "$riepilogo"; exit 0
fi

ultimo=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
ultimo=${ultimo:-0.0.0}
titoli=$(git log --no-merges --format='%s' "origin/$RAMO_PRODUZIONE..$origine")
corpi=$(git log --no-merges --format='%B' "origin/$RAMO_PRODUZIONE..$origine")

if grep -qE '^[a-z]+(\([^)]*\))?!:' <<< "$titoli" || grep -q 'BREAKING CHANGE' <<< "$corpi"; then livello="major"
elif grep -qE '^feat(\([^)]*\))?:' <<< "$titoli"; then livello="minor"
elif grep -qE '^fix(\([^)]*\))?:' <<< "$titoli"; then livello="patch"
else
  echo "Niente feat o fix da rilasciare ($origine)." >> "$riepilogo"; exit 0
fi

IFS=. read -r ma mi pa <<< "$ultimo"
case $livello in
  major) v="$((ma + 1)).0.0" ;;
  minor) v="$ma.$((mi + 1)).0" ;;
  patch) v="$ma.$mi.$((pa + 1))" ;;
esac
# Un hotfix aperto o un tag che ha già il numero: si prende il successivo
while git show-ref -q --verify "refs/remotes/origin/hotfix/$v" || git show-ref -q --verify "refs/tags/$v"; do
  IFS=. read -r ma mi pa <<< "$v"; v="$ma.$mi.$((pa + 1))"
done
nuovo="release/$v"

# Il corpo della pull request
distruttive=""
cartella=$(cfg migrazioni)
[ -z "$cartella" ] || distruttive=$(bash "$CATENA/scripts/ci/migrazioni-distruttive.sh" "origin/$RAMO_PRODUZIONE" "$origine" "$cartella")
{
  if [ -n "$distruttive" ]; then
    printf '> [!WARNING]\n> **Contiene migrazioni distruttive.** Prima di applicarle `rilascia` fa un dump del database; `torna` riporta il codice, il dump i dati.\n\n```\n%s\n```\n\n' "$distruttive"
  fi
  # Le issue in develop con un commento di una persona dopo l'ultimo di un bot: qualcosa che
  # non va, o una domanda, ancora senza risposta. I bot: github-actions e l'App della catena
  # (APP_NOME, lo slug: nei commenti compare senza [bot]); lo slug ha solo [a-z0-9-]
  bot='\\[bot\\]$|^github-actions$'   # dentro una stringa jq: \\[ è la parentesi letterale
  [[ "${APP_NOME:-}" =~ ^[a-z0-9-]+$ ]] && bot+="|^$APP_NOME\$"
  senza_risposta=$(gh issue list --label "$E_IN_DEVELOP" --state open --limit 100 --json number,title,comments \
    --jq '.[] | select((.comments | last | .author.login // "") as $a | $a != "" and ($a | test("'"$bot"'") | not)) | "- #\(.number) \(.title)"' || true)
  if [ -n "$senza_risposta" ]; then
    printf '> [!IMPORTANT]\n> **Issue in develop con un commento senza risposta**: vanno guardate prima di rilasciare.\n\n%s\n\n' "$senza_risposta"
  fi
  echo "Release $v, preparata dalla catena con i commit non ancora in \`$RAMO_PRODUZIONE\` ($origine)."
  novita=$(grep -E '^feat(\([^)]*\))?!?:' <<< "$titoli" | sed -E 's/^feat\(([^)]*)\)!?: */- \1: /; s/^feat!?: */- /' || true)
  correzioni=$(grep -E '^fix(\([^)]*\))?!?:' <<< "$titoli" | sed -E 's/^fix\(([^)]*)\)!?: */- \1: /; s/^fix!?: */- /' || true)
  [ -z "$novita" ] || printf '\n## Novità\n\n%s\n' "$novita"
  [ -z "$correzioni" ] || printf '\n## Correzioni\n\n%s\n' "$correzioni"
  printf '\nAl merge, tag-master crea il tag `%s`, riporta `%s` in `%s` e rilascia.\n' "$v" "$RAMO_PRODUZIONE" "$RAMO_SVILUPPO"
} > "$TMP_BASE/corpo-release.md"

# Il ramo della release: sempre una copia di origine, portata avanti senza commit di merge
avanza() {
  gh api -X PATCH "repos/$GH_REPO/git/refs/heads/$1" -f sha="$(git rev-parse "$origine")" -F force=false > /dev/null \
    || { errore "$1 ha commit che $RAMO_SVILUPPO non ha: non si porta avanti senza merge, va sistemata a mano"; exit 1; }
}
crea() { gh api "repos/$GH_REPO/git/refs" -f ref="refs/heads/$1" -f sha="$(git rev-parse "$origine")" > /dev/null; }
if [ -z "$aperta" ]; then
  crea "$nuovo"; echo "### Creata $nuovo" >> "$riepilogo"
elif [ "$aperta" = "$nuovo" ]; then
  avanza "$nuovo"; echo "### Aggiornata $nuovo" >> "$riepilogo"
else
  git merge-base --is-ancestor "origin/$aperta" "$origine" \
    || { errore "$aperta ha commit che $RAMO_SVILUPPO non ha: non si rinumera, va sistemata a mano"; exit 1; }
  crea "$nuovo"; echo "### $aperta diventa $nuovo" >> "$riepilogo"
fi

# La pull request (con la revisione chiesta al proprietario gli arriva la notifica)
pr=$(gh pr list --repo "$GH_REPO" --head "$nuovo" --base "$RAMO_PRODUZIONE" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  gh pr create --repo "$GH_REPO" --base "$RAMO_PRODUZIONE" --head "$nuovo" --reviewer "$PROPRIETARIO" \
    --title "Release $v" --body-file "$TMP_BASE/corpo-release.md"
else
  gh pr edit "$pr" --repo "$GH_REPO" --body-file "$TMP_BASE/corpo-release.md"
fi
if [ -n "$aperta" ] && [ "$aperta" != "$nuovo" ]; then
  vecchia=$(gh pr list --repo "$GH_REPO" --head "$aperta" --state open --json number --jq '.[0].number // empty')
  [ -z "$vecchia" ] || gh pr close "$vecchia" --repo "$GH_REPO" --comment "Sostituita da $nuovo: con i commit nuovi è cambiata la versione."
  gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$aperta"
fi
