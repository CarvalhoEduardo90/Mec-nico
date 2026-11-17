# Redes, APIs, protocolos, formatos de arquivo e bancos sem documentação

## Índice
- [Limites](#limites)
- [Capturar tráfego HTTP(S)](#capturar-tráfego-https)
- [Do tráfego à documentação](#do-tráfego-à-documentação)
- [Autenticação e tokens](#autenticação-e-tokens)
- [gRPC e Protobuf](#grpc-e-protobuf)
- [Tráfego que não é HTTP](#tráfego-que-não-é-http)
- [Protocolos binários desconhecidos](#protocolos-binários-desconhecidos)
- [Formatos de arquivo desconhecidos](#formatos-de-arquivo-desconhecidos)
- [Banco de dados sem documentação](#banco-de-dados-sem-documentação)

## Limites

Capture apenas tráfego dos seus próprios aplicativos, dispositivos e ambientes de teste, com contas de teste. Ao explorar uma API, fique dentro do que a sua credencial permite, respeite limites de taxa e não use produção para experimentos que alterem dados. Capturas contêm credenciais e dados pessoais: guarde-as fora do repositório e remova tokens antes de compartilhar qualquer trecho.

## Capturar tráfego HTTP(S)

**Antes de interceptar, veja se há caminho mais barato**: logs do servidor que você controla, modo verbose do cliente/SDK, HAR exportado pelo navegador, `curl -v`, variável de depuração do cliente HTTP.

**mitmproxy** (proxy de interceptação):

```bash
mitmweb --listen-port 8080                      # interface web
mitmdump --listen-port 8080 -w captura.flow     # sem interface, grava em arquivo
mitmdump -nr captura.flow --set hardump=trafego.har     # converte a captura em HAR
mitmdump -nr captura.flow --flow-detail 3 "~d api.exemplo.com & ~m POST"   # filtra e imprime
```

Para o cliente passar pelo proxy:
- **Processo local**: `HTTPS_PROXY=http://127.0.0.1:8080` e a CA do mitmproxy (`~/.mitmproxy/mitmproxy-ca-cert.pem`) confiável para aquele processo — `curl --cacert`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, truststore da JVM.
- **Navegador**: perfil separado com o proxy configurado e a CA importada só nesse perfil.
- **Dispositivo móvel/emulador**: proxy na rede Wi-Fi e CA instalada; particularidades em [android.md](android.md) e [ios.md](ios.md).
- **Modo transparente / WireGuard** (`mitmproxy --mode wireguard`) quando o cliente ignora as configurações de proxy.

Nunca instale a CA de interceptação no armazenamento de certificados principal da máquina de trabalho; se instalou em um dispositivo de teste, remova ao terminar.

**Descriptografar TLS dos seus próprios processos sem proxy**: `SSLKEYLOGFILE=/tmp/chaves.log` (respeitado por navegadores, curl e várias bibliotecas) + Wireshark/tshark com `-o tls.keylog_file:/tmp/chaves.log`.

## Do tráfego à documentação

```bash
# inventário de endpoints a partir de um HAR
jq -r '.log.entries[] | [.request.method, (.request.url | sub("\\?.*";"")), .response.status] | @tsv' trafego.har | sort | uniq -c | sort -rn

# gerar um esboço de OpenAPI a partir da captura
mitmproxy2swagger -i captura.flow -o api.yaml -p https://api.exemplo.com    # 1ª passada lista os caminhos
# edite api.yaml removendo o prefixo "ignore:" dos caminhos desejados e rode de novo o mesmo comando
```

Para cada endpoint, registre: método e caminho (com parâmetros identificados — `/pedidos/{id}`), consulta, cabeçalhos exigidos, corpo (esquema com tipos e obrigatoriedade), respostas de sucesso **e de erro**, paginação, ordenação/filtros, limites de taxa (cabeçalhos `RateLimit-*`, `Retry-After`), idempotência, versão.

Descubra as regras variando uma coisa por vez: remova um campo (é obrigatório?), mande tipo errado (qual a validação e o formato do erro?), repita a chamada (é idempotente?), use o token de outro usuário de teste (há controle de acesso por objeto?). Confirme o esboço reimplementando as chamadas com `curl` ou um script pequeno — a documentação só está certa quando um cliente escrito a partir dela funciona.

## Autenticação e tokens

- **Esquema**: `Authorization: Bearer`, cookie de sessão, chave de API em cabeçalho ou consulta, Basic, mTLS, requisição assinada.
- **JWT** (três partes separadas por ponto): decodifique cabeçalho e carga para ver algoritmo, emissor, audiência, expiração e escopos.
  ```bash
  python3 - "$TOKEN" <<'EOF'
  import sys, json, base64
  for parte in sys.argv[1].split('.')[:2]:
      print(json.dumps(json.loads(base64.urlsafe_b64decode(parte + '=' * (-len(parte) % 4))), indent=2))
  EOF
  ```
- **Fluxo**: de onde vem o token (login, OAuth com PKCE, troca de token do dispositivo), validade, renovação (refresh token e sua rotação), encerramento.
- **Requisições assinadas** (cabeçalhos como `X-Signature`, `X-Timestamp`, `X-Nonce`): a receita está no cliente — ache o código pelo nome do cabeçalho e documente a string canônica, o algoritmo (HMAC-SHA256 é o usual) e a origem da chave. Chave de assinatura fixa embutida no cliente é um achado de segurança.

## gRPC e Protobuf

```bash
grpcurl -plaintext localhost:50051 list                       # serviços (se a reflexão estiver habilitada)
grpcurl -plaintext localhost:50051 describe pacote.Servico
grpcurl -plaintext -d '{"id": 1}' localhost:50051 pacote.Servico/Metodo
grpcurl -import-path proto/ -proto servico.proto host:443 list     # sem reflexão, com os .proto

protoc --decode_raw < mensagem.bin                            # decodifica sem esquema: números de campo, tipos de fio, valores
protoc --decode=pacote.Mensagem -I proto/ arquivo.proto < mensagem.bin
```

- Corpo gRPC em HTTP/2: 1 byte de compressão + 4 bytes de tamanho (big-endian) + a mensagem Protobuf — remova os 5 bytes antes de decodificar.
- Sem `.proto`: o código gerado no cliente (classes Java/Kotlin, descritores embutidos em Go/C++/Python, definições em JS) contém o esquema; nomes de campo aparecem em descritores serializados (`strings | rg "\.proto"`).
- `--decode_raw` não distingue string de mensagem aninhada nem de bytes; compare várias amostras para nomear campos.
- gRPC-Web e Connect: mesmo conteúdo, enquadramento ligeiramente diferente, às vezes em base64.

## Tráfego que não é HTTP

```bash
ss -ltnp; ss -tnp                                    # quem escuta e quem conecta, por processo
tcpdump -i any -w captura.pcap host 10.0.0.5 and port 9000
tshark -r captura.pcap -q -z conv,tcp                # conversas
tshark -r captura.pcap -q -z io,phs                  # hierarquia de protocolos reconhecidos
tshark -r captura.pcap -Y 'tcp.port == 9000' -T fields -e frame.time_relative -e ip.src -e tcp.len -e data
tshark -r captura.pcap -q -z follow,tcp,hex,0        # conteúdo da primeira conversa TCP
strace -f -e trace=network -s 256 -p <pid>           # o que o processo envia e recebe (Linux, processo seu)
```

Protocolos conhecidos em portas inesperadas são comuns: force a decodificação (`tshark -d tcp.port==9000,http`). WebSocket, MQTT, AMQP, protocolos de banco (PostgreSQL, MySQL, Redis) e TLS são reconhecidos pelo Wireshark. TLS sem as chaves só mostra metadados (SNI, tamanhos, tempos).

## Protocolos binários desconhecidos

Método: muitas amostras + variação controlada de uma entrada por vez.

1. **Separe as mensagens**: procure enquadramento — prefixo de tamanho (2 ou 4 bytes cujo valor bate com o tamanho do restante), delimitador (`\n`, `\0`, `\r\n\r\n`), ou tamanho fixo.
2. **Procure o cabeçalho**: bytes mágicos, versão, tipo de mensagem (um byte/palavra com poucos valores distintos), identificador de sequência (cresce de 1 em 1), carimbo de tempo (valor próximo de `date +%s`, ou milissegundos), soma de verificação no fim (CRC-32, Adler-32, CRC-16 — teste calculando sobre o resto).
3. **Decida a ordem dos bytes**: inteiros pequenos aparecem como `00 00 00 2A` (big-endian, "ordem de rede") ou `2A 00 00 00` (little-endian).
4. **Reconheça codificações de uso geral antes de inventar uma**:

| Bytes iniciais / padrão | Codificação |
|---|---|
| `1f 8b` | gzip |
| `78 01` / `78 9c` / `78 da` | zlib |
| `28 b5 2f fd` | Zstandard |
| `04 22 4d 18` | LZ4 (quadro) |
| `7b`…/`5b`… texto | JSON |
| `0a`/`08`/`12` seguidos de varints | provável Protobuf |
| `8x`/`9x`/`dc`/`de`, `a0`–`bf` antes de textos curtos | MessagePack |
| `a1`–`bf` com textos precedidos de `6x`/`7x` | CBOR |
| `30 82` | ASN.1 DER (certificados, chaves) |
| 4 bytes de tamanho (little-endian) e documento terminado em `00` | BSON |
| só `A–Z a–z 0–9 + / =` | base64 (decodifique e recomece) |
| alta entropia, sem estrutura | comprimido ou cifrado — volte ao código do cliente para achar a chave e o algoritmo |

5. **Diferencie**: envie "A", depois "B", depois "AA"; observe quais bytes mudam (o campo), quais acompanham o tamanho (o comprimento) e quais mudam de forma imprevisível (soma de verificação, nonce, cifra).
6. **Formalize**: descreva o formato em Kaitai Struct (`.ksy`) — vira documentação e gera um parser em várias linguagens — ou escreva um parser pequeno em Python (`struct`) e passe todas as amostras por ele. Bytes que sobram sem explicação são o que falta entender.
7. **Valide** construindo uma mensagem do zero e conferindo que o sistema real (de teste) a aceita.

Ferramentas: `xxd`, `hexdump -C`, `cmp -l a b` e `diff <(xxd a) <(xxd b)` para comparar amostras, `binwalk`, ImHex/010 Editor com modelos, dissecador Lua no Wireshark.

## Formatos de arquivo desconhecidos

Mesmo método dos protocolos, com vantagens: você tem o arquivo inteiro e pode gerar variações à vontade.

```bash
file -k arquivo; xxd arquivo | head -n 20; xxd arquivo | tail -n 5
binwalk arquivo                         # arquivos e fluxos comprimidos embutidos
strings -n 6 arquivo | head -n 50
```

- Muitos formatos "proprietários" são contêineres conhecidos com outra extensão: ZIP (`PK`), SQLite (`SQLite format 3`), gzip, tar, OLE2 (`d0 cf 11 e0`), XML, plist binário (`bplist00`), RIFF, Parquet (`PAR1`), HDF5.
- Estruturas comuns: cabeçalho com mágico + versão + tabela de deslocamentos; blocos tipo-tamanho-valor (TLV); índice no fim do arquivo (como no ZIP e no PDF); registros de tamanho fixo (tamanho do arquivo divisível pelo do registro).
- Gere pares de arquivos com uma única diferença no programa de origem (um campo alterado, um registro a mais) e compare byte a byte.
- O código que lê/grava o formato é a especificação definitiva: ache-o pelo mágico ou pela extensão ([binarios.md](binarios.md), [codigo-legado.md](codigo-legado.md)).
- Entregue: descrição campo a campo (deslocamento, tamanho, tipo, significado, OBSERVADO/INFERIDO), um parser e, se o objetivo é migração, um conversor com teste de ida e volta.

## Banco de dados sem documentação

Trabalhe em cópia ou réplica de leitura, nunca experimentando na produção.

```bash
pg_dump --schema-only -d banco > esquema.sql          # PostgreSQL
mysqldump --no-data banco > esquema.sql               # MySQL/MariaDB
sqlite3 arquivo.db .schema
```

1. **Inventário**: tabelas, colunas, tipos, chaves, índices, visões, gatilhos, procedimentos, sequências (`information_schema`, catálogos do sistema).
2. **Tamanho e atividade**: contagem de linhas por tabela; tabelas mais lidas e escritas (`pg_stat_user_tables`, `sys.dm_db_index_usage_stats`, `performance_schema`). Tabela vazia ou parada há anos provavelmente é resto.
3. **Relacionamentos**: chaves estrangeiras declaradas e — mais comuns em legado — as *não* declaradas, inferidas por nome (`cliente_id`, `id_cliente`) e confirmadas por consulta (os valores existem todos na tabela de destino?).
4. **Significado das colunas**: amostras de valores, cardinalidade, nulos, mínimos e máximos, distribuição de colunas de status/tipo (`SELECT col, COUNT(*) … GROUP BY col`). Números mágicos (`status = 3`) se explicam no código ou em tabelas de domínio.
5. **Quem usa**: busque nomes de tabela no código, em procedimentos e em relatórios; os logs de consulta (`pg_stat_statements`) mostram o uso real, inclusive por sistemas que você não sabia que existiam.
6. **Lógica no banco**: gatilhos e procedimentos são regras de negócio — extraia e versione.
7. **Qualidade**: órfãos, duplicatas onde deveria haver unicidade, datas impossíveis, codificação de caracteres incorreta.

Entregue: diagrama entidade-relacionamento (Mermaid `erDiagram`), dicionário de dados (tabela, coluna, tipo, significado, origem da informação, confiança) e a lista das regras de negócio encontradas no banco. Dados pessoais vistos durante a análise não vão para o relatório — descreva a forma, não o conteúdo.
