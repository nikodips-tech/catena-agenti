# GitLab: non ancora fatto

Qui andranno `adattatore.sh` (le funzioni `pf_*` con `glab` o `curl`) e i template di
pipeline da includere nei progetti con `include: project:`. La mappa di cosa serve è in
`docs/portabilita.md`, sezione «Cosa servirà su GitLab».

Il nucleo (`agenti/`, `scripts/`) non cambia. Il wrapper del progetto sarà un `.gitlab-ci.yml`
che include i template e passa `PIATTAFORMA=gitlab`.
