---
name: dependencias
description: Manutenção de dependências em qualquer ecossistema — auditar vulnerabilidades (CVE), avaliar se são alcançáveis, atualizar pacotes com segurança, resolver conflitos de versão e lockfile, migrar entre versões maiores de framework ou runtime, e remover dependências sem uso. Use quando houver alerta de segurança, "npm audit"/"pip-audit"/Dependabot, build quebrado após atualização, conflito de versões, runtime ou framework fora de suporte, ou pedido de "atualize as dependências".
argument-hint: "[pacote | 'auditar' | 'atualizar' — opcional]"
---

# Manutenção de dependências

Pedido: $ARGUMENTS

Atualizar dependência é a mudança de código mais subestimada: uma linha no manifesto troca milhares de linhas que você não leu. O método é o mesmo de qualquer correção — linha de base, mudança pequena, verificação — com atenção especial ao lockfile.

Comandos por ecossistema (auditoria, árvore, defasados): veja `comandos-por-stack.md` na skill `detectar-stack`.

## Princípios

1. **O lockfile é a verdade** do que está instalado. Instale sempre no modo travado (`npm ci`, `--frozen-lockfile`, `poetry install`, `BUNDLE_FROZEN=true bundle install`). Lockfile alterado sem intenção é um defeito do diff.
2. **Uma atualização por vez** (ou um grupo coeso — o framework e seus plugins). Vinte pacotes atualizados juntos + teste quebrado = bisseção manual.
3. **Linha de base antes**: build e testes passando (ou falhas conhecidas anotadas) antes de tocar em qualquer versão.
4. **Não troque de gerenciador de pacotes** nem regenere o lockfile do zero como efeito colateral — isso atualiza tudo de uma vez, sem controle.
5. **Leia o que mudou**: changelog e guia de migração da versão exata; para atualizações maiores, o diff do pacote quando o changelog for vago.

## Auditoria de vulnerabilidades

Rode o auditor do ecossistema (`npm audit`, `pnpm audit`, `pip-audit`, `cargo audit`, `govulncheck ./...`, `composer audit`, `bundle audit`, `dotnet list package --vulnerable --include-transitive`) ou um multi-ecossistema (`trivy fs .`, `osv-scanner scan -r .`).

Não trate a lista como tarefa de zerar contador. Para cada alerta, responda:

| Pergunta | Como descobrir |
|---|---|
| É dependência direta ou transitiva? Quem a traz? | `npm ls <pkg>` · `pnpm why` · `pipdeptree -r -p <pkg>` · `mvn dependency:tree -Dincludes=` · `cargo tree -i` · `go mod why` |
| Roda em produção ou só em desenvolvimento/build? | seção do manifesto (`devDependencies`, grupos, escopo `test`) |
| O código vulnerável é alcançável? | leia o aviso: qual função/condição? O projeto a usa? `govulncheck` faz essa análise para Go; nos demais, busque o uso |
| Existe versão corrigida compatível? | o aviso indica a versão; confira se é correção menor ou salto maior |

Priorize: alcançável em produção com exploração remota → já. Só em ferramenta de desenvolvimento, não alcançável → registre e agende. Relate as duas categorias separadamente, com a justificativa.

**Correção, em ordem de preferência**:
1. Atualizar a dependência direta para a versão corrigida.
2. Transitiva: atualizar a direta que a traz; se não houver versão, forçar a transitiva (`overrides` no npm, `pnpm.overrides`, `resolutions` no Yarn, constraints no pip/uv, `<dependencyManagement>` no Maven, `constraints` no Gradle, `replace`/versão mínima no Go, `[patch]` no Cargo) — e anotar para remover o override depois.
3. Sem correção disponível: mitigar (desativar o recurso, validar a entrada, isolar), substituir a biblioteca, ou aceitar o risco de forma documentada — decisão do usuário.

`npm audit fix --force` e equivalentes aplicam saltos maiores sem critério: não use às cegas.

## Atualização segura

