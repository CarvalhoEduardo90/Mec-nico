#!/usr/bin/env bash
# ferramentas.sh — verifica (e opcionalmente instala) as ferramentas de linha de
# comando usadas em manutenção de código e engenharia reversa.
#
# Uso: ferramentas.sh [geral|re|tudo] [--instalar]
#
#   geral       ferramentas de manutenção (busca, lint, auditoria, containers)
#   re          ferramentas de engenharia reversa (binários, mobile, rede, JS)
#   tudo        as duas categorias (padrão)
#   --instalar  tenta instalar o que falta (apt-get ou Homebrew; pip/npm/go/dotnet
#               para o que não está nos repositórios). Sem essa opção, só relata.
#
# Compatível com bash 3.2 (macOS). Nunca usa sudo interativo.
set -u

CATEGORIA="tudo"
INSTALAR=0
for arg in "$@"; do
  case "$arg" in
    geral|re|tudo) CATEGORIA="$arg" ;;
    --instalar) INSTALAR=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argumento desconhecido: $arg (use geral|re|tudo e/ou --instalar)" >&2; exit 2 ;;
  esac
done

# categoria|comandos (alternativas separadas por vírgula)|pacote apt|pacote brew|outro meio|finalidade
# "outro meio": pip:<pacote> npm:<pacote> go:<módulo> dotnet:<pacote> manual:<URL ou instrução>
TABELA='
geral|git|git|git||controle de versão, blame, bisect
geral|rg|ripgrep|ripgrep||busca rápida em código
geral|fd,fdfind|fd-find|fd||busca de arquivos por nome
geral|jq|jq|jq||consulta e transformação de JSON
geral|yq||yq|go:github.com/mikefarah/yq/v4@latest|consulta de YAML (Compose, Kubernetes, CI)
geral|curl|curl|curl||requisições HTTP
geral|make|make|make||automação de build
geral|tree|tree|tree||visão da estrutura de diretórios
geral|ctags|universal-ctags|universal-ctags||índice de símbolos em dezenas de linguagens
geral|cloc|cloc|cloc||contagem de linhas por linguagem
geral|shellcheck|shellcheck|shellcheck||lint de scripts shell
geral|ast-grep||ast-grep|npm:@ast-grep/cli|busca e reescrita estrutural (AST) multi-linguagem
geral|semgrep||semgrep|pip:semgrep|análise estática e regras de segurança multi-linguagem
geral|gitleaks||gitleaks|manual:https://github.com/gitleaks/gitleaks/releases|segredos vazados no histórico
geral|trivy||trivy|manual:https://github.com/aquasecurity/trivy/releases|vulnerabilidades em dependências, imagens e IaC
geral|hadolint||hadolint|manual:https://github.com/hadolint/hadolint/releases|lint de Dockerfile
geral|docker|docker.io|docker||containers para reproduzir ambientes
geral|sqlite3|sqlite3|sqlite||inspeção de bancos SQLite
re|file|file|||identificação do tipo de arquivo
re|strings|binutils|binutils||textos embutidos em binários
re|objdump|binutils|binutils||desmontagem e cabeçalhos de binários
re|readelf|binutils|binutils||estrutura de binários ELF
re|nm|binutils|binutils||tabela de símbolos
re|xxd|xxd|||dump hexadecimal
re|gdb|gdb|gdb||depurador nativo (Linux)
re|lldb|lldb||manual:no macOS vem com o Xcode Command Line Tools (xcode-select --install)|depurador nativo (LLVM)
re|strace|strace|||chamadas de sistema em execução (Linux)
re|ltrace|ltrace|||chamadas de biblioteca em execução (Linux)
re|r2|radare2|radare2|manual:https://github.com/radareorg/radare2/releases|desmontagem e análise de binários (radare2)
re|analyzeHeadless,ghidraRun||ghidra|manual:https://github.com/NationalSecurityAgency/ghidra/releases|descompilador de código nativo (Ghidra)
re|binwalk|binwalk|binwalk||extração de firmware e arquivos embutidos
re|unzip|unzip|unzip||APK, IPA, JAR e afins são ZIPs
re|7z,7zz|p7zip-full|p7zip||extração de formatos de arquivo diversos
re|java|default-jre-headless|openjdk||necessário para jadx, apktool e Ghidra
re|jadx||jadx|manual:https://github.com/skylot/jadx/releases|descompilador de APK/DEX/JAR para Java
re|apktool|apktool|apktool||decodifica recursos, manifesto e smali de APK
re|adb|adb|android-platform-tools||ponte com dispositivo/emulador Android
re|plistutil|libplist-utils|libplist||leitura de plist binário (apps iOS/macOS)
re|otool|||manual:só macOS, vem com o Xcode Command Line Tools|cabeçalhos e dependências de binários Mach-O
re|frida||frida|pip:frida-tools|instrumentação dinâmica de apps
re|mitmproxy|mitmproxy|mitmproxy|pip:mitmproxy|interceptação de tráfego HTTP(S)
re|tshark|tshark|wireshark||captura e análise de pacotes
re|openssl|openssl|openssl||certificados, TLS e criptografia
re|protoc|protobuf-compiler|protobuf||decodificação de mensagens Protobuf (protoc --decode_raw)
re|grpcurl||grpcurl|go:github.com/fullstorydev/grpcurl/cmd/grpcurl@latest|exploração de APIs gRPC
re|wasm2wat|wabt|wabt||WebAssembly para texto legível
re|js-beautify|||npm:js-beautify|formatação de JavaScript minificado
re|webcrack|||npm:webcrack|desempacota bundles webpack e desofusca JavaScript
re|ilspycmd|||dotnet:ilspycmd|descompilador .NET
re|de4dot|||manual:https://github.com/de4dot/de4dot (no Linux/macOS roda via mono)|desofuscador de assemblies .NET
re|innoextract|innoextract|innoextract||extrai instaladores Inno Setup (.exe)
re|msiextract|msitools|msitools||extrai e inspeciona pacotes MSI (msiextract, msiinfo)
re|osslsigncode|osslsigncode|osslsigncode||verifica a assinatura Authenticode de .exe, .dll e .msi
re|yara|yara|yara||identificação por regras/assinaturas
re|exiftool|libimage-exiftool-perl|exiftool||metadados de arquivos
re|upx|upx-ucl|upx||detecta e desfaz empacotamento UPX
'

