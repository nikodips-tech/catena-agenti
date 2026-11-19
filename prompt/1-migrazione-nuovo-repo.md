# Collegare alla catena un progetto che non l'ha mai avuta

Da eseguire in una sessione aperta nella cartella del repository del progetto, **un progetto
per sessione**. Leggi prima `<CARTELLA>/prompt/regole-sessione.md`, poi
`<CARTELLA>/docs/specifica.md`, `<CARTELLA>/docs/configurazione.md`,
`<CARTELLA>/docs/permessi.md`. La catena è pubblicata su `nikodips-tech/catena-agenti`
(tag `v1`); qui si collega il progetto, non si copia niente della catena.

---

## 1. Ricognizione (solo lettura)

Prepara per te un quadro breve, che finirà nel resoconto.

**Nel repo**
- File di Claude: `CLAUDE.md`, `.claude/`, `.agenti/`, `.worktrees/`, altri.
- Workflow in `.github/workflows`: per ognuno evento, cosa fa, se usa
  `anthropics/claude-code-action` o `CLAUDE_CODE_OAUTH_TOKEN`.
- Altri file in `.github/` (script, CODEOWNERS, configurazioni) e da quali workflow sono usati.
- Stack e comandi: lint, formattazione, tipi, test unitari, test con database, build; se il
  progetto gira in container, come li lancia la CI. Il framework di test.
- Dove stanno i test e dove gli e2e, se esistono (servono per `file_test` e `file_e2e`).
- Dove sta la documentazione (`docs/`, `README.md`): servirà all'editor e al product owner.

**Su GitHub**
- Ruleset e protezione dei rami, con i controlli obbligatori.
- PR aperte, in particolare la PR di release.
- Variabili e segreti del repo (solo i nomi). Environment, in particolare `agenti`.
- Etichette. Rami remoti.
- "Allow GitHub Actions to create and approve pull requests".

**Prerequisiti che richiedono l'utente** (`docs/permessi.md`, «Cosa serve in ogni
repository»): segreto `CLAUDE_CODE_OAUTH_TOKEN`, App `dipstech-agenti` installata,
environment `agenti` con `AGENTI_CLIENT_ID` e `AGENTI_APP_KEY` e policy dei rami con
`develop`. Se manca qualcosa, fermati e dagli l'elenco preciso con i comandi.

## 2. Pulizia della vecchia parte Claude

Ordine obbligatorio: **prima GitHub, poi i file**, altrimenti le PR restano bloccate da
controlli obbligatori che non arrivano più.

**Si cancella**: `CLAUDE.md` (verrà riscritto), `.claude/` e `.agenti/` per intero,
`.worktrees/` e le sue righe in `.gitignore`, ogni workflow che usa `claude-code-action` o
`CLAUDE_CODE_OAUTH_TOKEN`, i workflow della vecchia catena (code di hotfix, reazioni alle
etichette, sorveglianza), script e configurazioni usati **solo** da workflow cancellati, file
sparsi della vecchia catena non richiamati da niente.

**Si tiene**: CI, release, tag, rilascio, staging, anteprima, chiusura delle issue,
CODEOWNERS, segreti, le etichette standard e `hotfix`.

Sequenza:
1. `gh workflow disable` sui workflow da cancellare.
2. Togli dai ruleset i controlli obbligatori che venivano da quei workflow, e `e2e` se c'è.
3. Ramo `pulizia-claude` da develop: cancella i file; nei workflow rimasti togli i riferimenti
   a file, etichette o workflow cancellati (un `--remove-label` su un'etichetta che non
   esisterà più fa fallire il passo). PR, controlli verdi, merge.
4. Cancella le etichette usate solo dalla vecchia catena (anche priorità e valutazione).
5. `git fetch --prune` e `git config fetch.prune true`.

Se il repo non ha mai avuto niente di Claude, questa sezione è vuota: dillo nel resoconto.

## 3. Fondamenta

Ramo `fondamenta` da develop, una PR.

**CLAUDE.md**: da `<CARTELLA>/modello-repo/CLAUDE.md`, compilato con il progetto. In italiano,
massimo 45 righe. I comandi come li lancia il progetto (container compreso) e **uguali** a
quelli che metterai in `.catena.yml`. Tieni la sezione «Due corsie». Non descrivere agenti o
orchestratori.

