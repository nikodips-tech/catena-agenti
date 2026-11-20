# Catena di agenti

Una issue entra con l'etichetta `auto`, una pull request unita esce. In mezzo: team leader,
developer (in TDD), revisore ed editor (Claude Code), coordinati da script senza Claude, su
GitHub Actions. Un repository solo per tutti i progetti: ogni progetto ha un wrapper di
workflow e un file di configurazione.

| Per | Leggi |
|---|---|
| Capire come funziona | [docs/specifica.md](docs/specifica.md), poi [docs/flusso.md](docs/flusso.md) |
| Decidere se passare dalle issue o fare la modifica direttamente | [docs/corsie.md](docs/corsie.md) |
| Collegare un progetto | [prompt/README.md](prompt/README.md) (i prompt per Claude Code), [docs/configurazione.md](docs/configurazione.md), [docs/permessi.md](docs/permessi.md) |
| La CI dei progetti | [docs/ci.md](docs/ci.md) |
| Release, tag e chiusura delle issue | [docs/rilascio.md](docs/rilascio.md) |
| Portarla su un'altra piattaforma | [docs/portabilita.md](docs/portabilita.md) |
| Farla girare in una sessione di Claude Code | [docs/locale.md](docs/locale.md) |
| Scrivere issue buone | [agenti/product-owner.md](agenti/product-owner.md), [docs/esempi/issue-task.md](docs/esempi/issue-task.md) |

## Struttura

```
agenti/                 prompt dei ruoli (portabili) + product owner
scripts/                logica della catena (portabile): avvio, contesto, agente, raccolta, esito-*, chiusura, unione…
scripts/ci/             la CI condivisa dei progetti: cambi, controlli, migrazioni e test indeboliti
scripts/rilascio/       release, tag-master e issue in develop dei progetti
piattaforme/github/     adattatore: le sole funzioni che parlano con GitHub
piattaforme/gitlab/     segnaposto
.github/workflows/      workflow riutilizzabili (workflow_call), chiamati dai progetti
modello-repo/           cosa va in ogni progetto: catena.yml, ci.yml, release, tag-master, in-develop, .catena.yml, CLAUDE.md, modelli di issue e PR,
                        product owner, skill /catena e agenti sottili per la sessione locale
docs/                   specifica, corsie, flusso, permessi, configurazione, CI, portabilità, esempi
prompt/                 i prompt per migrare o aggiornare un progetto con Claude Code
```

## Versioni

I progetti richiamano i workflow con `@v1`. Una correzione alla catena si pubblica spostando
il tag:

```bash
git tag -f v1 && git push -f origin v1
```

Tutti i progetti la prendono alla prossima esecuzione. Per bloccare un progetto a una
versione, nel suo `catena.yml` si sostituisce `@v1` con un tag fisso (`@v1.0.0`) o uno SHA.

## Regole fisse

- `auto` la mette solo il proprietario. Nessun agente, nessuno script.
- Mai in `master` da soli: la PR verso `master` la unisce il proprietario.
- Claude non ha git, gh né token. Scrive file; il resto lo fanno gli script.
- Niente copie della catena nei progetti: si corregge qui.
