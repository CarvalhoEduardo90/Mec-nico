# Mecânico

Agentes e skills para o [Claude Code](https://code.claude.com/docs) dar manutenção em código: **analisar, diagnosticar, corrigir e verificar**, em qualquer linguagem ou stack — com conhecimento de aplicações web, monólitos, microsserviços e engenharia reversa de aplicativos.

Coloque em um repositório e peça:

```
/manutencao o endpoint /pedidos devolve 500 quando o carrinho está vazio
/diagnostico
/engenharia-reversa build/app-release.apk
```

## O que vem na caixa

### Agentes

| Agente | Papel | Altera código? |
|---|---|---|
| `diagnosticador` | Investiga bug, erro, falha de build/teste ou lentidão e devolve a causa raiz com evidências e plano de correção | Não |
| `reparador` | Reproduz a falha, escreve o teste de regressão, aplica a mudança mínima na causa raiz e prova que funcionou | Sim |
| `revisor-de-correcao` | Revisão independente: a correção ataca a causa? o teste prova algo? houve regressão? Devolve veredito | Não |
| `arquiteto-de-sistemas` | Mapeia componentes, pontos de entrada, dados e comunicação; analisa onde mexer e o que pode quebrar | Não |
| `engenheiro-reverso` | Recupera arquitetura, lógica, contratos e formatos de artefatos sem fonte ou sem documentação | Só em área de trabalho própria |

Os agentes de análise são bloqueados para edição (`disallowedTools: Edit, Write, NotebookEdit`); os demais herdam todas as ferramentas da sessão, inclusive servidores MCP.

### Skills

| Skill | Para quê |
|---|---|
| `/manutencao` | Fluxo completo: reconhecer o terreno → definir o problema → diagnosticar → corrigir → verificar → relatar. Coordena os agentes |
| `/diagnostico` | Retrato da saúde do repositório, sem alterar nada: build, testes, lint, vulnerabilidades, pontos frágeis, priorizados por gravidade |
| `/corrigir` | Protocolo de correção: reproduzir, isolar, teste que falha, mudança mínima, verificação |
| `/detectar-stack` | Identifica linguagens, gerenciadores, frameworks, comandos, infraestrutura e arquitetura provável. Inclui referência de comandos para mais de 20 ecossistemas |
| `/web` | Frontend, HTTP, APIs, autenticação, CORS, cookies, cache, backend, banco, desempenho e segurança web |
| `/monolito` | Raio de impacto, acoplamento oculto, mudança em código sem testes, banco compartilhado, modularização gradual |
| `/microservicos` | Rastrear falhas entre serviços, timeouts e retries, mensageria, idempotência, consistência, contratos e ordem de deploy |
| `/dependencias` | Auditoria de vulnerabilidades, atualização segura, conflitos de versão, migração de framework/runtime |
| `/engenharia-reversa` | Roteiro por tipo de alvo: Android, iOS, binários e bytecode, JavaScript/web/Electron, redes/APIs/protocolos/formatos/bancos, código legado |
| `/ferramentas` | Verifica (e, a pedido, instala) as ferramentas de linha de comando para manutenção e engenharia reversa |

As skills de conhecimento (`web`, `monolito`, `microservicos`, `dependencias`, `engenharia-reversa`) também são carregadas sozinhas pelo Claude quando o assunto aparece na conversa.

### Scripts

- `detectar-stack.sh` — só leitura; mapeia o repositório em segundos (bash 3.2+, usa `git`, `grep`, `awk`).
- `ferramentas.sh [geral|re|tudo] [--instalar]` — inventário de mais de 50 ferramentas com o comando de instalação adequado ao sistema. Com `--instalar`, usa `apt-get` ou Homebrew, mais `pipx`/`pip`, `npm`, `go` e `dotnet` para o que não está nesses repositórios.

## Instalação

### Opção 1 — copiar para dentro do repositório (recomendada)

Deixa a oficina versionada junto com o código, sem depender de nada externo. Funciona em qualquer lugar onde o repositório for aberto, incluindo sessões na nuvem e CI.

```bash
git clone https://github.com/CarvalhoEduardo90/Mec-nico.git
./Mec-nico/install.sh /caminho/do/seu/repositorio
cd /caminho/do/seu/repositorio
git add .claude/agents .claude/skills && git commit -m "Adiciona agentes e skills de manutenção"
```

Arquivos que já existem e são diferentes não são sobrescritos (use `--forcar`). Para instalar para o seu usuário, valendo em todos os projetos: `./install.sh --usuario`.

Nesta forma, as skills são chamadas sem prefixo: `/manutencao`, `/diagnostico`…

### Opção 2 — como plugin

```bash
claude plugin marketplace add CarvalhoEduardo90/Mec-nico
claude plugin install mecanico@mecanico
```

Ou, dentro de uma sessão: `/plugin marketplace add CarvalhoEduardo90/Mec-nico` e `/plugin install mecanico@mecanico`.

Para o time inteiro receber o plugin ao abrir um repositório, adicione ao `.claude/settings.json` dele:

```json
{
  "extraKnownMarketplaces": {
    "mecanico": {
      "source": { "source": "github", "repo": "CarvalhoEduardo90/Mec-nico" }
    }
  },
  "enabledPlugins": {
    "mecanico@mecanico": true
  }
}
```

Nesta forma, skills e agentes ganham o prefixo do plugin: `/mecanico:manutencao`, agente `mecanico:diagnosticador`. Se este repositório for privado, cada pessoa (ou ambiente) precisa ter acesso de leitura a ele.

### Testar sem instalar

```bash
claude --plugin-dir ./Mec-nico/plugins/mecanico
```

## Como usar

**Um problema específico**

```
/manutencao os testes de integração do módulo de pagamento falham de forma intermitente
```

O Claude roda o detector de stack, reformula o problema, delega a investigação ao `diagnosticador`, a correção ao `reparador` e a conferência ao `revisor-de-correcao`, e entrega um relato com causa, mudança, verificação e pendências.

**Assumir um código desconhecido**

```
/diagnostico
```

Depois: `use o arquiteto-de-sistemas para mapear este sistema e me dizer o que pode quebrar se eu mudar a tabela de clientes`.

**Chamar um agente diretamente**

```
use o diagnosticador para descobrir por que o build do Android quebra só em release
use o engenheiro-reverso para documentar a API que este app consome (é o nosso app; perdemos a documentação do backend)
```

**Preparar o ambiente**

```
/ferramentas re
```

## Limites de propósito

- **Commit, push e PR** só acontecem quando você pede. Operações destrutivas ou contra produção pedem confirmação.
- **Correções não escondem falhas**: nada de desativar teste, engolir exceção ou suprimir erro para "fazer passar".
- **Engenharia reversa** é para manutenção, migração, interoperabilidade, auditoria autorizada e análise de artefato suspeito. Os agentes não quebram proteção de licença ou DRM, não ajudam em trapaça, não extraem credenciais ou dados de terceiros e não atacam sistemas alheios. Artefatos não confiáveis só são executados em ambiente isolado.
- **Segredos encontrados** são relatados (local e tipo, sem o valor) com recomendação de rotação.
- **Instalação de ferramentas** só com sua autorização.

## Estrutura

```
.claude-plugin/marketplace.json         catálogo (marketplace "mecanico")
plugins/mecanico/
  .claude-plugin/plugin.json            manifesto do plugin
  agents/                               5 agentes
  skills/
    manutencao/  diagnostico/  corrigir/
    detectar-stack/    SKILL.md · scripts/detectar-stack.sh · referencias/comandos-por-stack.md
    ferramentas/       SKILL.md · scripts/ferramentas.sh
    web/               SKILL.md · referencias/{frontend,backend-api,seguranca-web}.md
    monolito/
    microservicos/     SKILL.md · referencias/falhas-distribuidas.md
    dependencias/
    engenharia-reversa/ SKILL.md · referencias/{android,ios,binarios,web-js,rede-e-apis,codigo-legado}.md
install.sh                              copia agentes e skills para <repo>/.claude/
```

## Adaptar ao seu projeto

- **Comandos do projeto**: registre no `CLAUDE.md` do seu repositório como construir, testar e rodar. Os agentes leem esse arquivo antes de tudo e preferem o que ele diz às heurísticas do detector.
- **Modelo**: os agentes herdam o modelo da sessão. Para fixar, acrescente `model: sonnet` (ou `opus`, `haiku`) ao cabeçalho do arquivo do agente.
- **Novas stacks**: acrescente uma seção em `skills/detectar-stack/referencias/comandos-por-stack.md` e, se quiser detecção automática, um bloco em `scripts/detectar-stack.sh`.
- **Validar alterações**: `claude plugin validate .` (catálogo) e `claude plugin validate plugins/mecanico` (plugin).
