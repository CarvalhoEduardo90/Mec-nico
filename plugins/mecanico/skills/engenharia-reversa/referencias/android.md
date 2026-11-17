# Android: APK, AAB e derivados

## Índice
- [Formatos](#formatos)
- [Triagem](#triagem)
- [Identificar o framework](#identificar-o-framework)
- [Descompilar código Java/Kotlin](#descompilar-código-javakotlin)
- [Recursos e manifesto](#recursos-e-manifesto)
- [Código nativo](#código-nativo)
- [Frameworks multiplataforma](#frameworks-multiplataforma)
- [O que procurar](#o-que-procurar)
- [Análise dinâmica](#análise-dinâmica)
- [Tráfego de rede](#tráfego-de-rede)
- [Ofuscação (R8/ProGuard)](#ofuscação-r8proguard)

## Formatos

| Extensão | O que é | Como abrir |
|---|---|---|
| `.apk` | ZIP com `AndroidManifest.xml` (XML binário), `classes*.dex`, `resources.arsc`, `res/`, `assets/`, `lib/<abi>/*.so`, `META-INF/` | `unzip`, `apktool`, `jadx` |
| `.aab` | Android App Bundle (formato de publicação): módulos com `manifest/`, `dex/`, `res/` em protobuf | `bundletool build-apks --bundle=app.aab --output=app.apks --mode=universal`, depois extrair `universal.apk` do `.apks` |
| `.apks` / `.xapk` / `.apkm` | ZIP com APK base + APKs divididos (por ABI, idioma, densidade) | `unzip`; analise o `base.apk` e os splits de ABI para as `.so` |

No dispositivo: `adb shell pm path <pacote>` lista os caminhos; `adb pull <caminho>` copia.

## Triagem

```bash
unzip -l app.apk | head -n 60
unzip -l app.apk | awk '{print $4}' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head   # onde está o volume
aapt2 dump badging app.apk            # pacote, versão, SDKs, permissões, activity inicial (se houver aapt2)
apksigner verify --print-certs app.apk   # ou: keytool -printcert -jarfile app.apk
```

Sem `aapt2`: `apktool d` decodifica o manifesto; `jadx` também o exibe.

## Identificar o framework

Decide toda a estratégia — o código "de verdade" pode não estar nos `.dex`.

| Presença no APK | Framework | Onde está a lógica |
|---|---|---|
| Muitas classes próprias nos `.dex`, `kotlin/` | Nativo Java/Kotlin | `classes*.dex` → jadx |
| `lib/*/libflutter.so` + `libapp.so`, `assets/flutter_assets/` | Flutter | `libapp.so` (snapshot Dart AOT) |
| `assets/index.android.bundle`, `libreactnativejni.so`, `libhermes.so` | React Native | o bundle JS (texto ou bytecode Hermes) |
| `assemblies/*.dll` ou `libassemblies.*.blob.so`, `libmonodroid.so` | Xamarin / .NET MAUI | assemblies .NET |
| `assets/www/` ou `assets/public/` com HTML/JS | Cordova / Ionic / Capacitor | JavaScript em `assets/` |
| `libunity.so`, `libil2cpp.so`, `assets/bin/Data/Managed/Metadata/global-metadata.dat` | Unity (IL2CPP) | `libil2cpp.so` + metadados; com Mono: `assets/bin/Data/Managed/*.dll` |
| `libUE4.so` / `libUnreal.so` | Unreal | nativo |
| `assets/*.py`, `libpython*.so` | Kivy / Chaquopy | Python |

## Descompilar código Java/Kotlin

```bash
jadx -d saida/ app.apk                       # fontes Java + recursos decodificados
jadx -d saida/ --deobf app.apk               # renomeia identificadores curtos/ilegíveis de forma consistente
jadx -d saida/ --show-bad-code app.apk       # inclui métodos que falharam na descompilação
jadx-gui app.apk                             # navegação com referências cruzadas, se houver ambiente gráfico
```

- O resultado é uma aproximação: não recompila necessariamente, e métodos complexos podem falhar. Quando o Java gerado estiver errado ou ausente, leia o smali do mesmo método (`apktool d` → `smali*/`).
- Em Kotlin, a anotação `@Metadata` e as strings de `Intrinsics.checkNotNullParameter(x, "nomeDoParametro")` devolvem nomes originais mesmo com ofuscação.
- Comece pelo manifesto: `Application` (inicialização global), activity `LAUNCHER`, serviços, receivers, providers, deep links.
- Busque nas fontes geradas: `rg -n "https?://" saida/sources`, `rg -n "Retrofit|OkHttpClient|@GET|@POST|baseUrl" saida/sources`.

## Recursos e manifesto

```bash
apktool d app.apk -o apktool-out/      # AndroidManifest.xml legível, res/ decodificado, smali
```

- `AndroidManifest.xml`: permissões, componentes `exported`, `android:debuggable`, `allowBackup`, `usesCleartextTraffic`, `networkSecurityConfig`, intent-filters, esquemas de URL.
- `res/values/strings.xml`: textos da interface (âncoras!), às vezes chaves de API e URLs.
- `res/xml/`: `network_security_config.xml`, preferências, configurações de provedores.
- `assets/`: configurações JSON, bancos pré-carregados, certificados, bundles web.
- `google-services.json` embutido vira recursos: ID do projeto Firebase, chaves de API (públicas por natureza, mas confira as regras de segurança do backend).

## Código nativo

`lib/<abi>/*.so` são ELF — veja [binarios.md](binarios.md). Específico do Android:

- Funções JNI exportadas têm nome `Java_<pacote>_<Classe>_<metodo>`; registradas dinamicamente aparecem em `JNI_OnLoad` (tabela de `JNINativeMethod`).
- Do lado Java, procure `native` e `System.loadLibrary("x")` para saber o que cruza a fronteira.
- Prefira a ABI mais fácil de ler que estiver presente (`x86_64` e `arm64-v8a` descompilam melhor que `armeabi-v7a`).

## Frameworks multiplataforma

- **React Native**: `assets/index.android.bundle`. Se `file` disser texto/JavaScript → formate e trate como bundle JS ([web-js.md](web-js.md)). Se for bytecode Hermes (bytes iniciais `c6 1f bc 03`) → `hermes-dec` ou `hbctool` desmontam/descompilam para pseudo-JS; nomes de propriedades e strings sobrevivem.
- **Flutter**: o Dart é compilado para código de máquina em `libapp.so`; as strings ficam no pool de objetos. Ferramentas como `blutter` recuperam nomes de classes/funções e geram anotações para o desmontador, mas dependem da versão do Dart. `assets/flutter_assets/` contém recursos e, em builds de depuração, `kernel_blob.bin` (muito mais legível). Na prática, para Flutter, a análise de tráfego costuma render mais que a estática.
- **Xamarin / MAUI**: assemblies .NET em `assemblies/` — podem estar comprimidos (cabeçalho `XALZ`) ou agrupados em blob (`assemblies.blob`, ou dentro de `libassemblies.<abi>.blob.so`); ferramentas como `pyxamstore` extraem. Depois, `ilspycmd -p -o saida/ App.dll`.
- **Cordova / Ionic / Capacitor**: é um site em `assets/www` ou `assets/public`; os plugins nativos estão nos `.dex`.
- **Unity IL2CPP**: `Il2CppDumper` combina `libil2cpp.so` com `global-metadata.dat` e devolve assinaturas de classes e métodos com endereços, para usar no desmontador.

## O que procurar

- **Rede**: URLs base, interfaces Retrofit, interceptors do OkHttp (cabeçalhos de autenticação e assinatura de requisição), `CertificatePinner`, WebSocket, clientes gRPC/Protobuf (classes geradas revelam o esquema).
- **Armazenamento**: `SharedPreferences`, Room/SQLite (as entidades anotadas são o esquema), DataStore, arquivos, `EncryptedSharedPreferences`, uso do Keystore.
- **Autenticação**: fluxo de login, armazenamento e renovação de token, biometria.
- **Criptografia**: `Cipher.getInstance`, `SecretKeySpec`, `MessageDigest`, `Mac` — algoritmo, modo, origem da chave e do IV (chave fixa no código é achado de segurança).
- **Superfície exposta**: componentes `exported`, deep links e seu tratamento, `WebView` com `addJavascriptInterface` e `setJavaScriptEnabled`.
- **SDKs de terceiros**: analytics, anúncios, crash reporting — o que coletam.
- **Flags e configuração remota**: Firebase Remote Config, endpoints de configuração.

## Análise dinâmica

Em emulador ou dispositivo de teste, com o seu próprio app ou com autorização:

```bash
adb install app.apk                      # splits: adb install-multiple base.apk split_*.apk
adb logcat --pid=$(adb shell pidof -s <pacote>)
adb shell dumpsys package <pacote>       # permissões concedidas, componentes, versão
adb shell am start -n <pacote>/<Activity>
adb shell am start -a android.intent.action.VIEW -d "esquema://rota"    # testar deep link
adb shell run-as <pacote> ls -R /data/data/<pacote>     # só em build debuggable
adb exec-out run-as <pacote> cat databases/app.db > app.db
```

- **Build de depuração do próprio app** é o caminho mais simples: `debuggable`, logs ligados, sem ofuscação, e permite anexar o depurador do Android Studio.
- **Frida** (em build de teste / dispositivo de teste): `frida-ps -U` lista processos; `frida-trace -U -f <pacote> -j 'com.exemplo.Classe!metodo'` registra chamadas a métodos Java com argumentos e retorno; scripts próprios para observar valores. Requer `frida-server` no dispositivo ou o gadget embutido no build.
- **Banco e arquivos**: copie com `run-as` e inspecione com `sqlite3`.

## Tráfego de rede

Ver [rede-e-apis.md](rede-e-apis.md) para a captura. Específico do Android:

- A partir do Android 7 (API 24), apps não confiam em certificados instalados pelo usuário, a menos que o `network_security_config` permita. No **seu app**, adicione em build de depuração:

```xml
<network-security-config>
  <debug-overrides><trust-anchors><certificates src="user"/></trust-anchors></debug-overrides>
</network-security-config>
```

- Fixação de certificado (pinning): no seu app, desative-a no build de depuração (flag de build) para inspecionar o tráfego. Em app de terceiros, a alternativa legítima é observar pelo lado do servidor que você controla ou usar a documentação/SDK do fornecedor.
- O emulador oficial aceita proxy: `emulator -avd <nome> -http-proxy http://127.0.0.1:8080`.

## Ofuscação (R8/ProGuard)

- Sintoma: classes e métodos `a`, `b`, `c`; pacotes achatados.
- Com o `mapping.txt` do build (seu próprio app): `retrace mapping.txt stacktrace.txt` desofusca stack traces; o jadx aceita o arquivo de mapeamento para renomear tudo.
- Sem mapeamento: `--deobf` do jadx dá nomes estáveis; reconstrua o significado por strings, por chamadas a APIs do Android (que não são ofuscadas) e por classes de bibliotecas conhecidas.
- Bug que só aparece em release costuma ser regra de `keep` faltando: classe acessada por reflexão/serialização (Gson, Moshi, Room, JNI) foi renomeada ou removida. Compare `mapping.txt`, `usage.txt` e `seeds.txt` do build.
