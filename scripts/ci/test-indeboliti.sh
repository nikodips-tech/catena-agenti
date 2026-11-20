#!/usr/bin/env bash
# I test indeboliti tra due commit, senza AI: chi scrive il codice scrive anche i test,
# e niente deve permettergli di farli passare spegnendoli.
# - Blocca (uscita 1): righe aggiunte con .skip / .only / .todo / xit / xdescribe in un
#   file di test. Un test saltato o isolato non controlla più niente.
# - Segnala (nel riepilogo, senza bloccare): file di test cancellati, e casi di test in
#   meno (it/test tolti più di quelli aggiunti). Un refactor può farlo: lo guarda il
#   revisore, e la pull request deve dire perché.
#
# Uso: test-indeboliti.sh <base> <head> [regex dei file di test, PCRE; predefinita JS/TS].
# Stampa le righe trovate; il riepilogo va su
# $GITHUB_STEP_SUMMARY se c'è.

set -uo pipefail

base=$1
head=$2
riepilogo=${GITHUB_STEP_SUMMARY:-/dev/null}
filtro=${3:-'(\.test|\.spec)\.[cm]?[jt]sx?$'}

file=$(git diff --name-only "$base...$head" | grep -P "$filtro" || true)
cancellati=$(git diff --name-only --diff-filter=D "$base...$head" | grep -P "$filtro" || true)

spenti=""
tolti=0
aggiunti=0
for f in $file; do
  diff=$(git diff -U0 "$base...$head" -- "$f")
  righe=$(grep -E '^\+[^+]' <<< "$diff" | grep -nE '\b(it|test|describe)\.(skip|only|todo)\b|\b(xit|xtest|xdescribe)\s*\(' || true)
  [ -n "$righe" ] && spenti+="$f:"$'\n'"$righe"$'\n'
  tolti=$(( tolti + $(grep -cE '^-\s*(it|test)(\.each\([^)]*\))?\s*\(' <<< "$diff" || true) ))
  aggiunti=$(( aggiunti + $(grep -cE '^\+\s*(it|test)(\.each\([^)]*\))?\s*\(' <<< "$diff" || true) ))
done

if [ -n "$cancellati" ]; then
  { echo "### File di test cancellati"; echo '```'; echo "$cancellati"; echo '```'; } >> "$riepilogo"
fi
if [ "$tolti" -gt "$aggiunti" ]; then
  echo "### Casi di test in meno: $((tolti - aggiunti)) (tolti $tolti, aggiunti $aggiunti)" >> "$riepilogo"
fi
if [ -n "$spenti" ]; then
  { echo "### Test spenti (.skip, .only, .todo, xit)"; echo '```'; echo "$spenti"; echo '```'; } >> "$riepilogo"
  echo "$spenti"
  echo "::error::la pull request spegne dei test (.skip, .only, .todo, xit): un test saltato non controlla più niente"
  exit 1
fi
exit 0
