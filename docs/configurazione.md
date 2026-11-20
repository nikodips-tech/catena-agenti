# `.catena.yml`: la configurazione di un progetto

Un file piatto nella radice del repo, una chiave per riga (`chiave: valore`), senza liste
annidate: lo leggono script di shell senza `yq`. I commenti con `#` dopo uno spazio vanno
bene. Lo cambia solo il proprietario (è un file protetto per gli agenti). Esempi completi in
`docs/esempi/catena-node.yml` e `docs/esempi/catena-php.yml`.

## Rami e piattaforma

| Chiave | Predefinito | Significato |
|---|---|---|
| `ramo_sviluppo` | `develop` | base dei `task`, ramo predefinito |
| `ramo_produzione` | `master` | base degli `hotfix` |
| `workflow_catena` | `catena.yml` | il file del wrapper, per `workflow_dispatch` |
| `ci_nome` | `CI` | il `name:` del workflow della CI (lo aspetta `workflow_run`) |
| `prefisso_task` / `prefisso_hotfix` | `feat` / `fix` | prefisso del commit squash per il release |
| `chiudi_issue` | `unione` | `unione`: l'issue si chiude quando la PR entra nella base. `produzione`: entrata in develop resta aperta con `in-develop` (PR e squash con `Refs #n`, non `Closes`) e la chiude il rilascio del progetto; l'avvio la rifiuta |

## Comandi dei controlli

Girano nella `cartella`, dentro il `container` se c'è (montata in `/lavoro`), altrimenti sul
runner. Devono essere **gli stessi della CI**.

| Chiave | Esempio | Note |
|---|---|---|
| `cartella` | `app` | dove stanno package.json, composer.json…; `.` per la radice |
| `container` | `node:22-alpine` | immagine; vuoto = direttamente sul runner |
| `container_rete` | `host` | rete di `docker run` (serve per i test con database) |
| `container_opzioni` | `-e TZ=Europe/Rome` | altre opzioni di `docker run` |
| `installa` | `npm ci --no-audit --no-fund --silent` | dipendenze, prima di Claude |
| `installato_se` | `node_modules` | percorso (dalla cartella) che, se esiste, evita di rifare `installa` |
| `lint` | `npm run -s lint -- --quiet && npm run -s format:check` | solo errori |
| `tipi` | `npm run -s typecheck` | vuoto se il progetto non ha tipi |
| `test` | `npm test -s -- --reporter=dot` | reporter che mostra solo i fallimenti |
| `test_db` | `npm run -s test:db` | vuoto se la CI non li esegue |
| `db_avvia` | `docker compose -f docker-compose.ci.yaml up -d --wait db` | sul runner, prima di `test_db` |
| `db_ferma` | `docker compose -f docker-compose.ci.yaml down -v` | dopo |
| `formatta` | `npx prettier --write {file}` | `{file}` = i file cambiati, relativi alla cartella |
| `formatta_file` | `\.(js|ts|vue|json|css|md)$` | quali file passano al formattatore |
| `formatta_codice` | `npx eslint --fix {file}` | fix automatici del linter |
| `formatta_codice_file` | `\.(js|ts|vue)$` | quali file passano al linter |
| `filtro_errori` | `error|fail|✖` | regex delle righe da mostrare quando un controllo fallisce |

## Riconoscimento dei file

| Chiave | Predefinito | Significato |
|---|---|---|
| `file_test` | `\.(test|spec)\.[^/]+$` | regex (PCRE) dei file di test, sul percorso dalla radice |
| `file_e2e` | `(^|/)(e2e|e2e-screenshots)/|playwright\.config|\.e2e\.` | file e2e: nessun agente li tocca |
| `file_protetti` | vuoto | regex aggiuntiva di file che nessun agente può cambiare |
| `docs` | `^docs/|^README\.md$` | regex dei file che l'editor può toccare |
| `framework_test` | vuoto | nome per i prompt (`Vitest`, `PHPUnit`, `pytest`…) |

## Agenti

| Chiave | Predefinito | Significato |
|---|---|---|
| `modello_team_leader`, `modello_developer`, `modello_revisore`, `modello_editor` | vedi specifica | modello per ruolo |
| `turni_<ruolo>` | vedi specifica | turni massimi per ruolo |
| `guardiano_minuti` | `90` | fermo oltre il quale il guardiano riparte |

## Staging

| Chiave | Esempio | Significato |
|---|---|---|
| `staging_variabile` | `STAGING_AUTOMATICO` | variabile del repo che accende lo staging a ogni push su develop |
| `staging_valore` | `si` | il valore che significa "acceso" |
| `staging_workflow` | `staging.yml` | se la variabile non è accesa, l'unione lancia questo workflow |
| `staging_avvio` | `-f azione=accendi` | argomenti per quel lancio |

Senza `staging_variabile` il commento finale dice solo "Unita in develop".
