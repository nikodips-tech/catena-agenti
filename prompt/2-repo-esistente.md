# Un repository con un'impostazione precedente

Per un repository che ha già qualcosa di Claude o di un metodo precedente: `CLAUDE.md`,
`.claude/`, `.agenti/`, workflow con `claude-code-action` o `CLAUDE_CODE_OAUTH_TOKEN`, una
copia della catena (`catena-*.yml`), CI, release, tag e chiusura delle issue di una versione
precedente, script e configurazioni in `.github/`. **Si cancella tutto e si installa da zero**,
come se il repository non avesse mai avuto niente: l'unico modo di sapere che ciò che gira è
la catena di adesso. Sessione aperta nella cartella del repository, **un progetto per
sessione**.

Leggi prima `<CARTELLA>/prompt/regole-sessione.md`, poi `<CARTELLA>/docs/specifica.md`,
`<CARTELLA>/docs/configurazione.md`, `<CARTELLA>/docs/permessi.md`.

## 1. Ricognizione (solo lettura)

Un quadro breve, che finirà nel resoconto:
- Tutto ciò che c'è di Claude: `CLAUDE.md`, `.claude/`, `.agenti/`, `.worktrees/`, altro.
- Ogni workflow in `.github/workflows`: evento, cosa fa, in quale gruppo cade (vedi passo 2).
- Ogni file in `.github/` (script, configurazioni, CODEOWNERS) e **chi lo usa** (`grep`).
- Stack, comandi, framework di test, test ed e2e, Dockerfile, migrazioni, documentazione,
  struttura (come nel prompt 1).
- Su GitHub: ruleset e controlli obbligatori, etichette, environment, variabili e segreti
  (solo i nomi), PR aperte (release compresa), issue con etichette del vecchio metodo
  (`in-corso`, `auto`, `domanda`, `bloccato`, priorità…), rami remoti.
- **Fermati e riferisci** se una issue è in lavorazione dal vecchio metodo (`in-corso`, o una
  PR `issue-*` aperta): va finita o chiusa prima, a mano.
- Fermati anche se `git status` non è pulito o mancano `develop` e `master`.

## 2. Pulizia totale

Ordine obbligatorio: **prima GitHub, poi i file**, altrimenti le PR restano bloccate da
controlli obbligatori che non arrivano più.

**Si cancella**:
- `CLAUDE.md`, `.claude/`, `.agenti/`, `.worktrees/` (e le sue righe in `.gitignore`).
- Tutti i workflow di Claude e del metodo precedente: quelli con `claude-code-action` o
  `CLAUDE_CODE_OAUTH_TOKEN`, la copia della catena, CI, release, tag-master, chiusura delle
  issue, code di hotfix, reazioni alle etichette, sorveglianza. La catena li fornisce tutti.
- Gli script e le configurazioni in `.github/` usati **solo** da workflow cancellati.
- Le etichette del metodo precedente (anche priorità e valutazione). Quelle standard di
  GitHub restano; quelle della catena le ricrea il preflight.

**Resta**: i workflow di rilascio in produzione, staging e anteprima, con gli script e le
configurazioni che usano (per esempio `progetto.yml` e `progetto.sh`), i segreti, le
variabili, l'environment `agenti`. Sono del progetto, la catena non li sostituisce. Una PR di
release aperta resta: la nuova `Release` la riconosce dal nome del ramo.

Sequenza:
1. `gh workflow disable` su ogni workflow da cancellare.
2. Svuota i controlli obbligatori dei ruleset `develop` e `master` (li rimetterai al passo G
   dell'installazione con i nomi nuovi). Tieni il resto dei ruleset.
3. Ramo `pulizia` da develop: cancella i file; nei workflow rimasti togli i riferimenti a
   file, etichette o workflow cancellati che potrebbero farli fallire (un `--remove-label` su
   un'etichetta che non esisterà più). PR, merge con i soli check che esistono ancora (se
   nessuno, merge diretto da admin), ramo cancellato.
4. Cancella le etichette del metodo precedente.
5. `git fetch --prune` e `git config fetch.prune true`.

Nel dubbio su un file, tienilo e scrivilo nel resoconto.

## 3. Installazione

Esegui `<CARTELLA>/prompt/installazione.md`, dal passo A al passo I. Per `.catena.yml` parti
dai comandi che la vecchia CI usava: devono restare gli stessi.

## 4. Resoconto

Come in `regole-sessione.md`, più: l'elenco di ciò che hai cancellato e di ciò che hai
tenuto, con il motivo.
