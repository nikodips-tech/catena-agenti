# Esempio di issue `task` scritta con il product owner

Titolo: **Ricordare l'ultimo gruppo aperto**

## Contesto
Chi fa parte di più gruppi, a ogni apertura dell'app atterra sul primo gruppo in ordine
alfabetico e deve cambiarlo a mano. Succede a ogni sessione.

## Obiettivo
All'apertura l'app mostra l'ultimo gruppo che l'utente aveva aperto; se non ne ha mai aperto
uno, il primo come oggi.

## Criteri di accettazione
- [ ] Aprendo un gruppo, l'identificativo viene salvato per quell'utente (lato server, non nel
      browser: deve valere da un altro dispositivo).
- [ ] L'endpoint che restituisce i gruppi dell'utente indica quale è l'ultimo aperto.
- [ ] Se l'ultimo gruppo aperto non esiste più o l'utente ne è uscito, si torna al primo.
- [ ] Nessuna migrazione che cancella o trasforma dati: solo una colonna nuova, nullable.

## Fuori ambito
Ricordare la pagina dentro il gruppo (serata, classifica…). Sincronizzare la scelta tra più
schede aperte.

## Corsia proposta
completa: tocca modello dati, API e client, e va decomposto (migrazione, endpoint, client).

---

Titolo: **Il pulsante "Vota" deve essere verde come gli altri pulsanti primari**

## Contesto
Nella pagina della serata il pulsante "Vota" è blu, gli altri pulsanti primari sono verdi.

## Obiettivo
Il pulsante "Vota" usa la stessa classe dei pulsanti primari.

## Criteri di accettazione
- [ ] Il componente del pulsante "Vota" usa la variante primaria del componente bottone.
- [ ] Nessun altro cambiamento.

## Fuori ambito
Rivedere i colori del tema.

## Corsia proposta
diretta: chiusa, indivisibile, la CI (lint, tipi, test esistenti) basta, nessuna area delicata.
