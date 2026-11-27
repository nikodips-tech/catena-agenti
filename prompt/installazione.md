# Installazione della catena in un progetto

Passi comuni ai prompt 1 e 2, da eseguire dopo la loro ricognizione (e, per il 2, dopo la
pulizia). Valgono `regole-sessione.md` e i documenti della catena: `docs/specifica.md`,
`docs/configurazione.md`, `docs/permessi.md`, `docs/ci.md`, `docs/rilascio.md`. Qui si
collega il progetto alla catena pubblicata (`nikodips-tech/catena-agenti`, tag `v2`): non si
copia niente della catena, si scrivono solo i file del progetto.

Il risultato atteso: una issue con `auto` arriva da sola fino alla pull request unita in
`develop`, la release si prepara da sola, e il proprietario interviene solo per le fermate
di `docs/specifica.md`, sezione 10.

## A. Prerequisiti che richiedono le mani dell'utente

Controlla, con `gh`, tutto ciò che `docs/permessi.md` elenca in «Cosa serve in ogni
repository»: segreto `CLAUDE_CODE_OAUTH_TOKEN`, App della catena installata, environment
`agenti` con `AGENTI_CLIENT_ID` e `AGENTI_APP_KEY` e policy dei rami con **`develop` e
`master`**, "Allow GitHub Actions to create and approve pull requests", auto-merge abilitato.
Ciò che puoi fare con `gh` lo fai (policy, impostazioni); ciò che richiede lui (segreti,
installazione della App) glielo chiedi con l'elenco preciso dei comandi e **ti fermi**.

## B. Il ramo e la pull request

Tutto il resto entra in develop con **una sola PR**, ramo `catena` da `develop`. Una PR sola
perché la CI del progetto cambia insieme ai controlli obbligatori: a metà strada le PR
resterebbero bloccate. Ordine: apri la PR, aspetta che la CI condivisa produca i suoi check,
sistema i ruleset (passo G), unisci.

## C. Configurazione e istruzioni di Claude

| File | Da | Adattamenti |
|---|---|---|
| `.catena.yml` | `modello-repo/.catena.yml`, esempi in `docs/esempi/catena-*.yml` | **tutti i comandi** come li lancia il progetto, stesso container (`aggiorna` per le dipendenze); `retrospettiva` (`si` predefinito); `cartella`; `file_test`, `file_e2e` secondo dove stanno davvero; `framework_test`; `docs`; `dockerfile`/`immagini` e `migrazioni` (vuoti se non esistono); `test_db` solo se il progetto ha test con database che vuole in CI; `chiudi_issue: produzione`; staging solo se il progetto ha un workflow di staging (passo H) |
| `CLAUDE.md` | `modello-repo/CLAUDE.md` | compilato con il progetto: due righe su cos'è e lo stack, i comandi **uguali** a `.catena.yml`, i rami. In italiano, massimo 45 righe. Tieni la sezione «Due corsie». Non descrivere agenti o orchestratori |
| `.claude/agents/product-owner.md` | `agenti/product-owner.md` della catena | la sezione «Fonti»: se il repo ha già visione, roadmap, glossario o simili, indica quelli al posto di `docs/prodotto/*` |
| `.claude/skills/catena/SKILL.md`, `.claude/agents/catena-*.md` | `modello-repo/.claude/` | nessuno (la catena in sessione locale, `docs/locale.md`) |
| `docs/prodotto/visione.md`, `glossario.md`, `decisioni.md` | `modello-repo/docs/prodotto/` | solo se il repo non ha documenti equivalenti; la visione in tre righe dal README, gli altri come scheletro |

## D. Regole di progetto (`.claude/rules/`)

`CLAUDE.md` resta corto e generale. Se il repository ha **aree con convenzioni diverse** (più
pacchetti, backend e frontend, più frontend), scrivi una regola per area in
`.claude/rules/<area>.md`, con il frontmatter `paths:` che la limita a quelle cartelle:
struttura della cartella, come si scrivono i test lì, cosa non si fa. Massimo 30 righe
ciascuna, ricavate da ciò che il codice e la documentazione già fanno, non inventate. Se il
repository è omogeneo, nessuna regola: dillo nel resoconto. Le regole le legge anche la CLI
sul runner: gli agenti della catena le rispettano senza saperlo.

