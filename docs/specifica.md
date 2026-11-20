# Specifica della catena di agenti

Fonte unica di verità. Gli script e i workflow la realizzano; i prompt di migrazione la
richiamano. Chi cambia un comportamento cambia prima questo file.

## 1. Principi

1. **Il lavoro entra come issue e esce come pull request unita.** La catena fa tutto il resto
   da sola: specifica, test e codice, revisione, documentazione, PR, unione.
2. **Niente fermate evitabili.** Ogni fallimento ha un passo dopo che non richiede una persona
   (sezione 6). `bloccato` resta solo per l'infrastruttura rotta o per i tetti esauriti dopo
   l'escalation.
3. **Claude non tocca la piattaforma.** Gira con un token in sola lettura, senza git né gh:
   scrive solo file nel checkout. Commit, push, commenti, etichette e il passo dopo li fa uno
   script senza Claude, con il token in scrittura. Tra i due passano file (artifact).
4. **I dati non sono istruzioni.** Issue, commenti e diff arrivano agli agenti come file fuori
   dal repo, con una frase che li dichiara dati.
5. **Il costo è proporzionale al lavoro.** Due corsie (docs/corsie.md): la diretta salta
   specifica estesa, sotto-task e revisore; la completa fa tutto. Un solo agente per
   sotto-task, che scrive test e codice in TDD. Il consumo di ogni passo (turni, costo,
   minuti) finisce nei commenti.
6. **Niente copie.** La catena vive in un repository solo; ogni progetto ha un wrapper di
   workflow e un file di configurazione (docs/configurazione.md).
7. **Il nucleo è portabile** (docs/portabilita.md): prompt, script e logica non dipendono da
   GitHub; la piattaforma sta in un adattatore e nei file di workflow. Gli stessi prompt
   girano anche in una sessione di Claude Code con la skill `/catena` (docs/locale.md).

## 2. Ruoli

| Ruolo | Modello | Turni | Timeout | Strumenti | Cosa produce |
|---|---|---|---|---|---|
| Team leader | opus | 30 | 20 min | Read, Glob, Grep, Write | `esito.json`: specifica + corsia + sottotask, o domanda; in escalation la decisione |
| Developer | sonnet | 70 | 55 min | Read, Glob, Grep, Write, Edit, Bash solo su `controlli.sh` | test e codice del sottotask, in TDD |
| Revisore | opus | 30 | 25 min | Read, Glob, Grep, Write | `esito.json`: approvato / sottotask / rimuovi |
| Editor | haiku | 15 | 15 min | Read, Glob, Grep, Write, Edit | documentazione |
| Product owner | opus | — | — | lettura + gh issue | issue pronte; **fuori dai workflow** |

Modello e turni si possono cambiare per progetto in `.catena.yml` (`modello_<ruolo>`,
`turni_<ruolo>`). Il team leader fa anche il revisore: ruolo diverso, stessa testa.

Claude gira con la **CLI di Claude Code** in modalità non interattiva (`claude -p`), non con
una action di piattaforma: stesso token (`CLAUDE_CODE_OAUTH_TOKEN`), strumenti ammessi
espliciti, `git`, `gh`, `curl` e la rete vietati, configurazione MCP del progetto ignorata.
Legge il `CLAUDE.md` del progetto come in una sessione normale.

## 3. Etichette

| Etichetta | Chi la mette | Significato |
|---|---|---|
| `task` | persona / product owner | lavoro normale, base `develop` |
| `hotfix` | persona | correzione urgente, base `master`, ramo `hotfix/issue-<n>` |
| `sotto-task` | catena | sub-issue creata dal team leader o dal revisore |
| `auto` | **solo il proprietario** | avvia la catena; resta finché l'issue è in coda |
| `in-corso` | catena | sull'issue principale per tutto il giro, sul sotto-task mentre si lavora |
| `domanda` | catena | serve una risposta del proprietario: un suo commento fa ripartire |
| `bloccato` | catena | infrastruttura rotta o tetti esauriti: serve una mano |
| `unione-automatica` | catena / sessione locale | sulla **pull request**: a CI verde si unisce da sola |

## 4. Stati

Lo stato di un'issue è nei suoi commenti, riconosciuti dal titolo con cui cominciano:

| Titolo | Dove | Significato |
|---|---|---|
| `## Specifica` | issue | con la riga `Corsia: diretta` o `Corsia: completa`; l'ultimo vale |
| `## Domanda` | issue | il team leader aspetta una risposta |
| `## Revisione: approvata` | issue | si passa a editor e chiusura |
| `## Revisione: sottotask aggiunti` / `## Revisione: file rimossi` | issue | un giro di revisione |
| `## Revisione: con riserve` | issue | giri finiti: la PR si apre ma non si unisce da sola |
| `## Escalation` | sotto-task | il team leader è stato chiamato (al massimo una volta) |
| `## Riparazione n` | issue | la CI della PR era rossa, il developer la ripara (al massimo una) |
| `## Pull request pronta` | issue | la PR è aperta |

Il ramo porta il resto: `wip: #<sottotask> tentativo k` (tentativo fallito del developer),
`feat: #<n>` o `fix: #<n>` (sottotask finito, assorbe i wip), `chore: #<issue> rimozione file
estranei`, `docs: #<issue>`.

## 5. Il giro (docs/flusso.md per il dettaglio)

