#!/usr/bin/env bash
# Il `container` di .catena.yml, se sta su ghcr.io (anche privato): login con il token del job
# (GH_TOKEN, permesso packages: read), pull e logout. L'immagine resta in locale per docker run,
# le credenziali spariscono prima che girino Claude o il codice della PR.
# Altri registri o nessun container: niente, docker run la scarica da sé.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/comune.sh"
cd "$REPO_DIR" || exit 1

immagine=$(cfg container)
case "$immagine" in ghcr.io/*) ;; *) exit 0 ;; esac

trap 'docker logout ghcr.io > /dev/null 2>&1 || true' EXIT
printf '%s' "$GH_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-catena}" --password-stdin > /dev/null
docker pull -q "$immagine"