## E. Workflow

| File | Da | Adattamenti |
|---|---|---|
| `.github/workflows/catena.yml` | `modello-repo/.github/workflows/catena.yml` | nessuno |
| `.github/workflows/ci.yml` | `modello-repo/.github/workflows/ci.yml` | il `name:` resta `CI`. Aggiungi solo i job propri del progetto che la CI condivisa non copre, per esempio gli e2e: solo con `workflow_dispatch` e un input `e2e` (predefinito no), `needs: ci`, nessun altro job dipende da loro |
| `.github/workflows/release.yml`, `tag-master.yml`, `in-develop.yml` | `modello-repo/.github/workflows/` | nessuno |
| `.github/ISSUE_TEMPLATE/task.yml`, `hotfix.yml`, `.github/pull_request_template.md` | `modello-repo/.github/` | nessuno |

I workflow di **rilascio in produzione, staging e anteprima** sono del progetto: la catena non
li fornisce. Se esistono restano come sono, con i file che usano. Se il progetto non li ha,
non li creare: il tag `x.y.z` che `Tag master` crea è il punto a cui agganciare, un giorno,
il rilascio.

`CODEOWNERS`: se esiste, il proprietario su `/.github/`, `/.catena.yml`, `/CLAUDE.md`,
`/.claude/`. Se non esiste, crealo con queste righe: il ruleset di `master` chiede la review
del code owner.

## F. Etichette

Le crea il preflight della catena al primo avvio. Anticipale:
`GH_REPO=<owner>/<repo> CATENA=<CARTELLA> bash <CARTELLA>/scripts/preflight.sh etichette`
(serve Git Bash). Se non è possibile, `gh label create` dalla tabella in
`scripts/preflight.sh`. Quattordici etichette: `task`, `hotfix`, `sotto-task`, `auto`, `turn-team-leader`,
`turn-developer`, `turn-reviewer`, `turn-editor`, `turn-ci`, `turn-human`, `retrospective`,
`retrospective-approved`, `unione-automatica`, `in-develop`.

## G. Protezione dei rami

Ruleset `develop` e `master` da `docs/esempi/ruleset-*.json`, con i `context` dei check della
CI condivisa **come compaiono sulla PR del passo B**: `ci / lint`, `ci / tipi`, `ci / test`,
`ci / migrazioni`, `ci / build <servizio>` per ogni immagine, `ci / test-db` se configurato.
Mai e2e. Se i ruleset esistono, aggiorna solo i `context` e, in quello di `master`,
`allowed_merge_methods: ["merge"]` nella regola `pull_request`: in master si entra solo con un
merge commit (`docs/rilascio.md`). Un check richiesto che non esiste blocca ogni PR per
sempre: confronta con `gh pr checks`.

## H. Staging

Se il progetto ha un workflow di staging con un interruttore (per esempio una variabile
`STAGING_AUTOMATICO=si`), compila `staging_*` in `.catena.yml`, imposta la variabile e lancia
il workflow una volta a mano. Rosso: non ripararlo, riporta l'errore. Senza staging, niente.

## I. Verifica finale

1. La PR `catena` unita in develop con i check verdi, ramo cancellato.
2. I ruleset richiedono solo check che la PR ha davvero prodotto.
3. `gh workflow list`: `Catena`, `CI`, `Release`, `Tag master`, `In develop` attivi; nessun
   altro workflow di Claude o del vecchio metodo. Uno disattivato: `gh workflow enable`.
4. Nessun file rimasto cita file, etichette o workflow che non esistono più (`grep`).
5. Le quattordici etichette esistono. Nessun ramo remoto oltre a develop, master ed eventuale release.
6. Non hai messo `auto` e non hai lanciato nessun workflow della catena.

La prova vera la fa l'utente: una issue piccola e reale con `task`, poi `auto`. Cosa guardare:
il commento `## Specifica` con la riga `Corsia:`, il consumo in ogni commento, la PR aperta
dall'App con `unione-automatica`, la release che si apre da sola dopo l'unione.
