# ADR-002 — Integração da plataforma hospitalar com operadora e laboratório

- **Status:** proposto
- **Data:** 2026-08-29
- **Contexto do projeto integrador:** incremento 2 (APIs)
- **Decisores:** Gabriel Krzizanowski
- **Substitui / relaciona:** ADR-001 (estilo arquitetural da plataforma)

## Contexto

A plataforma hospitalar precisa consultar elegibilidade e solicitar autorização em operadoras, e
enviar pedidos de exame a um laboratório que só publica SOAP/XML aderente ao contexto TISS. Os
parceiros são organizações independentes: versionam, ficam indisponíveis e mudam vocabulário sem
coordenação com o hospital. Os consumidores internos da plataforma (canais administrativos)
consomem REST/JSON.

Duas forças dominam a decisão:

1. A plataforma não controla disponibilidade, versão nem semântica do parceiro.
2. O tempo do processo (minutos a dias) não é o tempo da requisição HTTP.

A API mínima validada no incremento 2 (`POST /elegibilidades` → `202 Accepted` + `Location`;
`GET /elegibilidades/{protocolo}` → estado conhecido) demonstra o formato, mas não prova
persistência, segurança, escala nem integração externa.

## Decisão

1. **Consumir o contrato oficial do parceiro através de um adaptador (anti-corruption layer) por
   parceiro.** Nem acesso direto ao banco do parceiro, nem mensageria neste incremento.
2. **A tradução SOAP/TISS ↔ vocabulário interno fica no adaptador**, não no gateway. O gateway,
   quando existir, aplica somente política técnica de fronteira.
3. **O mapeamento `matricula_plano` ↔ identificador da operadora pertence à operadora** e é
   implementado no adaptador da operadora; a plataforma armazena o dado, mas não é dona da regra.
4. **Notificação de exame pronto por webhook autenticado quando o parceiro suportar**, com
   reconciliação por consulta periódica; polling adaptativo com política documentada para os
   demais.
5. **Manter REST síncrono com estado explícito neste incremento.** Mensageria com idempotência só
   entra depois que este ADR registrar chave de negócio, retenção e comportamento de duplicidade.

## Alternativas consideradas

| # | Alternativa | Ganho | Consequência que a descartou (por ora) |
|---|---|---|---|
| 1a | Acesso direto ao banco do laboratório | integração inicial mais barata | acopla ao modelo externo, quebra a cada mudança do parceiro, sem contrato |
| 1b | **Contrato oficial via adaptador (escolhida)** | respeita a interface publicada; tradução isolada | mantém dependência temporal; exige componente, testes e observabilidade |
| 1c | Mensageria | desacopla tempo, permite retomada | consistência eventual, duplicidade e operação sem necessidade demonstrada |
| 2a | Padronizar a plataforma em SOAP | pilha uniforme aparente | transfere restrição externa para consumidores internos sem necessidade |
| 2b | Converter no gateway | fachada REST rápida | esconde perda semântica; espalha decisão de domínio na infraestrutura |
| 2c | **Adaptador / ACL (escolhida)** | contrato interno estável | componente adicional a manter |
| 4a | Polling fixo | simples; funciona com parceiro que só consulta | custo alto em prazo longo, atraso em prazo curto |
| 4b | Polling adaptativo | ajusta ao prazo esperado | continua consulta periódica; política precisa ser escrita |
| 4c | **Webhook + reconciliação (escolhida)** | notifica no instante do fato | exige endpoint autenticado, idempotência, ordenação e recuperação |
| 4d | WebSocket | canal em tempo real | não serve: resultado precisa ser processado sem tela aberta |

## Consequências

**Positivas**

- O contrato interno REST/JSON permanece estável quando o contrato externo mudar.
- Mudanças do parceiro ficam confinadas a uma fronteira revisável e testável.
- Estado externo desconhecido permanece explícito (`recebida`, `falha temporária`), nunca vira
  decisão presumida por conveniência de roteamento.

**Negativas / custos aceitos**

- Um adaptador por parceiro para construir, testar e observar.
- Dependência temporal da disponibilidade do parceiro permanece no incremento 2.
- Ao adotar webhook, a plataforma passa a ser servidor de um parceiro externo, com todo o custo
  de autenticidade, repetição, ordenação e recuperação.

## Pré-condições para introduzir mensageria com idempotência

| Item | O que precisa estar registrado |
|---|---|
| Identificador de negócio | `protocolo` (pedido) e `(numero_guia_laboratorio, codigo_exame, versao_resultado)` (resultado); estável, do emissor, persistido no instante do `202` |
| Retenção | 90 dias para chaves de processamento; 5 anos para histórico de estado; chave expirada é rejeitada com erro explícito |
| Duplicata idêntica | devolve o mesmo resultado, sem novo efeito colateral, com métrica |
| Duplicata divergente | rejeita com conflito e alerta |
| Resposta tardia | vira evento de reconciliação; nunca sobrescreve estado atual cegamente |
| Reinício | at-least-once com deduplicação no consumidor; fila morta com prazo de análise |
| Auditoria | rastro correlacionado de chave, decisão, momento e resultado |

## Gatilhos de revisão

- Indisponibilidade do parceiro acima do orçamento de erro acordado → reavaliar 1c (mensageria).
- Necessidade de segunda instância da aplicação → o armazenamento em memória deixa de servir.
- Primeiro parceiro com capacidade de notificação → habilitar 4c para aquele parceiro.
- Primeira duplicata observada em produção → fechar as pré-condições acima antes de qualquer fila.
- Nova versão do contrato TISS publicada pelo laboratório → revisar somente o adaptador.

## Evidências do incremento 2

- Contrato explícito: `laboratorios/plataforma-hospitalar/contratos/openapi.yaml` (OpenAPI 3.1).
- Lint aprovado: `laboratorios/plataforma-hospitalar/evidencias/spectral-valido.txt`.
- Falha deliberada detectada pelo lint: `evidencias/spectral-experimento.txt`.
- Testes de contrato: `evidencias/testes-contrato.txt` (7 aprovados).
- Respostas reais 202 / 200 / 422 / 404: `evidencias/respostas-http.txt`.
- Gateway roteando duas APIs por configuração: `extensao-gateway-ocelot/evidencias/gateway-ocelot.txt`.
