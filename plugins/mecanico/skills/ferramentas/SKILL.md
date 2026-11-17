---
name: ferramentas
description: Verifica quais ferramentas de linha de comando para manutenção de código e engenharia reversa estão instaladas (ripgrep, ast-grep, semgrep, trivy, gitleaks, jadx, apktool, radare2, Ghidra, frida, mitmproxy e outras) e mostra como instalar as que faltam. Use quando um comando necessário não existir, ao preparar um ambiente para manutenção ou análise, ou quando pedirem "instale as ferramentas", "o que preciso ter instalado", "prepare o ambiente".
argument-hint: "[geral | re | tudo] [--instalar]"
---

# Caixa de ferramentas

Um mecânico trabalha com as ferramentas que tem — mas precisa saber quais são. Esta skill inventaria o ambiente e, a pedido, instala o que falta.

## Verificar

```bash
${CLAUDE_SKILL_DIR}/scripts/ferramentas.sh tudo
```

Categorias: `geral` (busca, lint, auditoria, containers), `re` (engenharia reversa: binários, mobile, rede, JavaScript), `tudo`. Argumento recebido: $ARGUMENTS

A saída marca cada ferramenta como `[ok]` ou `[falta]`, diz para que serve e mostra o comando de instalação adequado ao sistema atual.

## Instalar

```bash
${CLAUDE_SKILL_DIR}/scripts/ferramentas.sh <categoria> --instalar
```

Instalar software altera a máquina do usuário. Por isso:

- **Só instale quando o usuário pedir ou autorizar.** Em caso de dúvida, mostre o que falta e pergunte.
- **Instale o que a tarefa precisa**, não a lista inteira. Para uma ou duas ferramentas, rode diretamente o comando indicado na coluna "instalar" em vez de `--instalar` na categoria toda.
- O script usa `apt-get` (Debian/Ubuntu) ou Homebrew (macOS/Linux) quando disponíveis, e `pipx`/`pip`, `npm`, `go install` ou `dotnet tool` para o que não está nesses repositórios. Sem root nem `sudo` sem senha, ele não instala pacotes de sistema — apenas informa o comando.
- Em outras distribuições (Fedora, Arch, Alpine) ou no Windows, os nomes de pacote mudam: use o gerenciador nativo (`dnf`, `pacman`, `apk`, `winget`, `scoop`) com o nome da ferramenta.
- Ferramentas marcadas com uma URL (Ghidra, jadx, gitleaks, trivy, hadolint) não têm instalação automática fora do Homebrew: baixe o release oficial indicado.

## Quando falta e não dá para instalar

Há quase sempre um substituto à mão — menos confortável, mas suficiente:

| Falta | Use |
|---|---|
| `rg` | `grep -rnE` · `git grep -n` |
| `fd` | `find . -name` · `git ls-files` |
| `jq` | `python3 -m json.tool` · `python3 -c 'import json,sys; ...'` |
| `ast-grep` / `semgrep` | `rg` com padrão cuidadoso + leitura |
| `cloc` | `wc -l` sobre a saída de `git ls-files` |
| `xxd` | `hexdump -C` · `od -A x -t x1z` |
| `jadx` | `unzip` + `strings` nos `.dex`; `apktool` para o manifesto |
| `r2` / Ghidra | `objdump -d` · `readelf -a` · `nm` · `strings` |
| `mitmproxy` | logs do próprio app/servidor; `curl -v`; `tshark` |
| `7z` | `unzip` · `tar` · `python3 -m zipfile -e` |

Diga no relatório quando uma conclusão ficou limitada pela falta de uma ferramenta.

## Ferramentas específicas de cada linguagem

Compiladores, runtimes, linters e auditores de cada ecossistema (Node, Python, JVM, .NET, Go, Rust, PHP, Ruby…) não são instalados por este script — eles pertencem ao projeto e devem vir na versão que ele fixa. A skill `detectar-stack` identifica o que o projeto usa; a referência `comandos-por-stack.md` dela lista os comandos por ecossistema.
