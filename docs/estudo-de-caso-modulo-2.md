# Estudo de caso — integrar hospital, operadora e laboratório

**Disciplina:** Arquitetura de Software — Módulo 2 (APIs)
**Autor:** Gabriel Krzizanowski
**Data:** 29 de agosto de 2026
**Fonte do caso:** <https://marco-mendes.github.io/arquitetura-software/modulo-2-apis/estudo-de-caso/>
**Repositório com o código da oficina:** ver `README.md` na raiz deste repositório

---

## 1. Contexto e forças de arquitetura

A plataforma hospitalar é a fronteira entre canais administrativos internos (agenda, elegibilidade, autorização, pedidos de exame) e duas organizações independentes — a operadora e o laboratório — que têm versões, disponibilidade, vocabulário e ritmo próprios. As duas forças que determinam todas as decisões abaixo são:

1. **A plataforma não controla o parceiro.** Disponibilidade, latência, versão e semântica do laboratório e da operadora mudam sem aviso e sem coordenação de release.
2. **O tempo do processo não é o tempo da requisição.** A elegibilidade é aceita em segundos, mas decidida em minutos; um resultado de exame pode levar minutos, horas ou dias.

Por isso o desenho começa registrando o pedido *antes* de falar com o parceiro e mantendo o estado externo **explícito** (`recebida`, `desconhecida`, `falha temporária`) em vez de presumir uma decisão que a plataforma não tomou. O laboratório da oficina prova esse formato: `POST /elegibilidades` responde `202 Accepted` com `Location`, e `GET /elegibilidades/{protocolo}` devolve a situação conhecida — nunca uma decisão inventada.

---

## 2. As cinco decisões

### Decisão 1 — Pedido ao laboratório: acesso direto, contrato oficial por adaptador ou mensageria?

**Escolha: contrato oficial SOAP/TISS consumido por um adaptador (anti-corruption layer).**

**Justificativa em uma frase:** o acesso direto ao banco do parceiro acopla a plataforma a um modelo de dados que ela não controla nem versiona, e a mensageria cobra hoje um preço de consistência eventual, duplicidade e operação que ainda não temos evidência de precisar pagar — o contrato oficial isolado atrás de um adaptador respeita a interface publicada pelo parceiro e concentra a tradução em um único ponto revisável.

**Consequências assumidas:**

- Permanece uma **dependência temporal** da disponibilidade do laboratório: a chamada externa pode falhar ou expirar. O desenho absorve isso registrando o protocolo antes da chamada e gravando *falha temporária correlacionada* em vez de erro final.
- O adaptador é um componente real: exige testes de tradução, mapeamento de erro e observabilidade própria (latência, taxa de timeout, divergência de estado).

**Evidência que mudaria a escolha:**

| Evidência observada | Para onde a decisão migra |
|---|---|
| Indisponibilidade do laboratório acima do orçamento de erro acordado, ou janela de manutenção regular do parceiro que exceda o timeout aceitável do canal administrativo | Mensageria com fila de saída (*outbox*) e retomada — desacopla o tempo do pedido do tempo do parceiro |
| Volume de pedidos que torne a chamada síncrona um gargalo, ou necessidade demonstrada de retomar pedidos após reinício da plataforma | Mensageria com idempotência (ver Decisão 5) |
| Laboratório passar a publicar contrato REST/JSON versionado e estável | O adaptador permanece, mas encolhe: deixa de traduzir XML e passa a traduzir apenas identificadores e códigos de erro |
| Perda de significado detectada na conversão (campo TISS sem equivalente interno) | Não muda a família de alternativa; muda o contrato interno, que passa a precisar de campo explícito em vez de valor inferido |

O acesso direto ao banco não volta a ser alternativa em nenhum desses cenários: ele troca um problema de integração por um problema de acoplamento permanente.

---

### Decisão 2 — A tradução SOAP/TISS ↔ vocabulário da plataforma fica no gateway ou no adaptador?

**Escolha: no adaptador.**

**Justificativa em uma frase:** o gateway é o lugar das **políticas técnicas de fronteira** — TLS, roteamento, autenticação técnica, rate limit, correlação, métricas — e colocar conversão TISS nele espalha decisão de domínio por um componente de infraestrutura, escondendo perda semântica atrás de uma fachada REST que *parece* correta.

A distinção prática é: **o gateway não consegue responder à pergunta "o que este código TISS significa para o hospital?"**. Essa pergunta é de domínio. Se a resposta mudar quando o laboratório publicar uma nova versão do contrato, a mudança precisa cair em um componente com teste de tradução, versionamento e dono — não em um arquivo de rota.

