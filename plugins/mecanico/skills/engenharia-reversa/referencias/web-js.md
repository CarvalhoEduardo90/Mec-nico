# JavaScript, aplicações web e Electron

## Índice
- [Coletar o que o site entrega](#coletar-o-que-o-site-entrega)
- [Source maps](#source-maps)
- [Identificar bundler e framework](#identificar-bundler-e-framework)
- [Tornar o código legível](#tornar-o-código-legível)
- [Ofuscação](#ofuscação)
- [Extrair a API que o frontend consome](#extrair-a-api-que-o-frontend-consome)
- [Depuração no navegador](#depuração-no-navegador)
- [Estado no cliente](#estado-no-cliente)
- [Electron](#electron)
- [Extensões de navegador](#extensões-de-navegador)
- [Backend Node sem fonte](#backend-node-sem-fonte)

## Coletar o que o site entrega

Para um site seu ou que você tem autorização de analisar:

```bash
mkdir -p web && cd web
curl -sS -D cabecalhos.txt -o index.html https://app.exemplo.com/
rg -o '(src|href)="[^"]+\.(js|css|map|json|wasm)[^"]*"' index.html | sort -u
```

Com Playwright, capture tudo o que é carregado de fato (inclusive código carregado sob demanda) e um HAR do tráfego:

```js
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ recordHar: { path: 'trafego.har' } });
  const page = await ctx.newPage();
  page.on('response', async r => {
    const u = new URL(r.url());
    if (!/\.(js|mjs|css|map|wasm|json)$/.test(u.pathname)) return;
    const destino = path.join('coleta', u.hostname, u.pathname);
    fs.mkdirSync(path.dirname(destino), { recursive: true });
    try { fs.writeFileSync(destino, await r.body()); } catch {}
  });
  await page.goto(process.argv[2], { waitUntil: 'networkidle' });
  // navegue pelos fluxos de interesse aqui (cliques, login com conta de teste) para disparar os carregamentos tardios
  await ctx.close(); await browser.close();
})();
```

Olhe também: cabeçalhos de resposta (servidor, cache, CSP — a CSP lista os domínios com que o site conversa), `robots.txt`, `sitemap.xml`, `manifest.json`, o service worker (`/sw.js`, `/service-worker.js`) e sua lista de pré-cache.

## Source maps

Se existem, quase todo o trabalho está feito: o código original, com nomes e comentários.

```bash
tail -c 300 app.abc123.js | rg -o "sourceMappingURL=.*"      # referência no fim do arquivo
curl -sS -o app.abc123.js.map https://app.exemplo.com/assets/app.abc123.js.map   # tente também o nome + .map
```

O cabeçalho HTTP `SourceMap` também pode indicar o mapa. A maioria dos mapas embute o código (`sourcesContent`); para restaurar a árvore de arquivos:

```js
// restaurar-fontes.js — uso: node restaurar-fontes.js arquivo.js.map saida/
const fs = require('fs'), path = require('path');
const [mapa, saida] = process.argv.slice(2);
const m = JSON.parse(fs.readFileSync(mapa, 'utf8'));
(m.sources || []).forEach((origem, i) => {
  const conteudo = m.sourcesContent && m.sourcesContent[i];
  if (conteudo == null) return;
  const limpo = origem.replace(/^[a-z-]+:\/\/+/i, '').replace(/\.\.\//g, '').replace(/^\/+/, '');
  const destino = path.join(saida, limpo);
  if (!path.resolve(destino).startsWith(path.resolve(saida))) return;   // nunca escrever fora da pasta de saída
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  fs.writeFileSync(destino, conteudo);
});
console.log((m.sources || []).length, 'fontes listadas no mapa');
```

Mapa sem `sourcesContent` ainda devolve nomes de arquivos, de funções e de variáveis (`names`), o que já orienta a leitura. Source map público em produção de um sistema seu é um achado a relatar (exposição do código-fonte).

## Identificar bundler e framework

| Indício | Conclusão |
|---|---|
| `__webpack_require__`, `webpackChunk<nome>`, `webpackJsonp` | webpack — módulos numerados em um objeto/array |
| `/_next/static/`, `__NEXT_DATA__`, `self.__next_f` | Next.js — `_buildManifest.js` lista todas as rotas e seus chunks |
| `window.__NUXT__`, `/_nuxt/` | Nuxt |
| `/assets/index-<hash>.js`, `import.meta`, `__vite__` | Vite/Rollup — módulos ES achatados |
| `ng-version` no HTML, `main.<hash>.js` + `runtime` + `polyfills` | Angular |
| `data-reactroot`, `_reactRootContainer`, `__REACT_DEVTOOLS_GLOBAL_HOOK__` | React |
| `data-v-<hash>`, `__vue_app__` | Vue |
| `__sveltekit`, classes `svelte-<hash>` | Svelte/SvelteKit |
| `System.register`, `define(` | SystemJS / AMD (RequireJS) — legado |
| `jQuery`, `$.ajax`, scripts inline por página | Aplicação tradicional renderizada no servidor |

Estado inicial embutido no HTML (`__NEXT_DATA__`, `__NUXT__`, `window.__INITIAL_STATE__`, `window.__ENV__`) costuma expor configuração, flags e a forma dos dados da API.

## Tornar o código legível

```bash
npx prettier --write coleta/**/*.js        # ou: js-beautify -r arquivo.js
npx webcrack bundle.js -o desempacotado/    # desempacota webpack/browserify em módulos e desfaz transformações de minificador/ofuscador
```

Estratégia de leitura de um bundle sem mapa:

1. **Separe o que é biblioteca**: a maior parte do bundle é React, lodash, etc. Banners de licença, strings de versão e nomes de exportação identificam os pacotes; ignore-os.
2. **Ache o código do aplicativo pelas âncoras**: textos da interface, rotas (`"/dashboard"`), caminhos de API (`"/api/`), nomes de eventos de analytics, mensagens de erro.
3. **Strings e chaves de objeto sobrevivem à minificação** — só nomes de variáveis locais se perdem. `rg -o '"[A-Za-z_/][^"]{3,60}"' arquivo.js | sort | uniq -c | sort -rn` dá um inventário.
4. **Siga os módulos**: no webpack, `n(1234)` é a importação do módulo 1234; depois do `webcrack`, cada módulo é um arquivo.
5. **Renomeie à medida que entende** (o `webcrack` e editores com renomeação por escopo ajudam).

Para transformações sob medida, trabalhe na AST (Babel: `@babel/parser` + `@babel/traverse` + `@babel/generator`): dobrar constantes, embutir chamadas de decodificação de strings, remover código morto.

## Ofuscação

| Padrão | Como reconhecer | Abordagem |
|---|---|---|
| Vetor de strings + função decodificadora (obfuscator.io) | um array grande de strings codificadas no topo, uma função `_0x1a2b(0x1f)` chamada em toda parte, um laço que rotaciona o array | `webcrack` resolve a maioria; ou, via AST, avaliar a decodificadora isoladamente e substituir as chamadas pelos literais |
| Achatamento de fluxo de controle | `while(true){switch(ordem[i++]){…}}` | `webcrack`/desofuscadores reconstroem a sequência; lendo à mão, siga a string de ordem |
| `eval` / `Function` / packer (`eval(function(p,a,c,k,e,d)`) | código dentro de string | troque o `eval` por impressão do argumento, em ambiente isolado |
| Codificações exóticas (JSFuck, aaencode) | só símbolos | decodificadores dedicados |
| Autodefesa / anti-depuração | `debugger` em laço, verificação de formatação do próprio código | remover via AST; nas ferramentas do navegador, "never pause here" |
| Lógica em WebAssembly | `.wasm` carregado; JS só de cola | ver [binarios.md](binarios.md) |

Código ofuscado é dado não confiável: só avalie trechos dele em ambiente isolado (container sem rede, `node` com `vm` não é isolamento de segurança), e avalie o mínimo — de preferência só a função decodificadora de strings.

## Extrair a API que o frontend consome

Combine as duas fontes:

**Do código**
```bash
rg -n -o "(fetch|axios\.(get|post|put|patch|delete)|\.request)\([^)]{0,160}" fontes/ | head -n 100
rg -n -o "[\"'\`](/api|/v[0-9]+|/graphql|/rest)[^\"'\`]{0,100}" fontes/ | sort -u
rg -n "baseURL|API_URL|apiBase|Authorization|Bearer|x-api-key|interceptors" fontes/
rg -n "query |mutation |gql\`" fontes/                # operações GraphQL embutidas
```

**Do tráfego** (HAR gravado acima, navegando com uma conta de teste):
```bash
jq -r '.log.entries[] | select(.request.url | test("/api/|graphql")) |
  [.request.method, .response.status, .request.url] | @tsv' trafego.har | sort -u
jq '.log.entries[] | select(.request.url | test("/api/login")) |
  {req: .request.postData.text, status: .response.status, resp: .response.content.text}' trafego.har
```

Documente por endpoint: método, caminho, parâmetros, corpo, cabeçalhos necessários, respostas (sucesso e erros), e de onde vem cada valor (token do login? cabeçalho de assinatura calculado no cliente?). Quando o cliente assina requisições (HMAC, carimbo de tempo, nonce), a função de assinatura está no bundle — ache-a pelo nome do cabeçalho. GraphQL: com introspecção habilitada no ambiente autorizado, o esquema completo sai de uma consulta; sem ela, reconstrua a partir das operações embutidas no código. Para gerar OpenAPI a partir do tráfego, ver [rede-e-apis.md](rede-e-apis.md).

## Depuração no navegador

- **Formatar** (`{}`) e pontos de parada no código formatado; **pontos de parada condicionais e de log** (logpoints) para observar valores sem alterar o código.
- **Pontos de parada por XHR/fetch** (por trecho de URL): param exatamente onde a requisição é montada — a pilha de chamadas leva à lógica de autenticação/assinatura.
- **Pontos de parada por evento** (clique, envio de formulário) e **por mutação de DOM**: do elemento ao código.
- **Substituições locais** (overrides): servir uma versão modificada de um arquivo JS para instrumentar.
- **Busca global** em todos os arquivos carregados; **cobertura** para ver que código rodou num fluxo.
- **Aba de rede**: "copiar como cURL" transforma qualquer requisição em comando reproduzível.
- Tudo isso também é automatizável via Playwright (`page.route` para interceptar, `page.evaluate` para inspecionar estado, protocolo CDP para o depurador).

## Estado no cliente

`localStorage`, `sessionStorage`, IndexedDB, Cache Storage e cookies revelam o modelo de dados local e onde ficam os tokens. Com Playwright: `await context.storageState({ path: 'estado.json' })` exporta cookies e `localStorage`. Token de sessão em `localStorage` é acessível a qualquer script da página — registre como observação de segurança em sistema próprio.

## Electron

```bash
# localizar o pacote do aplicativo
#   Windows/Linux: <app>/resources/app.asar        macOS: <App>.app/Contents/Resources/app.asar
npx @electron/asar list app.asar | head -n 50
npx @electron/asar extract app.asar app-extraido/
cat app-extraido/package.json            # "main" = processo principal; dependências e versões
```

- **Processo principal** (`main`): janelas, menus, IPC (`ipcMain.handle/on`), acesso a arquivos, atualizações automáticas, protocolos próprios.
- **Preload**: a ponte entre a página e o Node (`contextBridge.exposeInMainWorld`) — define o que a interface pode fazer no sistema.
- **Renderer**: uma aplicação web comum (tudo acima se aplica).
- Verifique as opções das janelas: `nodeIntegration`, `contextIsolation`, `sandbox`, `webSecurity` — configuração frouxa + conteúdo remoto é o risco clássico do Electron.
- `app.asar.unpacked/` contém módulos nativos (`.node`) — binários; ver [binarios.md](binarios.md).
- Código pode estar compilado para bytecode V8 (`.jsc`, via bytenode): aí não há fonte, só desmontagem do bytecode.
- Depuração do seu app: `--inspect=9229` (processo principal) e `--remote-debugging-port=9222` (renderers), anexando as ferramentas de desenvolvedor do Chrome.
- Outros empacotadores de desktop: Tauri (interface web + binário Rust; recursos embutidos no executável), NW.js (`package.nw` é um ZIP).

## Extensões de navegador

`.crx` é um ZIP precedido por um cabeçalho (o `unzip` costuma abrir mesmo assim, com aviso; `7z x` também); `.xpi` (Firefox) é ZIP puro. Comece pelo `manifest.json`: permissões, `host_permissions`, `content_scripts` (onde injeta código), service worker de segundo plano, recursos acessíveis pela web.

## Backend Node sem fonte

Só há `dist/` ou `node_modules` de produção? O JavaScript transpilado ainda é código: formate, procure `*.map` ao lado, leia o `package.json` (ponto de entrada, scripts, dependências) e parta do arquivo `main`. TypeScript compilado preserva a estrutura; arquivos `.d.ts` publicados devolvem os tipos. Imagens Docker: `docker save imagem | tar -x` e inspecione as camadas, ou `docker run --rm -it --entrypoint sh imagem` para explorar o sistema de arquivos; `docker history --no-trunc imagem` mostra os comandos de build.
