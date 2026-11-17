#!/usr/bin/env bash
# detectar-stack.sh — mapeia linguagens, gerenciadores de pacote, frameworks,
# testes, infraestrutura e arquitetura provável de um repositório.
#
# Uso: detectar-stack.sh [diretório]        (padrão: diretório atual)
#
# Só lê arquivos; não instala nem altera nada. Compatível com bash 3.2 (macOS).
set -u

RAIZ="${1:-.}"
cd "$RAIZ" 2>/dev/null || { echo "erro: diretório não encontrado: $RAIZ" >&2; exit 1; }

LISTA="$(mktemp)"
trap 'rm -f "$LISTA" "$LISTA.tmp"' EXIT

# --- inventário de arquivos ---------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -co --exclude-standard 2>/dev/null > "$LISTA"
fi
if [ ! -s "$LISTA" ]; then
  find . \( -name .git -o -name node_modules -o -name .venv -o -name venv \
            -o -name __pycache__ -o -name .gradle -o -name .terraform \) -prune \
         -o -type f -print 2>/dev/null | sed 's|^\./||' > "$LISTA"
fi
# dependências vendorizadas e saídas de build distorcem a contagem
grep -Ev '(^|/)(node_modules|vendor|third_party|\.venv|venv|dist|target|Pods|\.gradle|__pycache__|\.next|\.nuxt|coverage)/' \
  "$LISTA" > "$LISTA.tmp" || true
mv "$LISTA.tmp" "$LISTA"

TOTAL=$(wc -l < "$LISTA" | tr -d ' ')
if [ "$TOTAL" -eq 0 ]; then
  echo "Nenhum arquivo encontrado em $(pwd)."
  exit 0
fi

# --- utilitários --------------------------------------------------------------
tem()      { grep -Eq -- "$1" "$LISTA"; }
conta()    { grep -Ec -- "$1" "$LISTA"; }
exemplos() { grep -E -- "$1" "$LISTA" | head -n "${2:-4}" | sed 's/^/    - /'; }

# conteudo <regex de caminho> <regex de conteúdo>: algum arquivo casa com ambos?
conteudo() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && grep -Eqi -- "$2" "$f" 2>/dev/null && return 0
  done <<EOF
$(grep -E -- "$1" "$LISTA" | head -n 40)
EOF
  return 1
}

ACHADOS=""
anota() { ACHADOS="${ACHADOS}${ACHADOS:+, }$1"; }
# fw <rótulo> <regex de caminho> <regex de conteúdo>
fw() { conteudo "$2" "$3" && anota "$1"; return 0; }

secao() { printf '\n## %s\n' "$1"; }

echo "# Mapa do repositório: $(basename "$(pwd)")"
echo
echo "- Caminho: $(pwd)"
echo "- Arquivos analisados: $TOTAL"

# --- linguagens ---------------------------------------------------------------
secao "Linguagens (por número de arquivos)"
awk -F. 'NF>1 {
  e=tolower($NF); l=""
  if (e ~ /^(ts|tsx|mts|cts)$/) l="TypeScript"
  else if (e ~ /^(js|jsx|mjs|cjs)$/) l="JavaScript"
  else if (e ~ /^(py|pyi)$/) l="Python"
  else if (e == "java") l="Java"
  else if (e ~ /^(kt|kts)$/) l="Kotlin"
  else if (e ~ /^(cs|csx)$/) l="C#"
  else if (e ~ /^(fs|fsx)$/) l="F#"
  else if (e == "vb") l="Visual Basic"
  else if (e == "go") l="Go"
  else if (e == "rs") l="Rust"
  else if (e == "php") l="PHP"
  else if (e ~ /^(rb|erb|rake)$/) l="Ruby"
  else if (e ~ /^(c|h)$/) l="C"
  else if (e ~ /^(cpp|cc|cxx|hpp|hh|hxx)$/) l="C++"
  else if (e == "swift") l="Swift"
  else if (e ~ /^(m|mm)$/) l="Objective-C"
  else if (e == "dart") l="Dart"
  else if (e ~ /^(ex|exs|heex)$/) l="Elixir"
  else if (e == "erl") l="Erlang"
  else if (e ~ /^(scala|sc)$/) l="Scala"
  else if (e ~ /^(clj|cljs|cljc)$/) l="Clojure"
  else if (e ~ /^(hs|lhs)$/) l="Haskell"
  else if (e == "lua") l="Lua"
  else if (e ~ /^(pl|pm)$/) l="Perl"
  else if (e == "r") l="R"
  else if (e == "jl") l="Julia"
  else if (e ~ /^(sh|bash|zsh)$/) l="Shell"
  else if (e ~ /^(ps1|psm1)$/) l="PowerShell"
  else if (e == "sql") l="SQL"
  else if (e == "vue") l="Vue (SFC)"
  else if (e == "svelte") l="Svelte"
  else if (e == "astro") l="Astro"
  else if (e ~ /^(html|htm)$/) l="HTML"
  else if (e ~ /^(css|scss|sass|less)$/) l="CSS"
  else if (e ~ /^(tf|hcl)$/) l="Terraform/HCL"
  else if (e == "proto") l="Protobuf"
  else if (e ~ /^(graphql|gql)$/) l="GraphQL"
  else if (e ~ /^(cbl|cob|cpy)$/) l="COBOL"
  else if (e ~ /^(pas|dpr)$/) l="Pascal/Delphi"
  else if (e ~ /^(asm|s)$/) l="Assembly"
  else if (e == "sol") l="Solidity"
  else if (e == "zig") l="Zig"
  else if (e == "groovy") l="Groovy"
  if (l != "") c[l]++
}
END { for (l in c) printf "%d\t%s\n", c[l], l }' "$LISTA" | sort -rn | head -n 15 |
  awk -F'\t' '{ printf "- %s: %s arquivos\n", $2, $1 } END { if (NR==0) print "- Nenhuma linguagem de programação reconhecida pelas extensões." }'

