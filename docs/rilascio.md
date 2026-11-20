# Release, tag e chiusura delle issue

Tre workflow riutilizzabili portano il lavoro da `develop` alla produzione. Nel progetto ci
sono tre wrapper di poche righe (`modello-repo/.github/workflows/`); la logica sta in
`scripts/rilascio/`. Niente Claude.

| Wrapper del progetto | Riutilizzabile | Quando | Cosa fa |
|---|---|---|---|
| `release.yml` (`Release`) | `release.yml` | push su develop, a mano, dopo `Tag master` | crea o aggiorna `release/x.y.z` e la PR verso master con le note dai commit; in cima migrazioni distruttive e issue `in-develop` con un commento senza risposta. Il numero: `feat` → minor, `fix` → patch, `!` o `BREAKING CHANGE` → major. Dopo un `Tag master` rimette in pari solo una release già aperta |
| `tag-master.yml` (`Tag master`) | `tag-master.yml` | push su master | se il commit viene da `release/*` o `hotfix/*`: tag `x.y.z` (gli hotfix della catena prendono la patch successiva), issue citate nei commit della versione chiuse e senza `in-develop`, PR master → develop con merge automatico, ramo cancellato |
| `in-develop.yml` (`In develop`) | `in-develop.yml` | PR unita in develop | le issue citate (`Refs #N`, `Closes`, `Fixes`, `Resolves`) ricevono un commento e `in-develop`. Si saltano il riporto di master e i rami della catena (`issue-N`), che segue l'unione |

Il merge della release in master lo fa il proprietario: è il suo OK al rilascio, e va fatto
con un **merge commit**. Con uno squash i commit di develop non risultano in master: la
release successiva li ritroverebbe tutti, con le note già rilasciate. Per questo il ruleset di
master ammette solo il merge (`docs/esempi/ruleset-master.json`); in develop lo squash va
bene. Se succede, `Tag master` lo segnala, e si rimedia con una PR da develop verso master
unita con merge commit. La release non si apre se master e develop hanno gli stessi file.

Il push del
tag, fatto dall'App, fa partire il rilascio del progetto (`rilascio.yml`, che resta nel
progetto con staging e anteprime).

Release e tag-master usano l'App della catena (environment `agenti`, `secrets:
inherit`): ciò che fa l'App fa partire gli altri workflow, il token di Actions no. Leggono
`.catena.yml` da develop (`migrazioni`, `ramo_sviluppo`, `ramo_produzione`).

Con `chiudi_issue: produzione` (`docs/configurazione.md`) anche le issue della catena restano
aperte fino al rilascio: insieme a questi workflow, ogni issue si chiude quando va in
produzione.

## Passaggio di un progetto

1. La catena con questi workflow è in `v1`.
2. PR nel progetto: `release.yml` e `tag-master.yml` sostituiti dai wrapper (stessi nomi:
   `workflow_run` di `Release` aspetta `Tag master`); il vecchio workflow di chiusura delle issue, se c'è, sostituito da
   `in-develop.yml`; `.catena.yml` con `migrazioni` e `chiudi_issue: produzione`.
3. Si tolgono gli script di `.github/scripts/` che nessun workflow usa più
   (`migrazioni-distruttive.sh`, `test-indeboliti.sh` dopo la CI condivisa). `progetto.sh` e
   `.github/progetto.yml` restano finché li usano rilascio, staging e anteprime.
4. Nessun ruleset cambia: questi workflow non danno check obbligatori.
