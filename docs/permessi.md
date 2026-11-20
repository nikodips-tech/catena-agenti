# Permessi: chi deve poter fare cosa

## Il modello, indipendente dalla piattaforma

| Chi | Deve poter | Non deve poter |
|---|---|---|
| **Claude** (job agente) | leggere il checkout, scrivere file nel checkout, eseguire `controlli.sh` | leggere issue, usare git/gh/rete, vedere token o segreti |
| **Script di esito** | leggere e scrivere issue, etichette, commenti; push sui rami `issue-*`; avviare il passo dopo | push su `develop`/`master`; unire PR |
| **Identità "App"** | aprire PR, push che fanno partire la CI, unire PR in `develop` | leggere o scrivere issue (non serve e così non lo fa nessuno per sbaglio) |
| **Proprietario** | mettere `auto`, rispondere alle domande, unire in `master`, cambiare `.github/`, `CLAUDE.md`, `.claude/` | — |

Perché due identità: su GitHub (e su quasi tutte le piattaforme) gli eventi causati dal token
automatico di un job **non fanno partire altri workflow**, per evitare cicli. La PR aperta e
il merge fatto con il token di Actions non avviano CI, release e staging. Serve una seconda
identità, l'App.

## Realizzazione su GitHub

### Cosa serve in ogni repository (lo verifica il preflight)

| Cosa | Dove | Nome |
|---|---|---|
| Token di Claude | Settings → Secrets → Actions | `CLAUDE_CODE_OAUTH_TOKEN` |
| App installata | Settings → GitHub Apps | `dipstech-agenti`, con Contents e Pull requests in scrittura sul repo |
| Environment | Settings → Environments | `agenti`, deployment branch policy: `develop` |
| Variabile dell'environment | nell'environment `agenti` | `AGENTI_CLIENT_ID` |
| Segreto dell'environment | nell'environment `agenti` | `AGENTI_APP_KEY` (chiave privata PEM) |
| Workflow possono aprire PR | Settings → Actions → General | "Allow GitHub Actions to create and approve pull requests" |
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
gh variable set AGENTI_CLIENT_ID -e agenti -R <owner>/<repo> -b <client id>
gh secret set AGENTI_APP_KEY -e agenti -R <owner>/<repo> < chiave.pem
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```
L'installazione della App sul repository la fa il proprietario dall'interfaccia della App
(Settings → Developer settings → GitHub Apps → dipstech-agenti → Install App → repository).

### Permessi dei job

I workflow riutilizzabili ricevono i permessi del job che li chiama e possono solo ridurli:
per questo il wrapper `catena.yml` li dichiara job per job. Dentro la catena:

| Job | Permessi | Token |
|---|---|---|
| `agente` | `contents: read`, `issues: read` | nessun `GH_TOKEN` nel passo di Claude |
| `esito`, `avvio`, `guardiano`, `pr-chiusa` | `contents: write` (solo esito e pr-chiusa), `issues: write`, `actions: write`, `pull-requests: write` | `github.token` |
| `chiusura`, `unione` | `issues: write`, `pull-requests: write`, environment `agenti` | `github.token` per le issue, App per PR, push e merge |

`actions: write` serve a `gh workflow run` (il passo dopo). Il `workflow_dispatch` fatto con
il token di Actions **funziona**: è l'eccezione alla regola degli eventi.

### Ruleset

Due ruleset, `develop` e `master` (`docs/esempi/ruleset-develop.json`,
`docs/esempi/ruleset-master.json`):
- cancellazione e force push vietati;
- PR obbligatoria con 0 approvazioni (su `master` anche la review del code owner);
- controlli obbligatori: **i nomi esatti dei job** di lint, tipi, test, build, migrazioni
  presenti nella CI. Mai e2e. Un controllo che non esiste blocca ogni PR per sempre;
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
| "ha toccato file di test" | file di prova del developer | test del ramo suoi, test della base ripristinati |
| Molti token del developer | output completo dei controlli | riassunto corto, log su file |
| In coda per minuti senza job | rallentamento di GitHub | il guardiano riparte; le annullate non scrivono |
| Passo in errore su `--remove-label` | etichetta cancellata | `pf_etichetta_togli` ignora l'assenza, il preflight le crea |
| Team leader in errore "Broken pipe" con più sotto-task | `crea_sottotask … \| head -1` con pipefail | i numeri su file, poi `head` |
| Catena non trovata al checkout | repo della catena privato | pubblico, oppure `CATENA_TOKEN` |
| Chiamata al workflow riutilizzabile rifiutata | accesso ai workflow del repo della catena | repo pubblico, oppure Settings → Actions → Access |
