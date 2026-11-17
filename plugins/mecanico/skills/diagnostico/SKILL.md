---
name: diagnostico
description: Levantamento da saúde de um repositório sem alterar nada — o código constrói? os testes passam? há vulnerabilidades, dependências defasadas, código morto, pontos frágeis, dívida técnica? Use quando pedirem "analise este projeto", "o que há de errado aqui", "faça uma auditoria", "health check", "revisão geral", ou antes de assumir a manutenção de um código desconhecido.
argument-hint: "[caminho ou área de foco — opcional]"
---

# Diagnóstico de saúde do repositório

Foco: $ARGUMENTS

Objetivo: um retrato honesto do estado do código, priorizado por gravidade, com evidência para cada achado. Esta skill só observa — nenhuma alteração no projeto. Em repositórios grandes, delegue a coleta ao subagente `diagnosticador` (ou `mecanico:diagnosticador`) e a visão estrutural ao `arquiteto-de-sistemas`.

## Roteiro

### 1. Inventário

```bash
${CLAUDE_SKILL_DIR}/../detectar-stack/scripts/detectar-stack.sh .
```

Anote os comandos reais do projeto conferindo a pipeline de CI, o README e os scripts do manifesto. Em sistemas com várias unidades, repita os passos seguintes por unidade (ou amostre as mais alteradas e diga que amostrou).

### 2. Sinais vitais

Rode, nesta ordem, e guarde a saída relevante:

1. **Instalação de dependências** com lockfile travado (`npm ci`, `poetry install`, `go mod download`…). Falha aqui já é achado crítico.
2. **Build / compilação / checagem de tipos.**
3. **Testes.** Registre total, falhas, ignorados e tempo. Teste ignorado (`skip`, `xit`, `@Disabled`, `@Ignore`) é dívida escondida: conte-os.
4. **Lint** com a configuração do projeto. Não imponha regras que o projeto não adotou.

Se algo não puder rodar (falta runtime, serviço externo, segredo), registre como "não verificado" com o motivo — não como "ok".

### 3. Segurança e dependências

- Auditoria do ecossistema: `npm audit`, `pip-audit`, `cargo audit`, `govulncheck ./...`, `composer audit`, `bundle audit`, `dotnet list package --vulnerable`. A skill `dependencias` detalha como interpretar.
- Segredos versionados: `gitleaks detect` se disponível; senão `rg -ni "(api[_-]?key|secret|passwd|password|token)\s*[:=]\s*.{8,}" -g '!*.lock'` e arquivos `.env` versionados (`git ls-files | rg '\.env'`). Relate local e tipo, nunca o valor.
- Análise estática multi-linguagem, se instalada: `semgrep scan --config auto --error` (envia metadados do projeto ao registro de regras — em código confidencial, use regras locais).
- Infraestrutura: `hadolint` para Dockerfiles, `trivy fs .` ou `trivy config .` quando disponíveis.

A skill `ferramentas` mostra o que está instalado e como obter o que falta.

### 4. Pontos frágeis

- **Arquivos quentes**: os mais alterados no histórico (o script do passo 1 lista). Muito alterado + grande + sem teste = onde o próximo bug vai nascer.
- **Marcadores de dívida**: `rg -n 'TODO|FIXME|HACK|XXX|@deprecated' --stats`.
- **Tratamento de erro suspeito**: `catch` vazio, `except: pass`, erros ignorados (`_ = err`), `unwrap()` em caminho de produção.
- **Tamanho e complexidade**: arquivos e funções gigantes (`cloc`, ou `wc -l` nos maiores).
- **Código morto e duplicado**: exportações sem uso, dependências declaradas e não importadas (`knip`, `depcheck`, `vulture`, `deadcode`, conforme a stack).
- **Configuração**: valores de ambiente fixos no código, diferenças entre ambientes, padrões inseguros (debug ligado, CORS `*`, TLS desativado).
- **Operação**: há logs estruturados, health check, tratamento de timeout em chamadas externas, migrações reversíveis?

### 5. Cobertura da rede de segurança

Onde há testes e onde não há. Se o projeto mede cobertura, use o número dele; senão, compare a árvore de testes com a de código e aponte os módulos críticos descobertos (pagamento, autenticação, cálculo, migração de dados).

## Classificação

| Gravidade | Significado | Exemplos |
|---|---|---|
| **Crítica** | Quebrado agora ou explorável | build falha, teste do fluxo principal falha, segredo exposto, CVE crítica alcançável |
| **Alta** | Vai quebrar ou causar incidente | corrida em dado financeiro, falta de timeout em chamada externa, migração irreversível |
| **Média** | Atrapalha a manutenção | sem testes em módulo central, dependência principal sem suporte, duplicação extensa |
| **Baixa** | Higiene | lint, TODOs antigos, código morto |

## Relatório

```
# Diagnóstico — <projeto> — <data>

## Resumo
Estado geral em três linhas. Stack e arquitetura em uma.

## Sinais vitais
| Verificação | Resultado | Detalhe |
| Instalação | ok/falha/não verificado | … |
| Build | … | … |
| Testes | N passam, N falham, N ignorados | … |
| Lint | … | … |
| Auditoria de dependências | N críticas, N altas | … |

## Achados
### Críticos
- [C1] Título — arquivo:linha — evidência (comando/saída) — correção sugerida — esforço (P/M/G)
### Altos / Médios / Baixos
…

## Plano recomendado
Ordem de ataque, o que pode ser feito já e o que precisa de decisão.

## Não verificado
O que não foi possível rodar ou analisar, e por quê.
```

Termine oferecendo o próximo passo: corrigir os críticos com a skill `manutencao`.
