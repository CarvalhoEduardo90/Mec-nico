# Segurança web na manutenção

Dois usos: diagnosticar um problema causado por um mecanismo de segurança (CORS, cookies, CSP) e não introduzir — ou encontrar e fechar — uma vulnerabilidade ao corrigir.

## Índice
- [CORS](#cors)
- [Cookies](#cookies)
- [CSRF](#csrf)
- [XSS e CSP](#xss-e-csp)
- [Injeção](#injeção)
- [Controle de acesso](#controle-de-acesso)
- [Autenticação e senhas](#autenticação-e-senhas)
- [SSRF, redirecionamento e arquivos](#ssrf-redirecionamento-e-arquivos)
- [Cabeçalhos](#cabeçalhos)
- [Segredos e dados sensíveis](#segredos-e-dados-sensíveis)
- [Ao encontrar uma vulnerabilidade](#ao-encontrar-uma-vulnerabilidade)

## CORS

CORS é imposto pelo **navegador**; `curl` e servidores não são afetados. O servidor apenas declara, por cabeçalhos, quais origens podem ler a resposta. "Erro de CORS" no console tem poucas causas:

| Sintoma | Causa provável |
|---|---|
| Sem `Access-Control-Allow-Origin` na resposta | Origem não está na lista; middleware de CORS não roda nessa rota; **a resposta é um erro (500/502/redirecionamento) gerado antes ou fora do middleware** — olhe o status real primeiro |
| Preflight `OPTIONS` falha | Rota não responde `OPTIONS`; autenticação exigida no preflight (ele nunca leva credenciais); método ou cabeçalho fora de `Allow-Methods`/`Allow-Headers` |
| Com credenciais | `Allow-Origin: *` é proibido junto de `Allow-Credentials: true`; a origem deve ser ecoada explicitamente e a resposta levar `Vary: Origin` |
| Cabeçalho de resposta invisível ao JS | Falta `Access-Control-Expose-Headers` |
| Funciona às vezes | Cache (CDN/navegador) guardou resposta sem `Vary: Origin`; cabeçalhos duplicados (aplicação e proxy adicionando ambos) |

Diagnóstico:

```bash
curl -sS -D - -o /dev/null -X OPTIONS https://api.exemplo.com/recurso \
  -H 'Origin: https://app.exemplo.com' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type, authorization'
```

Correção segura: lista explícita de origens. Nunca "resolver" refletindo qualquer origem com credenciais, nem com `*` em API autenticada por cookie. Durante o desenvolvimento, um proxy no servidor de dev (mesma origem) evita o problema sem afrouxar a produção.

## Cookies

| Atributo | Efeito | Erro comum |
|---|---|---|
| `Secure` | Só trafega em HTTPS | Aplicação atrás de proxy acha que é HTTP e o cookie é rejeitado/omitido |
| `HttpOnly` | Invisível ao JavaScript | Ausente em cookie de sessão (roubo via XSS) |
| `SameSite=Lax` (padrão atual) | Não enviado em POST/fetch entre sites | Login via iframe ou POST vindo de outro site perde a sessão |
| `SameSite=None` | Enviado entre sites; exige `Secure` | Sem `Secure` é descartado; bloqueado quando cookies de terceiros estão desativados |
| `Domain` | Compartilha com subdomínios | Ausente → só o host exato; definido demais → exposto a subdomínios não confiáveis |
| `Path` / expiração | Escopo e duração | Dois cookies de mesmo nome com `Path` diferente; sessão que não expira |

`fetch` entre origens só envia cookies com `credentials: 'include'` (e o CORS correspondente). "Mesmo site" (domínio registrável) é diferente de "mesma origem" (esquema + host + porta): `app.exemplo.com` e `api.exemplo.com` são mesmo site, origens diferentes.

## CSRF

Vale para autenticação por cookie (o navegador o anexa sozinho). Defesas: token anti-CSRF verificado em toda requisição que altera estado, `SameSite`, verificação de `Origin`. APIs autenticadas por cabeçalho `Authorization` não sofrem CSRF clássico.

Na manutenção: 403/419 em POST costuma ser token ausente, expirado ou não enviado pelo cliente (formulário em cache, chamada AJAX sem o cabeçalho). Corrija enviando o token — não desative a proteção nem isente a rota, exceto webhooks, que se autenticam por assinatura. `GET` nunca deve alterar estado.

## XSS e CSP

- A saída deve ser escapada **para o contexto** (HTML, atributo, JavaScript, URL, CSS). Os mecanismos de template escapam por padrão; o risco está nas saídas de emergência: `innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `[innerHTML]`, `|safe`, `{!! !!}`, `html_safe`, `raw`. Ao revisar uma correção, procure por elas.
- HTML fornecido por usuário (rich text, Markdown): higienize com biblioteca mantida (DOMPurify, Bleach, sanitize-html) no momento de renderizar.
- URLs vindas do usuário em `href`/`src`: valide o esquema (`javascript:` é execução de código).
- Dados embutidos em `<script>` (estado inicial de SSR): serialize escapando `<`, `>` e `&`.
- **CSP** é a segunda linha: bloqueio no console ("Refused to load/execute…") indica a diretiva. Corrija adicionando a fonte necessária ou nonce/hash; `unsafe-inline` e `*` anulam a proteção.

## Injeção

- **SQL**: parâmetros vinculados, sempre. Concatenação e interpolação de string em consulta são o defeito, mesmo "só com número". Atenção aos pontos onde parâmetro não funciona — nome de coluna em `ORDER BY`, nome de tabela, `LIMIT` em alguns bancos: use lista permitida. Métodos de SQL bruto do ORM (`raw`, `$queryRawUnsafe`, `extra`, `FromSqlRaw`) merecem leitura atenta.
- **NoSQL**: objeto vindo do corpo usado como filtro (`{"$ne": null}`); valide tipos.
- **Comando**: nunca monte linha de shell com entrada do usuário; use a forma com vetor de argumentos (`execFile`, `subprocess.run([...], shell=False)`).
- **Caminho**: normalize e confirme que o resultado permanece dentro do diretório base; nunca use nome de arquivo do usuário diretamente.
- **Desserialização**: não desserialize dados não confiáveis em formatos que instanciam objetos (`pickle`, serialização nativa do Java, `Marshal`, `unserialize` do PHP, YAML com `load` inseguro).
- **Template (SSTI)**: entrada do usuário nunca é o template, só dado para ele.
- **Cabeçalhos e logs**: quebra de linha em valor de cabeçalho ou em linha de log.

## Controle de acesso

A falha mais comum e a que menos aparece em scanners.

- **Por objeto (IDOR)**: `GET /pedidos/123` verifica se o pedido 123 pertence a quem pede? Toda consulta por ID deve filtrar por dono/tenant, de preferência em um ponto central (escopo padrão, política, row-level security).
- **Por função**: rota administrativa protegida apenas por estar escondida no frontend.
- **Atribuição em massa**: o corpo aceita `role`, `is_admin`, `tenant_id`, `price`? Use lista permitida de campos graváveis.
- **Multi-tenant**: o filtro de tenant está em todas as consultas, jobs, exportações, caches e buscas?
- Regra de autorização vive no servidor. Esconder o botão não é controle.

Ao corrigir um bug de permissão, escreva o teste negativo (usuário B não acessa recurso de A) além do positivo.

## Autenticação e senhas

- Hash de senha com algoritmo próprio para isso (Argon2id, bcrypt, scrypt). MD5/SHA simples, mesmo com sal, é defeito — migre regravando o hash no próximo login.
- Comparação de segredos em tempo constante.
- Limite de tentativas e bloqueio progressivo em login, recuperação de senha e verificação de código.
- Mensagens e tempos de resposta que não revelem se o usuário existe.
- Token de recuperação: aleatório criptográfico, uso único, expiração curta, invalidado ao trocar a senha. Regenere o ID de sessão no login.
- Aleatoriedade para tokens vem de gerador criptográfico (`crypto.randomBytes`, `secrets`, `SecureRandom`), nunca de `Math.random()`/`random`.

## SSRF, redirecionamento e arquivos

- **SSRF**: servidor que busca URL fornecida pelo usuário (webhook, importação, prévia de link) deve restringir esquema e destino, bloquear endereços internos e de metadados de nuvem (169.254.169.254), revalidar após redirecionamentos e resolver o DNS uma única vez.
- **Redirecionamento aberto**: `?next=`/`?redirect=` só para caminhos relativos ou lista permitida.
- **Upload**: valide tipo pelo conteúdo, limite tamanho, gere o nome no servidor, armazene fora da raiz servida, sirva com `Content-Disposition` e tipo corretos; SVG e HTML enviados por usuário são vetores de XSS.
- **Extração de arquivo compactado**: caminho com `../` (zip slip) e bomba de descompressão.

## Cabeçalhos

| Cabeçalho | Valor de partida |
|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` (só depois de todo o site estar em HTTPS) |
| `Content-Security-Policy` | política restritiva com nonce/hash; `frame-ancestors` contra clickjacking |
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | negar o que o site não usa |
| `Cache-Control` | `no-store` em respostas com dados sensíveis |

Remova cabeçalhos que anunciam versões (`X-Powered-By`, `Server` detalhado). Mudança de cabeçalho de segurança pode quebrar funcionalidade (CSP bloqueando script legítimo, HSTS em subdomínio sem HTTPS): introduza em modo de relatório quando houver.

## Segredos e dados sensíveis

- Nada de segredo no repositório, em bundle de frontend, em log, em mensagem de erro ou em URL (URLs vão para logs e para o cabeçalho `Referer`).
- Segredo que foi versionado está comprometido mesmo depois de apagado: a correção é **rotacionar**, e só então limpar o histórico se necessário.
- Dados pessoais: registre o mínimo, mascare em logs, respeite a retenção.
- Dependências vulneráveis: veja a skill `dependencias`.

## Ao encontrar uma vulnerabilidade

Durante uma manutenção sobre outro assunto, se aparecer uma falha de segurança:

1. Relate ao usuário com local, cenário de exploração e gravidade — sem publicar detalhes em local aberto (issue pública, mensagem de commit detalhada em repositório público).
2. Corrija se estiver no escopo do pedido ou se for trivial e seguro; caso contrário, recomende e deixe a decisão com o usuário.
3. Procure o mesmo padrão no resto do código.
4. Adicione o teste que prova o fechamento (o caso malicioso é rejeitado).
5. Considere o passado: houve exploração? segredos a rotacionar? usuários a avisar? Isso é decisão do usuário, mas lembre-o.

Testes de exploração apenas contra ambiente local ou de teste do próprio usuário — nunca contra produção ou sistemas de terceiros.