# --- ecossistemas e comandos --------------------------------------------------
secao "Ecossistemas, manifestos e comandos prováveis"
ECOS=0
eco() { ECOS=$((ECOS+1)); printf '\n### %s\n' "$1"; }

if tem '(^|/)package\.json$'; then
  eco "JavaScript/TypeScript (Node)"
  echo "- Manifestos ($(conta '(^|/)package\.json$')):"; exemplos '(^|/)package\.json$'
  GP="npm"; LOCK=0
  tem '(^|/)(package-lock|npm-shrinkwrap)\.json$' && LOCK=1
  tem '(^|/)pnpm-lock\.yaml$' && { GP="pnpm"; LOCK=1; }
  tem '(^|/)yarn\.lock$' && { GP="yarn"; LOCK=1; }
  tem '(^|/)bun\.lockb?$' && { GP="bun"; LOCK=1; }
  PM_DECL=""
  [ -f package.json ] && PM_DECL=$(grep -Eo '"packageManager"[[:space:]]*:[[:space:]]*"[^"]+"' package.json 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
  if [ -n "$PM_DECL" ]; then
    echo "- Gerenciador declarado em packageManager: $PM_DECL"
    GP="${PM_DECL%%@*}"
  elif [ "$LOCK" -eq 1 ]; then
    echo "- Gerenciador (pelo lockfile): $GP"
  else
    echo "- Gerenciador: nenhum lockfile encontrado — npm presumido. Sem lockfile, as versões instaladas não são reprodutíveis e \`npm ci\` falha (use \`npm install\`)."
  fi
  if tem '(^|/)(pnpm-workspace\.yaml|nx\.json|turbo\.json|lerna\.json)$' || conteudo '^package\.json$' '"workspaces"'; then
    echo "- Monorepo/workspaces detectado ($(grep -E '(^|/)(pnpm-workspace\.yaml|nx\.json|turbo\.json|lerna\.json)$' "$LISTA" | tr '\n' ' '))"
  fi
  if [ -f package.json ]; then
    if command -v jq >/dev/null 2>&1; then
      S=$(jq -r '(.scripts // {}) | keys | join(", ")' package.json 2>/dev/null)
    else
      S=$(sed -n '/"scripts"/,/}/p' package.json | grep -Eo '^[[:space:]]*"[^"]+"[[:space:]]*:' | tr -d ' ":\t' | grep -v '^scripts$' | tr '\n' ' ')
    fi
    [ -n "${S:-}" ] && echo "- Scripts do package.json raiz: $S"
    [ -f .nvmrc ] && echo "- Versão do Node (.nvmrc): $(cat .nvmrc)"
  fi
  case "$GP" in
    npm)  if [ "$LOCK" -eq 1 ]; then INST="npm ci"; else INST="npm install"; fi
          echo "- Comandos: \`$INST\` · \`npm test\` · \`npm run build\` · \`npm run lint\` · \`npm audit\` (test/build/lint só existem se estiverem em \"scripts\")" ;;
    pnpm) echo "- Comandos: \`pnpm install --frozen-lockfile\` · \`pnpm test\` · \`pnpm build\` · \`pnpm lint\` · \`pnpm audit\`" ;;
    yarn) echo "- Comandos: \`yarn install --frozen-lockfile\` (v1) ou \`--immutable\` (v2+) · \`yarn test\` · \`yarn build\` · \`yarn lint\`" ;;
    bun)  echo "- Comandos: \`bun install --frozen-lockfile\` · \`bun test\` · \`bun run build\`" ;;
  esac
  tem '(^|/)tsconfig[^/]*\.json$' && echo "- TypeScript: checagem de tipos com \`npx tsc --noEmit\`"
fi
if tem '(^|/)deno\.jsonc?$'; then
  eco "Deno"; echo "- Config:"; exemplos '(^|/)deno\.jsonc?$'
  echo "- Comandos: \`deno task\` · \`deno test\` · \`deno lint\` · \`deno fmt --check\`"
