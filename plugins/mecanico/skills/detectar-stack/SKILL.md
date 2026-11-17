---
name: detectar-stack
description: Identifica linguagens, gerenciadores de pacote, frameworks, comandos de build/teste/lint, infraestrutura, CI e a arquitetura provável (monólito, monorepo, microsserviços, app móvel) de um repositório. Use ao entrar em qualquer código desconhecido, antes de diagnosticar ou corrigir, ou quando perguntarem "que stack é essa", "como rodo os testes", "como este projeto é organizado".
argument-hint: "[diretório — padrão: raiz do projeto]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/detectar-stack.sh *)
---

# Detectar a stack

Manutenção começa por saber com o que se está lidando. Rodar o comando errado de teste, ou assumir npm onde o projeto usa pnpm, desperdiça tempo e pode sujar o repositório (lockfile reescrito, por exemplo).

## Passo 1 — rode o detector

```bash
${CLAUDE_SKILL_DIR}/scripts/detectar-stack.sh <diretório>
```

Use `.` para a raiz do projeto, ou o argumento recebido: $ARGUMENTS

O script só lê arquivos. A saída traz: linguagens por volume, ecossistemas com manifestos e comandos prováveis, frameworks, testes, infraestrutura e contratos de API, arquitetura provável, documentação existente e os arquivos mais alterados no histórico.

## Passo 2 — confirme nas fontes do projeto

A saída é heurística. Em ordem de confiabilidade, a verdade sobre como construir e testar está em:

1. **Pipeline de CI** (`.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`…) — é o que de fato roda.
2. **Scripts do manifesto** (`package.json` → `scripts`, `Makefile`, `justfile`, `pyproject.toml` → `[tool.*]`, `composer.json` → `scripts`).
3. **README / CONTRIBUTING / CLAUDE.md.**
4. **Arquivos de versão de runtime** (`.nvmrc`, `.python-version`, `.tool-versions`, `go.mod`, `global.json`, `rust-toolchain.toml`) — usar a versão errada produz falhas que não são do código.

Se o projeto não tem `CLAUDE.md`, vale sugerir ao usuário registrar ali os comandos confirmados.

## Passo 3 — verifique se o ambiente roda o projeto

Antes de diagnosticar o código, garanta que a falha não é do ambiente: o runtime existe na versão pedida? as dependências instalam com o lockfile travado? o projeto precisa de serviços (banco, fila) — há `docker compose` ou equivalente para subi-los?

## Referência

Comandos de instalação, build, teste, lint, formatação, auditoria e depuração para mais de vinte ecossistemas, incluindo como rodar um único teste: [referencias/comandos-por-stack.md](referencias/comandos-por-stack.md). Consulte quando a stack não for a do seu dia a dia.

## Stack que o detector não reconhece

Linguagem rara, legado (COBOL, Delphi, VB6, Classic ASP, PL/SQL), scripts soltos ou apenas artefatos compilados: identifique pelos arquivos (`file`, extensões, cabeçalhos), procure o ponto de entrada (o que o servidor, o cron ou o instalador executa) e leia a partir dele. Sem fonte disponível, o caminho é a skill `engenharia-reversa`.