SO="$(uname -s)"
TEM_APT=0; command -v apt-get >/dev/null 2>&1 && TEM_APT=1
TEM_BREW=0; command -v brew >/dev/null 2>&1 && TEM_BREW=1
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo -n"; else SUDO="indisponivel"; fi
fi

achar() { # ecoa o primeiro comando existente da lista "a,b,c"
  local IFS=','; local c
  for c in $1; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }; done
  return 1
}

dica() { # como instalar, para o ambiente atual
  local apt="$1" brew="$2" outro="$3"
  if [ "$TEM_APT" -eq 1 ] && [ -n "$apt" ]; then echo "apt-get install -y $apt"; return; fi
  if [ "$TEM_BREW" -eq 1 ] && [ -n "$brew" ]; then echo "brew install $brew"; return; fi
  case "$outro" in
    pip:*)    echo "pipx install ${outro#pip:}  (ou: python3 -m pip install --user ${outro#pip:})" ;;
    npm:*)    echo "npm install -g ${outro#npm:}" ;;
    go:*)     echo "go install ${outro#go:}" ;;
    dotnet:*) echo "dotnet tool install -g ${outro#dotnet:}" ;;
    manual:*) echo "${outro#manual:}" ;;
    *) if [ -n "$apt" ] || [ -n "$brew" ]; then
         echo "pacote: ${apt:-$brew} (use o gerenciador do seu sistema)"
       else echo "sem instalação automática neste sistema"; fi ;;
  esac
}