fi

if tem '(^|/)(pyproject\.toml|requirements[^/]*\.txt|setup\.py|setup\.cfg|Pipfile|environment\.ya?ml)$'; then
  eco "Python"
  echo "- Manifestos:"; exemplos '(^|/)(pyproject\.toml|requirements[^/]*\.txt|setup\.py|Pipfile|environment\.ya?ml)$' 6
  GP="pip"
  tem '(^|/)Pipfile$' && GP="pipenv"
  tem '(^|/)environment\.ya?ml$' && GP="conda"
  tem '(^|/)poetry\.lock$' && GP="poetry"
  tem '(^|/)pdm\.lock$' && GP="pdm"
  tem '(^|/)uv\.lock$' && GP="uv"
  echo "- Gerenciador provável: $GP"
  case "$GP" in
    poetry) echo "- Comandos: \`poetry install\` · \`poetry run pytest\`" ;;
    uv)     echo "- Comandos: \`uv sync\` · \`uv run pytest\`" ;;
    pipenv) echo "- Comandos: \`pipenv install --dev\` · \`pipenv run pytest\`" ;;
    pdm)    echo "- Comandos: \`pdm install\` · \`pdm run pytest\`" ;;
    conda)  echo "- Comandos: \`conda env create -f environment.yml\` · \`pytest\`" ;;
    *)      echo "- Comandos: \`python -m venv .venv && . .venv/bin/activate\` · \`pip install -r requirements.txt\` (ou \`pip install -e .\`) · \`pytest\`" ;;
  esac
  echo "- Qualidade: \`ruff check .\` · \`mypy .\` · \`pip-audit\` (use os que o projeto configurar)"
  tem '(^|/)manage\.py$' && echo "- Django: \`python manage.py test\` · \`python manage.py check\` · \`python manage.py makemigrations --check\`"
  tem '(^|/)tox\.ini$' && echo "- tox configurado: \`tox\`"
  tem '(^|/)noxfile\.py$' && echo "- nox configurado: \`nox\`"
fi

if tem '(^|/)pom\.xml$'; then
  eco "Java/Kotlin — Maven"
  echo "- Módulos ($(conta '(^|/)pom\.xml$') pom.xml):"; exemplos '(^|/)pom\.xml$'
  MVN="mvn"; tem '(^|/)mvnw$' && MVN="./mvnw"
  echo "- Comandos: \`$MVN -q -DskipTests package\` · \`$MVN test\` · \`$MVN verify\` · \`$MVN dependency:tree\`"
fi
if tem '(^|/)(build|settings)\.gradle(\.kts)?$'; then
  eco "Java/Kotlin — Gradle"
  echo "- Builds ($(conta '(^|/)build\.gradle(\.kts)?$')):"; exemplos '(^|/)build\.gradle(\.kts)?$'
  GR="gradle"; tem '(^|/)gradlew$' && GR="./gradlew"
  echo "- Comandos: \`$GR build\` · \`$GR test\` · \`$GR check\` · \`$GR dependencies\`"
  tem '(^|/)AndroidManifest\.xml$' && echo "- Android: \`$GR assembleDebug\` · \`$GR testDebugUnitTest\` · \`$GR lint\`"
fi
if tem '(^|/)build\.sbt$'; then
  eco "Scala — sbt"; echo "- Comandos: \`sbt compile\` · \`sbt test\`"
fi

if tem '\.(sln|csproj|fsproj|vbproj)$'; then
  eco ".NET"
  echo "- Soluções/projetos:"; exemplos '\.(sln|csproj|fsproj|vbproj)$' 6
  echo "- Comandos: \`dotnet restore\` · \`dotnet build\` · \`dotnet test\` · \`dotnet list package --vulnerable\` · \`dotnet format --verify-no-changes\`"
fi

if tem '(^|/)go\.(mod|work)$'; then
  eco "Go"
  echo "- Módulos ($(conta '(^|/)go\.mod$')):"; exemplos '(^|/)go\.(mod|work)$'
  echo "- Comandos: \`go build ./...\` · \`go test ./...\` · \`go vet ./...\` · \`go test -race ./...\` · \`govulncheck ./...\`"
  tem '(^|/)\.golangci\.(ya?ml|toml)$' && echo "- Lint: \`golangci-lint run\`"
fi

if tem '(^|/)Cargo\.toml$'; then
  eco "Rust"
  echo "- Crates ($(conta '(^|/)Cargo\.toml$')):"; exemplos '(^|/)Cargo\.toml$'
  echo "- Comandos: \`cargo build\` · \`cargo test\` · \`cargo clippy --all-targets\` · \`cargo fmt --check\` · \`cargo audit\`"
fi

