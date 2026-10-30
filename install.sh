#!/usr/bin/env bash
# install.sh — instala a statusline a partir de um clone, sem marketplace.
#
#   git clone git@github.com:flisbao-ciandt/claude-code-statusline.git
#   cd claude-code-statusline && ./install.sh
#
# Faz o mesmo que `/claude-code-statusline:setup`, com uma diferença: em vez de o
# launcher procurar a cópia no cache de plugins, a flag `statusline-dev` aponta
# para este clone. Atualizar é `git pull`; o `settings.json` não muda mais.
#
# Seguro para rodar de novo: nada é reescrito quando já está igual, e tudo o que
# existia antes vira backup com timestamp.
#
#   ./install.sh            instala
#   ./install.sh --force    substitui uma `statusLine` diferente sem perguntar
#   ./install.sh --uninstall  desliga a statusline deste clone
#
# Compatível com o bash 3.2 do macOS. Sem `set -e`: cada passo diz o que houve.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SL_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-statusline"
LAUNCHER="$CONFIG_DIR/statusline.sh"
DEV_FLAG="$CONFIG_DIR/statusline-dev"
SETTINGS="$CONFIG_DIR/settings.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

force=0
uninstall=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
    -h|--help) sed -n 2,17p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'opção desconhecida: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

if [ ! -f "$ROOT/bin/launcher.sh" ] || [ ! -f "$ROOT/bin/statusline.sh" ]; then
  warn "rode o install.sh de dentro do clone (bin/launcher.sh não encontrado em $ROOT)"
  exit 1
fi

# ── Desinstalar ──
if [ "$uninstall" = 1 ]; then
  if [ -f "$DEV_FLAG" ]; then
    rm -f "$DEV_FLAG" && say "removido $DEV_FLAG"
  fi
  say "O launcher ($LAUNCHER) e o statusLine do settings.json ficam como estão."
  say "Para voltar à linha padrão do Claude Code, apague a chave statusLine do $SETTINGS."
  exit 0
fi

mkdir -p "$CONFIG_DIR" "$SL_CONFIG_DIR" || { warn "não consegui criar os diretórios"; exit 1; }

# ── Dependências ──
have_jq=1
if ! command -v jq >/dev/null 2>&1; then
  have_jq=0
  warn "jq não encontrado: a statusline quase não mostra nada sem ele."
  case "$(uname -s)" in
    Darwin) say "  instale com: brew install jq" ;;
    MINGW*|MSYS*) say "  instale com: winget install jqlang.jq  (ou scoop install jq)" ;;
    *) say "  instale com: sudo apt install jq  (ou o gerenciador da sua distro)" ;;
  esac
fi
command -v git >/dev/null 2>&1 || warn "git não encontrado: só os widgets de git ficam em silêncio."

# ── 1. Launcher ──
if [ -f "$LAUNCHER" ] && cmp -s "$ROOT/bin/launcher.sh" "$LAUNCHER"; then
  say "launcher: já instalado"
else
  if [ -f "$LAUNCHER" ]; then
    cp "$LAUNCHER" "$LAUNCHER.bak.$STAMP" && say "launcher: backup da sua statusline anterior em $LAUNCHER.bak.$STAMP"
  fi
  cp "$ROOT/bin/launcher.sh" "$LAUNCHER" && chmod +x "$LAUNCHER" && say "launcher: instalado em $LAUNCHER"
fi

# ── 2. Aponta o launcher para este clone ──
printf '%s\n# Gravado por install.sh. Para desligar: ./install.sh --uninstall\n' "$ROOT" > "$DEV_FLAG" \
  && say "clone:    $ROOT"

# ── 3. settings.json ──
cmd_path="$LAUNCHER"
if command -v cygpath >/dev/null 2>&1; then
  # `-m` (barras normais), nunca `-w`: contrabarras viram escape no Git Bash.
  cmd_path="$(cygpath -m "$LAUNCHER")"
fi
command_str="bash $cmd_path"

if [ "$have_jq" = 0 ]; then
  warn "sem jq não dá para editar o settings.json. Adicione na mão:"
  printf '  "statusLine": { "type": "command", "command": "%s", "padding": 0, "refreshInterval": 5 }\n' "$command_str"
else
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    warn "$SETTINGS não é um JSON válido; não mexi nele."
  else
    current="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
    if [ "$current" = "$command_str" ]; then
      say "settings:  statusLine já aponta para o launcher"
    else
      write=1
      if [ -n "$current" ] && [ "$force" = 0 ]; then
        say "settings:  já existe uma statusLine diferente:"
        say "           $current"
        if [ -t 0 ]; then
          printf '           substituir? [s/N] '
          read -r answer
          case "$answer" in s|S|y|Y) ;; *) write=0 ;; esac
        else
          write=0
          say "           (use --force para substituir)"
        fi
      fi
      if [ "$write" = 1 ]; then
        cp "$SETTINGS" "$SETTINGS.bak.$STAMP"
        tmp="$(mktemp)"
        if jq --arg c "$command_str" \
          '.statusLine = {type: "command", command: $c, padding: 0, refreshInterval: 5}' \
          "$SETTINGS" > "$tmp" 2>/dev/null; then
          # `cat >` e não `mv`: o arquivo costuma ser symlink de dotfiles.
          cat "$tmp" > "$SETTINGS" && say "settings:  statusLine gravada (backup em $SETTINGS.bak.$STAMP)"
        else
          warn "falha ao editar o settings.json; nada foi alterado."
        fi
        rm -f "$tmp"
      else
        say "settings:  mantido como estava"
      fi
    fi
  fi
fi

# ── 4. Configuração padrão ──
SL_CONFIG="$SL_CONFIG_DIR/config.json"
if [ -f "$SL_CONFIG" ]; then
  say "config:    $SL_CONFIG já existe, não toquei"
else
  cat > "$SL_CONFIG" <<'EOF'
{
  "version": 1,
  "lines": [
    ["repo", "branch", "git-status", "worktree", "velocity", "cache", "cost", "flow", "model"],
    ["context", "rate-forecast", "sprint"],
    ["tip"]
  ],
  "separator": "|",
  "icons": true,
  "widgets": {
    "cost": { "warn": 5, "crit": 15 },
    "flow": { "ttl": 300, "spent": true, "status": true }
  }
}
EOF
  say "config:    criada em $SL_CONFIG"
fi

# ── 5. Verificação ──
say ""
say "Teste (o ⚠ vermelho do Flow é esperado sem o token do gateway):"
bash "$LAUNCHER" < "$ROOT/tests/fixtures/session.json"
say ""

if [ -z "$ANTHROPIC_AUTH_TOKEN" ]; then
  say "Flow: ANTHROPIC_AUTH_TOKEN não está definido neste shell. O widget só"
  say "aparece quando o Claude Code roda com a chave do gateway Flow."
fi
say "Pronto. Reinicie o Claude Code. Para atualizar: git -C \"$ROOT\" pull"