**CI**:
- Il job `e2e`, se esiste, parte solo con `workflow_dispatch` e un input `e2e` (predefinito
  no). Nessun altro job dipende da lui. I test e2e restano nel repo.
- Se il repo non ha una CI sulle PR, creala da `<CARTELLA>/docs/esempi/ci-minima.yml`: job
  separati per lint, tipi, test, build (solo quelli che hanno senso per lo stack), nello stesso
  container del progetto, nomi dei job semplici (`lint`, `tipi`, `test`, `build app`). Il
  `name:` del workflow è `CI`.
- I job che saranno obbligatori girano anche con `workflow_dispatch`.

**Etichette**: le crea il preflight della catena. Puoi anticiparle da qui:
`GH_REPO=<owner>/<repo> CATENA=<CARTELLA> bash <CARTELLA>/scripts/preflight.sh etichette`
(serve Git Bash). Se il comando non è disponibile, creale con `gh label create` dalla tabella
in `scripts/preflight.sh`.

**Protezione dei rami**: se mancano, crea i ruleset `develop` e `master` da
`<CARTELLA>/docs/esempi/ruleset-*.json` adattando i `context` **ai nomi esatti dei job** della
CI di questo repo. Mai e2e. Abilita "Allow GitHub Actions to create and approve pull requests".

**Staging**: se il repo ha un workflow di staging, leggi quale variabile lo accende
(in cineNight `STAGING_AUTOMATICO=si`), impostala e lancia il workflow una volta a mano. Se
finisce rosso non ripararlo: riporta l'errore. Se il repo non ha staging, non crearlo.

## 4. Collegamento alla catena

Ramo `catena` da develop, una PR. Hai l'autorizzazione a creare questi file:

| File | Da | Adattamenti |
|---|---|---|
| `.github/workflows/catena.yml` | `modello-repo/.github/workflows/catena.yml` | nessuno, salvo `workflows: [CI]` se la CI ha un altro `name:` |
| `.catena.yml` | `modello-repo/.catena.yml` (esempi in `docs/esempi/catena-*.yml`) | **tutti i comandi** come la CI, stesso container; `file_test`, `file_e2e` secondo dove stanno davvero; `framework_test`; `docs`; staging solo se esiste; `test_db` solo se la CI lo esegue |
| `.github/ISSUE_TEMPLATE/task.yml`, `hotfix.yml` | `modello-repo/.github/ISSUE_TEMPLATE/` | nessuno |
| `.github/pull_request_template.md` | `modello-repo/.github/` | nessuno |
| `.claude/agents/product-owner.md` | `<CARTELLA>/agenti/product-owner.md` | la sezione «Fonti»: se il repo ha già `docs/visione.md`, roadmap o simili, indica quelli al posto di `docs/prodotto/*` |
| `.claude/skills/catena/SKILL.md`, `.claude/agents/catena-*.md` | `modello-repo/.claude/` | nessuno: è la catena in sessione locale (`docs/locale.md`) |
| `docs/prodotto/visione.md`, `glossario.md`, `decisioni.md` | `modello-repo/docs/prodotto/` | solo se il repo non ha già documenti equivalenti; compila la visione in tre righe dal README, lascia gli altri come scheletro |

Se il repo ha un `CODEOWNERS`, aggiungi `/.catena.yml`, `/.claude/agents/` e
`/.claude/skills/` alle righe del proprietario.

Prima della PR: `.catena.yml` deve avere almeno `lint` o `test`, e il `name:` della CI deve
coincidere con `ci_nome`. Le etichette `task`, `hotfix`, `sotto-task`, `auto`, `in-corso`,
`domanda`, `bloccato`, `unione-automatica` devono esistere.

## 5. Verifica finale

1. Tutte le PR della sessione unite in develop con controlli verdi e rami cancellati.
2. I ruleset richiedono solo controlli che esistono davvero nella CI.
3. Nessun workflow rimasto cita file, etichette o workflow cancellati in modo che possa
   fallire (i commenti vecchi vanno solo segnalati).
4. Le otto etichette esistono.
5. Nessun ramo remoto oltre a develop, master ed eventuale release.
6. `gh workflow list` mostra `Catena` attivo.
7. Non hai messo `auto` e non hai lanciato la catena.

La prova vera la fa l'utente: una issue piccola e reale con `task`, poi `auto`.

## 6. Resoconto

Come in `regole-sessione.md`.
