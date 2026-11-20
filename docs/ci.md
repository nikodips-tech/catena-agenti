# La CI condivisa

Ogni progetto ha un `.github/workflows/ci.yml` di poche righe
(`modello-repo/.github/workflows/ci.yml`) che chiama `.github/workflows/ci.yml` della catena.
Comandi, container e immagini vengono da `.catena.yml`, e i controlli girano con
`scripts/controlli.sh`, lo stesso del developer: la CI e la catena non possono giudicare in
modo diverso.

## I check

| Check | Cosa fa | Chiavi |
|---|---|---|
| `ci / cambi` | decide se c'è codice da controllare: con sola documentazione (`docs`) gli altri passano subito | `docs` |
| `ci / lint`, `ci / tipi`, `ci / test`, `ci / test-db` | `controlli.sh install` e il controllo, nel container; non configurato → verde | `lint`, `tipi`, `test`, `test_db` (+ `db_avvia`, `db_ferma`), `container`, `cartella`, `installa` |
| `ci / build <servizio>` | costruisce ogni immagine (solo in locale, niente push) | `dockerfile` o `immagini` |
| `ci / migrazioni` | istruzioni distruttive nelle migrazioni nuove (in un `hotfix/*` bloccano) e test indeboliti: `.skip`, `.only`, `.todo`, `xit` bloccano; test cancellati o casi in meno si segnalano | `migrazioni`, `file_test` |

`ci` è il nome del job nel wrapper. I nomi sono fissi: il ruleset li richiede così. Si
saltano i passi e non i job, perché un job saltato non dà il nome del check.

Il wrapper può avere job propri (gli e2e, solo a mano). L'output `codice` (`si`/`no`) dice
se la PR cambia solo documentazione:

```yaml
  e2e:
    needs: ci
    if: github.event_name == 'workflow_dispatch' && inputs.e2e == 'si' && needs.ci.outputs.codice == 'si'
```

Controlli che un progetto ha e la CI condivisa no: si propongono nel resoconto della
migrazione e si decide se generalizzarli (`prompt/regole-sessione.md`).

## Passaggio di un progetto alla CI condivisa

1. La catena con la CI condivisa è in `v1`.
2. PR nel progetto: `.catena.yml` con `dockerfile`/`immagini` e `migrazioni`; `ci.yml`
   sostituito dal wrapper, più i job propri. Gli script in `.github/scripts/` si tolgono
   solo se nessun altro workflow li usa (la release usa `migrazioni-distruttive.sh` finché
   non passa anche lei alla catena).
3. Sulla PR i check si chiamano `ci / …` e il ruleset aspetta ancora i vecchi nomi: la PR è
   bloccata. **Con il via esplicito del proprietario** si cambiano i `context` dei ruleset
   `develop` e `master` (`docs/esempi/ruleset-*.json`), poi si unisce subito.
4. Le altre PR aperte vanno rilanciate (un push o `gh workflow run`), altrimenti aspettano
   per sempre i nomi vecchi.