**O que o adaptador traduz (e o gateway não traduziria bem):**

| Dimensão | Exemplo no caso |
|---|---|
| Vocabulário | `pedido de exame` interno → estrutura de guia SOAP/TISS |
| Identificadores | protocolo interno ↔ número de guia/lote do laboratório |
| Erro | *fault* SOAP → `codigo` / `mensagem` / `detalhes` do contrato interno |
| Estado | timeout do parceiro → *falha temporária correlacionada*, nunca "negado" |

**Consequência assumida:** um componente a mais para construir, testar e observar. É o preço de manter o contrato interno estável quando o externo mudar.

---

### Decisão 3 — O mapeamento entre `matricula_plano` e o identificador da operadora pertence à plataforma ou à operadora?

**Escolha: à operadora — logo, ao adaptador da operadora dentro da plataforma, e não ao núcleo do domínio hospitalar nem ao gateway.**

**Justificativa em uma frase:** quem define, emite, versiona e revoga a matrícula é a operadora, então a regra de correspondência muda no ritmo da operadora e deve viver na fronteira que representa a operadora, não no modelo do hospital.

**Desdobramento prático:**

- A plataforma **guarda** `matricula_plano` e `codigo_operadora` como dados do pedido — é exatamente o que o contrato da oficina declara em `PedidoElegibilidade`. Guardar não é o mesmo que ser dona da regra.
- A **tradução** `matricula_plano` → identificador interno da operadora fica no adaptador daquela operadora. Com N operadoras existem N traduções e um contrato interno único; se a regra estivesse no domínio, cada operadora nova vazaria um `if` para dentro do núcleo.
- O gateway continua sem participar: ele roteia e aplica política, não resolve identidade de beneficiário.

**Teste de decisão usado para conferir:** *se a operadora mudar a regra sozinha, quem precisa publicar uma nova versão?* Se a resposta for "a operadora", a regra é dela e o código que a espelha é código de fronteira.

---

### Decisão 4 — Avisar que um exame ficou pronto: polling, polling adaptativo ou webhook?

**Escolha: webhook quando o laboratório conseguir notificar; polling adaptativo como contingência para os parceiros que só oferecem consulta.**

**Justificativa em uma frase:** os prazos vão de minutos a dias, e polling em intervalo fixo ou gasta chamadas em prazos longos ou atrasa o resultado em prazos curtos — o webhook transfere o custo para o instante em que o fato realmente aconteceu.

**Risco que aceito explicitamente:** o webhook transforma a plataforma em *servidor* de um parceiro externo, e com isso assumo, de forma declarada, a obrigação de construir:

1. **Autenticação e autenticidade** do endpoint que recebe a notificação (assinatura da mensagem, mTLS ou segredo compartilhado) — sem isso, qualquer um declara um exame pronto.
2. **Repetição:** o parceiro vai reenviar a mesma notificação. O recebimento precisa ser idempotente por identificador de negócio.
3. **Ordenação:** notificações podem chegar fora de ordem; o estado do exame não pode retroceder de `concluído` para `em processamento` só porque uma mensagem antiga chegou depois.
4. **Confirmação e recuperação:** se a plataforma estiver fora do ar, a notificação se perde. Por isso o webhook **não elimina** a consulta: mantenho uma varredura de reconciliação periódica para pedidos sem notificação dentro do prazo esperado.

**Limite registrado:** WebSocket não é alternativa aqui. É canal persistente para um consumidor conectado; o resultado de exame precisa ser processado mesmo sem ninguém com a tela aberta.

**Política de polling adaptativo documentada (para o parceiro que só oferece consulta):** consulta a cada 1 minuto na primeira meia hora, a cada 10 minutos até 6 horas, a cada 1 hora até 72 horas, e alerta operacional depois disso. Sem essa política escrita, "polling adaptativo" é só uma palavra.

---

### Decisão 5 — O que o ADR-002 precisa registrar antes de introduzir mensageria com idempotência?

Antes de trocar a chamada síncrona por mensageria, o ADR precisa fechar três lacunas — sem elas, "usar fila" e "usar retry" apenas deslocam a ambiguidade para a operação:

**a) Identificador de negócio (chave de idempotência)**

- Uma chave **estável, gerada pelo emissor e derivada do negócio**, não do transporte: para o pedido de exame, o `protocolo` da plataforma; para o recebimento de resultado, a tripla `(numero_guia_laboratorio, codigo_exame, versao_resultado)`.
- Ela precisa sobreviver a retry, reinício e reprocessamento manual — logo, é persistida junto com o pedido no mesmo instante em que o `202` é devolvido, e não gerada na hora do envio.
- Regra explícita: **um UUID novo por tentativa não é chave de idempotência**, é ruído.

