# Pubblicare la catena su GitHub

Da eseguire una volta sola, in una sessione aperta nella cartella della catena (`<CARTELLA>`).
Leggi prima `prompt/regole-sessione.md`. Qui l'unica eccezione alle regole: questa cartella
**si modifica**, perché è il repository stesso che stai creando.

## 1. Controlli

- La cartella contiene `README.md`, `docs/`, `agenti/`, `scripts/`, `piattaforme/`,
  `.github/workflows/`, `modello-repo/`, `prompt/`.
- `gh auth status` funziona e l'utente è `nikodips-tech` (o ha accesso a quell'organizzazione).
- Il repository `nikodips-tech/catena-agenti` non esiste ancora (`gh repo view`). Se esiste,
  fermati e chiedi.
- `bash -n` su ogni file in `scripts/` e `piattaforme/github/`: nessun errore di sintassi.
  Se trovi un errore, correggilo e segnalalo nel resoconto.

## 2. Repository

```bash
git init -b master
git add -A
git commit -m "Catena di agenti v2"
gh repo create nikodips-tech/catena-agenti --public --source . --push \
  --description "Catena di agenti Claude Code per i progetti: workflow riutilizzabili, script e prompt"
git tag -a v2.0.0 -m "v2.0.0"
git tag v2
git push origin v2.0.0 v2
```

**Pubblico**, perché i progetti leggono script e prompt al volo con il token di Actions e
chiamano i workflow riutilizzabili: con un repo privato servirebbero un PAT (`CATENA_TOKEN`)
in ogni progetto e l'accesso ai workflow (Settings → Actions → General → Access). Il
repository non contiene segreti. Se l'utente lo vuole privato, fallo privato, imposta
l'accesso ai workflow con
`gh api -X PUT repos/nikodips-tech/catena-agenti/actions/permissions/access -f access_level=user`
e scrivi nel resoconto che ogni progetto avrà bisogno del segreto `CATENA_TOKEN`.

## 3. Protezione minima

Ruleset su `master`: cancellazione e force push vietati, bypass admin. Niente PR obbligatoria:
le correzioni alla catena si fanno in sessione con l'utente.

```bash
gh api -X POST repos/nikodips-tech/catena-agenti/rulesets --input - <<'JSON'
{ "name": "master", "target": "branch", "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ],
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ] }
JSON
```

## 4. Verifica

- `gh api repos/nikodips-tech/catena-agenti/contents/.github/workflows` elenca i sei workflow.
- `gh api repos/nikodips-tech/catena-agenti/git/ref/tags/v2` esiste.

## 5. Resoconto

URL del repository, visibilità, tag pubblicati, eventuali correzioni fatte agli script, e la
riga da usare nei prompt successivi (la stessa `<CARTELLA>`: i documenti si leggono ancora da
lì).
