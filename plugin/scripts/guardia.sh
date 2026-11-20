#!/usr/bin/env bash
# Hook PreToolUse su Bash e PowerShell del plugin guardia (catena-agenti): blocca i comandi che
# Claude non deve mai lanciare. Legge su stdin il JSON dell'hook, estrae tool_input.command e
# applica queste regole:
#   1. git push ovunque, tranne: force, push su master, push di tag, cancellazione di master o develop;
#   2. gh api: niente approvazione dei deployment né modifiche a environments e rulesets;
#   3. niente merge in master nei repo di produzione (config/produzione.txt). Prima il repo (da
#      -R, dall'URL o dalla cartella): se non è di produzione il merge è libero. Se lo è (o non si
#      sa), gh pr merge chiede a GitHub la base e blocca master, main o una base sconosciuta; il
#      merge via gh api (pulls/N/merge, merges, graphql) si blocca sempre;
#   4. niente ssh, scp, sftp, ssh-copy-id;
#   5. niente docker compose down con -v, --volumes o --remove-orphans.
# Blocco: una riga su stderr (la regola e il perché) e uscita 2. Tutto il resto: uscita 0.
# Bash puro (Git Bash su Windows e Linux): niente jq, niente node. Test: hooks/test.sh.
set -u

input=$(cat 2>/dev/null || true)
[ -n "$input" ] || exit 0

# Solo i tool Bash e PowerShell (il matcher lo garantisce già, ma non costa niente).
case "$input" in
  *'"tool_name"'*'"Bash"'*|*'"tool_name"'*'"PowerShell"'*) ;;
  *) exit 0 ;;
esac

# Estrae il valore JSON di "command" (una stringa con gli escape) e lo decodifica.
estrai_comando() {
  local raw
  raw=$(printf '%s' "$input" | tr -d '\n' | grep -oP '"command"\s*:\s*"\K(?:\\.|[^"\\])*' | head -n 1) || return 1
  # Decodifica gli escape JSON più comuni (\" \\ \n \t \/); gli altri restano come sono.
  printf '%s' "$raw" | sed -e 's/\\"/"/g' -e 's/\\n/ /g' -e 's/\\t/ /g' -e 's/\\\//\//g' -e 's/\\\\/\\/g'
}

comando=$(estrai_comando) || exit 0
[ -n "$comando" ] || exit 0

blocca() {
  printf 'Bloccato: %s\n' "$1" >&2
  exit 2
}

# Cartella in cui gira il comando (per chiedere a gh il repo giusto); la cambiano i cd.
cartella=$(printf '%s' "$input" | tr -d '\n' | grep -oP '"cwd"\s*:\s*"\K(?:\\.|[^"\\])*' | head -n 1 | sed -e 's/\\\\/\\/g')
[ -n "$cartella" ] || cartella=.

# Esegue gh nella cartella del comando; stampa solo stdout, gli errori li butta.
gh_qui() {
  ( cd "$cartella" 2>/dev/null || exit 1; gh "$@" 2>/dev/null )
}

REGOLA_MASTER="Nei repo di produzione (plugin/config/produzione.txt di catena-agenti) il merge in master è il rilascio: lo fa sempre Nicola. Negli altri repo Claude può unire anche in master."

# Repo in cui master è produzione (minuscolo, uno per riga). Senza il file vale per tutti.
elenco_produzione="$(dirname "$0")/../config/produzione.txt"
if [ -r "$elenco_produzione" ]; then
  produzione=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$elenco_produzione" | grep -v '^$' | tr 'A-Z' 'a-z')
else
  produzione="*"
fi

# Vero se il repo ($1, nome o owner/nome) è di produzione; un repo sconosciuto conta come tale.
di_produzione() {
  local nome
  nome=$(printf '%s' "${1##*/}" | tr 'A-Z' 'a-z')
  [ -z "$nome" ] && return 0
  [ "$produzione" = "*" ] && return 0
  printf '%s\n' "$produzione" | grep -qxF -- "$nome"
}

# Nome del repo da un URL GitHub (https://github.com/owner/nome/...).
repo_da_url() {
  printf '%s' "$1" | sed -n -e 's#^https\{0,1\}://[^/]*/[^/]*/\([^/]*\).*#\1#p'
}

# Nome del repo da un percorso di gh api (repos/owner/nome/...); con {repo} lo chiede a gh.
repo_da_percorso() {
  local nome
  nome=$(printf '%s' "$1" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -n 1 | cut -d/ -f3)
  case "$nome" in
    ''|*'{'*|*'$'*) gh_qui repo view --json name -q .name ;;
    *) printf '%s' "$nome" ;;
  esac
}

# Blocca se la destinazione ($1) è master/main in un repo di produzione ($2), o se non si sa.
# $3 = cosa si sta facendo.
controlla_base() {
  case "$1" in
    master|main) di_produzione "$2" && blocca "$3 verso $1 di ${2:-un repo che non riesco a riconoscere}. $REGOLA_MASTER" ;;
    '') blocca "$3: non riesco a sapere da GitHub la destinazione, quindi non lo lascio passare. $REGOLA_MASTER" ;;
  esac
  return 0
}


