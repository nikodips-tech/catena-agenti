#!/usr/bin/env bash
# Le istruzioni distruttive nelle migrazioni SQL aggiunte o cambiate tra due
# commit: DROP di tabelle, colonne, schemi, tipi o viste, TRUNCATE, DELETE,
# cambi di tipo di una colonna, RENAME, SET NOT NULL (che fallisce o costringe a
# riempire le righe che ci sono). Una riga per istruzione, "file:riga: testo";
# niente se non ce ne sono. Esce sempre con 0: decide chi lo chiama.
#
# Uso: migrazioni-distruttive.sh <da> <a> <cartella delle migrazioni>
#   scripts/ci/migrazioni.sh (CI): nei rami hotfix/* blocca la pull request;
#   la release del progetto: le elenca in cima alla pull request della release.

set -euo pipefail

da=$1 a=$2 cartella=$3
distruttive='\b(DROP[[:space:]]+(TABLE|COLUMN|SCHEMA|TYPE|VIEW)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+COLUMN[^;]*[[:space:]]TYPE[[:space:]]|RENAME[[:space:]]+(TO|COLUMN)|SET[[:space:]]+NOT[[:space:]]+NULL)\b'

git diff --name-only --diff-filter=AM "$da...$a" -- "$cartella" \
  | { grep -E '\.sql$' || true; } \
  | while read -r file; do
      git show "$a:$file" | { grep -niE "$distruttive" || true; } | sed "s|^|$file:|"
    done
