# La guardia (plugin di Claude Code)

`plugin/` è un plugin di Claude Code con un solo hook, `PreToolUse` su Bash e PowerShell
(`plugin/scripts/guardia.sh`). Protegge le sessioni locali; la catena su GitHub non lo usa
(lì Claude non ha git, gh né token).

| Blocca | Perché |
|---|---|
| `git push` forzato, `+refspec`, cancellazione di `master`/`develop`, push su `master`/`main`, push di tag | difficili da annullare; i tag li crea il proprietario o la CI |
| `gh api` che approva deployment o modifica `environments` e `rulesets` | la produzione la approva il proprietario |
| merge in `master` nei repo di `plugin/config/produzione.txt` (gh pr merge con base master, main o sconosciuta; qualsiasi merge via `gh api`) | lì il merge in master è il rilascio |
| `ssh`, `scp`, `sftp`, `ssh-copy-id` | i server non si toccano |
| `docker compose down` con `-v`, `--volumes`, `--remove-orphans` | cancella dati |

Negli altri repo il merge in master è libero. Lo script è Bash puro (niente jq), per Git Bash
e Linux. Test: `bash plugin/hooks/test.sh`.

## Installazione

```bash
claude plugin marketplace add nikodips-tech/catena-agenti
claude plugin install guardia@catena-agenti
```

Un repo nuovo in produzione: una riga in `plugin/config/produzione.txt`, PR, e
`claude plugin marketplace update catena-agenti`.