# gh pr merge [<numero> | <url> | <branch>] [-R repo]: chiede a GitHub la base della PR.
# Le parole si separano con xargs, che rispetta le virgolette (es. -b "testo con spazi").
controlla_pr_merge() {
  local parole p pr="" repo="" salta="" iniziato=0 base
  [ "$da_stdin" = 1 ] && controlla_base "" "" "xargs gh pr merge (argomenti da stdin)"
  parole=$(printf '%s' "$1" | xargs printf '%s\n' 2>/dev/null) || parole=$(printf '%s' "$1" | tr ' ' '\n')
  while IFS= read -r p; do
    if [ "$iniziato" = 0 ]; then [ "$p" = merge ] && iniziato=1; continue; fi
    if [ -n "$salta" ]; then [ "$salta" = repo ] && repo=$p; salta=""; continue; fi
    case "$p" in
      -R|--repo) salta=repo ;;
      --repo=*) repo=${p#--repo=} ;;
      -b|--body|-F|--body-file|-t|--subject|-A|--author-email|--match-head-commit) salta=valore ;;
      -*) ;;
      *) [ -n "$pr" ] || pr=$p ;;
    esac
  done <<FINE
$parole
FINE
  case "$pr$repo" in
    *'$'*) controlla_base "" "" "gh pr merge $pr con una variabile (la espande la shell, dopo l'hook)" ;;
  esac
  # Prima il repo: -R, l'URL della PR o la cartella. Se non è di produzione non serve altro
  local nome=${repo##*/}
  [ -n "$nome" ] || nome=$(repo_da_url "$pr")
  [ -n "$nome" ] || nome=$(gh_qui repo view --json name -q .name)
  [ -n "$nome" ] && ! di_produzione "$nome" && return 0
  set -- pr view
  [ -n "$pr" ] && set -- "$@" "$pr"
  [ -n "$repo" ] && set -- "$@" -R "$repo"
  risposta=$(gh_qui "$@" --json baseRefName,url -q '.baseRefName + " " + .url')
  base=${risposta%% *}
  controlla_base "$base" "$(repo_da_url "${risposta#* }")" "gh pr merge${pr:+ $pr}"
}

# Spezza la riga nei singoli comandi: && || ; | newline, $( <( e backtick (comandi annidati).
segmenti=$(printf '%s' "$comando" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g' -e 's/[$<](/\n/g' -e 's/`/\n/g')

set -f   # niente espansione dei glob quando si spezzano le parole (case CLEAN*) ...)
while IFS= read -r seg; do
  # Via spazi iniziali, parentesi e prefissi innocui (cd, env, sudo, time).
  seg=$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/^[({][[:space:]]*//' -e 's/[[:space:]]*[)}][[:space:]]*$//')
  [ -n "$seg" ] || continue
  set -- $seg
  [ $# -gt 0 ] || continue
  da_stdin=0
  while [ $# -gt 0 ]; do
    case "$1" in
      env|sudo|time|nohup|command|exec) shift ;;
      # parole chiave della shell e pattern di case davanti al comando (then gh ..., x*) gh ...)
      then|do|else|elif|if|while|until|'!'|'{'|'('|*')') shift ;;
      case) shift   # case x in pattern) comando: salta fino al pattern
        while [ $# -gt 0 ]; do p=$1; shift; case "$p" in *')') break ;; esac; done ;;
      xargs) da_stdin=1; shift ;;   # gli argomenti arrivano da stdin: non si sanno
      *=*) shift ;;   # assegnazioni VAR=valore davanti al comando
      -*) if [ "$da_stdin" = 1 ]; then shift; else break; fi ;;   # opzioni di xargs
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || continue
  cmd=$1

  # cd cambia la cartella in cui si chiede a gh il repo (cd app && gh pr merge 3).
  if [ "$cmd" = "cd" ] && [ -n "${2:-}" ]; then
    d=$2; d=${d#\"}; d=${d%\"}; d=${d#\'}; d=${d%\'}
    case "$d" in
      /*|[A-Za-z]:*) cartella=$d ;;
      *) cartella="$cartella/$d" ;;
    esac
  fi

  case "$cmd" in
    ssh|scp|sftp|ssh-copy-id)
      blocca "$cmd. Claude non entra nei server: prepara i comandi, li esegue Nicola." ;;
  esac

  if [ "$cmd" = "git" ] && [ $# -ge 2 ]; then
    # Trova il sottocomando saltando le opzioni globali (-C dir, -c k=v, --git-dir=...).
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        -C|-c) shift 2 ;;
        --*=*|--no-pager|--bare) shift ;;
        *) break ;;
      esac
    done
    if [ "${1:-}" = "push" ]; then
      shift
      REGOLA="Claude ha pieni poteri su git, tranne force, push su master, push di tag e cancellazione di master o develop: quelli li fa Nicola (i tag li crea la CI)."
      cancella=0
      for a in "$@"; do
        case "$a" in
          --force|-f|--force-with-lease*|--force-if-includes)
            blocca "git push $a. $REGOLA" ;;
          --tags|--follow-tags|--mirror|--all)
            blocca "git push $a (tag o tutti i branch). $REGOLA" ;;
          --delete|-d) cancella=1 ;;
        esac
      done
      # I refspec (tutto ciò che non è un'opzione), il primo è il remote.
      remote=""; refspecs=""
      for a in "$@"; do
        case "$a" in
          -*) ;;
          *) if [ -z "$remote" ]; then remote=$a; else refspecs="$refspecs $a"; fi ;;
        esac
      done
      [ -n "$refspecs" ] || blocca "git push senza il nome del branch: scrivilo (git push origin <branch>), così si vede che non è master. $REGOLA"
      for r in $refspecs; do
        case "$r" in
          +*) blocca "git push $r (il + forza). $REGOLA" ;;
        esac
        if [ "$cancella" = 1 ]; then dest=$r
        else
          case "$r" in
            :*) dest=${r#:}; cancella_questo=1 ;;
            *:*) dest=${r#*:}; cancella_questo=0 ;;
            *) dest=$r; cancella_questo=0 ;;
          esac
        fi
        case "$dest" in
          refs/tags/*) blocca "git push di un tag ($dest). $REGOLA" ;;
        esac
        dest=${dest#refs/heads/}
        if printf '%s' "$dest" | grep -qE '^v?[0-9]+(\.[0-9]+){1,3}$'; then
          blocca "git push di $dest, che sembra un tag di versione. $REGOLA"
        fi
        case "$dest" in
          HEAD|'') blocca "git push verso HEAD: scrivi il nome del branch di destinazione. $REGOLA" ;;
        esac
        if [ "$cancella" = 1 ] || [ "${cancella_questo:-0}" = 1 ]; then
          case "$dest" in
            master|main|develop) blocca "git push che cancella $dest. $REGOLA" ;;
          esac
        else
          case "$dest" in
            master|main) blocca "git push su $dest. $REGOLA" ;;
          esac
        fi
      done
    fi
  fi

  if [ "$cmd" = "gh" ] && [ "${2:-}" = "api" ]; then
    REGOLA_GH="La produzione la approva Nicola: niente approvazione dei deployment né modifiche a environment e ruleset."
    if printf ' %s ' "$seg" | grep -qE 'pending_deployments|deployment_protection_rules'; then
      blocca "gh api su pending_deployments o deployment_protection_rules. $REGOLA_GH"
    fi
    modifica=0
    if printf ' %s ' "$seg" | grep -qE ' (-X|--method)[ =]*(PUT|POST|PATCH|DELETE)| (-f|-F|--field|--raw-field|--input)[ =]'; then
      modifica=1
    fi
    if [ "$modifica" = 1 ] && printf ' %s ' "$seg" | grep -qE '/(environments|rulesets)([/ ?]|$)'; then
      blocca "gh api che modifica environments o rulesets. $REGOLA_GH"
    fi
    # Merge via API: nei repo di produzione mai (si passa da gh pr merge, che controlla la base)
    if [ "$modifica" = 1 ] && printf ' %s ' "$seg" | grep -qE '/pulls/[0-9]+/merge([ ?]|$)|/merges([ ?]|$)'; then
      nome=$(repo_da_percorso "$seg")
      di_produzione "$nome" && blocca "gh api che unisce in ${nome:-un repo che non riesco a riconoscere}, repo di produzione: usa gh pr merge, che controlla la base. $REGOLA_MASTER"
    fi
    if printf ' %s ' "$seg" | grep -qE 'mergePullRequest|enablePullRequestAutoMerge|mergeBranch'; then
      blocca "gh api graphql che unisce una PR o un branch: usa gh pr merge, che l'hook sa controllare. $REGOLA_MASTER"
    fi
  fi

  if [ "$cmd" = "gh" ] && [ "${2:-}" = "pr" ] && [ "${3:-}" = "merge" ]; then
    controlla_pr_merge "$seg"
  fi

  if [ "$cmd" = "docker" ] || [ "$cmd" = "docker-compose" ]; then
    if printf ' %s ' "$seg" | grep -qE '(^| )(docker-compose|docker( +[^ ]+)* +compose)( +[^ ]+)* +down( |$)'; then
      for flag in -v --volumes --remove-orphans; do
        if printf ' %s ' "$seg" | grep -qF -- " $flag "; then
          blocca "docker compose down con $flag. I volumi contengono dati e nello stesso compose ci sono altri servizi: mai -v, --volumes o --remove-orphans."
        fi
      done
    fi
  fi
done <<EOF
$segmenti
EOF

exit 0
