# Portabilità: cosa dipende dalla piattaforma e cosa no

Oggi i progetti stanno su GitHub. Domani uno potrebbe stare su un GitLab self-hosted o
altrove: lì `.github/` non serve a niente. La catena è divisa in tre strati perché il
passaggio costi il meno possibile.

## I tre strati

| Strato | Dove | Dipende dalla piattaforma? |
|---|---|---|
| **Nucleo** | `agenti/` (prompt), `scripts/` (logica), `docs/`, `.catena.yml` del progetto | no |
| **Adattatore** | `piattaforme/<nome>/adattatore.sh` | sì: una funzione per ogni cosa chiesta alla piattaforma |
| **Innesco** | `.github/workflows/*.yml` (riutilizzabili) + `modello-repo/.github/workflows/catena.yml` | sì: eventi, job, permessi, identità |

Gli script del nucleo chiamano la piattaforma **solo** tramite le funzioni `pf_*`
dell'adattatore, caricato da `comune.sh` in base a `PIATTAFORMA`. Nessun `gh` fuori da
`piattaforme/`.

Nota su GitHub: i workflow riutilizzabili devono stare in `.github/workflows/` del repo che li
offre, per vincolo della piattaforma; per questo non stanno sotto `piattaforme/github/`. Sono
comunque strato di innesco: niente logica dentro, solo chiamate agli script.

## Perché la CLI e non la action

`anthropics/claude-code-action` esiste solo per GitHub Actions. La CLI di Claude Code
(`claude -p`) è ciò che la action esegue sotto, e gira in qualsiasi job con Node: stesso token
`CLAUDE_CODE_OAUTH_TOKEN`, stessi `--model`, `--max-turns`, `--allowedTools`. In più permette
di negare esplicitamente `git`, `gh` e la rete e di ignorare la configurazione MCP del
progetto. È il nucleo portabile; la action era un vincolo.

## Le funzioni dell'adattatore

Chi porta la catena su una piattaforma nuova scrive queste funzioni, con gli stessi nomi,
argomenti e formati di uscita (JSON con le chiavi indicate). L'elenco è
`piattaforme/github/adattatore.sh`, qui il riassunto:

| Gruppo | Funzioni |
|---|---|
| Identità | `pf_proprietario`, `pf_url_esecuzione` |
| Issue | `pf_issue_titolo`, `pf_issue_corpo`, `pf_issue_stato` (OPEN/CLOSED), `pf_issue_etichette` (spazi), `pf_issue_aggiornata` (ISO), `pf_issue_commenti` (JSON `[{autore, corpo}]`), `pf_issue_commenta`, `pf_commenta_testo`, `pf_etichetta_aggiungi`, `pf_etichetta_togli`, `pf_issue_chiudi`, `pf_issue_crea` (→ numero), `pf_issue_aperte_con` (JSON `[{numero, etichette, aggiornata}]`) |
| Sotto-issue | `pf_sottoissue_collega`, `pf_sottoissue` (JSON `[{numero, stato, titolo}]`), `pf_sottoissue_aperte` |
| Passi | `pf_passo_avvia <passo> <issue> [sottotask] [tentativo] [file nota]`, `pf_workflow_avvia`, `pf_esecuzioni_attive` |
| Rami e PR | `pf_ramo_esiste`, `pf_ramo_cancella`, `pf_push`, `pf_pr_aperta` (JSON `{numero, sha, etichette}`), `pf_pr_apri` (→ numero), `pf_pr_etichetta_aggiungi/togli`, `pf_pr_commenta`, `pf_pr_unisci`, `pf_pr_json` |
| CI | `pf_ci_falliti`, `pf_ci_log_falliti` |
| Repository | `pf_etichetta_crea`, `pf_etichette_repo`, `pf_controlli_obbligatori`, `pf_environment_esiste`, `pf_variabile` |

Convenzioni: etichette in ingresso separate da virgola; uscite JSON con chiavi italiane come
sopra; le funzioni che scrivono su rami e PR usano l'identità "App" quando `APP_TOKEN` è
impostato.

## Cosa servirà su GitLab (non fatto, solo mappato)

| Su GitHub | Su GitLab |
|---|---|
| workflow riutilizzabili `workflow_call` | template di pipeline inclusi con `include: project:` |
| `issues: labeled`, `issue_comment` | nessun evento di pipeline per etichette/commenti: webhook del progetto → trigger di pipeline (`POST /projects/:id/trigger/pipeline` con variabili `PASSO`, `ISSUE`), oppure il guardiano a orario che legge le issue con `auto` |
| `workflow_dispatch` tra i passi | `POST /projects/:id/trigger/pipeline` con un trigger token |
| `workflow_run` della CI | lo stesso pipeline: job di unione in uno stage finale, oppure `pipeline` events via webhook |
| sub-issue | **linked issues** (`/projects/:id/issues/:iid/links`) o task items; la funzione `pf_sottoissue*` nasconde la differenza |
| App + token di Actions | un project access token per la "App" e `CI_JOB_TOKEN` per il resto; i limiti sugli eventi dei token sono diversi: da verificare |
| environment `agenti` con policy di ramo | variabili CI protette (solo rami protetti) |
| ruleset | protected branches + approval rules |
| `gh` | `glab`, o `curl` sull'API |

Il prompt e gli script restano uguali. La CLI di Claude Code si installa con `npm` nel job
come su GitHub.

## Cosa non è portabile per scelta

- `docs/esempi/ci-minima.yml` e i ruleset: sono esempi GitHub.
- Il modello di repo contiene `.github/`; per un'altra piattaforma avrà la sua cartella.
