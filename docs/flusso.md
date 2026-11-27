# Il flusso, passo per passo

Chi fa cosa, con quale token, e quanto costa. `A` = token di Actions (sola lettura o scrittura
secondo il job), `App` = token della App della catena, `C` = Claude (costa token del
piano).

```
proprietario ──auto──► AVVIO (A) ──► TEAM LEADER (C opus, poi A)
                                        │ domanda ──► `turn-human` ──commento──► AVVIO
                                        │ corsia diretta ──────────────────────┐
                                        ▼ corsia completa                      │
                   ┌──► DEVELOPER (C sonnet, poi A): test, poi codice ◄── tentativo+1 (wip:)
                   │        │ verde: feat: #n                                 │ rosso ×2
                   │ prossimo sotto-task ◄──┤                                 ▼
                   │                        │ finiti        ESCALATION: TEAM LEADER (C opus)
                   │                        ▼                 riformula ──► sotto-task nuovi
                   │                 REVISORE (C opus, poi A)  bloccato ───► `turn-human`
                   └── sotto-task / rimuovi / ripristina (≤2) ◄──┤
                                                    │ approvata / riserve (PR unita lo stesso)
                                                    ▼
                                             EDITOR (C haiku, poi A) ── docs: #n
                                                    ▼
                                      CHIUSURA (App): PR ──► CI del progetto
                                                                ▼
                                 UNIONE (A + App) ◄── workflow_run ── verde: squash, chiudi, staging
                                                    rosso: RIPARAZIONE ─► DEVELOPER (1 volta) ─► CHIUSURA
                                                    ▼
                                                  CODA ──► AVVIO della prossima con `auto`
GUARDIANO (ogni ora, A): issue in corso (turn-*) ferme ─► AVVIO (ripartenza)
PR CHIUSA A MANO (A): ordine sull'issue, ramo via, CODA
```

## I passi

