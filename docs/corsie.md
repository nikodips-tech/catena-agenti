# Le corsie

Una sola regola, non un elenco di eccezioni.

## Il criterio

La catena completa compra tre garanzie: una **specifica scritta** da chi conosce il codice,
una **decomposizione in sottotask** sviluppati uno alla volta in TDD, una **revisione
indipendente**. Costano token e tempo. Una modifica va in **corsia diretta** quando nessuna
delle tre aggiunge qualcosa, cioè quando valgono tutte queste condizioni:

1. **Chiusa.** Chi ha il contesto (la conversazione, l'issue) sa già esattamente cosa fare:
   nessuna decisione di progettazione resta aperta.
2. **Indivisibile.** Si consegna in una sola PR, in una sola sessione, senza decomporla.
3. **Verificabile dalla CI.** Lint, tipi e test del progetto bastano a dire che è giusta; chi
   la fa scrive i test che servono nella stessa passata.
4. **Fuori dalle aree delicate.** Non tocca dati esistenti del database, autenticazione,
   pagamenti, segreti, `.github/`, `CLAUDE.md`, `.claude/`, migrazioni distruttive.

Se una condizione manca, **corsia completa**. Nel dubbio, completa. La dimensione in righe
non conta: un file di cinquanta righe chiuso e verificabile è diretto; una riga in una
migrazione è completa.

## Chi decide

Chi ha il contesto in quel momento, e lo scrive:

| Dove si è | Chi decide | Cosa fa in corsia diretta |
|---|---|---|
| Claude Code nel repo, claude.ai con il repo collegato | Claude nella sessione, con il proprietario | ramo, modifica, PR con `task` (o `hotfix`) e `unione-automatica`; nel corpo `Corsia: diretta` e il motivo |
| Issue con `auto` | il team leader | `corsia: diretta` in `esito.json`: parte un developer solo, codice e test insieme, poi la PR |
| Product owner | propone nell'issue (`Corsia proposta`) | il team leader decide |

La decisione è sempre leggibile dopo: nella PR o nella specifica.

## Cosa resta uguale nelle due corsie

- La **CI** e i **controlli obbligatori** del ruleset.
- L'**unione** (`unione.yml`): a CI verde, squash con il prefisso giusto, ramo cancellato,
  staging. Vale per qualsiasi PR verso `develop` con `unione-automatica`, da qualunque corsia.
- Le **regole dei file protetti**.
- **Mai in master da soli**: la PR verso `master` (hotfix compresi) la unisce sempre il
  proprietario; l'unione la salta anche se ha `unione-automatica`.

## Corsia diretta da una sessione: la procedura per Claude

1. Verifica il criterio ad alta voce, in una riga, e dillo al proprietario.
2. Ramo da `develop` con un nome parlante (`diretta/<slug>`); per un hotfix da `master`
   (`hotfix/<slug>`).
3. Modifica, test che servono, controlli locali se il progetto li prevede.
4. Commit con il prefisso del release (`feat:`, `fix:`, `docs:`, `chore:`).
5. PR verso `develop` (o `master`) con titolo prefissato, corpo come
   `docs/esempi/pr-diretta.md`, etichetta `task` (o `hotfix`). Solo verso `develop` anche
   `unione-automatica`, se il proprietario non ha chiesto di unirla lui; un hotfix lo unisce
   sempre lui.
6. Niente altro: la CI, l'unione, la release e lo staging fanno il resto.

## Corsia diretta da un'issue: cosa cambia nella catena

- La specifica è breve e contiene la riga `Corsia: diretta`; nessuna sub-issue.
- Il developer riceve l'issue come lavoro, scrive test e codice come sempre, ha i soliti 2
  tentativi.
- Niente revisore né editor: la PR si apre subito, con `unione-automatica`. Eccezione: se il
  developer ha modificato o cancellato test della base, prima della PR parte il revisore (che
  giudica la modifica con le note del developer); vale anche dopo una riparazione della CI.
- Se il developer fallisce 2 volte, l'escalation al team leader può `riformula`re: la catena
  passa alla corsia completa (nuova `## Specifica` con `Corsia: completa` e sub-issue).
