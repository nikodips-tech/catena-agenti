# Aggiornare un progetto già migrato con il vecchio metodo

Per i repository (cineNight) che hanno già fatto la migrazione descritta nel vecchio
`migrazione-catena-agenti.md`: CLAUDE.md nuovo, CI, etichette, ruleset, staging e una **copia
locale** della catena in `.github/workflows/catena-*.yml`, `.github/scripts/` e
`.claude/agenti/`. Qui si sostituisce la copia con il collegamento alla catena condivisa.
**Niente pulizie** della parte vecchia: è già stata fatta.

Da eseguire in una sessione aperta nella cartella del repository. Leggi prima
`<CARTELLA>/prompt/regole-sessione.md`, poi `<CARTELLA>/docs/specifica.md`,
`<CARTELLA>/docs/configurazione.md`.

---

## 1. Ricognizione (solo lettura)

- I file della vecchia copia: `.github/workflows/catena-*.yml`, in `.github/scripts/`
  `avvia-sottotask.sh`, `catena-controlli.sh`, `rimuovi-file.sh`, e `.claude/agenti/*.md`.
  Per ogni script in `.github/scripts/` verifica con `grep` **chi lo usa**: `progetto.sh`,
  `migrazioni-distruttive.sh`, `test-indeboliti.sh` li usano CI e release e **restano**.
- `CLAUDE.md`, `CODEOWNERS`, `.github/progetto.yml`.
- Etichette, ruleset e controlli obbligatori, variabili (`STAGING_AUTOMATICO`), environment
  `agenti`, PR aperte, issue con `in-corso`, `auto`, `domanda` o `bloccato`.
- Se una issue è `in-corso` o ha una PR `issue-*` aperta: **fermati e riferisci**. La catena
  vecchia e quella nuova non devono sovrapporsi su un lavoro in corso.

## 2. Confronto con la catena provata

Prima di cancellare, confronta la copia locale con la catena nuova e scrivi nel resoconto le
differenze che contano. In particolare, verifica che in `<CARTELLA>` siano presenti i rimedi
già provati qui:
- `catena-controlli.sh` → `scripts/controlli.sh` + `.catena.yml`: stesso container, stessi
  comandi, output corto, `npm ci` silenzioso, reporter dei test con solo i fallimenti,
  formattazione (prettier + eslint --fix).
- Chiusura con l'App e issue lette con il token di Actions; commit vuoto se la PR esiste.
- Unione con prefisso `feat:`/`fix:`, staging secondo `STAGING_AUTOMATICO`.
- Controlli scritti con `if …; then`, non `$?`.
- Test della base protetti dal developer.
Il tester separato della copia locale non esiste più nella catena nuova: il developer scrive
test e codice in TDD. Non è una mancanza da segnalare.
Se qualcosa di provato manca nella catena nuova, **non modificare la catena**: segnalalo nel
resoconto come «da correggere nella catena» e vai avanti.

## 3. Sostituzione

Ramo `catena-condivisa` da develop, una PR.

**Si cancella**: `.github/workflows/catena-avvio.yml`, `catena-team-leader.yml`,
`catena-tester.yml`, `catena-developer.yml`, `catena-revisione.yml`, `catena-editor.yml`,
`catena-chiusura.yml`, `catena-unione.yml`; `.github/scripts/avvia-sottotask.sh`,
`catena-controlli.sh`, `rimuovi-file.sh`; `.claude/agenti/` per intero. Prima,
`gh workflow disable` sugli otto workflow.

**Si aggiunge** (tabella in `1-migrazione-nuovo-repo.md`, sezione 4):
`.github/workflows/catena.yml`, `.catena.yml` (per cineNight parti da
`<CARTELLA>/docs/esempi/catena-node.yml`, che è già la sua configurazione: verifica i comandi
contro `ci.yml` e `package.json`), i modelli di issue e di PR, `.claude/agents/product-owner.md`
con la sezione «Fonti» che punta ai documenti esistenti (`docs/visione.md`, `docs/roadmap.md`,
`docs/INDICE.md`…), la skill `.claude/skills/catena/` con gli agenti `.claude/agents/catena-*.md`
(la catena in sessione locale, `docs/locale.md`), e `docs/prodotto/decisioni.md` e
`glossario.md` come scheletro solo se non esistono equivalenti.

**Si aggiorna**:
- `CLAUDE.md`: aggiungi la sezione «Due corsie per le modifiche» da
  `<CARTELLA>/modello-repo/CLAUDE.md` e la riga `.catena.yml` tra le cose per cui chiedere
  prima. Resto invariato.
- `CODEOWNERS`: `/.catena.yml`, `/.claude/agents/` e `/.claude/skills/` al proprietario
  (le righe già presenti in forma equivalente restano com'erano).
- `.github/workflows/ci.yml` e `release.yml`: **non toccarli**. Verifica solo che nessun
  commento o passo citi i file cancellati in modo che possa fallire (`grep catena-`).
- Etichette: aggiungi `unione-automatica` (le altre sette ci sono già). Puoi usare
  `GH_REPO=<owner>/<repo> CATENA=<CARTELLA> bash <CARTELLA>/scripts/preflight.sh etichette`.
- Ruleset: invariati. Verifica che i controlli obbligatori siano `lint`, `tipi`, `test`,
  `build app`, `migrazioni` e che corrispondano ai job di `ci.yml`.

PR, controlli verdi, merge, ramo cancellato.

## 4. Verifica

1. `gh workflow list`: `Catena` attivo, nessun `Catena *` vecchio attivo (cancellati con i
   file; se restano come disabilitati nell'elenco, va bene).
2. `gh api repos/<owner>/<repo>/contents/.catena.yml` esiste su develop.
3. Nessun riferimento a `catena-controlli.sh`, `avvia-sottotask.sh`, `.claude/agenti` nei file
   rimasti (`grep -r`).
4. Environment `agenti`, `STAGING_AUTOMATICO`, segreti: invariati.
5. Non hai messo `auto` e non hai lanciato la catena.

## 5. La prima prova (la fa l'utente, tu la prepari)

Suggerisci nel resoconto una issue piccola e reale già aperta (o proponi un titolo) con
`task`, da usare come primo giro con `auto`. Spiega cosa osservare: il commento `## Specifica`
con la riga `Corsia:`, i commenti con il consumo di ogni passo, la PR aperta dall'App con
`unione-automatica`. Se il primo giro fallisce, la correzione va nella catena
(`nikodips-tech/catena-agenti`), non qui.

## 6. Resoconto

Come in `regole-sessione.md`, più la sezione «Confronto»: le differenze tra copia locale e
catena nuova e cosa, se qualcosa, è da correggere nella catena.
