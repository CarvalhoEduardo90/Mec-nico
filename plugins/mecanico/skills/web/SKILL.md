---
name: web
description: Conhecimento de manutenção para aplicações web de ponta a ponta — navegador, frontend (React, Vue, Angular, Svelte, SSR/hidratação), HTTP, APIs REST/GraphQL, autenticação e sessão, CORS, cookies, cache e CDN, backend, banco, desempenho e segurança. Use ao diagnosticar ou corrigir qualquer problema em site, SPA, API ou aplicação web — erro 4xx/5xx, tela em branco, CORS, login que não persiste, página lenta, dado desatualizado, falha só em produção.
---

# Manutenção de aplicações web

Um problema web quase nunca está onde aparece. A tela em branco pode ser um erro de JavaScript, uma API devolvendo 500, um cache servindo um bundle antigo ou um cabeçalho bloqueando o carregamento. O primeiro trabalho é **localizar a camada**; só depois vale ler código.

## Passo 1 — localize a camada

Uma requisição atravessa, nesta ordem:

```
Navegador → DNS → CDN/WAF → balanceador/proxy reverso → aplicação → cache/banco/serviços externos
   (JS, cache local,        (cache, regras,   (TLS, timeout,      (rotas, middleware,
    cookies, service worker)  compressão)      cabeçalhos, limites)  regra de negócio)
```

Perguntas que cortam o problema ao meio:

1. **A requisição saiu do navegador?** (aba Rede / `curl -v`). Não saiu → problema no cliente: erro de JS, CORS no preflight, conteúdo misto, service worker, extensão.
2. **Chegou à aplicação?** (log de acesso da aplicação). Não chegou → DNS, CDN, WAF, proxy, TLS, tamanho do corpo, timeout intermediário.
3. **O que a aplicação respondeu?** Status, cabeçalhos e corpo, direto na origem, contornando CDN/proxy. Resposta certa na origem e errada no navegador → cache ou reescrita no caminho.
4. **A resposta está certa e a tela errada?** → renderização, estado, hidratação.

Reproduza com `curl` sempre que der: tira o navegador da equação e produz um comando que serve de teste.

```bash
curl -sS -D - -o /dev/null https://host/caminho                 # só status e cabeçalhos
curl -sS -X POST https://host/api -H 'Content-Type: application/json' -d '{"a":1}' -w '\n%{http_code} %{time_total}s\n'
curl -sS -H 'Origin: https://app.exemplo.com' -H 'Access-Control-Request-Method: POST' -X OPTIONS -D - https://api/recurso   # preflight CORS
```

## Passo 2 — leia o status como pista

| Status | Onde olhar primeiro |
|---|---|
| 400 / 422 | Validação: formato do corpo, `Content-Type`, campos obrigatórios, serialização de datas e números |
| 401 | Credencial ausente/expirada: cabeçalho `Authorization`, cookie não enviado (domínio, `SameSite`, `Secure`), relógio/expiração do token |
| 403 | Autenticado mas não autorizado: papel/escopo, CSRF, regra do WAF, política de IP |
| 404 | Rota (prefixo, barra final, método), reescrita do proxy, fallback de SPA ausente no servidor, recurso de outro tenant |
| 405 | Método errado ou preflight `OPTIONS` não tratado |
| 408 / 499 / 504 | Timeout: de quem? cliente, proxy ou upstream — compare os limites de cada salto |
| 409 | Conflito de estado: concorrência, chave única, versão otimista |
| 413 / 414 / 431 | Limites do proxy: corpo, URL, cabeçalhos (cookies gigantes) |
| 429 | Limite de taxa: de qual camada? laço de retry no cliente? |
| 500 | Exceção não tratada: stack trace no log da aplicação com o ID da requisição |
| 502 / 503 | Aplicação caiu, está reiniciando, health check falhando, pool esgotado, deploy em andamento |

## Passo 3 — aprofunde na camada certa

- **Cliente e renderização** — erros de JS, estado, hidratação SSR, bundle, service worker, desempenho percebido, acessibilidade: [referencias/frontend.md](referencias/frontend.md)
- **Servidor e API** — rotas, middleware, autenticação e sessão, banco e ORM, filas, cache, uploads, tempo real, desempenho: [referencias/backend-api.md](referencias/backend-api.md)
- **Segurança** — CORS, cookies, CSRF, XSS, injeção, controle de acesso, cabeçalhos, segredos: [referencias/seguranca-web.md](referencias/seguranca-web.md)

Leia a referência da camada onde o passo 1 localizou o problema.

## Causas recorrentes de "só acontece em produção"

- **Configuração**: variável de ambiente ausente ou diferente; variável embutida em tempo de build (prefixos `NEXT_PUBLIC_`, `VITE_`) em vez de lida em execução; modo debug desligado escondendo o erro.
- **Cache**: CDN ou navegador servindo HTML antigo que aponta para bundles que não existem mais; `Cache-Control` ausente na API; chave de cache sem o usuário/tenant/idioma (um usuário vê o dado de outro).
- **Proxy**: aplicação não confia nos cabeçalhos `X-Forwarded-*` → redirecionamento para `http`, cookie `Secure` rejeitado, IP errado no limite de taxa; WebSocket sem cabeçalhos de `Upgrade`; buffer do proxy quebrando streaming/SSE.
- **Várias instâncias**: sessão ou upload em memória/disco local; job agendado rodando em todas as réplicas; cache local divergente; migração aplicada com código antigo ainda no ar.
- **Dados**: volume real expõe consulta sem índice e N+1; registros antigos com formato que o código novo não espera; fuso horário e locale do servidor.
- **Rede**: DNS, certificados, firewall de saída, IPv6, timeouts menores entre saltos.

## Verificação de uma correção web

Teste automatizado no nível certo (unidade para a regra, integração para a rota, ponta a ponta para o fluxo), mais a requisição `curl` que reproduzia o problema. Para frontend, confirme no navegador real ou com Playwright — passar nos testes de componente não garante que a página carrega. Confira o console e a aba de rede sem erros novos, e pense no cache: usuários com a versão antiga em cache serão afetados pela mudança?
