# iOS: IPA e binários Mach-O

A análise completa pede macOS com Xcode; em Linux dá para fazer a triagem, ler plists, recursos e strings e desmontar com Ghidra/radare2. Diga no relato o que ficou limitado pelo ambiente.

## Índice
- [Estrutura do IPA](#estrutura-do-ipa)
- [Triagem](#triagem)
- [Binário cifrado](#binário-cifrado)
- [Identificar o framework](#identificar-o-framework)
- [Info.plist e entitlements](#infoplist-e-entitlements)
- [Classes, símbolos e strings](#classes-símbolos-e-strings)
- [Recursos e dados](#recursos-e-dados)
- [O que procurar](#o-que-procurar)
- [Análise dinâmica](#análise-dinâmica)
- [Simbolizar crashes](#simbolizar-crashes)

## Estrutura do IPA

```
Payload/<Nome>.app/
  <Nome>                     executável Mach-O (o nome está em CFBundleExecutable)
  Info.plist                 metadados (plist binário)
  embedded.mobileprovision   perfil de provisionamento (ausente em builds da App Store)
  Frameworks/                frameworks e dylibs embutidos
  PlugIns/                   extensões (.appex)
  _CodeSignature/            assinatura
  Assets.car                 catálogo de imagens compilado
  *.lproj/                   traduções (.strings)
  *.storyboardc, *.nib       interfaces compiladas
  *.momd/                    modelo Core Data compilado
```

```bash
mkdir ipa && unzip -q app.ipa -d ipa && ls -la ipa/Payload/*.app | head -n 60
```

## Triagem

```bash
APP=$(ls -d ipa/Payload/*.app)
plutil -p "$APP/Info.plist"                        # macOS
plistutil -i "$APP/Info.plist"                     # Linux (libplist-utils)
python3 -c 'import plistlib,sys,pprint; pprint.pprint(plistlib.load(open(sys.argv[1],"rb")))' "$APP/Info.plist"   # qualquer sistema
file "$APP"/<Executavel>                           # arquiteturas (arm64; "universal" = várias)
ls "$APP/Frameworks"                               # bibliotecas embutidas revelam o framework e os SDKs
```

## Binário cifrado

Apps baixados da App Store têm o segmento de código cifrado (FairPlay). Verifique:

```bash
otool -l "$APP/<Executavel>" | grep -A4 LC_ENCRYPTION_INFO    # cryptid 1 = cifrado, 0 = em claro
```

Com `cryptid 1`, a análise estática do código não é possível a partir desse arquivo. O caminho para manutenção é usar um build em que você tem direito e que não é cifrado: build de desenvolvimento, ad hoc ou enterprise do próprio app, o `.xcarchive`, ou o `.app` do simulador. Plists, recursos, frameworks listados e strings fora do segmento cifrado continuam legíveis.

## Identificar o framework

| Presença em `Frameworks/` ou no pacote | Framework | Lógica em |
|---|---|---|
| Só bibliotecas Swift (`libswift*.dylib`) e SDKs | Nativo Swift/Objective-C | executável principal |
| `Flutter.framework` + `App.framework` | Flutter | `App.framework/App` (Dart AOT) |
| `main.jsbundle`, `hermes.framework` | React Native | `main.jsbundle` (texto ou bytecode Hermes) |
| `Xamarin.iOS.dll`, `*.aotdata`, `Mono*` | Xamarin / MAUI | assemblies + código AOT |
| `www/` ou `public/` com HTML/JS, `Cordova`/`Capacitor` | Híbrido web | JavaScript no pacote |
| `UnityFramework.framework`, `Data/Managed/Metadata/global-metadata.dat` | Unity IL2CPP | `UnityFramework` + metadados |

Para React Native, Flutter e híbridos, valem as mesmas observações de [android.md](android.md) e [web-js.md](web-js.md).

## Info.plist e entitlements

Chaves que importam:

- `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `MinimumOSVersion`.
- `CFBundleURLTypes` → esquemas de URL próprios; `LSApplicationQueriesSchemes` → apps que ele consulta.
- `NSAppTransportSecurity` → exceções de TLS (`NSAllowsArbitraryLoads`, domínios com HTTP liberado).
- `NS*UsageDescription` → permissões pedidas (câmera, localização…). Chave ausente + uso da API = o app fecha ao pedir.
- `UIBackgroundModes`, `UIRequiredDeviceCapabilities`.
- Chaves do próprio app e de SDKs: URLs de backend, IDs e chaves de API (Firebase: `GoogleService-Info.plist`).

Entitlements (capacidades assinadas: grupos de app, keychain, domínios associados, push):

```bash
codesign -d --entitlements :- "$APP"                 # macOS
security cms -D -i "$APP/embedded.mobileprovision"   # macOS: perfil decodificado (inclui entitlements e dispositivos)
openssl smime -inform der -verify -noverify -in "$APP/embedded.mobileprovision"   # Linux
```

`applinks:` em domínios associados + o arquivo `apple-app-site-association` do site definem os universal links.

## Classes, símbolos e strings

```bash
otool -L "$APP/<Executavel>"          # macOS: bibliotecas ligadas       (Linux: rabin2 -l)
nm -gU "$APP/<Executavel>" | head     # macOS: símbolos exportados       (Linux: rabin2 -s / nm)
strings -n 8 "$APP/<Executavel>" | rg -i "https?://|api|token|key|sql"
xcrun swift-demangle < simbolos.txt   # desfaz a codificação de nomes Swift (swift demangle em Linux com toolchain)
```

- **Objective-C** guarda nomes de classes, métodos (seletores) e propriedades no binário — `class-dump` (ou equivalentes mantidos, como o subcomando `class-dump` do `ipsw`) reconstrói os cabeçalhos. É o melhor mapa inicial.
- **Swift** preserva nomes de tipos e, com menos detalhe, de métodos; o Ghidra e o Hopper os decodificam.
- Desmontagem/descompilação: Ghidra (importa Mach-O e fat binaries; escolha a fatia arm64), radare2 (`r2 -A`, `afl`, `pdf @ sym.<nome>`), Hopper.
- Âncoras úteis: seletores como `URLSession:…`, `application:didFinishLaunchingWithOptions:`, `SecItemAdd`, `CCCrypt`, `LAContext`.

## Recursos e dados

- `*.lproj/*.strings`: textos da interface — podem ser plists binários (`plutil -p`).
- `Assets.car`: `assetutil --info Assets.car` (macOS) lista os recursos.
- `*.momd/*.mom`: modelo Core Data compilado — nomes de entidades e atributos aparecem com `strings`; é o esquema do banco local.
- `*.storyboardc`/`*.nib`: nomes de view controllers, outlets e ações.
- Bancos e JSON pré-carregados, certificados (`*.cer`, `*.der` → fixação de certificado), `Settings.bundle`.

## O que procurar

- **Rede**: `URLSession`, Alamofire, URLs base, cabeçalhos de autenticação, fixação de certificado (delegates de `URLAuthenticationChallenge`, `SecTrustEvaluate`), exceções ATS.
- **Armazenamento**: Keychain (`SecItem*` — o correto para segredos), `UserDefaults` (plist em claro — segredo ali é achado), Core Data/SQLite/Realm, arquivos e sua classe de proteção de dados.
- **Autenticação**: fluxo de login, `ASWebAuthenticationSession`, biometria (`LAContext`), Sign in with Apple.
- **Criptografia**: CommonCrypto (`CCCrypt`, `CCHmac`), CryptoKit — algoritmo, origem de chave e IV.
- **Superfície**: tratamento de esquemas de URL e universal links, `WKWebView` e message handlers, extensões, área de transferência.
- **SDKs de terceiros** e o que coletam; manifesto de privacidade (`PrivacyInfo.xcprivacy`).

## Análise dinâmica

Com o seu app, em simulador ou dispositivo de desenvolvimento:

```bash
xcrun simctl list devices
xcrun simctl install booted Caminho/App.app
xcrun simctl launch --console booted <bundle id>
xcrun simctl get_app_container booted <bundle id> data     # sandbox do app: Documents, Library, bancos, plists
xcrun simctl openurl booted "esquema://rota"               # testar deep link
log stream --predicate 'subsystem == "<bundle id>"'        # logs unificados
```

- Xcode: anexar o depurador (LLDB), Instruments (tempo, alocações, vazamentos, rede), inspetor de hierarquia de views.
- Tráfego: o simulador usa a rede do Mac — configure o proxy do sistema; em dispositivo, proxy no Wi-Fi e certificado da CA de teste instalado e marcado como confiável. Ver [rede-e-apis.md](rede-e-apis.md).
- Frida funciona em builds de desenvolvimento com o gadget embutido, para observar chamadas no seu próprio app.

## Simbolizar crashes

Relatório de crash com endereços em vez de nomes precisa do dSYM **do mesmo build**:

```bash
dwarfdump --uuid App.app.dSYM                       # o UUID deve bater com o do relatório ("Binary Images")
atos -arch arm64 -o App.app.dSYM/Contents/Resources/DWARF/App -l <endereço de carga> <endereço...>
```

O endereço de carga está na seção "Binary Images" do relatório. Sem o dSYM correto, só os frames de bibliotecas do sistema são simbolizados. Bitcode e builds da App Store: baixe os dSYMs pelo App Store Connect/Xcode Organizer.