APT_ATUALIZADO=0
instalar() { # retorna 0 se o comando de instalação terminou bem
  local apt="$1" brew="$2" outro="$3"
  if [ "$TEM_APT" -eq 1 ] && [ -n "$apt" ]; then
    [ "$SUDO" = "indisponivel" ] && { echo "    (sem root nem sudo sem senha — rode manualmente)"; return 1; }
    if [ "$APT_ATUALIZADO" -eq 0 ]; then $SUDO apt-get update -qq >/dev/null 2>&1; APT_ATUALIZADO=1; fi
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$apt" >/dev/null 2>&1
    return $?
  fi
  if [ "$TEM_BREW" -eq 1 ] && [ -n "$brew" ]; then brew install "$brew" >/dev/null 2>&1; return $?; fi
  case "$outro" in
    pip:*)
      if command -v pipx >/dev/null 2>&1; then pipx install "${outro#pip:}" >/dev/null 2>&1
      else python3 -m pip install --user --quiet "${outro#pip:}" >/dev/null 2>&1; fi
      return $? ;;
    npm:*)    command -v npm >/dev/null 2>&1 || return 1; npm install -g --silent "${outro#npm:}" >/dev/null 2>&1; return $? ;;
    go:*)     command -v go >/dev/null 2>&1 || return 1; go install "${outro#go:}" >/dev/null 2>&1; return $? ;;
    dotnet:*) command -v dotnet >/dev/null 2>&1 || return 1; dotnet tool install -g "${outro#dotnet:}" >/dev/null 2>&1; return $? ;;
  esac
  return 1
}

echo "# Ferramentas — categoria: $CATEGORIA · sistema: $SO"
echo
OK=0; FALTAM=0; INSTALADAS=0; FALHAS=""
ULTIMA_CAT=""
while IFS='|' read -r cat cmds apt brew outro uso; do
  [ -z "${cat:-}" ] && continue
  [ "$CATEGORIA" != "tudo" ] && [ "$CATEGORIA" != "$cat" ] && continue
  if [ "$cat" != "$ULTIMA_CAT" ]; then
    [ "$cat" = "geral" ] && echo "## Manutenção geral" || { echo; echo "## Engenharia reversa"; }
    ULTIMA_CAT="$cat"
  fi
  nome="${cmds%%,*}"
  if achado=$(achar "$cmds"); then
    OK=$((OK+1)); echo "[ok]    $achado — $uso"
    continue
  fi
  if [ "$INSTALAR" -eq 1 ]; then
    case "$outro" in manual:*) manual=1 ;; *) manual=0 ;; esac
    tem_meio=0
    { [ "$TEM_APT" -eq 1 ] && [ -n "$apt" ]; } && tem_meio=1
    { [ "$TEM_BREW" -eq 1 ] && [ -n "$brew" ]; } && tem_meio=1
    { [ -n "$outro" ] && [ "$manual" -eq 0 ]; } && tem_meio=1
    if [ "$tem_meio" -eq 1 ]; then
      echo "[...]   $nome — instalando ($(dica "$apt" "$brew" "$outro"))"
      instalar "$apt" "$brew" "$outro"
      hash -r 2>/dev/null
      if achado=$(achar "$cmds"); then
        INSTALADAS=$((INSTALADAS+1)); echo "[ok]    $achado — instalado"
        continue
      fi
      FALHAS="${FALHAS}${FALHAS:+, }$nome"
      echo "[falta] $nome — a instalação não deixou o comando no PATH; tente: $(dica "$apt" "$brew" "$outro")"
      FALTAM=$((FALTAM+1))
      continue
    fi
  fi
  FALTAM=$((FALTAM+1))
  echo "[falta] $nome — $uso"
  echo "        instalar: $(dica "$apt" "$brew" "$outro")"
done <<EOF
$TABELA
EOF

echo
echo "Resumo: $OK presentes · $INSTALADAS instaladas agora · $FALTAM em falta"
[ -n "$FALHAS" ] && echo "Falharam na instalação: $FALHAS"
if [ "$INSTALAR" -eq 0 ] && [ "$FALTAM" -gt 0 ]; then
  echo "Nem tudo é necessário: instale só o que a tarefa em mãos exigir. Para tentar instalar o que falta: $0 $CATEGORIA --instalar"
fi
if [ "$TEM_APT" -eq 0 ] && [ "$TEM_BREW" -eq 0 ]; then
  echo "Aviso: sem apt-get nem Homebrew, a instalação automática cobre só pip/npm/go/dotnet; para o resto use o gerenciador do sistema."
fi
exit 0
