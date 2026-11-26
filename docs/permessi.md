# Permessi: chi deve poter fare cosa

## Il modello, indipendente dalla piattaforma

| Chi | Deve poter | Non deve poter |
|---|---|---|
| **Claude** (job agente) | leggere il checkout, scrivere file nel checkout, eseguire `controlli.sh`; il developer anche `rimuovi.sh` (cancella file normali del repo, mai protetti o e2e) | leggere issue, usare git/gh/rete, vedere token o segreti |
| **Script di esito** | leggere e scrivere issue, etichette, commenti; push sui rami `issue-*`; avviare il passo dopo | push su `develop`/`master`; unire PR |
| **Identità "App"** | aprire PR, push che fanno partire la CI, unire PR in `develop` | leggere o scrivere issue (non serve e così non lo fa nessuno per sbaglio) |
| **Proprietario** | mettere `auto`, rispondere alle domande, unire in `master`, cambiare `.github/`, `CLAUDE.md`, `.claude/` | — |

Perché due identità: su GitHub (e su quasi tutte le piattaforme) gli eventi causati dal token
automatico di un job **non fanno partire altri workflow**, per evitare cicli. La PR aperta e
il merge fatto con il token di Actions non avviano CI, release e staging. Serve una seconda
identità, l'App.

## Realizzazione su GitHub

### Cosa serve in ogni repository

Lo verifica l'installazione (`prompt/installazione.md`, passo A) con l'account del
proprietario. Il preflight della catena ricontrolla a ogni avvio ciò che il token di Actions
può vedere: segreto di Claude, token della App, environment, configurazione, workflow della
CI. L'auto-merge e, a seconda dei permessi, la policy dei rami li vede solo un
amministratore.

| Cosa | Dove | Nome |
|---|---|---|
| Token di Claude | Settings → Secrets → Actions | `CLAUDE_CODE_OAUTH_TOKEN` |
| App installata | Settings → GitHub Apps | la GitHub App della catena (una tua, per esempio `<account>-agenti`), con Contents e Pull requests in scrittura sul repo |
| Environment | Settings → Environments | `agenti`, deployment branch policy: `develop` **e** `master` (catena e release girano su develop, il tag su master) |
| Variabile dell'environment | nell'environment `agenti` | `AGENTI_CLIENT_ID` |
| Segreto dell'environment | nell'environment `agenti` | `AGENTI_APP_KEY` (chiave privata PEM) |
| Workflow possono aprire PR | Settings → Actions → General | "Allow GitHub Actions to create and approve pull requests" |
| Auto-merge | Settings → General → Pull Requests | "Allow auto-merge": lo usa il riporto di master in develop dopo un tag |
| Configurazione | radice di `develop` | `.catena.yml` |
| Workflow | `.github/workflows/catena.yml` | il wrapper di `modello-repo/` |
| Etichette | — | le crea il preflight (`preflight.sh etichette`) |
| Catena privata (facoltativo) | Secrets → Actions | `CATENA_TOKEN`: PAT in lettura sul repo della catena |

Comandi:
```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <owner>/<repo>            # il valore lo incolla il proprietario
gh api -X PUT repos/<owner>/<repo>/environments/agenti \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/<owner>/<repo>/environments/agenti/deployment-branch-policies -f name=develop -f type=branch
gh api -X POST repos/<owner>/<repo>/environments/agenti/deployment-branch-policies -f name=master -f type=branch
gh repo edit <owner>/<repo> --enable-auto-merge
gh variable set AGENTI_CLIENT_ID -e agenti -R <owner>/<repo> -b <client id>
gh secret set AGENTI_APP_KEY -e agenti -R <owner>/<repo> < chiave.pem
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```
L'installazione della App sul repository la fa il proprietario dall'interfaccia della App
(Settings → Developer settings → GitHub Apps → la tua App → Install App → repository).

### Permessi dei job

I workflow riutilizzabili ricevono i permessi del job che li chiama e possono solo ridurli:
per questo il wrapper `catena.yml` li dichiara job per job. Dentro la catena:

