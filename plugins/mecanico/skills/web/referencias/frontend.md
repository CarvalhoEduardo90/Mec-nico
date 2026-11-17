# Frontend: diagnóstico e correção

## Índice
- [Coleta de evidências](#coleta-de-evidências)
- [Tela em branco ou quebrada](#tela-em-branco-ou-quebrada)
- [Estado e dados](#estado-e-dados)
- [SSR, hidratação e roteamento](#ssr-hidratação-e-roteamento)
- [Por framework](#por-framework)
- [Build e bundle](#build-e-bundle)
- [Cache do cliente e service worker](#cache-do-cliente-e-service-worker)
- [Desempenho](#desempenho)
- [CSS e layout](#css-e-layout)
- [Formulários, acessibilidade e i18n](#formulários-acessibilidade-e-i18n)
- [Testes](#testes)

## Coleta de evidências

Sem navegador à mão, use Playwright para capturar o que um humano veria nas ferramentas de desenvolvedor:

```js
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  p.on('console', m => console.log('[console]', m.type(), m.text()));
  p.on('pageerror', e => console.log('[erro js]', e.message));
  p.on('requestfailed', r => console.log('[falhou]', r.url(), r.failure()?.errorText));
  p.on('response', r => r.status() >= 400 && console.log('[http]', r.status(), r.url()));
  await p.goto(process.argv[2], { waitUntil: 'networkidle' });
  await p.screenshot({ path: 'tela.png', fullPage: true });
  await b.close();
})();
```

O que coletar: primeiro erro do console (os seguintes costumam ser consequência), requisições com falha, captura de tela, e o HTML inicial (`curl`) comparado ao DOM depois do JavaScript.

## Tela em branco ou quebrada

1. **Erro de JS na inicialização** — exceção não capturada derruba a árvore inteira em React/Vue. Leia o primeiro erro; com source maps, o stack aponta o arquivo original.
2. **Bundle não carregou** — 404 em `*.js`/`*.css` (HTML antigo em cache apontando para hash que já não existe; `base`/`publicPath` errado em subdiretório); MIME incorreto (servidor devolvendo `index.html` para o caminho do asset); bloqueio por CSP; conteúdo misto.
3. **Fallback de SPA** — atualizar em `/rota/interna` dá 404 porque o servidor não devolve `index.html` para rotas do cliente.
4. **Variável de ambiente ausente no build** — `undefined` em URL de API; lembre que `NEXT_PUBLIC_*`, `VITE_*`, `REACT_APP_*` são fixadas na compilação.
5. **Navegador sem suporte** — sintaxe ou API nova sem transpilação/polyfill; confira o alvo de build e o `browserslist`.
6. **Dado inesperado** — `undefined.map`, campo nulo que a API passou a devolver. Corrija na fronteira (validação/normalização da resposta), não espalhando `?.` pela árvore.

## Estado e dados

- **Dado desatualizado na tela**: cache da biblioteca de dados (React Query/SWR/Apollo/RTK Query) sem invalidação após mutação; chave de cache que não inclui todos os parâmetros; atualização otimista sem reversão em erro.
- **Condição de corrida entre requisições**: resposta antiga chega depois da nova e sobrescreve. Cancele (`AbortController`) ou ignore respostas obsoletas; em buscas, aplique debounce.
- **Mutação direta de estado**: objeto/array alterado no lugar não dispara renderização (React, Redux) ou perde reatividade (Vue 2, desestruturação em Vue 3/Svelte).
- **Estado duplicado**: a mesma informação em dois lugares que saem de sincronia. Derive em vez de copiar.
- **Requisição duplicada ou em laço**: efeito com dependência que muda a cada renderização (objeto/função recriados).
- **Vazamento**: listeners, timers e assinaturas sem limpeza ao desmontar.

## SSR, hidratação e roteamento

- **Erro de hidratação**: o HTML do servidor difere da primeira renderização do cliente. Causas: `Date.now()`, `Math.random()`, fuso/locale, `window`/`localStorage` lidos na renderização, HTML inválido (`<div>` dentro de `<p>`), extensões do navegador. Solução: renderizar o valor dependente do cliente só após a montagem, ou passar o valor do servidor.
- **Código de servidor no cliente (e vice-versa)**: módulo Node importado em componente de cliente; segredo exposto por variável pública; `window is not defined` no servidor.
- **Cache de dados e de rota** (Next.js App Router, Nuxt, SvelteKit, Remix): página estática quando deveria ser dinâmica; revalidação não disparada após mutação; cabeçalhos/cookies tornando a rota dinâmica sem intenção. Leia a documentação da versão instalada — o comportamento padrão de cache mudou entre versões maiores.
- **Redirecionamento em laço**: middleware de autenticação que redireciona a própria página de login; divergência de barra final ou de `http`/`https` atrás de proxy.

## Por framework

**React**
- Hooks: dependências de `useEffect`/`useMemo`/`useCallback` incompletas (valor obsoleto em closure) ou instáveis (laço). `eslint-plugin-react-hooks` aponta ambos.
- `key` ausente ou baseada em índice em listas reordenáveis → estado trocado entre itens.
- Modo estrito em desenvolvimento executa efeitos duas vezes: se isso quebra algo, falta limpeza no efeito.
- Atualização de estado em componente desmontado; `setState` assíncrono lido logo em seguida.
- Renderizações em excesso: contexto grande demais, props recriadas; meça com o Profiler antes de espalhar `memo`.

**Vue**
- Reatividade perdida ao desestruturar `reactive`/props (use `toRefs`); `ref` sem `.value` no script.
- `v-if` com `v-for` no mesmo elemento; `key` ausente.
- `watch` sem `immediate`/`deep` quando necessário; mutação de prop no filho.

**Angular**
- `ExpressionChangedAfterItHasBeenChecked`: valor alterado durante a detecção de mudanças.
- `OnPush` com mutação de objeto no lugar; assinatura RxJS sem `unsubscribe`/`takeUntilDestroyed`/`async` pipe.
- Injeção: provedor no escopo errado gerando instâncias múltiplas; dependência circular.

**Svelte/SvelteKit**
- Reatividade exige atribuição (Svelte 4) / runas (`$state`, `$derived`) no Svelte 5; `load` de servidor × universal; `form actions` e invalidação.

## Build e bundle

- Erro só no build de produção: minificação expondo dependência de nome de função/classe; tree-shaking removendo módulo com efeito colateral (`sideEffects` no package.json); diferença entre servidor de desenvolvimento e bundle final.
- ESM × CommonJS: `require is not defined`, `default` indefinido ao importar pacote CJS.
- Duas cópias da mesma biblioteca (React duplicado → "Invalid hook call"): `npm ls react`; resolva com dedupe/alias.
- Tamanho: analise o bundle (`vite-bundle-visualizer`, `webpack-bundle-analyzer`, `source-map-explorer`); importações que trazem a biblioteca inteira; falta de divisão de código por rota.
- Source maps em produção: úteis para depurar, mas expõem o código-fonte — decisão consciente (envio privado ao serviço de erros é o meio-termo).

## Cache do cliente e service worker

- "Corrigi e o usuário ainda vê o bug": HTML em cache longo; service worker com estratégia cache-first servindo a versão antiga. O HTML deve ser `no-cache`; assets com hash, `immutable` de longa duração.
- Service worker antigo preso: precisa de fluxo de atualização (`skipWaiting`/`clients.claim` ou aviso de nova versão). Para remover de vez, publique um worker que se desregistra.
- `localStorage`/IndexedDB com formato antigo após deploy: versione o esquema e migre ou descarte.

## Desempenho

Meça primeiro (Lighthouse, painel Performance, `web-vitals`), depois corrija o maior ofensor.

| Métrica | Causas comuns | Correções |
|---|---|---|
| LCP (carregamento) | imagem principal pesada ou tardia, CSS/JS bloqueante, TTFB alto, fonte bloqueando texto | dimensionar e comprimir imagem, `fetchpriority="high"` e preload do recurso principal, SSR/cache na borda, `font-display: swap` |
| INP (interação) | tarefa longa na thread principal, renderização excessiva, hidratação pesada | dividir trabalho, virtualizar listas, adiar o não essencial, web worker |
| CLS (estabilidade) | imagem/iframe sem dimensões, conteúdo injetado acima, fonte trocando métricas | `width`/`height` ou `aspect-ratio`, reservar espaço, `size-adjust` |

Também: cascata de requisições em série (paralelize ou agregue no servidor), ausência de paginação, polling agressivo, imagens sem `loading="lazy"` abaixo da dobra.

## CSS e layout

- Regra não aplicada: especificidade, ordem de carregamento, escopo (CSS Modules, `scoped`, Shadow DOM), classe removida pelo purge (Tailwind com nome montado dinamicamente).
- Sobreposição: contexto de empilhamento (`z-index` só compete dentro do mesmo contexto; `transform`, `opacity`, `position` criam contexto novo).
- Estouro horizontal no celular: elemento com largura fixa, `100vw` com barra de rolagem, texto longo sem quebra, `min-width` implícito em item flex (`min-width: 0`).
- `100vh` em navegador móvel: use `dvh`/`svh`.
- Tema escuro e contraste: teste os dois temas.

## Formulários, acessibilidade e i18n

- Envio duplo: botão sem estado de carregamento; requisição não idempotente.
- Validação só no cliente não é validação: confirme que o servidor repete as regras.
- Entrada controlada × não controlada trocando no meio; máscara quebrando com colar/autofill; teclado virtual e `inputmode`.
- Acessibilidade que vira bug funcional: foco perdido após navegação/modal, elemento clicável sem papel/teclado, rótulo ausente, ordem de tabulação. `axe` (Playwright/Jest) automatiza a verificação básica.
- Datas, números e moeda: use `Intl` com locale explícito; nunca faça `new Date('2024-01-05')` esperando hora local (é interpretado como UTC); fuso do usuário × do servidor.

## Testes

- **Unidade/componente** (Vitest/Jest + Testing Library): consulte por papel e texto, não por classe CSS; simule a rede com MSW em vez de simular o módulo de dados.
- **Ponta a ponta** (Playwright/Cypress): poucos, nos fluxos críticos. Instabilidade vem de esperas por tempo fixo — espere por estado (`expect(locator).toBeVisible()`), isole dados por teste.
- **Regressão visual**: capturas com tolerância, em ambiente fixo (fontes e renderização variam entre sistemas).
- Um bug de frontend corrigido deve ganhar o teste no nível mais baixo que o reproduz.