### Avvio (`avvio.sh`, nessun Claude)
Eventi: `auto` del proprietario; commento del proprietario su `turn-human`; dispatch (coda,
guardiano, a mano). Rifiuti con commento: non del proprietario, sotto-task, né task né hotfix,
già in corso. PR già aperta per l'issue: non riparte. Coda: un'issue principale in corso
alla volta (l'issue in coda tiene `auto`). Preflight (`preflight.sh`). Poi la ripartenza:

| Stato trovato | Passo |
|---|---|
| nessuna `## Specifica` | team leader |
| corsia diretta, nessun `feat: #issue` sul ramo | developer (sottotask = issue) |
| corsia diretta, `feat: #issue` sul ramo, nessun sotto-task aperto, e nessun test della base toccato o revisione già fatta | chiusura |
| corsia diretta, `feat: #issue` sul ramo, con sotto-task aperti o test della base toccati senza revisione | come la corsia completa (sotto-task aperti → developer; ramo → revisore o chiusura) |
| sotto-task aperti | developer sul primo |
| nessun sotto-task aperto, ramo esistente, revisione approvata o con riserve | chiusura |
| nessun sotto-task aperto, ramo esistente, senza revisione | revisore |
| nessun sotto-task aperto, nessun ramo | team leader (si rifà la specifica) |

### Un agente (`agente.yml`, due job)
1. `agente` (A **sola lettura**): checkout della catena (al suo tag) e del progetto; `ramo.sh`
   sceglie il ramo e registra il commit di partenza; `contesto.sh` prepara i dati in file
   fuori dal repo; credenziali git tolte dal checkout; dipendenze installate (il loro output
   non entra nel contesto di Claude); `agente.sh` lancia la CLI senza nessun token di
   piattaforma nell'ambiente; `raccolta.sh` misura le modifiche rispetto al commit di
   partenza, ripristina i file protetti, gli e2e e i test bloccati dal revisore, scarta quelli fuori ambito,
   formatta, riallinea le dipendenze con `aggiorna` se manifest o lock sono cambiati, esegue i controlli (developer), scrive l'artifact `esito`.
2. `esito` (A scrittura): `esito-<ruolo>.sh` applica la patch, committa, pusha, commenta,
   etichetta e avvia il passo dopo con `passo` (un `workflow_dispatch` del wrapper
   del progetto). Un'esecuzione annullata non arriva qui.

### Developer
Per ogni sotto-task, in TDD: prima i test, eseguiti perché falliscano, poi il codice, poi
tutti i controlli. I test della base può modificarli e cancellarli se il sotto-task cambia o
toglie il comportamento che verificano; il perché lo scrive in `note-developer.md` (la
raccolta lo sposta fuori dal repo). Lo script ripristina solo gli e2e, i file protetti e i
test che il revisore ha bloccato (riga `Test bloccati:` del sotto-task). Quelli aggiunti sul
ramo sono suoi. Con `Test: no` non scrive test. Strumenti: Read, Glob, Grep, Write, Edit, e
Bash solo su `controlli.sh` e `rimuovi.sh`: con il secondo cancella i file che il sotto-task
chiede di togliere (mai protetti o e2e), così rilancia subito i controlli; la cancellazione
entra nel commit e il revisore la vede nel diff. Verde: un commit `feat: #n` che assorbe i
tentativi precedenti, con nel corpo note e test della base toccati; in corsia diretta e nelle
riparazioni, se ha toccato test della base parte il revisore invece della chiusura. Rosso: il
lavoro resta sul ramo come `wip: #n tentativo k`, il tentativo dopo riceve l'errore e
corregge. Al secondo rosso, escalation al team leader; subito, se lo script ha ripristinato
test bloccati (il tentativo dopo rifarebbe la stessa modifica). Il revisore riceve i test
della base modificati (M) o cancellati (D) e le note, e li giudica; con `ripristina` lo script
li rimette come nella base e li blocca per i sotto-task che seguono.

### Chiusura (`chiusura.sh`, App)
PR dal ramo alla base, aperta dall'App: la CI parte da sola (con il token di Actions no). PR
già aperta: commit vuoto dell'App per rilanciare la CI. Etichette sulla PR con il token di
Actions. Commento `## Pull request pronta`. Con le riserve del revisore la PR si unisce lo
stesso (task): le riserve sono in fondo al corpo della PR e il proprietario le guarda prima del
passaggio in master. Gli hotfix li unisce lui.

### Unione (`unione.sh`, App per il merge)
Solo PR con `unione-automatica` e CI dell'ultimo commit. Verde: squash con titolo
`<prefisso>: <titolo> (#issue)`, ramo cancellato, issue chiusa (con `chiudi_issue:
produzione` resta aperta con `in-develop` fino al rilascio), commento, staging secondo
`.catena.yml`. Rosso: `## Riparazione 1` e developer sull'issue con job falliti e log; la
seconda volta `turn-human`. Se la riparazione tocca test della base, prima della chiusura parte
il revisore. Poi la coda.

### Guardiano (`guardiano.sh`)
Se nessuna esecuzione della catena è attiva: la prima issue in corso (un `turn-*` diverso da `turn-human`) senza novità da più di
`guardiano_minuti` riparte (commento "Ripresa automatica"); se nessuna è in corso, la coda.

## Quanto costa un giro

Ordine di grandezza per un'issue media in corsia completa con tre sotto-task: un team leader
(opus), tre o quattro developer (sonnet), un revisore (opus), un editor (haiku). In corsia
diretta: un team leader breve e un developer. Il consumo di ogni passo (turni, USD, minuti) è
nel commento che il passo lascia sull'issue o sul sotto-task.

Cosa tiene bassi i token: le dipendenze installate prima di Claude; `controlli.sh` che stampa
solo OK/FALLITO e trenta righe; i tentativi che ripartono dal lavoro già fatto (`wip:`); il
diff al revisore troncato; la corsia diretta.
