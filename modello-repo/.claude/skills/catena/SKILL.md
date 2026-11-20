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
dell'interfaccia, niente `auto`. In più: i test che esistono già in `develop` non si
cancellano e si modificano solo quelli che il team leader mette in `test_modificabili`, e
non si toccano i file protetti (`.github/`, `.claude/`, `CLAUDE.md`,
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
`test: false`). In `$CATENA/lavoro/test-modificabili.txt`, uno per riga, i test di `develop`
che il developer può modificare: il `test_modificabili` del sottotask (in corsia diretta
quello al primo livello) più quelli già modificati sul ramo
(`git diff --diff-filter=M --name-only develop...HEAD -- <file di test>`).

**Developer**, fino a 3 tentativi: lancia `catena-developer` con `developer.md`,
`specifica.md`, `sottotask.md`, l'elenco dei file di test aggiunti sul ramo,
`test-modificabili.txt`, e dal secondo tentativo `errore.txt` con le ultime righe
dell'errore. Dopo ogni tentativo:
1. ripristina file protetti ed e2e, e i test che esistono già in `develop` se li ha
   cancellati o modificati senza che siano in `test-modificabili.txt`
   (`git diff --name-status develop -- <file di test>`);
2. `bash $CATENA/scripts/controlli.sh formatta <file cambiati rispetto a develop>`;
3. `bash $CATENA/scripts/controlli.sh tutto`;
4. verde → commit `feat: <titolo>` (o `fix:` per hotfix), prossimo sottotask;
   rosso → lascia il lavoro nel checkout (il tentativo dopo lo corregge), scrivi
   `errore.txt`, riprova. Al terzo rosso, o al primo rosso dopo aver ripristinato test di
   `develop` (il tentativo dopo rifarebbe la stessa modifica): fermati, mostra l'errore
   all'utente e chiedi se riformulare il sottotask (rilanci il team leader con l'errore, che
   può autorizzare quei test in `test_modificabili`) o interrompere.

## 4. Revisore (solo corsia completa, al massimo 2 giri)

Lancia `catena-revisore` con `revisore.md`, `specifica.md`, il diff `develop...HEAD`
salvato in `$CATENA/lavoro/differenze.diff`, l'elenco dei test aggiunti dal developer e
quello dei test di `develop` modificati sul ramo. Esito
in `$CATENA/lavoro/esito.json`:
- `approvato` → avanti;
- `rimuovi` → cancella solo file aggiunti sul ramo e assenti in develop, commit
  `chore: rimozione file estranei`, rilancia (conta come giro);
- `sottotask` → torna al passo 3 per quelli nuovi.
Dopo 2 giri senza approvazione: avanti "con riserve", e la PR non avrà `unione-automatica`.

## 5. Editor

Lancia `catena-editor` con `editor.md`, `specifica.md`, `differenze.diff`. Tieni solo le
modifiche dentro `docs/` e `README.md`; commit `docs: <titolo>` se c'è qualcosa.

## 6. Pull request

Push del ramo e `gh pr create` verso `develop` (o `master` per hotfix) con titolo prefissato
(`feat:`/`fix:`), corpo con `Closes #n` se c'è l'issue (`Refs #n` se `.catena.yml` ha `chiudi_issue:
produzione` e la PR va in `develop`: l'issue resta aperta fino al rilascio), `Corsia:`, `Revisione:` e l'elenco dei
sottotask, etichetta `task` (o `hotfix`). `unione-automatica` solo se: task, revisione
approvata o corsia diretta, e l'utente non ha chiesto di guardarla prima. La CI e l'unione
sono le stesse della catena su GitHub.

## 7. Chiusura

Cancella `$CATENA`. Riferisci: ramo, PR, sottotask fatti, tentativi, cosa è stato scartato,
riserve del revisore.
