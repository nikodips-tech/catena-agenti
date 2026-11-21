---
name: catena
description: Esegue la catena di agenti in sessione locale (team leader, developer, revisore, editor) su una issue o su una richiesta detta a voce, e apre la pull request. Usala quando l'utente chiede "/catena", "fai girare la catena qui", "sviluppa la issue #n in locale". Non per modifiche in corsia diretta decise in sessione: quelle le fai direttamente.
---

# La catena in sessione locale

Sei l'orchestratore: fai in sessione ciò che su GitHub fanno `avvio.sh` e gli script di
esito. Gli agenti sono i sottoagenti `catena-*` di `.claude/agents/`, che leggono gli stessi
prompt della catena su GitHub. Tu hai git e gh; loro no. Ogni passo lo esegui con l'Agent
tool, uno alla volta, e riporti all'utente una riga per passo.

Regole di `CLAUDE.md` sempre valide: mai in `master`, niente e2e, niente verifiche
dell'interfaccia, niente `auto`. In più: i test che esistono già in `develop` il developer può
modificarli e cancellarli se il sottotask cambia o toglie il comportamento che verificano (con
le note in `$CATENA/lavoro/note-developer.md`), tranne quelli che il revisore ha bloccato; non
si toccano i file protetti (`.github/`, `.claude/`, `CLAUDE.md`,
`.catena.yml`, `.env`).

## 0. Preparazione

1. `git status` pulito e ramo `develop` aggiornato; altrimenti fermati.
2. Scarica la catena al suo tag in una cartella temporanea (`$CATENA`), fuori dal repo:
   `gh repo clone nikodips-tech/catena-agenti "$CATENA" -- --depth 1 --branch v1`
3. Leggi `.catena.yml` del progetto (comandi, `file_test`, `framework_test`).
4. Input: un numero di issue (`gh issue view`) oppure la richiesta dell'utente. Scrivi il
   testo in `$CATENA/lavoro/issue.md`. Tutti i file dati stanno in `$CATENA/lavoro/`, mai nel
   repo.

## 1. Team leader

Lancia `catena-team-leader` con: il percorso di `$CATENA/agenti/team-leader.md`, di
`issue.md`, e dove scrivere `esito.json` (`$CATENA/lavoro/esito.json`, **non** nella radice
del repo). Poi:
- `domanda` → fai la domanda all'utente, aggiungi la risposta a `issue.md`, rilancia.
- `corsia: diretta` → un solo "sottotask" che è la specifica intera, con `test: true`, e si
  salta il revisore.
- `corsia: completa` → l'elenco dei sottotask, in ordine. Scrivi la specifica in
  `$CATENA/lavoro/specifica.md`.
Mostra all'utente specifica e sottotask in breve e vai avanti senza aspettare, salvo che
chieda di fermarsi.

## 2. Ramo

`issue-<n>` da `develop` se c'è una issue, altrimenti `diretta/<slug>`. Per un hotfix:
`hotfix/issue-<n>` da `master`.

## 3. Per ogni sottotask

Scrivi il sottotask in `$CATENA/lavoro/sottotask.md` (con la riga `Test: no` se
`test: false`). In `$CATENA/lavoro/test-bloccati.txt`, uno per riga, i test di `develop` che il
revisore ha fatto ripristinare e che il developer non può toccare (vuoto all'inizio e in
corsia diretta); cresce quando il revisore chiede `ripristina` (passo 4).

**Developer**, fino a 2 tentativi: lancia `catena-developer` con `developer.md`,
`specifica.md`, `sottotask.md`, l'elenco dei file di test aggiunti sul ramo,
`test-bloccati.txt`, il comando per cancellare i file che il sottotask chiede di togliere
(`bash $CATENA/scripts/rimuovi.sh <file…>`, con `BASE=develop` o `master`), e dal secondo
tentativo `errore.txt` con le ultime righe
dell'errore. Digli che in locale le note stanno in `$CATENA/lavoro/note-developer.md` (non nel
repo): una riga per ogni test di `develop` toccato o scelta particolare, con il perché. Dopo
ogni tentativo:
1. ripristina file protetti ed e2e, e i test di `test-bloccati.txt` se li ha toccati;
2. `bash $CATENA/scripts/controlli.sh formatta <file cambiati rispetto a develop>`;
3. `bash $CATENA/scripts/controlli.sh tutto`;
4. verde → commit `feat: <titolo>` (o `fix:` per hotfix), con le note nel corpo, prossimo
   sottotask;
   rosso → lascia il lavoro nel checkout (il tentativo dopo lo corregge), scrivi
   `errore.txt`, riprova. Al secondo rosso, o al primo rosso dopo aver ripristinato test
   bloccati (il tentativo dopo rifarebbe la stessa modifica): fermati, mostra l'errore
   all'utente e chiedi se riformulare il sottotask (rilanci il team leader con l'errore, che
   può tenere i test bloccati o sbloccarli) o interrompere.

In corsia diretta, se il lavoro ha modificato o cancellato test di `develop`
(`git diff --name-status develop...HEAD`), passa dal revisore (passo 4) prima della PR.

## 4. Revisore (corsia completa, o diretta se il lavoro ha toccato test di `develop`; al massimo 2 giri)

Lancia `catena-revisore` con `revisore.md`, `specifica.md`, il diff `develop...HEAD`
salvato in `$CATENA/lavoro/differenze.diff`, l'elenco dei test aggiunti dal developer, le
righe `M file`/`D file` dei test di `develop` modificati o cancellati sul ramo
(`test-base-toccati.txt`) e le note del developer (`note-developer.md`). Esito
in `$CATENA/lavoro/esito.json`:
- `approvato` → avanti;
- `rimuovi` → cancella solo file aggiunti sul ramo e assenti in develop, commit
  `chore: rimozione file estranei`, rilancia (conta come giro);
- `ripristina` → per ogni file `git checkout develop -- <file>` (solo test che esistono in
  `develop`, mai protetti o e2e), commit `chore: ripristino test`; i file entrano in
  `test-bloccati.txt` e nei sottotask nuovi;
- `sottotask` → torna al passo 3 per quelli nuovi.
Dopo 2 giri senza approvazione: avanti "con riserve": la PR ha comunque `unione-automatica`
e le riserve stanno nel corpo.

## 5. Editor

Lancia `catena-editor` con `editor.md`, `specifica.md`, `differenze.diff`. Tieni solo le
modifiche dentro `docs/` e `README.md`; commit `docs: <titolo>` se c'è qualcosa.

## 6. Pull request

Push del ramo e `gh pr create` verso `develop` (o `master` per hotfix) con titolo prefissato
(`feat:`/`fix:`), corpo con `Closes #n` se c'è l'issue (`Refs #n` se `.catena.yml` ha `chiudi_issue:
produzione` e la PR va in `develop`: l'issue resta aperta fino al rilascio), `Corsia:`, `Revisione:` e l'elenco dei
sottotask, etichetta `task` (o `hotfix`). `unione-automatica` solo se: task (anche con
riserve, scritte nel corpo) e l'utente non ha chiesto di guardarla prima. La CI e l'unione
sono le stesse della catena su GitHub.

## 7. Chiusura

Cancella `$CATENA`. Riferisci: ramo, PR, sottotask fatti, tentativi, cosa è stato scartato,
riserve del revisore.
