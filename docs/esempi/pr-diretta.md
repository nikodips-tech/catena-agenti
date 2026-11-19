# Esempio di pull request in corsia diretta (da Claude Code o claude.ai)

Ramo: `diretta/pulsante-vota-primario` → `develop`
Titolo: `fix: pulsante Vota con la variante primaria`
Etichette: `task`, `unione-automatica`

Corpo:

```
Corsia: diretta
Motivo: richiesta chiusa (decisa in sessione), un solo file, verificabile dalla CI, nessuna area delicata.

## Cosa cambia
Il pulsante "Vota" in `app/app/components/SerataVoto.vue` usa `variant="primary"` come gli altri pulsanti primari.

## Come verificare
Lint, tipi e test esistenti (nessun test nuovo: non cambia comportamento).
```

Cosa succede dopo, senza altri interventi: la CI parte (la PR l'ha aperta il proprietario,
non un token di Actions); a controlli verdi `unione.yml` fa lo squash con il titolo così com'è
(ha già il prefisso), cancella il ramo e, se lo staging automatico è acceso, lo aggiorna.

Senza `unione-automatica`, la PR resta aperta finché il proprietario non la unisce: è il modo
di dire "voglio guardarla prima".

Per un hotfix: ramo `hotfix/<slug>` da `master`, PR verso `master`, etichetta `hotfix`,
**senza** `unione-automatica` (in master unisce solo il proprietario).