if tem '(^|/)composer\.json$'; then
  eco "PHP"
  echo "- Manifestos:"; exemplos '(^|/)composer\.json$'
  echo "- Comandos: \`composer install\` · \`vendor/bin/phpunit\` (ou \`vendor/bin/pest\`) · \`composer audit\` · \`vendor/bin/phpstan analyse\`"
  tem '(^|/)artisan$' && echo "- Laravel: \`php artisan test\` · \`php artisan route:list\` · \`php artisan migrate:status\`"
fi

if tem '(^|/)Gemfile$'; then
  eco "Ruby"
  echo "- Manifestos:"; exemplos '(^|/)Gemfile$'
  echo "- Comandos: \`bundle install\` · \`bundle exec rspec\` (ou \`bin/rails test\`) · \`bundle exec rubocop\` · \`bundle audit\`"
fi

if tem '(^|/)mix\.exs$'; then
  eco "Elixir"; echo "- Comandos: \`mix deps.get\` · \`mix test\` · \`mix format --check-formatted\` · \`mix credo\`"
fi

if tem '(^|/)pubspec\.yaml$'; then
  eco "Dart/Flutter"
  echo "- Manifestos:"; exemplos '(^|/)pubspec\.yaml$'
  if conteudo '(^|/)pubspec\.yaml$' 'sdk:[[:space:]]*flutter'; then
    echo "- Comandos: \`flutter pub get\` · \`flutter analyze\` · \`flutter test\` · \`flutter build apk|ios|web\`"
  else
    echo "- Comandos: \`dart pub get\` · \`dart analyze\` · \`dart test\`"
  fi
fi

if tem '(^|/)Package\.swift$|\.xcodeproj/|\.xcworkspace/|(^|/)Podfile$'; then
  eco "Swift / plataformas Apple"
  echo "- Projetos:"; exemplos '(^|/)Package\.swift$|(^|/)Podfile$|\.xcodeproj/project\.pbxproj$' 5
  echo "- Comandos: \`swift build\` · \`swift test\` (SwiftPM) · \`xcodebuild -list\` e \`xcodebuild test -scheme <esquema>\` (Xcode, só em macOS)"
fi

if tem '(^|/)(CMakeLists\.txt|meson\.build|conanfile\.(txt|py)|vcpkg\.json|configure\.ac)$'; then
  eco "C/C++"
  echo "- Builds:"; exemplos '(^|/)(CMakeLists\.txt|meson\.build|conanfile\.(txt|py)|vcpkg\.json|configure\.ac)$' 5
  tem '(^|/)CMakeLists\.txt$' && echo "- CMake: \`cmake -S . -B build\` · \`cmake --build build\` · \`ctest --test-dir build\`"
  tem '(^|/)meson\.build$' && echo "- Meson: \`meson setup build\` · \`meson test -C build\`"
fi

if tem '(^|/)(Makefile|makefile|GNUmakefile|justfile|Justfile|Taskfile\.ya?ml)$'; then
  eco "Automação de tarefas"
  echo "- Arquivos:"; exemplos '(^|/)(Makefile|makefile|GNUmakefile|justfile|Justfile|Taskfile\.ya?ml)$' 5
  if [ -f Makefile ] || [ -f makefile ] || [ -f GNUmakefile ]; then
    ALVOS=$(grep -Eho '^[A-Za-z0-9_.-]+:([^=]|$)' Makefile makefile GNUmakefile 2>/dev/null | cut -d: -f1 | grep -v '^\.' | sort -u | head -n 25 | tr '\n' ' ')
    [ -n "$ALVOS" ] && echo "- Alvos do Makefile raiz: $ALVOS"
  fi
fi

[ "$ECOS" -eq 0 ] && echo "Nenhum manifesto conhecido encontrado — pode ser código legado, scripts soltos ou artefatos compilados (veja a skill de engenharia reversa)."

# --- frameworks e bibliotecas -------------------------------------------------
secao "Frameworks e bibliotecas detectados"
PJ='(^|/)package\.json$'
PY='(^|/)(pyproject\.toml|requirements[^/]*\.txt|setup\.py|setup\.cfg|Pipfile)$'
JV='(^|/)(pom\.xml|build\.gradle(\.kts)?|libs\.versions\.toml)$'
NET='\.(csproj|fsproj)$|(^|/)Directory\.Packages\.props$'
GOM='(^|/)go\.mod$'
CRG='(^|/)Cargo\.toml$'
CMP='(^|/)composer\.json$'
GEM='(^|/)Gemfile$'

