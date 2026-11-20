# <Nome del progetto>

<Due righe: cos'è il progetto e lo stack, ricavate da README, package e compose.>

## Comandi

<Come li lancia il progetto, container compreso. Devono coincidere con `.catena.yml`.>

```bash
docker compose exec app npm run lint
docker compose exec app npm run format:check
docker compose exec app npm run typecheck
docker compose exec app npm run test
```

## Rami

- `develop` è il ramo predefinito: le PR vanno lì.
- `master` è la produzione.

## Regole

- Le operazioni git e GitHub le fa Claude, non l'utente.
- Niente verifiche dell'interfaccia (Playwright, browser, screenshot) se non richieste
  esplicitamente.
- I test e2e non si scrivono e non si modificano.
- Non unire mai nulla in `master`.
- Non collegarsi ai server (ssh, scp).
- Non leggere né scrivere segreti e file `.env` veri (solo i `.example`).
- Chiedere prima di: modifiche al database che cancellano o trasformano dati; modifiche a
  `.github/workflows`; modifiche a `CLAUDE.md`, `.claude/` e `.catena.yml`.

## Due corsie per le modifiche

Il lavoro passa dalle issue e dalla catena di agenti (`auto` la mette solo il proprietario),
**oppure** si fa direttamente in sessione quando valgono tutte queste condizioni: la richiesta
è chiusa (nessuna decisione aperta), si consegna in una sola PR, la CI basta a verificarla,
non tocca dati esistenti, autenticazione, segreti, `.github/`, `CLAUDE.md`, `.claude/`.
Nel dubbio, issue. In corsia diretta: ramo `diretta/<slug>` da `develop`, commit con prefisso
(`feat:`, `fix:`, `docs:`, `chore:`), PR verso `develop` con etichette `task` e
`unione-automatica` (salvo richiesta di guardarla prima), corpo con `Corsia: diretta` e il
motivo. Per un hotfix: da `master`, etichetta `hotfix`, senza `unione-automatica`.

Per ragionare su idee e scrivere issue: l'agente `product-owner` (`.claude/agents/`).
