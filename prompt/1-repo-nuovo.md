# Un repository nuovo

Per un repository che non ha niente di Claude (`CLAUDE.md`, `.claude/`) e nessun workflow di
Claude o di un metodo precedente. Può avere altri workflow, che restano. Sessione aperta nella
cartella del repository, **un progetto per sessione**.

Leggi prima `<CARTELLA>/prompt/regole-sessione.md`, poi `<CARTELLA>/docs/specifica.md`,
`<CARTELLA>/docs/configurazione.md`, `<CARTELLA>/docs/permessi.md`.

## 1. Ricognizione (solo lettura)

Un quadro breve, che finirà nel resoconto:
- Rami: `develop` e `master` (o `main`). Se c'è un solo ramo, **fermati** e proponi: creare
  `develop` da quello, e il ramo attuale diventa la produzione (`ramo_produzione` in
  `.catena.yml`). Aspetta la risposta.
- Stack e comandi: lint, formattazione, tipi, test unitari, test con database, build; se il
  progetto gira in container, con quale immagine. Il framework di test. Dove stanno i test e
  gli e2e, se esistono. Il Dockerfile e la cartella delle migrazioni, se esistono.
- Documentazione: dove sta (`docs/`, `README.md`), se c'è una visione o una roadmap.
- Struttura: un solo pacchetto o più aree con convenzioni diverse (serve per le regole di
  progetto).
- Workflow esistenti: cosa fanno; quelli di rilascio, staging o anteprima restano.
- Su GitHub: ruleset, etichette, environment, PR aperte, "Allow GitHub Actions to create and
  approve pull requests", auto-merge.
- Se il progetto non ha nessun framework di test unitari, **fermati**: introdurlo è una
  decisione dell'utente.

## 2. Installazione

Esegui `<CARTELLA>/prompt/installazione.md`, dal passo A al passo I.

## 3. Resoconto

Come in `regole-sessione.md`.