ALGUM_FW=0
ACHADOS=""
fw "React" "$PJ" '"react"[[:space:]]*:'
fw "Next.js" "$PJ" '"next"[[:space:]]*:'
fw "Vue" "$PJ" '"vue"[[:space:]]*:'
fw "Nuxt" "$PJ" '"nuxt"[[:space:]]*:'
fw "Angular" "$PJ" '"@angular/core"'
fw "Svelte/SvelteKit" "$PJ" '"(svelte|@sveltejs/kit)"'
fw "Remix" "$PJ" '"@remix-run/'
fw "Astro" "$PJ" '"astro"[[:space:]]*:'
fw "React Native" "$PJ" '"react-native"[[:space:]]*:'
fw "Expo" "$PJ" '"expo"[[:space:]]*:'
fw "Electron" "$PJ" '"electron"[[:space:]]*:'
fw "Ionic/Capacitor/Cordova" "$PJ" '"(@ionic/|@capacitor/core|cordova)'
fw "Tailwind CSS" "$PJ" '"tailwindcss"'
fw "Vite" "$PJ" '"vite"[[:space:]]*:'
fw "Webpack" "$PJ" '"webpack"[[:space:]]*:'
[ -n "$ACHADOS" ] && { ALGUM_FW=1; echo "- Frontend/cliente: $ACHADOS"; }

ACHADOS=""
fw "Express" "$PJ" '"express"[[:space:]]*:'
fw "Fastify" "$PJ" '"fastify"[[:space:]]*:'
fw "NestJS" "$PJ" '"@nestjs/core"'
fw "Koa" "$PJ" '"koa"[[:space:]]*:'
fw "Hono" "$PJ" '"hono"[[:space:]]*:'
fw "Django" "$PY" '(^|[^a-z])django([^a-z-]|$)'
fw "Flask" "$PY" '(^|[^a-z])flask([^a-z-]|$)'
fw "FastAPI" "$PY" 'fastapi'
fw "Celery" "$PY" 'celery'
fw "Spring Boot" "$JV" 'spring-boot'
fw "Quarkus" "$JV" 'quarkus'
fw "Micronaut" "$JV" 'micronaut'
fw "Ktor" "$JV" 'io\.ktor'
fw "ASP.NET Core" '\.(csproj|fsproj)$' 'Microsoft\.NET\.Sdk\.Web|Microsoft\.AspNetCore'
fw "Gin" "$GOM" 'gin-gonic/gin'
fw "Echo" "$GOM" 'labstack/echo'
fw "Fiber" "$GOM" 'gofiber/fiber'
fw "chi" "$GOM" 'go-chi/chi'
fw "Actix Web" "$CRG" 'actix-web'
fw "Axum" "$CRG" '(^|[^a-z])axum'
fw "Rocket" "$CRG" '^rocket'
fw "Laravel" "$CMP" 'laravel/framework'
fw "Symfony" "$CMP" 'symfony/framework-bundle'
fw "Rails" "$GEM" "gem ['\"]rails['\"]"
fw "Sinatra" "$GEM" "gem ['\"]sinatra['\"]"
fw "Phoenix" '(^|/)mix\.exs$' ':phoenix'
tem '(^|/)wp-config(-sample)?\.php$' && anota "WordPress"
[ -n "$ACHADOS" ] && { ALGUM_FW=1; echo "- Backend/servidor: $ACHADOS"; }

ACHADOS=""
fw "Prisma" "$PJ" '"(prisma|@prisma/client)"'
fw "TypeORM" "$PJ" '"typeorm"'
fw "Sequelize" "$PJ" '"sequelize"'
fw "Drizzle" "$PJ" '"drizzle-orm"'
fw "Mongoose" "$PJ" '"mongoose"'
fw "SQLAlchemy" "$PY" 'sqlalchemy'
fw "Alembic" "$PY" 'alembic'
fw "Hibernate/JPA" "$JV" 'hibernate|spring-boot-starter-data-jpa|jakarta\.persistence'
fw "Flyway" "$JV" 'flyway'
fw "Liquibase" "$JV" 'liquibase'
fw "Entity Framework" "$NET" 'EntityFramework'
fw "Dapper" "$NET" 'Dapper'
fw "GORM" "$GOM" 'gorm\.io'
fw "sqlx" "$GOM|$CRG" 'sqlx'
fw "Diesel" "$CRG" '^diesel'
fw "Doctrine" "$CMP" 'doctrine/orm'
[ -n "$ACHADOS" ] && { ALGUM_FW=1; echo "- Dados/ORM/migrações: $ACHADOS"; }

ACHADOS=""
MANIF="$PJ|$PY|$JV|$NET|$GOM|$CRG|$CMP|$GEM"
fw "gRPC" "$MANIF" 'grpc'
fw "GraphQL" "$MANIF" 'graphql'
fw "Kafka" "$MANIF" 'kafka'
fw "RabbitMQ/AMQP" "$MANIF" 'amqp|rabbitmq|bunny|pika'
fw "NATS" "$MANIF" '(^|[^a-z])nats([^a-z]|$)'
fw "Redis" "$MANIF" 'redis'
fw "WebSocket/Socket.IO" "$MANIF" 'socket\.io|websocket|"ws"[[:space:]]*:'
fw "OpenTelemetry" "$MANIF" 'opentelemetry'
fw "Sentry" "$MANIF" 'sentry'
fw "AWS SDK" "$MANIF" 'aws-sdk|boto3|software\.amazon\.awssdk|AWSSDK'
[ -n "$ACHADOS" ] && { ALGUM_FW=1; echo "- Comunicação/observabilidade/nuvem: $ACHADOS"; }