| Job | Permessi | Token |
|---|---|---|
| `agente` | `contents: read`, `issues: read`, `packages: read` (il `container` su ghcr.io) | nessun `GH_TOKEN` nel passo di Claude |
| `esito`, `avvio`, `guardiano`, `pr-chiusa` | `contents: write` (solo esito e pr-chiusa), `issues: write`, `actions: write`, `pull-requests: write` | `github.token` |
| `chiusura`, `unione` | `issues: write`, `pull-requests: write`, environment `agenti` | `github.token` per le issue, App per PR, push e merge |

`actions: write` serve a `gh workflow run` (il passo dopo). Il `workflow_dispatch` fatto con
il token di Actions **funziona**: è l'eccezione alla regola degli eventi.

### Ruleset

Due ruleset, `develop` e `master` (`docs/esempi/ruleset-develop.json`,
`docs/esempi/ruleset-master.json`):
- cancellazione e force push vietati;
- PR obbligatoria con 0 approvazioni (su `master` anche la review del code owner);
- controlli obbligatori: **i nomi esatti dei check** della CI condivisa (`ci / lint`,
  `ci / tipi`, `ci / test`, `ci / build <servizio>`, `ci / migrazioni`; `ci / test-db` se
  configurato), `docs/ci.md`. Mai e2e. Un controllo che non esiste blocca ogni PR per sempre;
- bypass per il ruolo admin.

```bash
gh api -X POST repos/<owner>/<repo>/rulesets --input docs/esempi/ruleset-develop.json
gh api repos/<owner>/<repo>/rules/branches/develop        # verifica
```

### Tabella degli errori già visti

| Sintomo | Causa | Rimedio nella catena |
|---|---|---|
| L'agente non parte: "non-human actor" | la action rifiutava gli avvii fatti dal bot | la CLI al posto della action |
| "esito.json non trovato" | permesso di scrittura ristretto a un percorso | `esito.json` nella radice, Write libero in un job in sola lettura |
| "Non sono riuscito ad aprire la pull request" | il token della App non legge le issue | issue lette con il token di Actions |
| PR aperta ma CI ferma | gli eventi del token di Actions non avviano workflow | PR, push e merge con l'App |
| Commit assente dalla release | titolo squash senza `feat:`/`fix:` | prefisso da `titolo_squash` |
| "Il developer non ha prodotto un risultato" | `bash -e` chiudeva il passo prima dello stato | controlli dentro `if …; then` |
| Tre fallimenti su `format:check` | file scritti dall'agente non formattati | formattazione di tutto il ramo prima dei controlli |
| "ha toccato file di test" | il developer cambiava test della base | liberi, con note e giudizio del revisore; ripristinati solo quelli che il revisore ha bloccato (`test_bloccati`) |
| Molti token del developer | output completo dei controlli | riassunto corto, log su file |
| In coda per minuti senza job | rallentamento di GitHub | il guardiano riparte; le annullate non scrivono |
| Passo in errore su `--remove-label` | etichetta cancellata | `pf_etichetta_togli` ignora l'assenza, il preflight le crea |
| Team leader in errore "Broken pipe" con più sotto-task | `crea_sottotask … \| head -1` con pipefail | i numeri su file, poi `head` |
| Team leader che non parte, "esito.json non trovato" con un ramo grande | `git diff \| head -c` con pipefail: SIGPIPE, `contesto.sh` esce con 141 | `limita` legge tutto l'input dopo il taglio; niente `head` o `grep -q` in fondo a una pipe con pipefail |
| Tipi rossi tre volte su un sotto-task che toglie file | il developer non poteva cancellare file della base | `rimuovi.sh` tra gli strumenti del developer |
| Catena non trovata al checkout | repo della catena privato | pubblico, oppure `CATENA_TOKEN` |
| Chiamata al workflow riutilizzabile rifiutata | accesso ai workflow del repo della catena | repo pubblico, oppure Settings → Actions → Access |
| Team leader "riformula" fermo dopo il commento di escalation, "not a git repository" | `git fetch` in `esito-team-leader.sh` prima di entrare nel checkout | `cd "$REPO_DIR"` prima dei comandi git; gli script che usano git entrano nel checkout in cima o con `ramo_checkout` |
