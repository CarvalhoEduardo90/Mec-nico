---
name: monolito
description: Conhecimento de manutenção para aplicações monolíticas e código legado — localizar onde mexer em base grande, lidar com acoplamento e efeitos colaterais ocultos, mudar código sem testes com segurança, transações e esquema de banco compartilhado, jobs e agendamentos, modularização e extração gradual de serviços. Use ao diagnosticar, corrigir ou refatorar em monólito (Rails, Django, Laravel, Spring, ASP.NET, Java EE, PHP legado) ou em qualquer base grande e antiga em que uma mudança pode quebrar algo distante.
---

# Manutenção de monólitos

O monólito tem uma vantagem enorme para manutenção — tudo roda em um processo, com uma transação e um stack trace completo — e um risco característico: **acoplamento invisível**. A função que você altera é chamada de lugares que você não conhece; a tabela que você muda é lida por um relatório esquecido; o callback do modelo dispara um e-mail. O método aqui é tornar o acoplamento visível antes de mexer.

## 1. Achar o lugar certo

Em base grande, não leia de cima para baixo. Entre por uma âncora e siga o fio:

- **Pelo que o usuário vê**: texto da tela ou da mensagem de erro → `rg "texto"` → template/arquivo de tradução → controller → serviço → modelo.
- **Pela URL**: tabela de rotas (`route:list`, `rails routes`, `/actuator/mappings`, `urls.py`) → handler.
- **Pelo dado**: nome da tabela/coluna → modelo/entidade → quem grava (`rg "campo\s*="`, setters, SQL bruto).
- **Pelo erro**: stack trace → primeiro frame do projeto.
- **Pelo histórico**: `git log -S"termo"` e `git log --follow -- arquivo` mostram quando e por que aquilo entrou; mensagens de commit e PRs antigos são a documentação que sobrou.

Identifique as camadas que este monólito usa (controller → serviço → repositório? MVC com modelo gordo? procedures no banco?) e em qual delas vivem as regras de negócio. A correção pertence à camada dona da regra.

## 2. Medir o raio de impacto

Antes de alterar uma função, classe, tabela ou configuração, liste quem depende dela. A busca textual não basta em monólitos — procure também os acoplamentos que não aparecem em "encontrar referências":

| Acoplamento oculto | Onde procurar |
|---|---|
| Callbacks, hooks e eventos do ORM | `before_save`/`after_commit` (Rails), signals (Django), observers/eventos de modelo (Laravel), listeners JPA, triggers de domínio |
| Triggers, views e procedures no banco | catálogo do banco; migrações antigas |
| Reflexão, metaprogramação, nomes montados em string | `send`, `method_missing`, `getattr`, `Class.forName`, `call_user_func`, `eval`; busque pelo **pedaço** do nome |
| Injeção de dependência e autoconfiguração | anotações, arquivos de contexto, convenções de nome |
| AOP, interceptors, middleware, filtros globais | configuração do framework |
| Configuração e feature flags | arquivos de config, tabela de flags, variáveis de ambiente |
| Estado global | singletons, variáveis estáticas, cache de processo, thread-locals |
| Outros leitores da mesma tabela | relatórios, ETL, BI, jobs noturnos, scripts de operação, outros sistemas com acesso direto ao banco |
| Serialização | o nome da classe/campo está gravado em fila, cache, sessão ou coluna JSON? Renomear quebra dados já gravados |
| Templates e frontend | campos acessados em views, JS que consome o JSON |

Rode os testes **antes** de mudar: é a sua linha de base.

## 3. Mudar código sem testes

Código sem teste é o caso normal em legado. Não é motivo para mudar às cegas, nem para reescrever tudo:

1. **Teste de caracterização**: escreva um teste que registra o que o código faz *hoje* para as entradas relevantes — inclusive comportamentos estranhos. Ele não diz o que é certo; avisa quando algo mudou.
2. **Ache uma costura**: um ponto onde dá para trocar a dependência difícil (banco, relógio, rede, sistema de arquivos, singleton) sem alterar a lógica — parâmetro, construtor, método sobrescrito em subclasse de teste, variável de configuração.
3. **Extraia o miolo**: quando a regra está enterrada num método de 500 linhas com I/O misturado, extraia a decisão pura para uma função testável, com mudanças mecânicas e pequenas. Extrair e mudar comportamento são alterações separadas.
4. **Teste em nível mais alto quando o código não se deixa isolar**: um teste de integração da rota ou do job, com banco de teste, protege a refatoração inicial. *Golden master* (gravar a saída completa e comparar) funciona para relatórios, cálculos e geração de arquivos.
5. **Só então corrija**, com o teste do bug.