ACHADOS=""
fw "Jest" "$PJ" '"jest"[[:space:]]*:'
fw "Vitest" "$PJ" '"vitest"'
fw "Mocha" "$PJ" '"mocha"'
fw "Playwright" "$PJ|$PY" 'playwright'
fw "Cypress" "$PJ" '"cypress"'
fw "Testing Library" "$PJ" '@testing-library/'
fw "pytest" "$PY|(^|/)(pytest\.ini|tox\.ini|conftest\.py)$" 'pytest'
fw "JUnit" "$JV" 'junit'
fw "Mockito" "$JV" 'mockito'
fw "Testcontainers" "$MANIF" 'testcontainers'
fw "xUnit/NUnit/MSTest" "$NET" 'xunit|nunit|MSTest'
fw "PHPUnit/Pest" "$CMP" 'phpunit|pestphp'
fw "RSpec" "$GEM" 'rspec'
[ -n "$ACHADOS" ] && { ALGUM_FW=1; echo "- Testes: $ACHADOS"; }

ACHADOS=""
fw "ESLint" "$PJ" '"eslint"'
tem '(^|/)(\.eslintrc[^/]*|eslint\.config\.[cm]?[jt]s)$' && case "$ACHADOS" in *ESLint*) ;; *) anota "ESLint" ;; esac
fw "Biome" "$PJ" '"@biomejs/biome"'
fw "Prettier" "$PJ" '"prettier"'
fw "Ruff" "$PY|(^|/)ruff\.toml$" 'ruff'
fw "mypy" "$PY|(^|/)mypy\.ini$" 'mypy'
fw "Black" "$PY" '(^|[^a-z])black([^a-z]|$)'
fw "flake8" "$PY|(^|/)\.flake8$" 'flake8'
tem '(^|/)\.golangci\.(ya?ml|toml)$' && anota "golangci-lint"
tem '(^|/)\.rubocop\.yml$' && anota "RuboCop"
tem '(^|/)phpstan\.neon(\.dist)?$' && anota "PHPStan"
tem '(^|/)(checkstyle|spotbugs|pmd)[^/]*\.xml$' && anota "Checkstyle/SpotBugs/PMD"
tem '(^|/)\.editorconfig$' && anota "EditorConfig"
tem '(^|/)\.pre-commit-config\.yaml$' && anota "pre-commit"
tem '(^|/)\.husky/' && anota "Husky"
tem '(^|/)sonar-project\.properties$' && anota "SonarQube"
[ -n "$ACHADOS" ] && { ALGUM_FW=1; echo "- Lint/formatação/qualidade: $ACHADOS"; }
[ "$ALGUM_FW" -eq 0 ] && echo "- Nenhum framework conhecido identificado nos manifestos."

# --- testes -------------------------------------------------------------------
secao "Testes"
RE_TESTE='(^|/)(tests?|__tests__|specs?|e2e|integration[-_]tests?)/|\.(test|spec)\.[cm]?[jt]sx?$|_test\.(go|py|rb|exs|dart)$|(^|/)test_[^/]*\.py$|(Tests?|IT|Spec)\.(java|kt|cs|scala|groovy|swift)$|_spec\.rb$|Test\.php$'
NT=$(conta "$RE_TESTE")
echo "- Arquivos de teste (heurística): $NT de $TOTAL"
[ "$NT" -eq 0 ] && echo "- ATENÇÃO: nenhum teste encontrado — qualquer correção precisa começar criando um teste de caracterização do comportamento atual."
[ "$NT" -gt 0 ] && exemplos "$RE_TESTE" 4

# --- infraestrutura -----------------------------------------------------------
secao "Infraestrutura, entrega e contratos"
ND=$(conta '(^|/)[^/]*Dockerfile[^/]*$|(^|/)Containerfile$')
[ "$ND" -gt 0 ] && { echo "- Dockerfiles: $ND"; exemplos '(^|/)[^/]*Dockerfile[^/]*$|(^|/)Containerfile$' 8; }
RE_COMPOSE='(^|/)(docker-)?compose[^/]*\.ya?ml$'
NSVC=0
if tem "$RE_COMPOSE"; then
  echo "- Docker Compose:"; exemplos "$RE_COMPOSE" 4
  CF=$(grep -E -- "$RE_COMPOSE" "$LISTA" | head -n 1)
  # serviços = chaves com 2 espaços de recuo dentro do bloco "services:"
  SVCS=$(awk '/^services:/ {s=1; next} /^[^[:space:]#]/ {s=0} s && /^  [A-Za-z0-9_.-]+:/ {gsub(/[ :]/,""); print}' "$CF" 2>/dev/null)
  NSVC=$(printf '%s\n' "$SVCS" | grep -c . || true)
  [ "$NSVC" -gt 0 ] && echo "- Serviços em $CF ($NSVC): $(printf '%s' "$SVCS" | tr '\n' ' ')"