1. **Planeje**: liste os defasados (`npm outdated`, `pip list --outdated`, `mvn versions:display-dependency-updates`…). Agrupe: correções e menores primeiro; maiores uma a uma.
2. **Atualize** com o comando do gerenciador (para que manifesto e lockfile mudem juntos).
3. **Revise o diff do lockfile**: mudou só o esperado? Apareceu dependência nova, pacote duplicado em duas versões maiores, troca de registro/URL?
4. **Verifique**: instalação limpa, build, tipos, lint, testes. Suba a aplicação e exercite o fluxo principal — erro de inicialização e de configuração não aparece em teste de unidade.
5. **Avisos de depreciação** na saída são o roteiro da próxima quebra: registre ou resolva.
6. **Relate**: de → para, motivo, mudanças incompatíveis tratadas, o que foi verificado.

### Atualização maior de framework ou runtime

- Siga o guia oficial de migração da versão exata; salte **uma versão maior por vez** (os guias e as ferramentas assumem isso).
- Antes de subir, elimine os avisos de depreciação na versão atual — é a parte da migração que dá para fazer sem quebrar nada.
- Use as ferramentas de migração automática quando existirem (codemods do framework, `ng update`, `rails app:update`, OpenRewrite, Rector, `pyupgrade`, `go fix`, `cargo fix --edition`) e revise o resultado.
- Confira a matriz de compatibilidade: runtime × framework × plugins × ferramentas de build (em Android: AGP × Gradle × JDK × Kotlin; em JS: Node × framework × bundler; em Python: versão do interpretador × rodas disponíveis).
- Runtime: atualize também a imagem Docker, o CI, os arquivos de versão (`.nvmrc`, `.python-version`, `global.json`, toolchain) e a documentação — todos no mesmo conjunto de mudanças.
- Mudanças de comportamento padrão (cache, serialização, fuso, segurança) não geram erro de compilação: leia a seção de "breaking changes" inteira e teste os fluxos afetados.

## Conflitos de versão

**Sintomas**: instalação falha com conflito de resolução; erro de `peerDependencies`; em tempo de execução, "método não existe", `ClassNotFoundException`/`NoSuchMethodError`, "Invalid hook call", dois singletons onde deveria haver um.

**Diagnóstico**: imprima a árvore e ache quem pede cada versão. Entenda a regra de resolução do ecossistema — npm aninha versões diferentes; Maven escolhe a declaração mais próxima da raiz; Gradle, a mais alta; pip/Poetry/Cargo/Go exigem uma única versão que satisfaça todos (Go escolhe a mínima suficiente).

**Correção**: alinhar as dependências diretas para faixas compatíveis; atualizar a que está segurando a versão antiga; override/constraint como último recurso, com comentário; BOM/plataforma (Maven, Gradle) ou catálogo de versões para manter famílias alinhadas. Evite `--legacy-peer-deps`, `--force` e `--ignore-platform-reqs` como solução permanente: eles escondem a incompatibilidade.

## Higiene

- **Sem uso**: `knip`/`depcheck` (JS), `deptry` (Python), `go mod tidy`, `cargo machete`, `composer-unused`. Confirme antes de remover — plugins, carregamento dinâmico e CLIs usadas em scripts não aparecem como importação.
- **Abandonadas**: último lançamento há anos, repositório arquivado, sem correção para CVE. Planeje a substituição antes de virar urgência.
- **Cadeia de suprimentos**: desconfie de pacote com nome parecido com um conhecido (typosquatting), de script de instalação em dependência nova e de mudança de mantenedor seguida de versão estranha. Pacote publicado há poucos dias não precisa entrar hoje. Fixe versões, mantenha o lockfile no repositório e mantenha hashes de integridade.
- **Licença**: dependência nova com licença incompatível com o projeto é assunto para o usuário decidir — mencione.
- **Automação**: se o projeto não tem Dependabot/Renovate, sugira; atualizações pequenas e frequentes custam menos que uma grande por ano.

## Relato

```
## Dependências — <o que foi feito>
| Pacote | De | Para | Tipo (correção/menor/maior) | Motivo |

## Vulnerabilidades
- Corrigidas: <id> em <pacote> — como
- Pendentes: <id> — por que (sem correção / não alcançável / exige decisão)

## Mudanças incompatíveis tratadas
## Verificação
Comandos e resultados (instalação limpa, build, testes, aplicação subiu).
## Acompanhamento
Depreciações, overrides temporários a remover, próximas versões maiores.
```
