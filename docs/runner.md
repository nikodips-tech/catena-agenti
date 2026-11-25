# Il runner

Tutti i job della catena e della CI condivisa girano su `ubuntu-24.04` di GitHub, salvo
che il repository del progetto abbia la variabile di Actions `CATENA_RUNNER`: le etichette
del runner, in JSON.

```bash
gh variable set CATENA_RUNNER --body '["self-hosted","catena"]'   # runner proprio
gh variable delete CATENA_RUNNER                                  # di nuovo GitHub
```

I wrapper del progetto non cambiano. I job propri del progetto (e2e, release…) scelgono il
runner da soli.

## Cosa deve avere un runner proprio

- **Un ambiente nuovo per ogni job** (runner `--ephemeral` o JIT, in un container o in una
  VM buttati alla fine). Sullo stesso runner girano il codice delle PR e degli agenti e,
  dopo, job con token in scrittura: un runner che resta tra un job e l'altro può lasciare
  qualcosa al job dopo.
- **Docker** dentro l'ambiente del job, senza accesso al Docker della macchina: i controlli
  girano in `docker run` (`scripts/controlli.sh`), la CI costruisce le immagini con buildx,
  `db_avvia` usa `docker compose`.
- `git`, `gh`, `jq`, `curl`, `node` e `npm` (con un prefisso globale scrivibile: il passo
  Claude Code fa `npm install -g`), GNU `grep` (con `-P`), `coreutils`.
- Uscita verso GitHub, ghcr.io, il registry npm e l'API di Anthropic.