fi
K8S=0
if conteudo '\.ya?ml$' '^kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|CronJob|Ingress|Service)'; then K8S=1; echo "- Manifestos Kubernetes presentes"; fi
tem '(^|/)Chart\.yaml$' && { K8S=1; echo "- Helm charts: $(conta '(^|/)Chart\.yaml$')"; }
tem '(^|/)kustomization\.ya?ml$' && echo "- Kustomize presente"
tem '\.tf$' && echo "- Terraform: $(conta '\.tf$') arquivos .tf (\`terraform validate\`, \`terraform plan\` — nunca \`apply\` sem pedido explícito)"
tem '(^|/)serverless\.(ya?ml|ts|js)$' && echo "- Serverless Framework presente"
tem '(^|/)(template|sam)\.ya?ml$' && conteudo '(^|/)(template|sam)\.ya?ml$' 'AWS::Serverless' && echo "- AWS SAM presente"
tem '(^|/)(vercel|netlify|fly|render|app)\.(json|toml|ya?ml)$' && echo "- Config de PaaS: $(grep -E '(^|/)(vercel\.json|netlify\.toml|fly\.toml|render\.ya?ml|app\.ya?ml)$' "$LISTA" | head -n 5 | tr '\n' ' ')"

ACHADOS=""
tem '^\.github/workflows/' && anota "GitHub Actions ($(conta '^\.github/workflows/') workflows)"
tem '(^|/)\.gitlab-ci\.yml$' && anota "GitLab CI"
tem '(^|/)Jenkinsfile' && anota "Jenkins"
tem '(^|/)azure-pipelines[^/]*\.ya?ml$' && anota "Azure Pipelines"
tem '^\.circleci/' && anota "CircleCI"
tem '(^|/)bitbucket-pipelines\.yml$' && anota "Bitbucket Pipelines"
tem '(^|/)\.travis\.yml$' && anota "Travis CI"
if [ -n "$ACHADOS" ]; then
  echo "- CI/CD: $ACHADOS — a pipeline é a fonte mais confiável dos comandos reais de build e teste"
else
  echo "- CI/CD: nenhuma pipeline encontrada"
fi

ACHADOS=""
tem '(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$' && anota "OpenAPI/Swagger"
tem '\.proto$' && anota "Protobuf/gRPC ($(conta '\.proto$') .proto)"
tem '\.(graphql|gql)$' && anota "esquemas GraphQL"
tem '(^|/)asyncapi[^/]*\.(ya?ml|json)$' && anota "AsyncAPI"
tem '(^|/)pacts?/' && anota "contratos Pact"
[ -n "$ACHADOS" ] && echo "- Contratos de API: $ACHADOS"

RE_MIG='(^|/)(migrations?|db/migrate|alembic/versions|flyway|liquibase|changelogs?)/'
tem "$RE_MIG" && echo "- Migrações de banco: $(conta "$RE_MIG") arquivos (ex.: $(grep -E -- "$RE_MIG" "$LISTA" | head -n 1))"

ACHADOS=""
RE_CFG="$RE_COMPOSE|(^|/)\.env[^/]*(example|sample|dist|template)[^/]*$|(^|/)application[^/]*\.(ya?ml|properties)$|(^|/)appsettings[^/]*\.json$|(^|/)config/[^/]*\.(ya?ml|json|exs|rb|php)$"
fw "PostgreSQL" "$RE_CFG|$MANIF" 'postgres|psycopg|npgsql'
fw "MySQL/MariaDB" "$RE_CFG|$MANIF" 'mysql|mariadb'
fw "SQL Server" "$RE_CFG|$MANIF" 'sqlserver|mssql'
fw "Oracle" "$RE_CFG|$MANIF" 'ojdbc|oracle\.jdbc|cx_oracle|oracledb'
fw "SQLite" "$RE_CFG|$MANIF" 'sqlite'
fw "MongoDB" "$RE_CFG|$MANIF" 'mongo'
fw "Redis" "$RE_CFG" 'redis'
fw "Elasticsearch/OpenSearch" "$RE_CFG|$MANIF" 'elasticsearch|opensearch'
fw "Kafka" "$RE_CFG" 'kafka'
fw "RabbitMQ" "$RE_CFG" 'rabbitmq|amqp'
fw "DynamoDB" "$RE_CFG|$MANIF" 'dynamodb'
[ -n "$ACHADOS" ] && echo "- Bancos e mensageria citados em config/manifestos: $ACHADOS"

