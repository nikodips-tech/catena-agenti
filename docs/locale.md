# La catena in sessione locale

La sessione di Claude Code è un terzo innesco, accanto a GitHub Actions e al futuro GitLab:
stessi prompt dei ruoli, stessi controlli, stessa PR alla fine. Cambia chi orchestra: non gli
script, ma Claude stesso, con la skill `/catena` (`modello-repo/.claude/skills/catena/`) e
quattro sottoagenti sottili (`modello-repo/.claude/agents/catena-*.md`).

## Come funziona

- I sottoagenti non contengono i prompt: hanno solo il frontmatter (modello, strumenti) e una
  riga che dice "leggi le istruzioni nel file indicato". La skill scarica `agenti/*.md` e
  `scripts/controlli.sh` e `scripts/rimuovi.sh` dal repository della catena al tag `v1` in una
  cartella temporanea, all'inizio del giro. La fonte resta una sola.
- La skill fa ciò che su GitHub fanno `avvio.sh` e gli `esito-*.sh`: ramo, ordine dei passi,
  ripristino dei file protetti, formattazione, controlli, commit, PR. Niente App, niente
  artifact: git e gh li ha l'orchestratore.
- Lo stato non passa dalle etichette e dai commenti dell'issue: vive nella sessione. La PR ha
  lo stesso corpo e le stesse etichette di quella aperta dalla catena, così `unione.yml` la
  tratta allo stesso modo.

## Quando usarla

- Quando sei lì e vuoi vedere i passi mentre succedono.
- Quando il repository non è su GitHub, o la catena su GitHub non è ancora collegata.
- Per task piccoli: uno o due sottotask.

## Quando non usarla

- Per lavoro che vuoi lasciare andare: su GitHub il giro va avanti da solo, in locale il PC e
  la sessione restano occupati.
- Per issue grandi: il contesto dell'orchestratore cresce a ogni sottoagente che torna con il
  suo rapporto; in CI ogni passo è una sessione pulita.
- Per la corsia diretta decisa in sessione: lì non serve nessuna catena, si fa la modifica e
  si apre la PR (docs/corsie.md).

## Limiti rispetto alla catena su GitHub

- Isolamento più debole: in CI Claude non ha git, gh né token, e uno script controlla i file
  toccati; in locale i vincoli sono i `tools` del frontmatter e le istruzioni della skill.
- Niente coda, niente guardiano, niente consumo per passo nei commenti.
- `/loop` non serve: la skill esegue i passi in sequenza con l'Agent tool.

## Installazione in un progetto

I prompt di migrazione copiano skill e agenti da `modello-repo/.claude/`. Il frontmatter dei
sottoagenti (`tools`, `model`) è la sola cosa che un progetto può voler adattare, per esempio
i pattern di `Bash` del developer se `controlli.sh` e `rimuovi.sh` stanno in un percorso diverso.
