# Código legado: recuperar o entendimento de um sistema que tem fonte, mas não tem dono

Existe código-fonte, mas ninguém mais sabe como funciona, a documentação sumiu ou mente, e talvez ele nem compile. O objetivo é reconstruir o conhecimento — arquitetura, regras de negócio, dados — a ponto de permitir manutenção ou migração segura.

## Índice
- [Princípios](#princípios)
- [1. Arqueologia: o que existe e o que roda](#1-arqueologia-o-que-existe-e-o-que-roda)
- [2. Fazer compilar e executar](#2-fazer-compilar-e-executar)
- [3. Mapa estrutural](#3-mapa-estrutural)
- [4. O modelo de dados primeiro](#4-o-modelo-de-dados-primeiro)
- [5. Seguir fluxos de ponta a ponta](#5-seguir-fluxos-de-ponta-a-ponta)
- [6. Extrair regras de negócio](#6-extrair-regras-de-negócio)
- [7. Observar em execução](#7-observar-em-execução)
- [8. Fixar o comportamento com testes](#8-fixar-o-comportamento-com-testes)
- [9. Documentar](#9-documentar)
- [Código morto](#código-morto)
- [Quando o objetivo é migrar](#quando-o-objetivo-é-migrar)

## Princípios

- **O código em produção é a especificação.** Comentários, documentos e nomes de variáveis são pistas; o comportamento é o fato.
- **Comportamento estranho pode ser requisito.** Antes de "corrigir" uma esquisitice, descubra se alguém depende dela (o histórico e os dados costumam dizer).
- **Não reescreva para entender.** Leia, execute, observe, teste — nessa ordem. A vontade de reescrever é maior quanto menos se entende.
- **Escreva enquanto descobre.** O entendimento que fica só na cabeça se perde de novo.

## 1. Arqueologia: o que existe e o que roda

1. **Inventário**: rode o detector da skill `detectar-stack`; liste diretórios de primeiro nível com tamanho e data da última alteração.
2. **O que está em produção, de fato**: qual branch/tag/pacote está implantado? O repositório corresponde ao que roda? (Em legado, é comum haver correção feita direto no servidor — compare, se possível, o artefato implantado com o build do repositório.)
3. **Pontos de entrada reais**: configuração do servidor web/aplicação (virtual hosts, `web.xml`, `Procfile`, unidades systemd), `crontab`, agendadores, scripts de inicialização, jobs do banco, filas.
4. **Histórico**: `git log --format='%ad %an %s' --date=short | head -n 50` e `| tail -n 50`; `git shortlog -sn` (quem sabia); os arquivos mais alterados; as mensagens dos commits grandes. Sem git: datas de arquivo, cabeçalhos de comentário, nomes como `_old`, `_bkp`, `_v2`, `novo_`.
5. **Documentos e pistas periféricas**: wiki, tickets antigos referenciados em comentários, manuais do usuário (descrevem regras de negócio do ponto de vista de quem usa), scripts de implantação, planilhas de teste.
6. **Pessoas**: se o usuário tem acesso a quem usa ou operou o sistema, uma lista curta de perguntas objetivas economiza dias. Sugira as perguntas.

## 2. Fazer compilar e executar

Um sistema que roda localmente pode ser observado e testado; vale o investimento.

- **Fixe o ambiente antigo em um container**: a versão do runtime/compilador da época (imagens antigas de `php:5.6`, `node:8`, `python:2.7`, `openjdk:8`, `mono`…), em vez de adaptar o código ao ambiente novo. Adaptar é mudar, e ainda não há testes.
- **Descubra as versões** pelo lockfile, por arquivos de versão, pela sintaxe usada, pelos cabeçalhos dos artefatos compilados, pela data do último commit.
- **Dependências desaparecidas**: procure cópias vendorizadas, caches de build, o servidor de produção, espelhos e arquivos públicos. Registre tudo o que precisou ser obtido fora do repositório.
- **Banco**: esquema a partir das migrações ou de um dump só de estrutura; dados sintéticos ou anonimizados.
- **Serviços externos**: simule (WireMock, servidor falso mínimo) — as chamadas feitas mostram o contrato esperado.
- **Registre o procedimento** em um `Dockerfile`/`docker-compose.yml` e um README: é o primeiro entregável.

Se não der para executar (hardware específico, mainframe, licença de compilador), siga com análise estática e deixe isso explícito — as conclusões terão confiança menor.

## 3. Mapa estrutural

```bash
cloc . --by-file --quiet | sort -k5 -n -r | head -n 30        # onde está o volume
ctags -R --fields=+n -f tags .                                # índice de símbolos (dezenas de linguagens)
git ls-files | xargs wc -l | sort -rn | head -n 30                # arquivos maiores, sem cloc
```

Grafo de dependências entre módulos, conforme a linguagem: `madge --image grafo.svg src/` (JS/TS) · `pydeps pacote` ou `pyan3` (Python) · `jdeps -summary -recursive app.jar` (JVM) · `go list -deps ./...` e `go-callvis` (Go) · `cargo modules` (Rust) · `deptrac`/`pdepend` (PHP) · Doxygen com `CALL_GRAPH = YES` e Graphviz (C/C++ e outras) · NDepend ou os grafos do Visual Studio (.NET).

O que extrair do mapa:
- **Camadas e direção das dependências** (interface → regras → dados?) e onde a direção é violada.
- **Módulos centrais** (muito referenciados): mudanças ali têm raio de impacto máximo.
- **Ciclos**: grupos de módulos que só se entendem juntos.
- **Código copiado**: `jscpd .` ou `simian` — cópias divergentes de uma mesma regra são fonte de bugs e de dúvida sobre qual é a correta.
- **Fronteiras com o exterior**: banco, arquivos, rede, outros sistemas, impressão, e-mail.

## 4. O modelo de dados primeiro

Os dados sobrevivem ao código e mudam menos; entendê-los dá o vocabulário do domínio. Siga o roteiro "Banco de dados sem documentação" em [rede-e-apis.md](rede-e-apis.md). Em sistemas antigos, o "banco" também pode ser: arquivos de registro de tamanho fixo (os *copybooks* COBOL e as declarações de `struct`/`record` são o esquema), arquivos indexados (ISAM, DBF, Paradox, Btrieve), planilhas, ou layouts posicionais de troca de arquivos (CNAB, EDI) — aqui o manual do layout, quando existe, é documentação de verdade.

Monte um glossário: termo do domínio ↔ tabela/campo ↔ nome no código. Abreviações de legado (`VL_TOT_LIQ`, `fl_atv`, `dt_ult_mov`) deixam de ser ruído quando traduzidas uma vez.

## 5. Seguir fluxos de ponta a ponta

Escolha os dois ou três casos de uso mais importantes para o objetivo e acompanhe cada um da entrada até a persistência e a saída, anotando arquivo:linha em cada salto. Âncoras de entrada: o texto de um botão ou de uma mensagem, o nome de uma tela, uma URL, o nome de um arquivo gerado, o nome de um job.

Atenção ao que não aparece numa leitura linear:
- **Despacho indireto**: tabelas de funções, reflexão, nomes de classe ou de procedimento montados em string, `eval`, includes dinâmicos, fábricas configuradas em XML.
- **Estado global** alterado em um ponto e lido em outro (variáveis globais, sessão, singletons, áreas comuns).
- **Efeitos por gatilho**: triggers do banco, eventos, callbacks de framework.
- **Fluxo guiado por dados**: tabelas de parâmetros e de configuração que mudam o comportamento sem mudar o código — leia os *dados* dessas tabelas.
- **Tratamento de erro que muda o fluxo**: `ON ERROR RESUME NEXT`, `catch` vazio, códigos de retorno ignorados, `GOTO`.

Desenhe cada fluxo como diagrama de sequência (Mermaid).

## 6. Extrair regras de negócio

Regras se escondem em:

| Onde | Como achar |
|---|---|
| Condicionais com números e textos fixos | `rg -n "if .*[=<>]=? *[0-9]{2,}"`; constantes nomeadas; `switch` sobre tipo/status |
| Cálculos | operações aritméticas sobre campos monetários, percentuais, datas; arredondamentos |
| Validações | mensagens de erro (cada mensagem corresponde a uma regra) |
| Consultas | cláusulas `WHERE` fixas (`status <> 9 AND dt_canc IS NULL`) definem o que "conta" |
| Datas fixas no código | `if data >= '2019-07-01'` → mudança de regra com vigência (legal, comercial) |
| Exceções por cliente/filial | `if cliente_id in (…)` → acordos especiais |
| Procedimentos e gatilhos | regras impostas pelo banco |
| Tabelas de parâmetros | regras configuráveis: os dados atuais são a regra vigente |
| Relatórios | a definição de cada total é uma regra |

Para cada regra, registre: enunciado em linguagem de negócio, condição, ação, local (arquivo:linha), exemplo com números, e confiança (OBSERVADO no código / CONFIRMADO em execução / INFERIDO). Regras duplicadas em mais de um lugar com diferenças: registre todas as versões e marque a divergência — decidir qual é a correta cabe ao dono do negócio.

## 7. Observar em execução

- **Depurador** nos pontos de entrada dos fluxos escolhidos.
- **Rastreamento sem alterar o código**: log de consultas do banco (mostra exatamente o que cada tela lê e grava), `strace`/`ltrace`, log de acesso do servidor web, Xdebug/trace (PHP), `-verbose:class` e agentes (JVM), `sys.settrace`/`python -m trace --trace`, `ruby -rtracer`.
- **Cobertura como mapa**: execute um caso de uso com a ferramenta de cobertura ligada; as linhas executadas *são* a implementação daquele caso de uso.
- **Comparação de estado**: fotografe o banco (ou as tabelas relevantes) antes e depois de uma operação e compare — revela todos os efeitos, inclusive os de gatilhos.
- **Logs de produção** (se disponíveis): quais telas, relatórios e jobs são realmente usados, com que frequência e por quem.

## 8. Fixar o comportamento com testes

Antes de qualquer alteração:

- **Testes de caracterização**: para cada regra extraída, um teste que afirma o que o sistema faz hoje.
- **Golden master**: para relatórios, arquivos gerados e cálculos em lote, guarde a saída completa para um conjunto de entradas e compare a cada mudança. Normalize o que varia (datas, IDs gerados).
- **Testes na fronteira mais externa disponível** (HTTP, linha de comando, arquivo de entrada → arquivo de saída) quando o interior não é testável.
- **Dados de teste** derivados de casos reais (anonimizados), incluindo os casos esquisitos encontrados nos dados.

Esses testes são, também, a especificação executável para uma eventual migração.

## 9. Documentar

Conjunto mínimo que paga o esforço, em arquivos versionados junto ao código (`docs/`):

1. **Como construir e executar** — reprodutível (container).
2. **Visão de arquitetura** — componentes, pontos de entrada, integrações, diagrama.
3. **Modelo de dados** — diagrama e dicionário.
4. **Fluxos principais** — diagramas de sequência com referências ao código.
5. **Catálogo de regras de negócio** — com local e confiança.
6. **Glossário** do domínio e das abreviações.
7. **Riscos e armadilhas** — o que surpreende, o que é frágil, o que não tem teste.
8. **Perguntas em aberto** — para quem conhece o negócio.

Marque sempre o grau de certeza. Uma documentação que afirma com segurança algo errado é pior que a ausência dela — foi assim que a anterior se perdeu.

## Código morto

Remover o que não é usado reduz o que precisa ser entendido, mas em legado "não é referenciado" não significa "não é usado":

- Evidência de uso **em execução** vale mais que análise estática: logs de acesso, cobertura em produção, contadores, logs de consulta.
- Procure chamadas indiretas (nomes em strings, configuração, banco, agendadores, outros sistemas) antes de concluir.
- Jobs anuais (fechamento, imposto, virada de ano) passam onze meses parecendo mortos.
- Remoção em etapas: registrar uso (log) → esperar um ciclo completo do negócio → desativar → remover.

## Quando o objetivo é migrar

- Migre comportamento, não código: os testes de caracterização e o catálogo de regras são o contrato.
- Incremental sempre que possível (estrangulamento: o novo assume uma funcionalidade por vez atrás de uma fachada) — ver a skill `monolito`.
- Execute o velho e o novo em paralelo sobre as mesmas entradas e compare as saídas antes de desligar o velho.
- Migração de dados é projeto próprio: mapeamento campo a campo, tratamento dos dados que violam as regras novas, ensaios repetidos e conferência de totais.
- Liste explicitamente o que **não** será migrado e obtenha a concordância do dono do negócio.