# --- arquitetura provável -----------------------------------------------------
secao "Arquitetura provável (heurística — confirme lendo o código)"
# unidades = diretórios distintos que contêm manifesto de aplicação
RE_MANIF_APP='(^|/)(package\.json|pyproject\.toml|requirements\.txt|pom\.xml|build\.gradle(\.kts)?|go\.mod|Cargo\.toml|composer\.json|Gemfile|mix\.exs|pubspec\.yaml)$|\.csproj$'
UNIDADES=$(grep -E -- "$RE_MANIF_APP" "$LISTA" | sed 's|/[^/]*$||; s|^[^/]*\.[^/]*$|.|' | sort -u)
NU=$(printf '%s\n' "$UNIDADES" | grep -c . || true)
DIRS_DOCKER=$(grep -E '(^|/)[^/]*Dockerfile[^/]*$' "$LISTA" | sed 's|/[^/]*$||; s|^[^/]*Dockerfile[^/]*$|.|' | sort -u | grep -c . || true)
MOBILE=0
if tem '(^|/)AndroidManifest\.xml$|\.xcodeproj/|(^|/)Info\.plist$' || conteudo "$PJ" '"(react-native|expo)"' || conteudo '(^|/)pubspec\.yaml$' 'sdk:[[:space:]]*flutter'; then MOBILE=1; fi

echo "- Unidades com manifesto próprio: $NU · diretórios com Dockerfile: $DIRS_DOCKER · serviços no Compose: $NSVC · Kubernetes/Helm: $([ "$K8S" -eq 1 ] && echo sim || echo não)"
if [ "$DIRS_DOCKER" -ge 3 ] || { [ "$NU" -ge 3 ] && { [ "$K8S" -eq 1 ] || [ "$NSVC" -ge 3 ]; }; }; then
  echo "- Indício forte de **microsserviços / sistema distribuído**: várias unidades implantáveis. Mapeie quem chama quem (HTTP, gRPC, filas) antes de corrigir — veja a skill \`microservicos\`."
elif [ "$NU" -eq 0 ]; then
  echo "- Sem manifestos de aplicação: não dá para inferir a arquitetura pela estrutura. Leia os pontos de entrada (scripts, binários, configs) diretamente."
elif [ "$NU" -ge 3 ]; then
  echo "- Indício de **monorepo com vários pacotes/módulos** (pode ser monólito modular ou vários serviços). Verifique como cada unidade é implantada."
else
  echo "- Indício de **aplicação única (monólito ou biblioteca)**: poucas unidades implantáveis. Veja a skill \`monolito\` para localizar fronteiras internas."
fi
[ "$MOBILE" -eq 1 ] && echo "- Há **aplicativo móvel** no repositório (Android/iOS/Flutter/React Native)."
tem '\.(apk|aab|ipa|dex|jar|war|ear|dll|exe|so|dylib|wasm|class|pyc)$' &&
  echo "- Há **artefatos compilados versionados** ($(grep -Ec '\.(apk|aab|ipa|dex|jar|war|ear|dll|exe|so|dylib|wasm|class|pyc)$' "$LISTA")): se não houver fonte correspondente, veja a skill \`engenharia-reversa\`."
if [ "$NU" -gt 1 ]; then
  echo "- Unidades:"
  printf '%s\n' "$UNIDADES" | head -n 30 | sed 's/^/    - /'
  [ "$NU" -gt 30 ] && echo "    - … (+$((NU-30)))"
fi

# --- documentação e instruções ------------------------------------------------
secao "Documentação e instruções para agentes"
DOCS=$(grep -Ei '^(README[^/]*|CONTRIBUTING[^/]*|CLAUDE\.md|AGENTS\.md|ARCHITECTURE[^/]*|CHANGELOG[^/]*|docs/[^/]*\.md|\.claude/CLAUDE\.md)$' "$LISTA" | head -n 12)
if [ -n "$DOCS" ]; then printf '%s\n' "$DOCS" | sed 's/^/- /'; else echo "- Nenhum README/CONTRIBUTING/CLAUDE.md na raiz — a documentação terá de ser inferida do código."; fi

# --- histórico git ------------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
  secao "Histórico git"
  echo "- Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null) · commits: $(git rev-list --count HEAD 2>/dev/null) · último: $(git log -1 --format='%ad — %s' --date=short 2>/dev/null)"
  [ -n "$(git status --porcelain 2>/dev/null | head -n 1)" ] && echo "- Há alterações não commitadas na árvore de trabalho — não as sobrescreva."
  QUENTES=$(git log -n 400 --since='12 months ago' --name-only --format= 2>/dev/null | grep -v '^$' |
            grep -Ev '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Cargo\.lock|go\.sum|composer\.lock|Gemfile\.lock)$|^CHANGELOG' |
            sort | uniq -c | sort -rn | awk '$1 > 1' | head -n 10)
  if [ -n "$QUENTES" ]; then
    echo "- Arquivos mais alterados (últimos 400 commits / 12 meses) — onde bugs costumam se concentrar:"
    printf '%s\n' "$QUENTES" | awk '{ n=$1; $1=""; sub(/^ /,""); printf "    - %s (%s alterações)\n", $0, n }'
  fi
fi

echo
echo "_Heurística: confirme comandos na pipeline de CI, no README e nos scripts do projeto antes de assumir._"
