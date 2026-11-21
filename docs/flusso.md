# Il flusso, passo per passo

Chi fa cosa, con quale token, e quanto costa. `A` = token di Actions (sola lettura o scrittura
secondo il job), `App` = token della App della catena, `C` = Claude (costa token del
piano).

```
proprietario ──auto──► AVVIO (A) ──► TEAM LEADER (C opus, poi A)
                                        │ domanda ──► `domanda` ──risposta──► AVVIO
                                        │ corsia diretta ──────────────────────┐
                                        ▼ corsia completa                      │
                   ┌──► DEVELOPER (C sonnet, poi A): test, poi codice ◄── tentativo+1 (wip:)
                   │        │ verde: feat: #n                                 │ rosso ×3
                   │ prossimo sotto-task ◄──┤                                 ▼
                   │                        │ finiti        ESCALATION: TEAM LEADER (C opus)
                   │                        ▼                 riformula ──► sotto-task nuovi
                   │                 REVISORE (C opus, poi A)  bloccato ───► `bloccato`
                   └── sotto-task / rimuovi (≤2) ◄──┤
                                                    │ approvata / riserve
                                                    ▼
                                             EDITOR (C haiku, poi A) ── docs: #n
                                                    ▼
                                      CHIUSURA (App): PR ──► CI del progetto
                                                                ▼
                                 UNIONE (A + App) ◄── workflow_run ── verde: squash, chiudi, staging
                                                    rosso: RIPARAZIONE ─► DEVELOPER (1 volta) ─► CHIUSURA
                                                    ▼
                                                  CODA ──► AVVIO della prossima con `auto`
GUARDIANO (ogni ora, A): issue in-corso ferme ─► AVVIO (ripartenza)
PR CHIUSA A MANO (A): ordine sull'issue, ramo via, CODA
```

## I passi

### Avvio (`avvio.sh`, nessun Claude)
Eventi: `auto` del proprietario; commento del proprietario su `domanda`; dispatch (coda,
guardiano, a mano). Rifiuti con commento: non del proprietario, sotto-task, né task né hotfix,
già in corso. PR già aperta per l'issue: non riparte. Coda: un'issue principale `in-corso`
alla volta (l'issue in coda tiene `auto`). Preflight (`preflight.sh`). Poi la ripartenza:

| Stato trovato | Passo |
|---|---|
| nessuna `## Specifica` | team leader |
| corsia diretta, nessun `feat: #issue` sul ramo | developer (sottotask = issue) |
| corsia diretta, `feat: #issue` sul ramo | chiusura |
| sotto-task aperti | developer sul primo |
| nessun sotto-task aperto, ramo esistente, revisione approvata o con riserve | chiusura |
| nessun sotto-task aperto, ramo esistente, senza revisione | revisore |
| nessun sotto-task aperto, nessun ramo | team leader (si rifà la specifica) |

### Un agente (`agente.yml`, tre job)
1. `inizio` (A scrittura): `in-corso` sul sotto-task.
2. `agente` (A **sola lettura**): checkout della catena (al suo tag) e del progetto; `ramo.sh`
   sceglie il ramo e registra il commit di partenza; `contesto.sh` prepara i dati in file
   fuori dal repo; credenziali git tolte dal checkout; dipendenze installate (il loro output
   non entra nel contesto di Claude); `agente.sh` lancia la CLI senza nessun token di
   piattaforma nell'ambiente; `raccolta.sh` misura le modifiche rispetto al commit di
   partenza, ripristina i file protetti e i test della base, scarta quelli fuori ambito,
   formatta, esegue i controlli (developer), scrive l'artifact `esito`.
3. `esito` (A scrittura): `esito-<ruolo>.sh` applica la patch, committa, pusha, commenta,
   etichetta e avvia il passo dopo con `pf_passo_avvia` (un `workflow_dispatch` del wrapper
   del progetto). Un'esecuzione annullata non arriva qui.

### Developer
Per ogni sotto-task, in TDD: prima i test, eseguiti perché falliscano, poi il codice, poi
tutti i controlli. I test che esistono già nella base non si cancellano e si modificano solo
quelli che il team leader elenca nella riga `Test modificabili:` del sotto-task (in corsia
diretta della specifica), più quelli già modificati sul ramo: gli altri lo script li
ripristina. Quelli aggiunti sul ramo sono suoi. Con `Test: no` non scrive test. Strumenti:
Read, Glob, Grep, Write, Edit, e Bash solo su `controlli.sh` e `rimuovi.sh`: con il secondo
cancella i file che il sotto-task chiede di togliere (mai protetti, e2e o test della base),
così rilancia subito i controlli; la cancellazione entra nel commit e il revisore la vede nel
diff. Verde: un
commit `feat: #n` che assorbe i tentativi precedenti. Rosso: il lavoro resta sul ramo come
`wip: #n tentativo k`, il tentativo dopo riceve l'errore e corregge. Al terzo rosso,
escalation al team leader; subito, se lo script ha ripristinato test della base (il
tentativo dopo rifarebbe la stessa modifica). Il revisore riceve l'elenco dei test della base
modificati e controlla che non siano stati indeboliti.

### Chiusura (`chiusura.sh`, App)
PR dal ramo alla base, aperta dall'App: la CI parte da sola (con il token di Actions no). PR
già aperta: commit vuoto dell'App per rilanciare la CI. Etichette sulla PR con il token di
Actions. Commento `## Pull request pronta`.

### Unione (`unione.sh`, App per il merge)
Solo PR con `unione-automatica` e CI dell'ultimo commit. Verde: squash con titolo
`<prefisso>: <titolo> (#issue)`, ramo cancellato, issue chiusa (con `chiudi_issue:
produzione` resta aperta con `in-develop` fino al rilascio), commento, staging secondo
`.catena.yml`. Rosso: `## Riparazione 1` e developer sull'issue con job falliti e log; la
seconda volta `bloccato`. Poi la coda.

### Guardiano (`guardiano.sh`)
Se nessuna esecuzione della catena è attiva: la prima issue `in-corso` senza novità da più di
`guardiano_minuti` riparte (commento "Ripresa automatica"); se nessuna è in corso, la coda.

## Quanto costa un giro

Ordine di grandezza per un'issue media in corsia completa con tre sotto-task: un team leader
(opus), tre o quattro developer (sonnet), un revisore (opus), un editor (haiku). In corsia
diretta: un team leader breve e un developer. Il consumo di ogni passo (turni, USD, minuti) è
nel commento che il passo lascia sull'issue o sul sotto-task.

Cosa tiene bassi i token: le dipendenze installate prima di Claude; `controlli.sh` che stampa
solo OK/FALLITO e trenta righe; i tentativi che ripartono dal lavoro già fatto (`wip:`); il
diff al revisore troncato; la corsia diretta.
