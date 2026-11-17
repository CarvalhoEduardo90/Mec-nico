# Backend e APIs: diagnóstico e correção

## Índice
- [Seguir uma requisição](#seguir-uma-requisição)
- [Rotas, middleware e serialização](#rotas-middleware-e-serialização)
- [Autenticação e sessão](#autenticação-e-sessão)
- [Banco de dados e ORM](#banco-de-dados-e-orm)
- [Concorrência e consistência](#concorrência-e-consistência)
- [Chamadas externas](#chamadas-externas)
- [Cache](#cache)
- [Trabalho assíncrono e agendado](#trabalho-assíncrono-e-agendado)
- [Uploads, streaming e tempo real](#uploads-streaming-e-tempo-real)
- [Desempenho e recursos](#desempenho-e-recursos)
- [Evolução de API](#evolução-de-api)
- [GraphQL](#graphql)
- [Configuração e ambiente](#configuração-e-ambiente)
- [Observabilidade mínima](#observabilidade-mínima)
- [Testes](#testes)

## Seguir uma requisição

1. Ache a rota: liste as rotas registradas (`php artisan route:list`, `bin/rails routes`, `/actuator/mappings`, `flask routes`, `python manage.py show_urls`, ou busque o caminho no código).
2. Liste o que roda antes do handler, na ordem: middleware, filtros, guards, interceptors, validação. Muito "bug do endpoint" está aqui.
3. No handler, acompanhe: entrada → validação → regra de negócio → persistência → efeitos colaterais (e-mail, evento, cache) → resposta.
4. Ache o log daquela requisição pelo ID de correlação (`X-Request-Id`, `traceparent`). Se não existe ID, o primeiro conserto é criá-lo.

## Rotas, middleware e serialização

- **Ordem importa**: rota genérica antes da específica (`/users/:id` capturando `/users/me`); middleware de autenticação depois do handler; parser de corpo ausente ou com limite baixo.
- **Corpo vazio no handler**: `Content-Type` não corresponde ao parser; corpo já consumido por outro middleware.
- **Serialização**: datas sem fuso; `BigInt`/decimais convertidos para ponto flutuante (dinheiro em `float` é bug esperando acontecer — use inteiros de centavos ou decimal); campos nulos × ausentes; referências circulares; enum renomeado quebrando clientes; diferença `snake_case` × `camelCase`.
- **Erros**: formato de erro inconsistente entre endpoints; exceção virando 500 quando deveria ser 4xx; stack trace vazando ao cliente; erro assíncrono não capturado derrubando o processo (Node: promessa rejeitada sem tratamento).
- **Validação**: valide na borda com esquema (Zod, Pydantic, Bean Validation, FluentValidation) e confie no tipo dali para dentro; rejeite campos desconhecidos em operações de escrita (atribuição em massa).

## Autenticação e sessão

- **Sessão em cookie**: precisa de armazenamento compartilhado (Redis/banco) com várias instâncias; atributos `HttpOnly`, `Secure`, `SameSite`, `Domain`, `Path` corretos; atrás de proxy TLS a aplicação precisa confiar em `X-Forwarded-Proto` para emitir cookie `Secure`.
- **JWT**: valide assinatura, algoritmo (rejeite `none`; não aceite o algoritmo que o token declara sem lista permitida), `exp`, `iss`, `aud`; tolere pequeno desvio de relógio; chaves em rotação (JWKS com cache e recarga quando o `kid` é desconhecido). JWT não se revoga sozinho: expiração curta + refresh token com rotação.
- **OAuth/OIDC**: URI de redirecionamento exata; `state` e PKCE; escopos; troca de código no servidor; relógio do servidor.
- **"Desloga sozinho"**: expiração do token sem renovação; refresh concorrente em várias abas invalidando um ao outro; cookie perdido em subdomínio/`SameSite`; segredo de assinatura diferente entre instâncias ou regenerado a cada deploy.
- **Autorização**: verificada no servidor em toda rota, incluindo o recurso específico (o usuário pode acessar *este* registro?). Veja a referência de segurança.

## Banco de dados e ORM

- **N+1**: uma consulta por item da lista. Ligue o log de SQL e conte consultas por requisição; corrija com carregamento antecipado (`include`/`joinedload`/`with`/`JOIN FETCH`/`Include`) ou agregação.
- **Consulta lenta**: `EXPLAIN (ANALYZE)`; índice ausente; função sobre a coluna indexada; tipo do parâmetro diferente do tipo da coluna; `OFFSET` alto (prefira paginação por cursor); `SELECT *` trazendo colunas grandes.
- **Transações**: operação que deveria ser atômica fora de transação; transação longa segurando locks; chamada externa dentro da transação; no Spring, `@Transactional` ignorado em chamada interna da mesma classe; nível de isolamento assumido errado.
- **Pool de conexões**: esgotado (requisições pendurando e depois 500/503) por conexões não devolvidas, transação aberta durante I/O lento, ou soma dos pools das instâncias acima do limite do banco.
- **Migrações**: em deploy sem parada, o código antigo e o novo convivem com o mesmo esquema. Use expandir → migrar → contrair: adicionar coluna anulável → código novo escreve nos dois → preencher dados → remover o antigo em deploy posterior. Renomear ou remover coluna de uma vez derruba a versão que ainda está no ar. Em tabela grande, criação de índice sem bloqueio (`CONCURRENTLY`, `ALGORITHM=INPLACE`) e preenchimento em lotes.
- **Estado do esquema**: confira se o banco do ambiente está na migração que o código espera antes de culpar o código.
- **Dados antigos**: código novo assumindo formato que registros antigos não têm (nulos, enum extinto, JSON com outra forma).

## Concorrência e consistência

- **Ler-modificar-gravar sem proteção**: dois pedidos leem saldo/estoque, ambos gravam, uma atualização se perde. Use atualização atômica (`UPDATE … SET x = x - 1 WHERE x >= 1`), lock pessimista (`SELECT … FOR UPDATE`) ou versão otimista com nova tentativa.
- **Verificar-depois-agir**: "existe? senão cria" duplica sob concorrência. Garanta com restrição única no banco e trate a violação.
- **Clique duplo / retry do cliente**: operações de escrita devem ser idempotentes — chave de idempotência enviada pelo cliente e registrada com o resultado.
- **Estado em memória do processo**: contadores, caches e locks locais não valem com várias instâncias.
- **Deadlock**: adquira locks sempre na mesma ordem; mantenha transações curtas; tente de novo no erro de deadlock.

## Chamadas externas

Toda chamada de rede precisa de:
- **Timeout** de conexão e de leitura explícitos. Muitas bibliotecas não têm padrão (ou têm infinito): `requests` em Python, `http.Client` em Go, `fetch` em JS, vários clientes Java.
- **Retry** só para erros transitórios e operações idempotentes, com recuo exponencial e jitter, e limite.
- **Tratamento de falha** definido: degradar, enfileirar, ou falhar rápido com erro claro.
- **Timeout menor que o de quem chamou**: se o proxy desiste em 30 s, o cliente HTTP interno não pode esperar 60 s.

Erros clássicos: retry sem limite multiplicando carga; resposta não-2xx tratada como sucesso; corpo de erro em HTML passado ao parser JSON; conexão não reutilizada (novo cliente a cada requisição); DNS em cache para sempre.

## Cache

- **Chave**: precisa conter tudo que altera a resposta — usuário, tenant, idioma, permissões, parâmetros. Chave incompleta = vazamento de dados entre usuários.
- **Invalidação**: quem escreve invalida; TTL como rede de segurança. Dado desatualizado após atualização = caminho de escrita que não invalida.
- **HTTP**: `Cache-Control: private` para conteúdo por usuário; `Vary` para o que diferencia respostas; `no-store` para dados sensíveis; ETag para revalidação. Confira o que a CDN realmente armazenou (cabeçalhos `Age`, `X-Cache`, `CF-Cache-Status`).
- **Estouro de manada**: expiração simultânea de chave quente derruba o banco. Use lock/recomputação única, TTL com jitter, ou stale-while-revalidate.
- **Cache negativo**: erro ou "não encontrado" guardado por tempo demais.

## Trabalho assíncrono e agendado

- Job precisa ser **idempotente**: filas entregam ao menos uma vez; retry reexecuta.
- Job enfileirado **dentro da transação** pode rodar antes do commit e não achar o registro: enfileire após o commit ou use outbox.
- Falha silenciosa: sem alerta para fila morta, sem log de erro do worker.
- Argumentos: passe IDs, não objetos serializados (ficam obsoletos; quebram com mudança de classe).
- Agendador rodando em todas as réplicas → execução duplicada: use lock distribuído ou agendador único.
- Deploy: workers com código antigo consumindo mensagens em formato novo (e vice-versa).

## Uploads, streaming e tempo real

- **Upload**: limites em cada salto (cliente, CDN, proxy, framework); arquivo inteiro em memória; disco local com várias instâncias (use armazenamento de objetos, de preferência com URL pré-assinada); valide tipo pelo conteúdo, não pela extensão; nome de arquivo vindo do usuário nunca vira caminho.
- **Streaming/SSE**: buffer do proxy segurando a resposta (`X-Accel-Buffering: no`, `proxy_buffering off`); compressão acumulando; timeout de ociosidade.
- **WebSocket**: proxy sem cabeçalhos `Upgrade`/`Connection`; timeout de ociosidade sem ping/pong; várias instâncias sem barramento compartilhado (Redis pub/sub) ou afinidade; reconexão sem recuo; autenticação no handshake.

## Desempenho e recursos

Meça onde o tempo vai (APM, tracing, log de tempo por etapa) antes de otimizar.

- **Latência**: consultas (N+1, sem índice), chamadas externas em série que poderiam ser paralelas, serialização de respostas enormes, falta de paginação, trabalho síncrono que deveria ir para fila.
- **Thread/loop bloqueado**: I/O ou CPU pesada no event loop (Node, asyncio); pool de threads esgotado por chamadas lentas.
- **Memória**: coleção crescendo sem limite (cache sem expiração, listeners acumulados), carga de tabela inteira, leitura de arquivo grande em memória. Compare dois heap dumps.
- **Arranque a frio / autoescala**: primeira requisição lenta; health check passando antes de a aplicação estar pronta.
- **Encerramento**: sem desligamento gracioso, requisições em andamento morrem a cada deploy (trate `SIGTERM`, pare de aceitar, termine o que está em curso).

## Evolução de API

- Mudança compatível: adicionar campo opcional, endpoint novo, valor aceito a mais. Incompatível: remover/renomear campo, mudar tipo, tornar obrigatório, mudar semântica, novo valor de enum em resposta para clientes estritos.
- Clientes já publicados (apps móveis, integrações de terceiros) não atualizam junto com o servidor: antes de mudar um contrato, descubra quem consome (logs de acesso por versão/agente).
- Se o projeto tem OpenAPI/esquema, a correção atualiza o contrato junto; ferramentas de diff (`oasdiff`, `buf breaking`, `graphql-inspector`) detectam quebras.

## GraphQL

- N+1 nos resolvers → DataLoader/agrupamento.
- Erros vêm com HTTP 200 no campo `errors`: clientes e monitoração precisam olhar o corpo.
- Autorização por campo/resolver, não só na raiz.
- Consultas abusivas: limite profundidade/complexidade; persisted queries.
- Nulabilidade: campo não nulo que falha anula o objeto pai inteiro.

## Configuração e ambiente

- Uma só fonte por valor; falhe na inicialização quando faltar configuração obrigatória (em vez de `undefined` em tempo de execução).
- Precedência entre arquivo, variável de ambiente e padrão: descubra o valor **efetivo** no ambiente com problema.
- Segredos fora do repositório e fora dos logs.
- Fuso horário do processo e do banco em UTC; converta na apresentação.

## Observabilidade mínima

Se depurar foi difícil, parte da correção é tornar o próximo diagnóstico fácil: log estruturado com ID de requisição, nível adequado, sem dados pessoais nem segredos; erro registrado uma vez, com contexto, onde é tratado; métrica ou alerta para a condição que falhou em silêncio; health check que verifica dependências reais.

## Testes

- **Integração de rota** com banco real descartável (Testcontainers, SQLite só se o dialeto não importar): cobre middleware, validação, serialização e consulta de uma vez — é onde a maioria dos bugs de API vive.
- **Unidade** para regra de negócio pura.
- **Contrato** entre serviços quando há consumidores separados.
- Simule a rede externa no nível HTTP (WireMock, nock, responses, MSW), incluindo timeout e erro 5xx — o caminho de falha é o menos testado.
- Controle o relógio e a aleatoriedade nos testes; nada de `sleep`.
