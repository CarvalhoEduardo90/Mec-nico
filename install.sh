#!/usr/bin/env bash
# install.sh — copia os agentes e skills do Mecânico para dentro de um
# repositório (em .claude/), sem depender de plugin nem de marketplace.
#
# Uso:
#   ./install.sh <caminho-do-repositório> [--forcar]
#   ./install.sh --usuario [--forcar]        # instala em ~/.claude (vale para todos os projetos)
#
# Arquivos já existentes e diferentes NÃO são sobrescritos, a menos que se
# passe --forcar. Nada é apagado.
set -eu

ORIGEM="$(cd "$(dirname "$0")" && pwd)/plugins/mecanico"
DESTINO=""
FORCAR=0

for arg in "$@"; do
  case "$arg" in
    --forcar) FORCAR=1 ;;
    --usuario) DESTINO="$HOME/.claude" ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "opção desconhecida: $arg" >&2; exit 2 ;;
    *)
      [ -d "$arg" ] || { echo "erro: diretório não encontrado: $arg" >&2; exit 1; }
      DESTINO="$(cd "$arg" && pwd)/.claude" ;;
  esac
done

if [ -z "$DESTINO" ]; then
  echo "uso: $0 <caminho-do-repositório> [--forcar]   |   $0 --usuario [--forcar]" >&2
  exit 2
fi
[ -d "$ORIGEM/agents" ] && [ -d "$ORIGEM/skills" ] || { echo "erro: não encontrei $ORIGEM/agents e $ORIGEM/skills" >&2; exit 1; }

COPIADOS=0; IGUAIS=0; PULADOS=0

copiar() { # copiar <arquivo de origem> <arquivo de destino>
  local de="$1" para="$2"
  if [ -e "$para" ]; then
    if cmp -s "$de" "$para"; then IGUAIS=$((IGUAIS+1)); return 0; fi
    if [ "$FORCAR" -eq 0 ]; then
      PULADOS=$((PULADOS+1)); echo "  pulado (já existe e é diferente): ${para#"$DESTINO"/}"; return 0
    fi
  fi
  mkdir -p "$(dirname "$para")"
  cp -p "$de" "$para"
  COPIADOS=$((COPIADOS+1))
}

echo "Instalando o Mecânico em: $DESTINO"

for f in "$ORIGEM"/agents/*.md; do
  copiar "$f" "$DESTINO/agents/$(basename "$f")"
done

# skills: preserva a estrutura de diretórios (SKILL.md, referencias/, scripts/)
LISTA="$(mktemp)"
trap 'rm -f "$LISTA"' EXIT
( cd "$ORIGEM/skills" && find . -type f | sed 's|^\./||' ) > "$LISTA"
while IFS= read -r rel; do
  copiar "$ORIGEM/skills/$rel" "$DESTINO/skills/$rel"
done < "$LISTA"

chmod +x "$DESTINO"/skills/*/scripts/*.sh 2>/dev/null || true

echo
echo "Concluído: $COPIADOS copiados · $IGUAIS já estavam atualizados · $PULADOS pulados"
[ "$PULADOS" -gt 0 ] && echo "Para sobrescrever os pulados, rode de novo com --forcar."
cat <<'EOF'

Próximos passos:
  1. Abra o Claude Code no repositório (ou reinicie a sessão) para carregar os agentes e skills.
  2. Experimente:  /manutencao <descreva o problema>     ou     /diagnostico
  3. Versione a pasta .claude/agents e .claude/skills para que o time inteiro
     (e as sessões na nuvem) tenham a oficina disponível.
EOF
