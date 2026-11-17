---
name: manutencao
description: Fluxo completo de manutenção de código — entender o problema, diagnosticar a causa raiz, corrigir, verificar e relatar — em qualquer linguagem ou stack. Use quando pedirem para "dar manutenção", "analisar e corrigir", "consertar o que está quebrado", "arrumar este projeto", "fix this", ou quando houver um problema relatado sem causa conhecida.
argument-hint: "[descrição do problema | caminho | vazio para revisão geral]"
---

# Manutenção: do sintoma à correção verificada

Pedido: $ARGUMENTS

Você coordena a oficina. O trabalho passa por cinco etapas; pular uma delas é a origem mais comum de correção que não corrige. Ajuste a profundidade ao tamanho do problema — um erro de digitação não precisa de subagentes; uma falha intermitente em produção precisa de todas as etapas.

Os subagentes e skills deste kit podem aparecer com o prefixo `mecanico:` (instalação como plugin) ou sem prefixo (copiados para `.claude/`). Use o nome que estiver disponível.

## 1. Reconhecer o terreno

Antes de qualquer coisa, saiba onde está pisando:

```bash
${CLAUDE_SKILL_DIR}/../detectar-stack/scripts/detectar-stack.sh .
```

O script mostra linguagens, gerenciadores, frameworks, comandos prováveis de build/teste, infraestrutura e a arquitetura provável. Leia também README, CLAUDE.md e a pipeline de CI — eles dizem como *este* projeto se constrói e se testa. Confira `git status`: se houver alterações não commitadas, preserve-as.

## 2. Definir o problema

Com um pedido específico: reformule em uma frase o comportamento esperado e o observado. Se faltar informação que só o usuário tem (qual é o comportamento certo? em que ambiente?), pergunte uma vez, de forma objetiva, e siga com o que não depende da resposta.

Sem pedido específico ("geral", vazio): use a skill `diagnostico` para levantar a saúde do repositório, apresente os achados por gravidade e corrija, nesta ordem: build quebrado → testes falhando → vulnerabilidades críticas → bugs evidentes. Não saia refatorando por conta própria: melhoria que ninguém pediu fica como recomendação.

## 3. Diagnosticar

Delegue ao subagente `diagnosticador` quando a causa não for evidente. Passe o sintoma, como reproduzir (se souber) e o que já foi descartado. Em paralelo, quando fizer sentido:

- `arquiteto-de-sistemas` — o problema atravessa camadas ou serviços, ou você precisa saber o que a mudança pode quebrar.
- `engenheiro-reverso` — parte do comportamento está em binário, app compilado, bundle minificado ou API sem documentação.

Conhecimento de domínio para carregar conforme o caso: skills `web`, `monolito`, `microservicos`, `dependencias`, `engenharia-reversa`.

Só avance com uma causa raiz sustentada por evidência. "Provavelmente é X" não é diagnóstico — é hipótese a testar.

## 4. Corrigir

Delegue ao subagente `reparador` com o diagnóstico completo, ou siga você mesmo a skill `corrigir` em correções pequenas. Em ambos os casos vale o protocolo: reproduzir → teste que falha → mudança mínima na causa raiz → verificação com os comandos do projeto.

Se houver vários defeitos independentes, corrija um de cada vez, cada um com seu teste. Correções misturadas não se deixam revisar nem reverter.

## 5. Verificar

Para qualquer mudança que não seja trivial, peça uma revisão independente ao subagente `revisor-de-correcao`: passe o que foi mudado e o defeito original, e deixe que ele leia o diff. Trate bloqueios apontados antes de declarar pronto; se discordar de um bloqueio, explique o motivo ao usuário em vez de ignorá-lo.

A verificação mínima, com ou sem revisor: o teste de regressão passa, a suíte relevante passa, build e lint passam.

## 6. Relatar

Entregue ao usuário, em linguagem direta:

- **Problema** — o que estava errado e a causa raiz (arquivo:linha).
- **Correção** — o que foi alterado e por quê.
- **Verificação** — comandos rodados e resultados; veredito do revisor, se houve.
- **Pendências** — o que não foi verificado, riscos, falhas pré-existentes não relacionadas, recomendações de acompanhamento.

Seja fiel ao que aconteceu: se um teste continua falhando, se algo não pôde ser reproduzido, se uma etapa foi pulada, diga.

## Regras da oficina

- Commit, push e pull request só quando o usuário pedir.
- Nada destrutivo nem contra produção sem confirmação explícita: migrações, exclusão de dados, `force push`, deploy.
- Não desative testes nem suprima erros para "fazer passar".
- Segredos encontrados no código são um achado a relatar (sem reproduzir o valor), com recomendação de rotação.
