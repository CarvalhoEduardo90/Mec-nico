# Falhas típicas de sistemas distribuídos

Cada seção: sintoma → como confirmar → causa → correção.

## Índice
- [Timeouts e latência em cadeia](#timeouts-e-latência-em-cadeia)
- [Tempestade de retries e falha em cascata](#tempestade-de-retries-e-falha-em-cascata)
- [Mensagens duplicadas](#mensagens-duplicadas)
- [Mensagens fora de ordem](#mensagens-fora-de-ordem)
- [Mensagens perdidas ou paradas](#mensagens-perdidas-ou-paradas)
- [Mensagem venenosa e fila morta](#mensagem-venenosa-e-fila-morta)
- [Escrita dupla: banco e evento divergem](#escrita-dupla-banco-e-evento-divergem)
- [Leitura de dado desatualizado](#leitura-de-dado-desatualizado)
- [Processo de vários passos pela metade](#processo-de-vários-passos-pela-metade)
- [Quebra de contrato após deploy](#quebra-de-contrato-após-deploy)
- [Descoberta, DNS e configuração](#descoberta-dns-e-configuração)
- [Autenticação entre serviços](#autenticação-entre-serviços)
- [Kubernetes](#kubernetes)
- [Banco compartilhado entre serviços](#banco-compartilhado-entre-serviços)
- [Notas por tecnologia de mensageria](#notas-por-tecnologia-de-mensageria)

## Timeouts e latência em cadeia

**Sintoma**: 504 no gateway; requisições "penduradas"; erro em A enquanto B registra sucesso segundos depois.

**Confirmar**: liste o timeout de cada salto (cliente → gateway → A → B → banco). No trace, veja qual span consome o tempo.

**Causas**: cliente HTTP sem timeout (padrão infinito em várias bibliotecas); timeout interno *maior* que o externo — A desiste em 5 s, mas B continua trabalhando 30 s e conclui uma operação que A já reportou como falha; chamadas em série que poderiam ser paralelas; cadeia síncrona longa.

**Correção**: timeout explícito de conexão e de leitura em toda chamada; cada salto com prazo menor que o anterior, ou prazo propagado (deadline do gRPC, cabeçalho com o orçamento restante); cancelamento propagado (contexto) para o trabalho parar quando o chamador desistiu; operação que continua após o timeout do chamador deve ser idempotente, porque virá o retry; fluxo longo → assíncrono (aceitar com 202 e notificar/consultar depois).

## Tempestade de retries e falha em cascata

**Sintoma**: um serviço lento derruba os que dependem dele; a carga sobe justamente quando algo falha; a recuperação não acontece mesmo após a causa original sumir.

**Confirmar**: taxa de requisições recebidas pelo serviço doente maior que o normal; threads/conexões esgotadas nos chamadores; mesma requisição aparecendo várias vezes nos logs.

**Causas**: retry em várias camadas multiplicando (3 × 3 × 3 = 27 tentativas); retry imediato e sincronizado; retry de erro não transitório (400, 404, validação); chamador sem limite de concorrência por dependência.

**Correção**: retry em **uma** camada, com recuo exponencial + jitter e teto de tentativas; orçamento de retry (fração máxima do tráfego); só para erros transitórios (timeouts, 502/503/504, 429 respeitando `Retry-After`) e operações idempotentes; circuit breaker que falha rápido enquanto o destino está doente; bulkhead (pool/semaforo por dependência) para uma dependência lenta não consumir tudo; descarte de carga (responder 503 cedo) e degradação planejada para dependências não essenciais; fila entre os serviços quando a resposta não precisa ser imediata.

## Mensagens duplicadas

**Sintoma**: cobrança em dobro, e-mail repetido, contador a mais, registro duplicado.

**Confirmar**: mesmo ID de mensagem/chave de negócio processado duas vezes nos logs do consumidor.

**Causa**: entrega *ao menos uma vez* é o normal em Kafka, RabbitMQ, SQS e afins. Duplicatas vêm de: consumidor que processou e caiu antes de confirmar; rebalanceamento; timeout de visibilidade menor que o tempo de processamento; retry do produtor; reprocessamento manual.

**Correção — consumidor idempotente**, por um destes meios:
- Operação naturalmente idempotente (`SET status = 'pago'`, upsert por chave de negócio) em vez de incremental.
- Tabela de mensagens processadas: grave o ID da mensagem **na mesma transação** do efeito, com restrição única; violação = já processado, confirme e siga.
- Chave de idempotência repassada às chamadas externas (gateways de pagamento aceitam).
- Verificação de estado: transição só é aplicada se o estado atual for o esperado.

"Exatamente uma vez" de ponta a ponta não existe para efeitos externos; o que existe é entrega ao menos uma vez + processamento idempotente.

## Mensagens fora de ordem

**Sintoma**: estado final errado (pedido "criado" depois de "cancelado"); atualização antiga sobrescrevendo a nova.

**Causas**: partições/consumidores paralelos; chave de particionamento ausente ou errada; retry reenfileirando no fim; várias instâncias produtoras; eventos de entidades relacionadas em tópicos diferentes.

**Correção**: mesma chave de partição/grupo de mensagens para eventos da mesma entidade (Kafka: chave; SQS FIFO: `MessageGroupId`; RabbitMQ: uma fila por chave ou consistent-hash); número de versão/sequência no evento e descarte do que for mais antigo que o estado atual; eventos com o estado completo em vez de deltas, quando possível; consumidor tolerante a evento cuja dependência ainda não chegou (estacionar e tentar depois).

## Mensagens perdidas ou paradas

**Sintoma**: o produtor "enviou", o consumidor nunca viu; atraso crescente.

**Confirmar**: profundidade da fila / lag do grupo de consumidores; logs do produtor (houve confirmação do broker?); o consumidor está vivo e inscrito no tópico/fila certo, com o nome certo naquele ambiente?

**Causas**: publicação sem confirmação (fire-and-forget) seguida de queda; confirmação automática antes do processamento — a mensagem é dada como entregue e o consumidor falha; exceção engolida no handler; binding/roteamento errado (RabbitMQ: mensagem sem rota é descartada sem aviso, a menos que `mandatory`/exchange alternativo); retenção expirada antes da leitura (Kafka); consumidor novo começando do fim (`auto.offset.reset=latest`); consumidor lento ou travado; rebalanceamento em laço porque o processamento excede `max.poll.interval.ms`.

**Correção**: confirmar a publicação (acks do broker, `acks=all`, publisher confirms); confirmar o consumo **depois** de processar; nunca engolir exceção no handler; alertas de lag e de idade da mensagem mais antiga; ajustar concorrência/lote e tempo de processamento; publicação transacional via outbox.

## Mensagem venenosa e fila morta

**Sintoma**: consumidor em laço no mesmo erro; fila parada atrás de uma mensagem; fila morta crescendo sem ninguém olhar.

**Causa**: mensagem que nunca poderá ser processada (formato inválido, referência inexistente, bug do consumidor) sendo retentada para sempre.

**Correção**: limite de tentativas com recuo, depois fila morta (DLQ) com o motivo anexado; distinguir erro transitório (tentar de novo) de permanente (direto para a DLQ); alerta sobre a DLQ; procedimento de reprocessamento depois de corrigir o consumidor — e o consumidor precisa ser idempotente para isso; validação de esquema na entrada do consumidor.

## Escrita dupla: banco e evento divergem

**Sintoma**: registro existe sem o evento correspondente (ou o contrário); serviços a jusante com dado faltando, sem erro em lugar nenhum.

**Causa**: o código grava no banco e publica no broker como duas operações independentes. Falha entre as duas — ou rollback depois de publicar — deixa os dois lados divergentes.

**Correção**:
- **Outbox transacional**: na mesma transação do dado, insira o evento em uma tabela `outbox`; um relé (poller ou CDC, como Debezium) publica e marca como enviado. Entrega ao menos uma vez → consumidores idempotentes.
- **Publicar depois do commit** (hook pós-commit) reduz, mas não elimina: a queda entre o commit e a publicação ainda perde o evento. Aceitável só com reconciliação periódica.
- **Inbox** no consumidor para deduplicar.
- Nunca chame serviço externo dentro de transação de banco esperando atomicidade.

## Leitura de dado desatualizado

**Sintoma**: usuário cria algo e não vê na tela seguinte; serviço B decide com dado antigo de A.

**Causas**: leitura em réplica com atraso; projeção/cópia local atualizada por eventos (consistência eventual); cache.

**Correção**: decidir caso a caso se o atraso é aceitável — e dizer isso. Quando não é: ler do primário/dono logo após escrever; devolver o recurso criado na própria resposta; versão/token de consistência para "ler o que escrevi"; a interface refletir o estado pendente. Para decisões críticas (saldo, estoque), consulte o dono do dado de forma síncrona ou reserve explicitamente.

## Processo de vários passos pela metade

**Sintoma**: pagamento cobrado sem pedido confirmado; estoque reservado para sempre; entidades em estado intermediário.

**Causa**: sequência de chamadas a vários serviços sem tratamento da falha no meio — não há rollback distribuído.

**Correção — saga**: cada passo tem uma ação de compensação; o estado do processo é persistido; um orquestrador (ou a coreografia por eventos) avança ou compensa. Requisitos: passos e compensações idempotentes; timeouts por passo; estados intermediários visíveis e válidos ("pagamento pendente"); job de reconciliação que encontra e resolve processos parados. Ferramentas de workflow durável (Temporal, Step Functions, Camunda) implementam isso; em sistema simples, uma tabela de estado + job de retomada resolve.

Para os registros que já ficaram pela metade: script de reparo idempotente, executado com aprovação do usuário.

## Quebra de contrato após deploy

**Sintoma**: erros de desserialização, 400/422 entre serviços, campo nulo inesperado, consumidor falhando em todas as mensagens — começando logo após um deploy.

**Confirmar**: horário do deploy × início dos erros; diff do contrato entre as versões (`buf breaking`, `oasdiff`, diff de esquema).

**Correção imediata**: reverter o provedor **ou** torná-lo compatível novamente (voltar a emitir/aceitar o formato antigo ao lado do novo). **Definitiva**: expandir → migrar → contrair; leitor tolerante; testes de contrato dirigidos pelo consumidor no CI; registro de esquemas com verificação de compatibilidade. Lembre das mensagens já publicadas no formato quebrado: precisam de consumidor que as entenda ou de descarte consciente.

## Descoberta, DNS e configuração

**Sintomas e causas**:
- `connection refused` / `no such host`: nome do serviço errado para aquele ambiente; porta do Service × porta do container; serviço sem endpoints prontos; namespace diferente (`servico.namespace.svc.cluster.local`).
- Funciona local, falha no cluster: `localhost` no lugar do nome do serviço; variável de ambiente ausente no manifesto; ConfigMap/Secret alterado sem reiniciar os pods.
- Erros intermitentes após deploy: conexões keep-alive presas a pods encerrados; DNS em cache; balanceamento de conexões longas (gRPC/HTTP2 concentra tudo em um pod sem balanceamento no cliente ou malha).
- Um ambiente apontando para o outro: URL de produção em configuração de homologação — confira a configuração **efetiva**.

**Diagnóstico**: `kubectl get endpoints <svc>`; `kubectl exec <pod> -- nslookup <svc>` / `curl -v`; `kubectl describe svc`; `docker compose config`; imprimir a configuração resolvida na inicialização (sem segredos).

## Autenticação entre serviços

- Token do usuário não propagado ou propagado a quem não deveria; escopo/audiência incorretos (`aud`).
- Token de serviço expirado sem renovação; relógio fora de sincronia invalidando JWT.
- mTLS: certificado expirado, CA não confiada, SAN que não corresponde ao nome usado.
- Gateway autentica, serviços internos confiam cegamente em cabeçalhos (`X-User-Id`) que podem ser forjados por quem alcança a rede interna: valide o token no serviço ou garanta, por política de rede, que só o gateway o alcança.
- Autorização por recurso continua sendo responsabilidade do serviço dono do dado.

## Kubernetes

| Estado | Significado | Onde olhar |
|---|---|---|
| `CrashLoopBackOff` | processo sai logo após iniciar | `kubectl logs <pod> --previous`; configuração/segredo ausente; migração falhando; probe de liveness matando |
| `OOMKilled` | passou do limite de memória | `describe pod` (Last State); limite baixo, vazamento, heap da JVM/Node não ajustado ao limite do container |
| `ImagePullBackOff` | não baixa a imagem | tag inexistente, credencial do registro, arquitetura |
| `Pending` | não agendado | recursos insuficientes, afinidade/taints, PVC não vinculado |
| Pronto mas sem tráfego | readiness falhando ou seletor errado | `get endpoints`, rótulos × seletor do Service |
| Reinícios periódicos | liveness agressiva | probe mais lenta que a resposta sob carga; use startup probe para inicialização lenta |
| Erros durante o deploy | encerramento não gracioso | tratar `SIGTERM`, `preStop` com pequena espera, `terminationGracePeriodSeconds`, readiness falhando antes de parar |
| Lentidão sem uso alto de CPU | estrangulamento de CPU | limites de CPU baixos (throttling) |

`kubectl describe pod` e `kubectl get events --sort-by=.lastTimestamp` explicam a maior parte. Comandos que alteram o cluster (`apply`, `delete`, `rollout restart`, `scale`) só com pedido explícito do usuário.

## Banco compartilhado entre serviços

**Sintoma**: mudança de esquema em um serviço quebra outro; ninguém sabe quem pode alterar a tabela.

É acoplamento disfarçado: os serviços são implantados separadamente, mas mudam juntos. Na manutenção: descubra **todos** os leitores e escritores antes de alterar o esquema (`pg_stat_statements`, usuários de banco distintos por serviço, busca nos repositórios); trate o esquema como contrato público (expandir → migrar → contrair). Como direção de médio prazo: um dono por tabela, e os demais acessam por API ou por cópia alimentada por eventos.

## Notas por tecnologia de mensageria

**Kafka**
- Ordem só dentro da partição; a chave define a partição. Mudar o número de partições altera o mapeamento chave → partição.
- O offset é confirmado pelo consumidor: confirmação antes do processamento perde mensagens; depois, duplica em caso de queda.
- `max.poll.interval.ms` excedido → o consumidor é expulso do grupo → rebalanceamento → reprocessamento em laço. Reduza o lote (`max.poll.records`) ou tire o trabalho pesado do laço de poll.
- Lag: `kafka-consumer-groups --describe --group <g>`.
- Retenção e compactação: mensagens somem por tempo/tamanho; em tópico compactado, só fica a última por chave.

**RabbitMQ**
- Mensagem sem fila ligada à chave de roteamento é descartada em silêncio (use `mandatory` ou exchange alternativo).
- `ack` manual depois de processar; `nack`/`reject` com `requeue=true` em erro permanente cria laço — use DLX.
- `prefetch` sem limite entrega tudo a um consumidor só.
- Filas e mensagens não duráveis somem ao reiniciar o broker.

**SQS / SNS**
- Timeout de visibilidade menor que o tempo de processamento → entrega duplicada em paralelo.
- Fila padrão: ao menos uma vez, sem ordem. FIFO: ordem por `MessageGroupId`, deduplicação em janela de 5 minutos.
- Política de redrive define a DLQ; sem ela, a mensagem volta até a retenção expirar.
- Limite de tamanho de mensagem: carga grande vai para armazenamento de objetos, com referência na mensagem.

**gRPC**
- Deadline propagado pelo contexto — defina sempre no cliente.
- Códigos de status dizem o que é seguro repetir (`UNAVAILABLE` sim; `INVALID_ARGUMENT` nunca; `DEADLINE_EXCEEDED` só se idempotente).
- Conexões HTTP/2 longas não são rebalanceadas por balanceador de camada 4.
- Compatibilidade de `.proto`: não reutilizar números de campo; não mudar tipos; `reserved` para os removidos.
