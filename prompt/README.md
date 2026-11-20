# I prompt da incollare in Claude Code

Tre prompt, da lanciare ognuno in una **nuova sessione** di Claude Code. Sostituisci
`<CARTELLA>` con il percorso della cartella in cui hai estratto la catena (per esempio
`D:\strumenti\catena-agenti`). Tutti i prompt leggono prima `regole-sessione.md`.

## 0. Pubblicare la catena (una volta sola)

Sessione aperta **nella cartella estratta**:

```
Leggi <CARTELLA>/prompt/0-pubblica-catena.md ed eseguilo. La cartella della catena è <CARTELLA>.
```

Crea il repository `nikodips-tech/catena-agenti` su GitHub, lo pubblica e mette il tag `v1`.
Da qui in avanti i progetti leggono la catena da GitHub; la cartella estratta serve ai prompt
di migrazione solo per leggere i documenti.

## 1. Un progetto che non ha mai avuto la catena

Sessione aperta **nella cartella del repository del progetto**:

```
Leggi <CARTELLA>/prompt/1-migrazione-nuovo-repo.md ed eseguilo in questo repository. La cartella della catena è <CARTELLA>.
```

Ricognizione, pulizia della vecchia parte Claude, fondamenta (CLAUDE.md, CI, etichette,
ruleset, staging), collegamento alla catena, verifica, resoconto.

## 2. Un progetto già migrato con il vecchio metodo

Sessione aperta **nella cartella del repository del progetto**:

```
Leggi <CARTELLA>/prompt/2-aggiornamento-repo-migrato.md ed eseguilo in questo repository. La cartella della catena è <CARTELLA>.
```

Sostituisce la copia locale della catena con il wrapper, aggiunge `.catena.yml`, product
owner e modelli, confronta i vecchi file provati con i nuovi e riferisce le differenze. Niente
pulizie.

## Dopo

La prova vera la fai tu: una issue piccola e reale con `task`, poi `auto`. Prima sul progetto pilota,
poi sugli altri. Se qualcosa non va, la correzione si fa nel repository della catena e si
ripubblica il tag (`README.md` della catena, sezione Versioni): nessun progetto va ritoccato.
