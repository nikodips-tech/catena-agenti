# Passare un progetto da v1 a v2

Per un progetto che usa già la catena con `@v1` e va portato alla `@v2`. Sessione aperta nella
cartella del repository, **un progetto per sessione**.

Leggi prima `<CARTELLA>/prompt/regole-sessione.md`, poi `<CARTELLA>/docs/specifica.md`,
`<CARTELLA>/docs/configurazione.md`.

## 1. Prima di cominciare (solo lettura)

- **Aspetta che nessuna issue sia in corso**: nessuna con l'etichetta `in-corso`, nessuna PR
  `issue-*` aperta. Se ce n'è una, fermati e riferisci: va finita prima, a mano.
- `git status` pulito, rami `develop` e `master` presenti.

## 2. Modifiche (una PR verso develop, titolo `chore:`)

- `.github/workflows/catena.yml`: sostituiscilo con quello di `<CARTELLA>/modello-repo/` (usa
  `@v2`, e il commento dell'`issue_comment` ora aspetta `turn-human` al posto di `domanda`).
  Conserva solo gli adattamenti del progetto (cron, runner).
- Gli altri workflow del modello (`ci.yml`, `release.yml`, `tag-master.yml`, `in-develop.yml`):
  stessi nomi, solo `@v1` → `@v2`.
- `.claude/skills/catena/SKILL.md`: dal modello (`--branch v2`).
- `.catena.yml`: le chiavi nuove, da `<CARTELLA>/docs/configurazione.md`:
  - `aggiorna`: il comando che aggiorna le dipendenze e riallinea il lock (npm:
    `npm install --no-audit --no-fund`; composer: `composer update --no-interaction
    --no-scripts --minimal-changes`). Il developer ora cambia da solo le dipendenze.
  - `retrospettiva`: `si` (predefinito) o `no`.
  - Le chiavi `dipendenze`, `dipendenze_sviluppo`, `dipendenze_togli` e `file_lock`, se ci
    sono, si tolgono.

## 3. Etichette

Le etichette del vecchio metodo non servono più: dopo il merge, `gh label delete in-corso`,
`gh label delete domanda`, `gh label delete bloccato`. Quelle nuove (`turn-*`, `retrospective`,
`retrospective-approved`) le crea il preflight al primo avvio.

## 4. Dopo il merge

Gli eventi delle issue (`auto`, i commenti) usano il `catena.yml` del **ramo predefinito** del
repository; i passi (`workflow_dispatch`) quello di `develop`. Se il ramo predefinito non è
`develop` (di solito `master`), il nuovo `catena.yml` deve arrivare anche lì prima della
prossima `auto`, altrimenti l'avvio resta su v1 e i passi girano su v2: una PR da `develop` al
ramo predefinito, che unisce il proprietario.
Fino ad allora nessuna `auto`.

Niente da lanciare. Il resoconto dice cosa è cambiato e che la prima issue con `auto` mostrerà
le etichette `turn-*`. Mai l'etichetta `auto` da qui.
