# I prompt da incollare in Claude Code

Due prompt per i progetti, uno per il repository della catena. Ognuno in una **nuova
sessione** di Claude Code. Sostituisci `<CARTELLA>` con il percorso di una copia locale della
catena (clone o cartella estratta), che serve solo per leggere i documenti: i progetti usano
la catena da GitHub.

Tutti leggono prima `regole-sessione.md`; i due prompt dei progetti eseguono poi
`installazione.md`, che è uguale per entrambi. Alla fine di ogni prompt il resoconto.

## 1. Un repository nuovo

Un repository senza niente di Claude e senza workflow, o con workflow che non c'entrano con
Claude e che restano. Sessione aperta **nella cartella del repository**:

```
Leggi <CARTELLA>/prompt/1-repo-nuovo.md ed eseguilo in questo repository. La cartella della catena è <CARTELLA>.
```

## 2. Un repository con un'impostazione precedente

Un repository che ha già `CLAUDE.md`, `.claude/`, workflow di Claude o di una versione
precedente del metodo (CI, release, tag, chiusura delle issue, catena copiata). Si cancella
tutto il vecchio e si installa da zero. Sessione aperta **nella cartella del repository**:

```
Leggi <CARTELLA>/prompt/2-repo-esistente.md ed eseguilo in questo repository. La cartella della catena è <CARTELLA>.
```

## 0. Pubblicare la catena (una volta sola)

Serve solo se il repository della catena non esiste ancora su GitHub:

```
Leggi <CARTELLA>/prompt/0-pubblica-catena.md ed eseguilo. La cartella della catena è <CARTELLA>.
```

## Dopo

La prova vera la fai tu: una issue piccola e reale con `task`, poi `auto`. Prima su un
progetto, poi sugli altri. Se qualcosa non va, la correzione si fa nel repository della catena
e si ripubblica il tag (`README.md` della catena, sezione Versioni): nessun progetto va
ritoccato.
