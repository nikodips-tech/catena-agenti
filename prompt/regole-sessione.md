# Regole per tutta la sessione

Valgono per ogni prompt di questa cartella. `<CARTELLA>` è la cartella della catena indicata
nel prompt che ti ha chiamato: lì stanno i documenti da leggere (`docs/`, `modello-repo/`,
`agenti/`).

- **Git e GitHub li fai tu**: rami, commit, PR, merge, cancellazione dei rami, etichette,
  variabili, ruleset. L'utente non lancia comandi. Ciò che richiede le sue mani (segreti,
  installazione della App) glielo chiedi con un elenco preciso e ti fermi.
- **Mai in master.** Non unire niente in master, neanche la PR di release.
- **Niente verifiche dell'interfaccia**: niente Playwright, browser, screenshot, e2e.
- **Niente test in locale**: bastano i controlli delle PR su GitHub.
- **Risparmio di token**: non esplorare il codice dell'app. Leggi solo i file che servono al
  passo in corso (workflow, package e configurazioni, README, compose, docs). Della catena
  leggi `docs/specifica.md`, `docs/configurazione.md`, `docs/permessi.md` e i file di
  `modello-repo/`; il resto solo se un passo lo richiede.
- **Non toccare niente fuori dal repo**: `~/.claude`, plugin, altre cartelle. La cartella
  della catena si legge e non si modifica: se trovi un errore nella catena, segnalalo nel
  resoconto.
- **Non toccare** il codice dell'app, i test esistenti, i workflow di rilascio, staging,
  anteprima e CI (salvo i ritocchi indicati), i segreti.
- **Mai l'etichetta `auto`**, mai lanciare a mano i workflow della catena.
- **Nel dubbio tieni e riferisci**, invece di cancellare.
- Ogni gruppo di modifiche al repo passa da **una PR verso develop**: controlli verdi, merge
  (squash), ramo cancellato in locale e in remoto. Un controllo obbligatorio rosso: fermati e
  riferisci. Titolo della PR con prefisso `chore:`.
- Attribuzione nei commit e nelle PR come da istruzioni di sistema della sessione.

## Quando fermarti subito

Fermati, scrivi il motivo e cosa servirebbe, senza improvvisare, se:

1. `git status` non è pulito all'inizio.
2. Il repo non ha i rami `develop` e `master` (o equivalenti chiari: in tal caso proponi i
   valori per `ramo_sviluppo` e `ramo_produzione` di `.catena.yml` e aspetta).
3. Il progetto non ha nessun framework di test unitari: introdurlo è una decisione dell'utente.
4. Manca un prerequisito che richiede le mani dell'utente (`docs/permessi.md`, «Cosa serve in
   ogni repository»).
5. Una modifica richiederebbe di cambiare i permessi della App della catena o la policy
   di un environment.

## Resoconto finale (breve, a elenco)

- Cosa hai cancellato e cosa hai tenuto tra i casi dubbi.
- Controlli obbligatori finali di develop e master.
- I comandi di `.catena.yml` (lint, tipi, test, test con database) e il container.
- Controlli propri del progetto: quelli della CI che non sono tra quelli della catena (lint,
  tipi, test, test con database, build, migrazioni distruttive, test indeboliti), con cosa
  fanno e se andrebbero generalizzati. Solo una proposta da discutere con l'utente: non
  aggiungerli a `.catena.yml`.
- Stato dello staging (acceso e verde, rosso con errore, assente).
- Adattamenti fatti rispetto al modello.
- Cose strane trovate e non toccate (documentazione vecchia, commenti).
- Errori o dubbi trovati nella catena stessa (da correggere nel suo repository).
- Cosa resta da fare all'utente.