Regra do escoteiro com moderação: deixe o trecho tocado um pouco melhor (um nome, um teste), mas não transforme a correção de um bug em reforma.

## 4. Banco de dados compartilhado

No monólito, o banco é o ponto de integração de tudo.

- **Transações**: saiba onde começa e termina a transação do fluxo que está alterando (por requisição? por método anotado? manual?). Bugs clássicos: efeito externo (e-mail, chamada HTTP, mensagem em fila) disparado dentro da transação que depois faz rollback; job enfileirado antes do commit; transação longa por causa de I/O no meio; em Spring/.NET, anotação transacional que não vale em chamada interna.
- **Migrações**: expandir → migrar → contrair, mesmo sendo um único sistema — durante o deploy, a versão antiga e a nova rodam juntas. Operações que travam tabela grande (adicionar coluna com valor padrão em bancos antigos, criar índice sem a opção concorrente, alterar tipo) precisam de plano. Toda migração com caminho de volta.
- **Integridade**: regra garantida só no código da aplicação é violada por scripts, importações e condições de corrida. Restrições no banco (única, chave estrangeira, `NOT NULL`, `CHECK`) são a defesa final — mas adicioná-las exige limpar antes os dados que já as violam.
- **Dados antigos**: consulte a produção (ou cópia anonimizada) para saber se os dados reais obedecem ao que o código assume: `SELECT campo, COUNT(*) … GROUP BY campo` revela os casos esquecidos.
- **Lógica no banco**: procedures e triggers fazem parte do sistema; versione-as antes de alterar.

## 5. Processos além da requisição web

O monólito costuma ter mais de um ponto de entrada compartilhando o mesmo código: workers de fila, cron/agendador, comandos de console, importações em lote, consumidores de webhook. Uma mudança no modelo afeta todos. Pergunte sempre: este código também roda fora da requisição web? Lá existe usuário autenticado, tenant corrente, fuso, locale?

## 6. Desempenho típico

- N+1 e carregamento de coleções inteiras em memória (processe em lotes/cursor).
- Trabalho pesado dentro da requisição que deveria ir para fila.
- Inicialização lenta e consumo de memória por carregar tudo; cache de processo que diverge entre instâncias.
- Um endpoint lento que esgota o pool de threads/conexões e derruba todo o resto: no monólito não há isolamento de falha, então limites e timeouts por operação importam.

## 7. Modularizar e extrair — quando a manutenção pede

Problema estrutural recorrente (todo bug naquele módulo vem do mesmo emaranhado) justifica propor reorganização, de forma incremental:

- **Monólito modular primeiro**: fronteiras internas explícitas (pacotes/módulos com interface pública pequena, dependências em uma direção só, sem acesso às tabelas alheias). Dá a maior parte do benefício sem custo de sistema distribuído. Ferramentas de verificação de fronteira: ArchUnit, Packwerk, `import-linter`, `dependency-cruiser`, Deptrac, regras do Nx.
- **Estrangulamento (strangler fig)**: o novo cresce ao lado do velho atrás de uma fachada/roteador que desvia uma funcionalidade por vez; o velho só sai quando o tráfego dele chega a zero.
- **Ramificação por abstração**: introduza uma interface na frente da implementação antiga, crie a nova atrás da mesma interface, alterne por flag, remova a antiga.
- **Execução em paralelo**: rode as duas implementações e compare resultados antes de trocar.
- **Extraia serviço só com motivo concreto** (escala, ritmo de deploy ou time independentes, isolamento de falha) e só depois de a fronteira estar limpa *dentro* do monólito, incluindo os dados. Extrair cedo transforma chamada de função em chamada de rede e transação local em problema de consistência — veja a skill `microservicos`.

Reescrever do zero quase nunca é a resposta: o código antigo carrega anos de correções de casos reais que ninguém mais lembra.

## Lista antes de entregar uma mudança em monólito

- [ ] Sei quem mais chama/lê o que alterei (incluindo callbacks, jobs, relatórios e banco)?
- [ ] Há teste cobrindo o comportamento antes e depois?
- [ ] A migração convive com a versão anterior do código e tem volta?
- [ ] Efeitos externos acontecem depois do commit da transação?
- [ ] A mudança vale também para os caminhos fora da web (fila, cron, console)?
- [ ] Mudei nome de classe/campo que está serializado em algum lugar?
- [ ] A suíte completa passou, não só os testes do módulo?
