---
name: microservicos
description: Conhecimento de manutenção para microsserviços e sistemas distribuídos — rastrear uma falha através de vários serviços, timeouts, retries e falhas em cascata, mensageria (Kafka, RabbitMQ, SQS), idempotência, consistência eventual, sagas e outbox, contratos entre serviços e compatibilidade de versões, gateway, descoberta de serviço, Kubernetes e ordem de deploy. Use ao diagnosticar ou corrigir problema que envolve mais de um serviço, comunicação entre serviços, filas e eventos, ou quando uma mudança em um serviço pode afetar outros.
---

# Manutenção de microsserviços

Em sistema distribuído, o defeito e o sintoma raramente moram no mesmo serviço. O serviço A devolve 500 porque B demorou, porque C esgotou o pool de conexões, porque um deploy em D mudou o formato de um evento. Três verdades orientam o trabalho:

1. **A rede falha, atrasa e duplica.** Toda chamada entre serviços pode não chegar, chegar tarde, chegar duas vezes ou ter sucesso sem que o chamador saiba.
2. **Não existe transação global.** Cada serviço confirma o seu pedaço; o conjunto fica consistente *eventualmente* — ou não fica, se ninguém projetou a compensação.
3. **Os serviços são implantados separadamente.** Em qualquer momento convivem versões diferentes; todo contrato precisa funcionar com o vizinho na versão anterior e na seguinte.

## 1. Mapear antes de mexer

Você precisa do grafo: quem chama quem, por qual protocolo, síncrono ou assíncrono. Fontes, das mais para as menos confiáveis:

- **Rastreamento distribuído** (Jaeger, Tempo, Zipkin, X-Ray, APM): mostra o caminho real de uma requisição.
- **Infraestrutura como código**: Compose, manifestos Kubernetes, Helm, Terraform — serviços, portas, variáveis de ambiente com URLs de outros serviços, tópicos e filas.
- **Código**: clientes HTTP/gRPC (`rg -n "https?://|BASE_URL|_SERVICE_URL|_HOST"`), arquivos `.proto`, produtores e consumidores (`rg -n "publish|produce|send\(|subscribe|consume|@KafkaListener|@RabbitListener|@SqsListener"`), nomes de tópicos.
- **Gateway / malha**: rotas do gateway, configuração de ingress, regras do service mesh.

O script da skill `detectar-stack` lista as unidades e a infraestrutura. Para um mapa completo com análise de impacto, delegue ao subagente `arquiteto-de-sistemas`.

Registre, para cada aresta do grafo: protocolo, timeout, política de retry e o que acontece quando o destino falha. As arestas sem resposta para a última pergunta são onde os incidentes acontecem.

## 2. Rastrear uma falha entre serviços

1. **Pegue o identificador de correlação** da requisição que falhou (`traceparent`, `X-Request-Id`, `X-Correlation-Id`). Com rastreamento, abra o trace e vá ao primeiro span com erro — o primeiro no tempo, não o mais externo.
2. **Sem rastreamento**: busque o ID nos logs de cada serviço e monte a linha do tempo à mão. Sem ID propagado, correlacione por horário e entidade (ID do pedido, do usuário) — e anote que a correção deve incluir a propagação do ID.
3. **Siga para o serviço mais profundo que errou.** Os erros a montante são, em geral, propagação.
4. **Distinga**: o serviço de baixo *errou* (bug ou dado inválido), *demorou* (timeout a montante) ou *não foi alcançado* (DNS, descoberta, rede, política, certificado)?
5. **Confira versões e horários de deploy** de todos os serviços no caminho. "Começou às 14h10" + "deploy de X às 14h08" encerra muita investigação.
6. **Reproduza localmente o menor recorte**: o serviço suspeito com suas dependências simuladas (WireMock, mocks de contrato) ou via Compose. Reproduzir a malha inteira raramente é necessário.

Problemas de relógio: horários de servidores diferentes divergem; ordene eventos pelo trace ou por números de sequência, não só por timestamp.

## 3. Catálogo de falhas e correções

Sintomas, causas e correções detalhadas — timeouts em cadeia, tempestade de retries, mensagens duplicadas e fora de ordem, fila morta, escrita dupla, consistência, descoberta e configuração, Kubernetes: [referencias/falhas-distribuidas.md](referencias/falhas-distribuidas.md). Leia a seção que corresponde ao sintoma antes de propor a correção.

Resumo dos princípios que as correções seguem:

