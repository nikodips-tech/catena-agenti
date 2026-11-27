#!/usr/bin/env bash
# Prepara il checkout del progetto per un ruolo e scrive nelle variabili del job (GITHUB_ENV,
# o stdout) TIPO, BASE, RAMO e INIZIO (il commit da cui parte l'agente: la raccolta misura le
# modifiche rispetto a questo, qualunque cosa faccia Claude nel frattempo).
# Uso: ramo.sh <ruolo>. Variabili: ISSUE.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
ruolo=$1
cd "$REPO_DIR"

etichette=$(pf_issue_etichette "$ISSUE"); tipo=$(tipo_issue "$etichette")
[ -n "$tipo" ] || { errore "l'issue #$ISSUE non è né task né hotfix"; exit 1; }
base=$(base_di "$tipo"); ramo=$(ramo_di "$ISSUE" "$tipo")

git fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
case "$ruolo" in
  # Il team leader legge il codice com'è nella base (in escalation il ramo gli arriva come diff)
  team-leader) git checkout -q -B "$base" "origin/$base" ;;
  # Il developer lavora sul ramo dell'issue, creato dalla base se non c'è
  developer) ramo_checkout "$ramo" "$base" ;;
  # La retrospettiva legge la base com'è, come il team leader
  retrospettiva) git checkout -q -B "$base" "origin/$base" ;;
  # I consigli approvati si applicano su un ramo proprio, creato dalla base di sviluppo
  applica) base=$RAMO_SVILUPPO; ramo=$(ramo_retro "$ISSUE"); ramo_checkout "$ramo" "$base" ;;
  # Revisore ed editor guardano il lavoro finito: il ramo deve esistere
  revisore|editor)
    git show-ref -q --verify "refs/remotes/origin/$ramo" || { errore "il ramo $ramo non esiste"; exit 1; }
    ramo_checkout "$ramo" "$base" ;;
  esito) ;;
  *) errore "ruolo sconosciuto: $ruolo"; exit 2 ;;
esac

{
  echo "TIPO=$tipo"
  echo "BASE=$base"
  echo "RAMO=$ramo"
  echo "INIZIO=$(git rev-parse HEAD)"
} >> "${GITHUB_ENV:-/dev/stdout}"
