#!/usr/bin/env bash
# I ruoli della catena: modello, turni e strumenti di ogni agente, con la possibilità
# di cambiarli per progetto da .catena.yml (modello_<ruolo>, turni_<ruolo>).
# Il timeout del job sta nel workflow (piattaforme/github: agente.yml), con gli stessi valori.
# Uso: ruoli.sh <ruolo> modello|turni|strumenti|timeout   (sorgente di verità: docs/specifica.md)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"

ruolo=$1 cosa=$2
case "$ruolo" in
  team-leader) modello=opus;   turni=30; timeout=20; strumenti="Read,Glob,Grep,Write" ;;
  developer)   modello=sonnet; turni=70; timeout=55; strumenti="Read,Glob,Grep,Write,Edit,Bash(bash $CATENA/scripts/controlli.sh:*),Bash(bash $CATENA/scripts/rimuovi.sh:*)" ;;
  revisore)    modello=opus;   turni=30; timeout=25; strumenti="Read,Glob,Grep,Write" ;;
  editor)      modello=haiku;  turni=15; timeout=15; strumenti="Read,Glob,Grep,Write,Edit" ;;
  *) errore "ruolo sconosciuto: $ruolo"; exit 2 ;;
esac
chiave=${ruolo//-/_}
case "$cosa" in
  modello)   cfg "modello_$chiave" "$modello" ;;
  turni)     cfg "turni_$chiave" "$turni" ;;
  timeout)   echo "$timeout" ;;
  strumenti) echo "$strumenti" ;;
  *) errore "cosa: modello|turni|strumenti|timeout"; exit 2 ;;
esac