- **Timeout em toda chamada**, menor que o de quem chamou; orçamento de tempo propagado.
- **Retry só no que é idempotente e transitório**, com recuo exponencial, jitter e limite; em uma camada só.
- **Idempotência em todo consumidor e em toda escrita exposta**: a mesma mensagem ou requisição processada duas vezes produz o mesmo resultado.
- **Outbox em vez de escrita dupla**: gravar no banco e publicar evento na mesma transação local; um relé publica depois.
- **Isolamento de falha**: circuit breaker, bulkhead, degradação definida para dependência não essencial.
- **Compensação explícita** para processos de vários passos (saga), com estado persistido.

## 4. Mudar contratos sem quebrar vizinhos

Contrato é tudo o que outro serviço observa: rota, campos, tipos, códigos de status, esquema de evento, nome de tópico, semântica.

**Antes de alterar, descubra os consumidores**: busca nos outros repositórios, testes de contrato (Pact), registro de esquemas, logs de acesso. Um consumidor desconhecido é a regra, não a exceção.

**Mudanças compatíveis** (podem ir direto): adicionar campo opcional, novo endpoint, novo tipo de evento, aceitar valor a mais na entrada.

**Mudanças incompatíveis** (remover/renomear campo, mudar tipo ou significado, tornar obrigatório, novo valor de enum para leitor estrito) seguem **expandir → migrar → contrair**:

1. *Expandir*: o provedor passa a aceitar/emitir o formato novo **e** o antigo.
2. *Migrar*: cada consumidor passa a usar o novo; confirme por métricas/logs que o antigo não é mais usado.
3. *Contrair*: remova o antigo, em deploy posterior.

Regras práticas: leitores tolerantes (ignorar campos desconhecidos; não falhar com enum novo); em Protobuf, nunca reutilizar número de campo e reservar os removidos; em Avro/JSON Schema, usar o modo de compatibilidade do registro; versionar eventos no próprio envelope; `buf breaking`, `oasdiff` e testes de contrato no CI detectam a quebra antes do deploy.

**Ordem de deploy**: se a correção exige ordem ("B antes de A"), isso é um risco a declarar — e geralmente sinal de que falta o passo de expansão. Mensagens já enfileiradas no formato antigo continuarão chegando depois do deploy.

## 5. Corrigir em um serviço: o que muda em relação ao monólito

- **A correção fica no serviço dono da regra.** Compensar no chamador o erro do chamado cria dois lugares para manter. Se o dono é de outro time/repositório, a entrega pode ser um contorno temporário *mais* o relato do defeito na origem.
- **Teste na fronteira**: além do teste de unidade, um teste de integração do endpoint/consumidor com as dependências simuladas no nível de protocolo — incluindo os caminhos de falha (timeout, 5xx, mensagem duplicada, mensagem malformada).
- **Correção que atravessa serviços** vira uma sequência de mudanças pequenas, cada uma implantável e reversível sozinha. Descreva a sequência.
- **Dados já gravados errados**: corrigir o código não corrige os registros e eventos que o bug produziu. Avalie reprocessamento, script de reparo ou evento de compensação — e que seja idempotente.
- **Observabilidade como parte da correção**: se achar o problema exigiu arqueologia, acrescente o log com ID de correlação, a métrica ou o alerta que teria mostrado a falha.

## 6. Ambiente local

```bash
docker compose config --services            # o que existe
docker compose up -d <servico> <dependencias>
docker compose logs -f --tail=100 <servico>
kubectl get pods -n <ns>; kubectl describe pod <p>; kubectl logs <p> --previous
kubectl port-forward svc/<servico> 8080:80   # falar com um serviço do cluster
```

Aponte apenas para ambientes locais ou de desenvolvimento. Não publique mensagens em tópicos nem chame APIs de produção para "testar".

## Lista antes de entregar

- [ ] Sei quais serviços consomem o que alterei?
- [ ] A mudança funciona com os vizinhos na versão atual **e** na anterior?
- [ ] Toda chamada nova tem timeout, e retry só onde é seguro?
- [ ] Consumidores e escritas são idempotentes?
- [ ] Publicação de evento e gravação no banco não podem divergir?
- [ ] Há ordem de deploy obrigatória? Está documentada?
- [ ] O que acontece com mensagens antigas ainda na fila?
- [ ] Dados corrompidos pelo bug precisam de reparo?
- [ ] O ID de correlação é propagado e registrado no caminho alterado?
