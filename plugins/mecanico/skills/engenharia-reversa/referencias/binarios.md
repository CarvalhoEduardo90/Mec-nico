# Binários nativos e bytecode

## Índice
- [Triagem segura](#triagem-segura)
- [Identificar linguagem e empacotamento](#identificar-linguagem-e-empacotamento)
- [Bytecode: descompile em vez de desmontar](#bytecode-descompile-em-vez-de-desmontar)
- [ELF (Linux, Android)](#elf-linux-android)
- [PE (Windows)](#pe-windows)
- [Mach-O (macOS, iOS)](#mach-o-macos-ios)
- [radare2](#radare2)
- [Ghidra](#ghidra)
- [Análise dinâmica](#análise-dinâmica)
- [Go e Rust](#go-e-rust)
- [WebAssembly](#webassembly)
- [Firmware e imagens](#firmware-e-imagens)
- [Roteiro de leitura de uma função](#roteiro-de-leitura-de-uma-função)

## Triagem segura

Nada aqui executa o alvo:

```bash
sha256sum alvo; file alvo
strings -n 8 alvo | head -n 200          # ASCII
strings -n 8 -el alvo | head -n 100      # UTF-16LE (comum em Windows)
readelf -h alvo 2>/dev/null || objdump -f alvo
```

`ldd alvo` **pode executar código do binário** — para alvo não confiável use `readelf -d alvo | grep NEEDED` ou `objdump -p alvo | grep NEEDED`.

Perguntas da triagem: formato e arquitetura? ligado estática ou dinamicamente? com símbolos (`not stripped`) ou sem? empacotado/comprimido? em que linguagem foi escrito? que bibliotecas usa?

## Identificar linguagem e empacotamento

| Indício | Conclusão | Caminho |
|---|---|---|
| `UPX!` nas strings, seções `UPX0/UPX1` | Empacotado com UPX | `upx -t alvo`; `upx -d -o saida alvo` (em cópia) |
| Alta entropia, poucas strings e poucas importações | Empacotado/cifrado por outro meio | análise dinâmica em ambiente isolado; `binwalk -E` mostra a entropia |
| `Go build ID`, `runtime.gopanic`, `go1.` | Go | ver [Go e Rust](#go-e-rust) |
| Caminhos `.rs`, `rustc`, `core::panicking` | Rust | idem |
| `_MEIPASS`, `pyi-`, `PYZ-00.pyz` | Python empacotado (PyInstaller) | `pyinstxtractor` extrai os `.pyc`; depois descompilador de bytecode |
| `mscoree.dll`, `_CorExeMain`, cabeçalho CLR; `file` diz "Mono/.Net assembly" | .NET | ILSpy — ver abaixo |
| ZIP com `META-INF/MANIFEST.MF`, `.class` | Java (JAR/WAR/EAR) | jadx / CFR |
| `app.asar`, `electron`, `chrome_100_percent.pak` ao lado | Electron | ver [web-js.md](web-js.md) |
| `node`, `pkg/prelude`, `nexe` | Node empacotado | o JavaScript está anexado ao executável; procure o snapshot/arquivo embutido |
| `Borland`, `TForm`, recursos `DFM` | Delphi | IDR / DeDe recuperam formulários e eventos |
| `AU3!` | AutoIt compilado | o script está embutido |
| `MSVBVM60.DLL` | Visual Basic 6 | P-code ou nativo; formulários recuperáveis |

## Bytecode: descompile em vez de desmontar

A saída é quase o código original.

```bash
# .NET (C#, VB.NET, F#)
ilspycmd -p -o saida/ App.dll              # gera um projeto com as fontes
ilspycmd -l c App.dll                      # lista classes

# Java / Kotlin / Scala (JAR, WAR, .class)
jadx -d saida/ app.jar
unzip -p app.jar META-INF/MANIFEST.MF      # Main-Class, Class-Path
javap -p -c -cp app.jar pacote.Classe      # bytecode de uma classe, sem descompilador

# Python (.pyc)
python3 -c "import sys,marshal,dis; f=open(sys.argv[1],'rb'); f.read(16); dis.dis(marshal.load(f))" modulo.pyc
```

- O `.pyc` precisa ser lido com a mesma versão do Python que o gerou (o número mágico nos primeiros bytes indica). Descompiladores (`pycdc`, `decompyle3`/`uncompyle6`) cobrem versões específicas; o desmontador `dis` sempre funciona.
- Ofuscadores (.NET: ConfuserEx, Dotfuscator; Java: ProGuard, Allatori) renomeiam e embaralham o fluxo; `de4dot` desfaz parte disso em .NET. Strings, chamadas a APIs do framework e a estrutura de classes continuam legíveis.
- WAR/EAR: `WEB-INF/web.xml`, `WEB-INF/classes/`, `WEB-INF/lib/*.jar` — os descritores e arquivos de configuração (Spring XML, `persistence.xml`, `application.properties`) dizem como tudo se liga.

## ELF (Linux, Android)

```bash
readelf -h alvo            # cabeçalho: classe, arquitetura, tipo (EXEC/DYN), ponto de entrada
readelf -lW alvo           # segmentos (permissões de memória)
readelf -SW alvo           # seções
readelf -d alvo            # dependências dinâmicas (NEEDED), RPATH/RUNPATH
readelf -sW alvo | head    # símbolos; em binário sem símbolos resta a tabela dinâmica
nm -D --demangle alvo      # símbolos exportados/importados, com nomes C++ decodificados
objdump -d -M intel --no-show-raw-insn alvo | less      # desmontagem
objdump -s -j .rodata alvo | head                        # constantes e strings
readelf -p .comment alvo   # compilador e versão
readelf -n alvo            # notas: build-id
```

- Importações dizem o que o programa *pode* fazer: `socket/connect` (rede), `fopen/open` (arquivos), `execve/system` (processos), `dlopen` (carga dinâmica), funções de OpenSSL (criptografia).
- Símbolos de depuração separados: pacote `-dbg`/`-debuginfo` da distribuição ou `debuginfod`, localizados pelo build-id.
- Proteções: `checksec --file=alvo` (ou observe PIE, RELRO, NX e canário pelo `readelf`).

## PE (Windows)

```bash
file alvo.exe
objdump -x alvo.exe | less                  # cabeçalhos, seções, tabela de importação/exportação
python3 -c "import pefile,sys; pe=pefile.PE(sys.argv[1]); print(pe.dump_info())" alvo.exe | less   # se o módulo pefile estiver instalado
rabin2 -I alvo.exe; rabin2 -i alvo.exe; rabin2 -E alvo.exe
7z l alvo.exe                               # instaladores e autoextraíveis abrem como arquivo; recursos embutidos
```

- Instaladores (NSIS, Inno Setup, MSI, WiX) são contêineres: extraia (`7z x`, `innoextract`, `msiextract`) antes de analisar o que instalam.
- Recursos (`.rsrc`): ícones, diálogos, manifestos, strings de versão, às vezes arquivos inteiros embutidos.
- Informações de versão e caminho do PDB (`strings | rg -i "\.pdb"`) revelam nome do projeto e do diretório de build; com o PDB correspondente, os nomes voltam.
- Assinatura Authenticode: `osslsigncode verify alvo.exe`.

## Mach-O (macOS, iOS)

Em macOS: `otool -hv` (cabeçalho), `otool -L` (bibliotecas), `otool -l` (comandos de carga), `nm -gU`, `codesign -dvvv`, `lipo -info` (arquiteturas de binário universal; `lipo -thin arm64 -output fatia alvo` separa uma). Em Linux: `rabin2 -I/-l/-s` e Ghidra. Detalhes de apps em [ios.md](ios.md).

## radare2

```bash
rabin2 -I alvo        # informações gerais         rabin2 -z alvo    # strings das seções de dados
rabin2 -i alvo        # importações                rabin2 -E alvo    # exportações
r2 -A alvo            # abre e analisa (aaa)
```

Dentro do r2: `afl` (funções) · `afl~nome` (filtrar) · `s main` (ir para) · `pdf` (desmontar a função atual) · `pdf @ sym.funcao` · `iz` (strings) · `axt @ str.texto` (quem referencia) · `axt @ sym.imp.connect` (quem chama a importação) · `afn novo_nome` (renomear) · `VV` (grafo) · `pdg`/`pdc` (pseudocódigo, com plugin r2ghidra ou nativo) · `q`.

Em lote, sem interação: `r2 -q -A -c 'afl; iz~http; axt @ sym.imp.connect' alvo`.

## Ghidra

Melhor descompilador gratuito para código nativo. Em modo sem interface, útil em terminal:

```bash
analyzeHeadless /tmp/ghidra-proj Projeto -import alvo -postScript <Script.java> -scriptPath <dir>
```

Scripts (Java/Python) exportam o pseudocódigo de todas as funções, a lista de strings com referências ou o grafo de chamadas. Na interface: Symbol Tree → Functions; janela *Defined Strings* → referências (`Ctrl+Shift+F`); renomear (`L`), definir tipo (`Ctrl+L`), comentar (`;`). Aplicar assinaturas de função e definir estruturas melhora muito o pseudocódigo.

## Análise dinâmica

Somente em ambiente isolado e descartável, para alvo não confiável:

```bash
docker run --rm -it --network none -v "$PWD/alvo:/alvo:ro" debian:stable-slim /alvo     # sem rede, sistema descartável

strace -f -o trace.txt ./alvo args                    # todas as chamadas de sistema, incluindo processos filhos
strace -f -e trace=openat,read,write,connect,execve ./alvo
ltrace -f -o ltrace.txt ./alvo                        # chamadas a bibliotecas (ligação dinâmica)

gdb -q --args ./alvo args
  (gdb) info functions <regex>   break *0x401234   break nome   run
  (gdb) bt   info registers   x/s $rdi   x/32xb $rsp   finish   si   ni   disassemble
```

- Sem símbolos, pontos de parada em importações (`break connect`, `break open`) levam ao código de interesse; `bt` mostra quem chamou.
- `LD_PRELOAD` com uma pequena biblioteca intercepta funções de biblioteca para registrar argumentos.
- Arquiteturas diferentes da máquina: `qemu-<arch> -strace ./alvo` e `qemu-<arch> -g 1234` + `gdb-multiarch`.
- Core dump: `gdb ./alvo core` → `bt full`, `info threads`.
- Windows: x64dbg/WinDbg, Process Monitor, API Monitor.

## Go e Rust

**Go**: binários grandes, ligados estaticamente, com muita informação de tempo de execução.
- `go version -m alvo` mostra a versão do Go, o caminho do módulo e as dependências com versões — vale ouro.
- A tabela `pclntab` guarda nomes de funções mesmo sem símbolos; Ghidra e radare2 recentes a leem (ou `GoReSym`).
- Strings não terminam em zero (ponteiro + tamanho): `strings` as mostra coladas; use o descompilador para delimitar.
- Nomes `main.*` são o código do alvo; o resto é runtime e bibliotecas.

**Rust**:
- Mensagens de pânico incluem caminhos de arquivo-fonte e nomes de crates (`/cargo/registry/src/.../crate-versão/src/...`) — inventário de dependências.
- Nomes de símbolos codificados: `rustfilt` ou `nm --demangle`.
- Muito código genérico expandido: concentre-se nas funções do crate principal.

## WebAssembly

```bash
wasm-objdump -x modulo.wasm        # seções, importações, exportações, memória
wasm2wat modulo.wasm -o modulo.wat # formato texto
wasm-decompile modulo.wasm -o modulo.dcmp   # pseudocódigo mais legível
strings -n 6 modulo.wasm | head -n 100
```

Importações e exportações definem a fronteira com o JavaScript — comece por elas e pelo código "cola" no JS. Seção `name` (quando presente) traz nomes de funções; seções personalizadas podem indicar a linguagem de origem (Rust, Go, Emscripten, AssemblyScript). Para depurar, as ferramentas de desenvolvedor do navegador desmontam e aceitam pontos de parada; com DWARF embutido, mostram o código original.

## Firmware e imagens

```bash
binwalk alvo.bin            # assinaturas: cabeçalhos, sistemas de arquivos, compressão
binwalk -E alvo.bin         # entropia: regiões cifradas/comprimidas
binwalk -e alvo.bin         # extrai o que reconhece
```

Depois da extração, o sistema de arquivos costuma ser um Linux embarcado: `etc/` (configuração, usuários), scripts de inicialização, binários próprios do fabricante em `usr/bin` ou `usr/sbin` (alvos reais da análise), páginas da interface web. A arquitetura (`file` em qualquer binário extraído) define o `qemu` a usar.

## Roteiro de leitura de uma função

1. **Fronteira**: argumentos, retorno, convenção de chamada (x86-64 System V: `rdi, rsi, rdx, rcx, r8, r9`; Windows x64: `rcx, rdx, r8, r9`; ARM64: `x0–x7`).
2. **Chamadas feitas**: as funções chamadas (importações, sobretudo) contam a história em alto nível.
3. **Constantes e strings** referenciadas: mensagens de erro nomeiam a operação; constantes identificam algoritmos (`0x67452301` → MD5/SHA-1; `0x9E3779B9` → TEA/dispersão; `0xEDB88320` → CRC-32; tabela iniciando em `63 7c 77 7b` → S-box do AES).
4. **Forma do fluxo**: laço sobre buffer (parser, cifra, soma de verificação), `switch` grande (máquina de estados, interpretador de comandos), sequência de verificações com saída antecipada (validação).
5. **Dados**: deslocamentos fixos a partir de um ponteiro revelam uma estrutura — defina-a no descompilador e o código ao redor se esclarece.
6. **Nomeie e siga adiante**: dê um nome provisório e suba para quem chama.