**b) Retenção**

- Por quanto tempo a plataforma guarda a chave já processada para reconhecer uma duplicata.
- Proposta a registrar: **90 dias** para chaves de processamento, cobrindo com folga o prazo máximo de resultado (72 h) e a janela de reprocessamento operacional; **5 anos** para o histórico de estado do pedido, alinhado à guarda de prontuário e faturamento.
- O ADR precisa dizer o que acontece **depois** da retenção: mensagem com chave expirada é tratada como novo pedido ou rejeitada? Proposta: rejeitada com erro explícito, porque aceitar em silêncio recria o problema que a idempotência resolve.

**c) Comportamento de duplicidade**

- Duplicata **idêntica**: devolver o mesmo resultado do primeiro processamento (mesmo protocolo, mesmo `Location`), sem novo efeito colateral, e registrar a ocorrência em métrica.
- Duplicata com **conteúdo divergente sob a mesma chave**: rejeitar com erro de conflito e alertar — é sintoma de defeito do emissor, não de rede.
- Resposta externa **tardia**, que chega depois de a plataforma já ter concluído o pedido por outro caminho: registrar como evento de reconciliação, comparar com o estado atual e nunca sobrescrever cegamente.
- **Reinício** no meio do processamento: definir se o efeito é *at-least-once* com deduplicação no consumidor (opção proposta) ou *exactly-once* transacional; e onde ficam as mensagens não processáveis (fila morta, com prazo de análise).
- **Auditoria:** toda decisão de deduplicação precisa deixar rastro correlacionado — chave, decisão, momento e resultado — porque em saúde a pergunta "por que este pedido não foi enviado duas vezes?" é auditável.

---

## 3. Baseline recomendada e limites honestos

**Baseline para o incremento 2:** uma aplicação, REST/HTTP interno, `202 Accepted` com `Location`, contrato OpenAPI 3.1 explícito e versionado, adaptador planejado por parceiro. Gateway e entrega assíncrona permanecem **condicionais**, com gatilhos escritos.

**O que a API mínima da oficina prova de fato:**

- Semântica de aceite (`202`) separada de decisão, com `Location` para recuperar o recurso.
- Erro como parte do contrato (`422` estruturado com `codigo = dados_invalidos`).
- Contrato explícito validável por lint (Spectral) e comparável ao contrato gerado pela aplicação, com teste automatizado que reprova a divergência.

**O que ela não prova — e por isso não pode ser afirmado:** persistência (o estado vive em memória e some no reinício), segurança (não há autenticação), escalabilidade (uma instância com memória local não sobrevive a duas réplicas), integração externa real (não existe operadora nem laboratório do outro lado) e comportamento sob duplicidade (não há chave de idempotência).

**Gatilhos de revisão registrados:** indisponibilidade do parceiro acima do orçamento de erro; necessidade de segunda instância (que quebra o armazenamento em memória); primeiro parceiro capaz de notificar por webhook; primeira duplicata observada em produção.

---

## 4. Como estas respostas alimentam o ADR-002

Cada decisão acima entra no ADR-002 como **alternativa registrada**, com consequência e gatilho de revisão — nunca como escolha única sem contraditório. O ADR completo está em [`ADR-002-integracao-com-parceiros.md`](ADR-002-integracao-com-parceiros.md).

| Decisão | Alternativa escolhida | Alternativas registradas e descartadas | Gatilho de revisão |
|---|---|---|---|
| 1. Pedido ao laboratório | Contrato oficial via adaptador | Acesso direto ao banco; mensageria | Indisponibilidade acima do orçamento de erro; volume; necessidade de retomada |
| 2. Tradução TISS | No adaptador (ACL) | No gateway; padronizar tudo em SOAP | Nenhum — mover para o gateway seria regressão de projeto |
| 3. `matricula_plano` | Pertence à operadora (adaptador da operadora) | Pertence ao domínio da plataforma | Operadora publicar identificador estável e público |
| 4. Aviso de exame pronto | Webhook + reconciliação; polling adaptativo como contingência | Polling fixo; WebSocket | Parceiro sem capacidade de notificar; volume de notificações |
| 5. Confiabilidade | REST síncrono com estado explícito hoje | Mensageria com idempotência | Fechar chave de negócio, retenção e regra de duplicidade |