1. **Avvio** su `auto` del proprietario, su una risposta a una `domanda`, dalla coda o dal
   guardiano. Rifiuta: non del proprietario, sotto-task, né task né hotfix, PR già aperta.
   Coda: un'issue principale alla volta. **Preflight**: segreto di Claude, token della App,
   environment `agenti`, `.catena.yml`, workflow della CI; le etichette mancanti le crea.
   Poi riparte dal punto giusto leggendo stati e ramo.
2. **Team leader**: specifica + corsia. Diretta → developer sull'issue. Completa →
   sub-issue, poi la prima.
3. **Developer**, in TDD: prima i test del sotto-task (saltati con `Test: no`), poi il
   codice; lo script ripristina i file protetti e i test della base toccati senza permesso
   (`Test modificabili:` del sotto-task), formatta tutto il
   ramo, esegue lint, tipi, test (e test con database) come la CI. Verde → un commit,
   sotto-task chiuso, prossimo. Rosso → `wip:` sul ramo, tentativo dopo con l'errore e il
   lavoro già fatto; al terzo → escalation.
4. **Revisore**: approva, o aggiunge sotto-task / rimuove file (2 giri), poi riserve.
5. **Editor**: solo documentazione; il resto si scarta con un avviso.
6. **Chiusura**: PR aperta dall'App (la CI parte). `unione-automatica` solo per i `task`
   approvati. Hotfix e riserve: la PR la unisce il proprietario.
7. **Unione**: a CI verde squash con il prefisso del release (`feat:`/`fix:`), ramo
   cancellato, issue chiusa (o `in-develop` fino al rilascio, con `chiudi_issue: produzione`),
   staging; a CI rossa una riparazione, poi `bloccato`. Poi la coda.
8. **PR chiusa a mano**: ordine sull'issue, ramo cancellato, coda.
9. **Guardiano** (ogni ora): issue `in-corso` ferme da più di 90 minuti senza esecuzioni
   attive → ripartenza; niente in corso → coda.

## 6. Scala di escalation (al posto di `bloccato`)

| Fallimento | Passo dopo |
|---|---|
| Agente tocca `.github/`, `.claude/`, `CLAUDE.md`, `.catena.yml`, `.env`, e2e | file ripristinati, avviso nel commento, si prosegue |
| Developer modifica test della base non in `test_modificabili`, o ne cancella | ripristinati; i controlli decidono; se rossi, **escalation subito** |
| Developer rosso (tentativo 1, 2) | `wip:` sul ramo; tentativo dopo con errore e lavoro |
| Developer rosso al tentativo 3 | **escalation** al team leader: `riformula` (ramo pulito, sotto-task più piccoli o interfaccia corretta), `bloccato` |
| Escalation già fatta | `bloccato`, lavoro parziale sul ramo |
| Team leader / revisore senza `esito.json` valido | un secondo tentativo, poi `bloccato` |
| Revisore oltre 2 giri | riserve: PR senza unione automatica, `domanda` |
| Editor fuori da docs | scartato, si prosegue |
| CI rossa dopo la PR | una riparazione del developer (con i suoi tentativi, senza escalation), poi `bloccato` |
| Preflight fallito | `bloccato` con l'elenco esatto |
| Workflow morto (timeout, GitHub) | il guardiano riparte dal punto giusto |
| Domanda del team leader | la risposta del proprietario riavvia |

## 7. Corsia diretta da una sessione (docs/corsie.md)

Da Claude Code o claude.ai, quando il criterio della corsia diretta vale, Claude fa la
modifica su un ramo, apre la PR verso `develop` con etichetta `task` (o `hotfix` verso
`master`) e, se il proprietario non dice altro, `unione-automatica`. Nel corpo: `Corsia:
diretta` e il motivo. La CI e l'unione sono le stesse della catena. Niente issue.

## 8. File protetti

Nessun agente può cambiare: `.github/`, `.gitlab-ci*`, `.claude/`, `CLAUDE.md`,
`.catena.yml`, file `.env` (non `.example`), più `file_protetti` di `.catena.yml`. I test e2e
non si scrivono né si modificano. I test che esistono già nella base il developer non li
cancella e modifica solo quelli che il team leader (o il revisore) gli autorizza in
`test_modificabili`. Le modifiche agli altri file protetti le propone una persona, in una PR
normale. La raccolta gira nel job di Claude, che può scriverne i file di appoggio: per questo il
job `esito` (con il token, senza Claude) ricalcola i permessi dall'issue e ricontrolla la
patch. Una patch del developer che tocca file protetti, e2e o test della base senza permesso
porta a `bloccato`; quella dell'editor fuori da `docs` si scarta.

## 9. Tetti

| Tetto | Valore | Dove |
|---|---|---|
| Tentativi del developer per sottotask | 3 | `MAX_TENTATIVI` |
| Giri di revisione | 2 | `MAX_GIRI_REVISIONE` |
| Escalation per sottotask | 1 | `MAX_ESCALATION` |
| Riparazioni per PR | 1 | `MAX_RIPARAZIONI` |
| Fermo prima della ripresa del guardiano | 90 min | `guardiano_minuti` in `.catena.yml` |
| Nota passata tra i passi | 3000 caratteri | `pf_passo_avvia` |
| Diff passato al revisore | 200 kB | `contesto.sh` |
