---
name: corrigir
description: Protocolo de correção de defeitos — reproduzir, isolar, escrever o teste que falha, corrigir a causa raiz com a menor mudança, verificar. Use para qualquer correção de bug, teste falhando, erro de build, exceção, regressão ou "isto não funciona", em qualquer linguagem. Também serve de guia quando uma correção anterior não resolveu.
argument-hint: "[erro, stack trace, teste ou descrição do bug]"
---

# Corrigir um defeito

Defeito: $ARGUMENTS

Uma correção está pronta quando a falha está demonstrada, a causa está explicada, a mudança é a menor que elimina a causa e existe prova de que funciona. O protocolo abaixo existe porque cada passo pulado tem um modo de falha conhecido.

## 1. Reproduzir

Chegue a **um comando** que mostra a falha: um teste, um script, uma requisição `curl`, uma sequência de passos.

- Use os comandos do projeto (veja CI, README, manifesto). Em repositório desconhecido, rode antes o script da skill `detectar-stack`.
- Reduza: menor entrada, menor caminho, menos dependências externas.
- Falha intermitente: rode em laço e meça a taxa (`for i in $(seq 50); do <cmd> || echo FALHOU; done`). Uma correção de falha intermitente só se prova com taxa antes e depois.
- Não reproduz? Compare ambientes (versões, configuração, dados, fuso, locale) antes de concluir que "funciona aqui". Se continuar impossível, diga claramente que a correção será baseada em análise, não em reprodução.

*Sem reprodução, você não sabe se consertou.*

## 2. Isolar a causa

| Situação | Técnica |
|---|---|
| Stack trace | Primeiro frame do projeto; siga o dado errado para trás até onde ele nasce |
| "Funcionava antes" | `git log -p -- <caminho>`, `git blame`, `git bisect run <comando de teste>` |
| Resultado errado | Imprima/inspecione estados intermediários; divida o caminho ao meio |
| Só com certa entrada | Diferença mínima entre a entrada que funciona e a que falha |
| Só em produção | Diferenças de ambiente, volume de dados, concorrência, cache, versão implantada |
| Erro de build | O **primeiro** erro; versão do runtime; lockfile; cache limpo |
| Erro em dependência | Leia o código da dependência na versão instalada, não a documentação da última |

Formule a causa como mecanismo: "quando A, o código faz B, mas deveria fazer C, porque D". Se não consegue escrever essa frase, ainda não achou.

Pergunte um nível acima: por que isso foi possível? O ponto onde o erro aparece (o `null` que estoura) raramente é onde ele nasce (quem deixou o `null` chegar ali).

## 3. Teste que falha

Escreva o teste antes da correção, no estilo e no local que o projeto usa.

- Deve falhar **pelo motivo do bug** — leia a mensagem de falha e confirme.
- Deve afirmar o comportamento correto, não a implementação.
- Nomeie pelo comportamento: `rejeita_pedido_com_quantidade_zero`, não `teste_bug_1234`.
- Código sem nenhum teste: escreva primeiro um teste de caracterização do comportamento atual ao redor do ponto, depois o teste do bug. Se nem framework de teste existe, um script de verificação reproduzível vale mais que nada — e diga que foi isso.

## 4. Corrigir

- Mude onde a causa está. Corrigir no ponto do sintoma (um `if (x != null)` a mais) deixa a causa viva para estourar em outro lugar.
- A menor mudança que resolve. Refatoração, renomeação e formatação não entram na mesma alteração.
- Siga o padrão do código vizinho para erros, logs, nomes e estrutura.
- Procure as irmãs: o mesmo defeito em código copiado ou análogo (`rg`, `ast-grep`). Corrija-as ou liste-as.
- Considere quem depende do comportamento antigo — às vezes o bug virou contrato para algum chamador.

## 5. Verificar

1. O teste novo passa.
2. A suíte do módulo passa; depois a suíte completa, se o tempo permitir.
3. Build, tipos e lint passam.
4. O comando de reprodução do passo 1 agora mostra o comportamento certo.
5. Releia o `git diff` completo: nada de depuração esquecida, nada fora do escopo.

Se a verificação falhar, volte ao passo 2 com a nova informação. Não empilhe remendos sobre uma hipótese que os fatos já derrubaram. Depois de três tentativas sem sucesso, pare, escreva o que foi tentado e aprendido, e reavalie o diagnóstico — o problema costuma ser a premissa.

## Atalhos que criam o próximo bug

- Desativar, apagar ou afrouxar o teste que falha.
- `try/catch` que engole o erro; `|| true`; código de saída ignorado.
- `any`, `@ts-ignore`, `# type: ignore`, `// nolint`, `@SuppressWarnings` para calar o compilador.
- `sleep`/aumento de timeout para "resolver" condição de corrida.
- Valor fixo que só satisfaz o caso do teste.
- Atualizar snapshot sem ler a diferença.
- `--no-verify`, `--force`, `-DskipTests` para passar da barreira.

Qualquer um deles só é aceitável com justificativa explícita no relato.

## Relato

Problema e causa (arquivo:linha) · o que mudou · teste de regressão · comandos de verificação e resultados · irmãs do defeito encontradas · riscos e pendências.

Para revisão independente antes de entregar, use o subagente `revisor-de-correcao` (ou `mecanico:revisor-de-correcao`).
