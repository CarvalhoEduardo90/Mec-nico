# Comandos por stack

Referência rápida para manutenção. Sempre prefira o que o projeto define (CI, scripts do manifesto, Makefile); use esta tabela quando ele não define ou para saber o que procurar.

## Índice

- [JavaScript / TypeScript](#javascript--typescript)
- [Python](#python)
- [Java / Kotlin (JVM)](#java--kotlin-jvm)
- [C# / .NET](#c--net)
- [Go](#go)
- [Rust](#rust)
- [PHP](#php)
- [Ruby](#ruby)
- [C / C++](#c--c)
- [Swift / iOS / macOS](#swift--ios--macos)
- [Android](#android)
- [Dart / Flutter](#dart--flutter)
- [Elixir](#elixir)
- [Scala](#scala)
- [Shell](#shell)
- [SQL e bancos](#sql-e-bancos)
- [Containers e infraestrutura](#containers-e-infraestrutura)
- [Legado](#legado)
- [Ferramentas que servem para qualquer linguagem](#ferramentas-que-servem-para-qualquer-linguagem)

---

## JavaScript / TypeScript

Identifique o gerenciador pelo lockfile e **não troque**: `package-lock.json` → npm · `pnpm-lock.yaml` → pnpm · `yarn.lock` → yarn · `bun.lock`/`bun.lockb` → bun. O campo `packageManager` do `package.json` fixa a versão (via Corepack).

| Tarefa | npm | pnpm | yarn |
|---|---|---|---|
| Instalar travado | `npm ci` | `pnpm install --frozen-lockfile` | `yarn install --immutable` (v2+) / `--frozen-lockfile` (v1) |
| Rodar script | `npm run <s>` | `pnpm <s>` | `yarn <s>` |
| Por que este pacote está aqui | `npm ls <pkg>` / `npm explain <pkg>` | `pnpm why <pkg>` | `yarn why <pkg>` |
| Auditoria | `npm audit` | `pnpm audit` | `yarn npm audit` (v2+) |
| Defasados | `npm outdated` | `pnpm outdated` | `yarn outdated` (v1) |
| Num workspace | `npm run <s> -w <pkg>` | `pnpm --filter <pkg> <s>` | `yarn workspace <pkg> <s>` |

- **Tipos**: `npx tsc --noEmit` (ou `-p <tsconfig>`; em monorepo com project references, `tsc -b`).
- **Lint/formatação**: `npx eslint .` · `npx prettier --check .` · `npx biome check .`
- **Um único teste**: Jest `npx jest caminho/arquivo.test.ts -t "nome"` · Vitest `npx vitest run caminho/arquivo.test.ts -t "nome"` · Mocha `npx mocha caminho --grep "nome"` · Node nativo `node --test caminho` · Playwright `npx playwright test arquivo.spec.ts -g "nome"`.
- **Depurar**: `node --inspect-brk arquivo.js` · `NODE_OPTIONS=--stack-trace-limit=100` · `node --trace-warnings` · memória: `node --inspect` + heap snapshot, `--max-old-space-size`.
- **Código morto / dependências sem uso**: `npx knip` · `npx depcheck`.
- **Armadilhas**: ESM × CommonJS (`"type": "module"`, extensões `.mjs/.cjs`, `exports` no package.json); versão do Node diferente da `.nvmrc`; dependência duplicada em versões distintas (`npm ls <pkg>`); `peerDependencies` não satisfeitas; variáveis de ambiente lidas em tempo de build (Next/Vite) e não de execução.

## Python

Gerenciador: `uv.lock` → uv · `poetry.lock` → Poetry · `Pipfile.lock` → Pipenv · `pdm.lock` → PDM · `environment.yml` → Conda · só `requirements*.txt` → pip + venv.

| Tarefa | Comando |
|---|---|
| Ambiente (pip) | `python -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt` |
| Instalar (outros) | `uv sync` · `poetry install` · `pipenv install --dev` · `pdm install` |
| Rodar dentro do ambiente | `uv run <cmd>` · `poetry run <cmd>` · `pipenv run <cmd>` |
| Testes | `pytest` · um teste: `pytest caminho/test_x.py::TestClasse::test_nome` · por nome: `pytest -k "trecho"` · parar na primeira falha com detalhes: `pytest -x -vv` |
| Lint / formatação | `ruff check .` · `ruff format --check .` · `black --check .` · `flake8` |
| Tipos | `mypy .` · `pyright` |
| Auditoria | `pip-audit` · `uv pip list --outdated` / `pip list --outdated` |
| Árvore de dependências | `pipdeptree` · `poetry show --tree` · `uv tree` |

- **Depurar**: `python -X dev -W error script.py` (ativa avisos como erro) · `breakpoint()` · `pytest --pdb` · `python -X importtime` · perfil: `python -m cProfile -o out.prof` / `py-spy top --pid <pid>`.
- **Django**: `python manage.py check --deploy` · `makemigrations --check --dry-run` · `showmigrations` · `test app.tests.Classe.metodo`.
- **Armadilhas**: ambiente virtual errado ativo (`which python`); versão do Python diferente da `.python-version`/`requires-python`; `requirements.txt` sem versões fixas; importação circular; argumento padrão mutável; `datetime` sem fuso; pacote com extensão em C sem roda (wheel) para a plataforma.

## Java / Kotlin (JVM)

Use o wrapper quando existir (`./mvnw`, `./gradlew`) — ele fixa a versão da ferramenta.

| Tarefa | Maven | Gradle |
|---|---|---|
| Compilar sem testes | `./mvnw -q -DskipTests package` | `./gradlew assemble` |
| Testes | `./mvnw test` | `./gradlew test` |
| Um teste | `./mvnw test -Dtest=Classe#metodo` | `./gradlew test --tests "pacote.Classe.metodo"` |
| Um módulo | `./mvnw -pl modulo -am test` | `./gradlew :modulo:test` |
| Verificação completa | `./mvnw verify` | `./gradlew check` |
| Árvore de dependências | `./mvnw dependency:tree -Dincludes=grupo:artefato` | `./gradlew dependencies --configuration runtimeClasspath` · `dependencyInsight --dependency <nome>` |
| Atualizações | `./mvnw versions:display-dependency-updates` | plugin `com.github.ben-manes.versions` → `dependencyUpdates` |
| Vulnerabilidades | OWASP `dependency-check:check` · `trivy fs .` | idem |

- **Depurar**: relatórios em `target/surefire-reports/` ou `build/reports/tests/`; `-X`/`--stacktrace --info`; depuração remota `-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005`; thread dump `jstack <pid>` / `jcmd <pid> Thread.print`; heap `jcmd <pid> GC.heap_dump arquivo.hprof`; `jcmd <pid> VM.flags`.
- **Spring Boot**: `./mvnw spring-boot:run -Dspring-boot.run.profiles=local` · endpoints `/actuator/health`, `/actuator/env`, `/actuator/mappings` · `--debug` mostra o relatório de autoconfiguração.
- **Armadilhas**: versão do JDK (`java -version` × `maven.compiler.release`/toolchain); conflito de versões transitivas (o que vence difere entre Maven "mais próximo" e Gradle "mais alto"); migração `javax.*` → `jakarta.*`; proxies do Spring (`@Transactional`/`@Async` não funcionam em chamada interna à própria classe); N+1 e `LazyInitializationException` no JPA; Lombok/annotation processors fora do IDE.

## C# / .NET

| Tarefa | Comando |
|---|---|
| Restaurar / compilar | `dotnet restore` · `dotnet build -warnaserror` |
| Testes | `dotnet test` · um teste: `dotnet test --filter "FullyQualifiedName~Namespace.Classe.Metodo"` · log detalhado: `--logger "console;verbosity=detailed"` |
| Formatação / analisadores | `dotnet format --verify-no-changes` |
| Vulneráveis / defasados | `dotnet list package --vulnerable --include-transitive` · `dotnet list package --outdated` |
| EF Core | `dotnet ef migrations list` · `dotnet ef migrations script --idempotent` (gera SQL sem aplicar) |
| Executar | `dotnet run --project caminho/Projeto.csproj` |

- **Depurar**: `dotnet-dump collect -p <pid>` / `dotnet-dump analyze` · `dotnet-trace collect -p <pid>` · `dotnet-counters monitor -p <pid>` · `DOTNET_ENVIRONMENT`/`ASPNETCORE_ENVIRONMENT`.
- **Armadilhas**: `global.json` fixando SDK ausente; `TargetFramework` múltiplos; `async void` e `.Result`/`.Wait()` causando deadlock; `DbContext` compartilhado entre threads; tempo de vida de injeção (scoped dentro de singleton); `appsettings.{Ambiente}.json` sobrepondo valores; .NET Framework legado exige Windows/MSBuild (`msbuild /t:Build`, `nuget restore`).

## Go

| Tarefa | Comando |
|---|---|
| Compilar / verificar | `go build ./...` · `go vet ./...` |
| Testes | `go test ./...` · um teste: `go test ./pkg/x -run '^TestNome$' -v` · sem cache: `-count=1` · corrida: `go test -race ./...` |
| Lint | `golangci-lint run` · `staticcheck ./...` |
| Dependências | `go mod tidy` (altera go.mod/go.sum — rode de propósito) · `go mod why <mod>` · `go mod graph` · `go list -m -u all` |
| Vulnerabilidades | `govulncheck ./...` |
| Perfil | `go test -bench . -cpuprofile cpu.out` · `go tool pprof cpu.out` · endpoint `net/http/pprof` |

- **Depurar**: `dlv debug ./cmd/app` · `dlv test ./pkg/x -- -test.run TestNome` · `GODEBUG=gctrace=1` · dump de goroutines com `SIGQUIT`.
- **Armadilhas**: goroutine vazando (canal sem leitor, `context` não cancelado); `nil` em interface com tipo concreto não nulo; `err` sombreado por `:=`; mapa acessado concorrentemente; `defer` dentro de laço; corpo de resposta HTTP não fechado; `http.Client` sem timeout.

## Rust

| Tarefa | Comando |
|---|---|
| Verificar rápido / compilar | `cargo check --all-targets` · `cargo build` |
| Testes | `cargo test` · um teste: `cargo test nome_do_teste -- --exact --nocapture` · um crate: `cargo test -p crate` |
| Lint / formatação | `cargo clippy --all-targets --all-features -- -D warnings` · `cargo fmt --check` |
| Dependências | `cargo tree -i <crate>` (quem depende) · `cargo tree -d` (duplicadas) · `cargo update -p <crate>` |
| Auditoria | `cargo audit` · `cargo deny check` |

- **Depurar**: `RUST_BACKTRACE=1` (ou `full`) · `cargo expand` (macros) · `cargo test -- --test-threads=1` para isolar interferência · `rust-gdb`/`rust-lldb`.
- **Armadilhas**: features divergentes entre crates do workspace; `unwrap()`/`expect()` em caminho de produção; bloqueio em contexto assíncrono (use `spawn_blocking`); `Mutex` mantido através de `.await`; versão mínima do compilador (`rust-version`, `rust-toolchain.toml`).

## PHP

| Tarefa | Comando |
|---|---|
| Instalar | `composer install` (respeita `composer.lock`) |
| Testes | `vendor/bin/phpunit` · um teste: `vendor/bin/phpunit --filter 'Classe::metodo'` · Pest: `vendor/bin/pest --filter "nome"` |
| Análise estática | `vendor/bin/phpstan analyse` · `vendor/bin/psalm` |
| Estilo | `vendor/bin/php-cs-fixer fix --dry-run --diff` · `vendor/bin/phpcs` · Laravel Pint: `vendor/bin/pint --test` |
| Dependências | `composer audit` · `composer outdated --direct` · `composer why <pkg>` · `composer why-not <pkg> <versão>` |
| Sintaxe | `php -l arquivo.php` |

- **Laravel**: `php artisan test --filter Nome` · `route:list` · `migrate:status` · `config:clear && cache:clear` (config em cache é causa clássica de "mudei o .env e nada aconteceu") · `tinker` · logs em `storage/logs/`.
- **Symfony**: `bin/console debug:router` · `debug:container` · `doctrine:migrations:status` · `lint:container`.
- **WordPress**: `wp plugin list` · `wp core verify-checksums` · `WP_DEBUG_LOG` → `wp-content/debug.log`.
- **Armadilhas**: versão do PHP e extensões (`php -m`); `display_errors` desligado escondendo o erro (olhe o log do PHP-FPM/servidor); comparação frouxa `==`; autoload desatualizado (`composer dump-autoload`); permissões de `storage/` e `cache/`.

## Ruby

| Tarefa | Comando |
|---|---|
| Instalar | `bundle install` |
| Testes | `bundle exec rspec` · um exemplo: `bundle exec rspec spec/x_spec.rb:42` · Minitest/Rails: `bin/rails test test/x_test.rb:42` |
| Lint | `bundle exec rubocop` |
| Dependências | `bundle outdated` · `bundle exec bundle-audit check --update` · o `Gemfile.lock` mostra quem exige cada gem |
| Segurança (Rails) | `bundle exec brakeman` |

- **Rails**: `bin/rails routes -g <padrão>` · `db:migrate:status` · `bin/rails console --sandbox` · `log/development.log` mostra as queries (procure N+1) · `bin/rails zeitwerk:check`.
- **Armadilhas**: versão do Ruby (`.ruby-version`); callbacks do ActiveRecord com efeitos colaterais; `default_scope`; migração que trava tabela grande; diferenças entre `development` e `production` (eager loading, cache de classes).

## C / C++

| Tarefa | Comando |
|---|---|
| CMake | `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` · `cmake --build build -j` · `ctest --test-dir build --output-on-failure -R <regex>` |
| Make / Autotools | `make -j` · `make check` · `./configure && make` |
| Meson | `meson setup build` · `meson compile -C build` · `meson test -C build` |
| Análise estática | `clang-tidy -p build arquivo.cpp` · `cppcheck --enable=warning,performance .` · `scan-build make` |
| Formatação | `clang-format --dry-run -Werror arquivo` |

- **Depurar**: compile com `-g -O0 -fsanitize=address,undefined` (ASan/UBSan acham a maioria dos erros de memória na primeira execução); `-fsanitize=thread` para corridas; `valgrind --leak-check=full ./bin`; `gdb --args ./bin args` → `bt full`; core dump: `ulimit -c unlimited` e `gdb ./bin core`.
- **Armadilhas**: comportamento indefinido que só aparece com otimização; ordem de inicialização estática; ABI entre compiladores/versões de biblioteca; cabeçalhos de versão diferente da biblioteca ligada (`ldd ./bin`); variável não inicializada.

## Swift / iOS / macOS

| Tarefa | Comando |
|---|---|
| SwiftPM | `swift build` · `swift test` · um teste: `swift test --filter Modulo.Classe/metodo` |
| Xcode (só macOS) | `xcodebuild -list` · `xcodebuild -scheme <S> -destination 'platform=iOS Simulator,name=iPhone 16' build test` · um teste: `-only-testing:Alvo/Classe/metodo` |
| Dependências | `swift package resolve` · `swift package show-dependencies` · CocoaPods: `pod install` (abra o `.xcworkspace`) |
| Lint | `swiftlint` · `swift-format lint -r .` |
| Simulador | `xcrun simctl list devices` · `xcrun simctl launch --console booted <bundle id>` |

- **Armadilhas**: build e testes de iOS exigem macOS com Xcode — em Linux só SwiftPM puro funciona, e isso deve ser dito no relato; assinatura e provisioning; ciclos de retenção em closures (`[weak self]`); atualização de UI fora da main thread; `Info.plist` sem chave de permissão (o app fecha ao pedir a permissão).

## Android

| Tarefa | Comando |
|---|---|
| Compilar | `./gradlew assembleDebug` |
| Testes unitários | `./gradlew testDebugUnitTest --tests "pacote.Classe.metodo"` |
| Testes instrumentados | `./gradlew connectedDebugAndroidTest` (exige dispositivo/emulador) |
| Lint | `./gradlew lintDebug` (relatório em `build/reports/`) · `./gradlew detekt` / `ktlintCheck` se configurados |
| Dependências | `./gradlew :app:dependencies --configuration debugRuntimeClasspath` |
| Dispositivo | `adb devices` · `adb logcat --pid=$(adb shell pidof -s <pacote>)` · `adb shell am start -n <pacote>/<Activity>` · `adb shell dumpsys activity activities` |

- **Armadilhas**: versão do AGP × Gradle × JDK × Kotlin (a tabela de compatibilidade é a primeira coisa a conferir em build quebrado); `minSdk`/`targetSdk` e permissões em tempo de execução; R8/ProGuard removendo classe usada por reflexão (bug que só aparece em release — veja `mapping.txt`); ciclo de vida (rotação, processo morto em segundo plano); trabalho pesado na main thread (ANR).

## Dart / Flutter

| Tarefa | Comando |
|---|---|
| Dependências | `flutter pub get` · `flutter pub outdated` · `flutter pub deps` |
| Análise / formatação | `flutter analyze` · `dart format --output=none --set-exit-if-changed .` |
| Testes | `flutter test` · um teste: `flutter test test/x_test.dart --plain-name "nome"` · integração: `flutter test integration_test` |
| Ambiente | `flutter doctor -v` |
| Geração de código | `dart run build_runner build --delete-conflicting-outputs` |

- **Armadilhas**: código gerado desatualizado (`*.g.dart`, `*.freezed.dart`); versão do Flutter (`.fvmrc`/`fvm`); `setState` após `dispose`; canal de plataforma com implementação faltando em um dos lados; diferenças entre modo debug e release.

## Elixir

`mix deps.get` · `mix compile --warnings-as-errors` · `mix test` (um: `mix test test/x_test.exs:42`) · `mix format --check-formatted` · `mix credo --strict` · `mix dialyzer` · `mix hex.audit` · `mix deps.audit` · Phoenix: `mix phx.routes`, `mix ecto.migrations`.

Armadilhas: processo que morre em silêncio sem supervisão adequada; caixa de mensagens crescendo; configuração de compilação × de execução (`config/runtime.exs`).

## Scala

`sbt compile` · `sbt test` · um teste: `sbt "testOnly pacote.Classe -- -z \"trecho\""` · `sbt scalafmtCheckAll` · `sbt dependencyTree` · `sbt dependencyUpdates` (plugin sbt-updates).

## Shell

`shellcheck script.sh` · `shfmt -d script.sh` · `bash -n script.sh` (sintaxe) · `bash -x script.sh` (rastreio) · testes: `bats test/`.

Armadilhas: falta de `set -euo pipefail`; variável sem aspas; diferenças bash × sh × zsh e GNU × BSD (`sed -i`, `date`, `readlink`); `cd` sem checar falha; `rm -rf "$VAR/"` com variável vazia.

## SQL e bancos

- **Plano de execução**: PostgreSQL `EXPLAIN (ANALYZE, BUFFERS) <consulta>` (executa de verdade — cuidado com escrita) · MySQL `EXPLAIN ANALYZE` · SQL Server `SET STATISTICS IO, TIME ON` · Oracle `EXPLAIN PLAN FOR` + `DBMS_XPLAN.DISPLAY`.
- **O que está rodando / travando**: PostgreSQL `pg_stat_activity`, `pg_locks`, extensão `pg_stat_statements` · MySQL `SHOW FULL PROCESSLIST`, `performance_schema` · SQL Server `sys.dm_exec_requests`.
- **Esquema**: `pg_dump --schema-only` · `mysqldump --no-data` · `sqlite3 arquivo.db .schema`.
- **Lint**: `sqlfluff lint`.
- **Migrações**: confira o estado antes de mexer (`alembic current`, `flyway info`, `liquibase status`, `prisma migrate status`, `rails db:migrate:status`, `php artisan migrate:status`). Nunca edite migração já aplicada em algum ambiente — crie uma nova.
- **Armadilhas**: índice ausente ou não usado (função na coluna, tipo divergente, `LIKE '%x'`); N+1 vindo do ORM; transação longa segurando lock; `NULL` em comparação e em `NOT IN`; fuso horário e `timestamp` sem zona; collation; `ALTER TABLE` que reescreve tabela grande em produção.

## Containers e infraestrutura

| Área | Comandos |
|---|---|
| Docker | `docker build --progress=plain .` · `docker run --rm -it --entrypoint sh <imagem>` · `docker logs -f --tail 200 <c>` · `docker inspect <c>` · `docker history <imagem>` · `hadolint Dockerfile` |
| Compose | `docker compose config` (mostra a config resolvida) · `up -d` · `logs -f <svc>` · `exec <svc> sh` · `ps` |
| Kubernetes | `kubectl get pods -A` · `describe pod <p>` (eventos explicam a maioria dos problemas) · `logs <p> -c <c> --previous` · `get events --sort-by=.lastTimestamp` · `rollout status/history deploy/<d>` · `kubectl diff -f` antes de aplicar |
| Helm | `helm template . -f values.yaml` · `helm lint` · `helm diff upgrade` (plugin) |
| Terraform | `terraform fmt -check` · `validate` · `plan` (leia tudo; `apply` e `destroy` só com pedido explícito) · `tflint` · `trivy config .` |
| CI | GitHub Actions: `actionlint` · rode localmente os mesmos comandos do workflow antes de culpar o runner |

Armadilhas: imagem `latest` mudando sob os pés; diferença de arquitetura (arm64 × amd64); variável de ambiente ausente no container; `localhost` dentro do container não é o host; limites de memória matando o processo (`OOMKilled`); probes de liveness mal calibradas reiniciando serviço lento.

## Legado

| Tecnologia | Como abordar |
|---|---|
| COBOL | GnuCOBOL: `cobc -x programa.cbl` · `cobc -fsyntax-only` · copybooks (`.cpy`) definem os layouts de dados — comece por eles |
| Delphi / Pascal | Free Pascal/Lazarus compila parte do código: `fpc programa.pas` · `.dfm` descreve os formulários em texto |
| VB6 / VBA / Classic ASP | Sem toolchain moderno: leitura estática; `.frm`/`.bas`/`.cls` são texto; a lógica costuma estar nos eventos dos formulários |
| PL/SQL / T-SQL | A lógica mora no banco: extraia procedures, triggers e views do catálogo (`ALL_SOURCE`, `sys.sql_modules`) e versione antes de alterar |
| Perl | `perl -c script.pl` · `perl -d` · `prove -lr t/` · `perlcritic` |
| .NET Framework / WebForms | Exige Windows + MSBuild; `web.config` concentra a configuração |
| Java EE antigo | Descritores XML (`web.xml`, `ejb-jar.xml`, `struts-config.xml`) dizem quem chama quem |

Em qualquer legado: descubra o que é executado em produção (cron, serviço, instalador), versione o estado atual antes de tocar, e crie testes de caracterização antes da primeira mudança. A skill `engenharia-reversa` (referência de código legado) detalha o processo.

## Ferramentas que servem para qualquer linguagem

- **Busca**: `rg -n "padrão" -g '*.ext'` · `rg -l` (só arquivos) · `rg -U` (multilinha) · `fd nome`.
- **Busca estrutural**: `ast-grep run -p 'console.log($$$)' -l ts` — acha padrões de código ignorando formatação; ótimo para localizar as "irmãs" de um defeito.
- **Histórico**: `git log -S'texto' --oneline` (quando o texto entrou/saiu) · `git log -L :funcao:arquivo` · `git blame -w -C` · `git bisect start <ruim> <bom> && git bisect run <cmd>`.
- **Análise estática**: `semgrep scan --config auto` · **segredos**: `gitleaks detect` · **vulnerabilidades**: `trivy fs .` · `osv-scanner scan -r .`
- **Medição**: `hyperfine '<cmd>'` · `time` · `cloc .`
- **Dados**: `jq` (JSON) · `yq` (YAML) · `sqlite3` · `xxd`/`hexdump -C` (binário).
- **Rede**: `curl -v` · `curl -w '%{time_total}\n' -o /dev/null -s <url>` · `openssl s_client -connect host:443 -servername host` · `dig` · `ss -ltnp` / `lsof -i :porta`.
- **Processo**: `strace -f -e trace=network,file <cmd>` (Linux) · `lsof -p <pid>` · `ps aux --sort=-%mem`.
