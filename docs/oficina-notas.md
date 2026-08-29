# Oficina de ferramentas — módulo 2 (APIs)

**Autor:** Gabriel Krzizanowski · **Data da execução:** 29 de agosto de 2026
**Roteiro:** <https://marco-mendes.github.io/arquitetura-software/modulo-2-apis/oficina-de-ferramentas/>

Ambiente usado: Windows 11, Python 3.12.10 (venv local), Node 18.20.7,
`@stoplight/spectral-cli@6.16.1`, .NET SDK 9.0.200 com Ocelot 25.0.0.

---

## 1. O que foi executado

| Passo | Comando | Resultado | Evidência |
|---|---|---|---|
| Testes de contrato | `pytest tests/test_api_contract.py -q` | **7 passed** | `laboratorios/plataforma-hospitalar/evidencias/testes-contrato.txt` |
| Lint do contrato original | `npx @stoplight/spectral-cli@6.16.1 lint contratos/openapi.yaml` | `No results with a severity of 'error' found!` (exit 0) | `evidencias/spectral-valido.txt` |
| Falha deliberada | lint sobre `openapi-experimento.yaml` | 1 erro `oas3-valid-media-example` (exit 1) | `evidencias/spectral-experimento.txt` |
| Execução HTTP | Uvicorn + requisições reais | 202 / 200 / 422 / 422 / 422 / 404 | `evidencias/respostas-http.txt` |
| Coleção de consumidor | coleção Bruno versionada | 5 requisições com asserts | `evidencias/bruno/` |
| Extensão: gateway | 3 serviços .NET + Ocelot | 200 nas duas rotas via `:4000` | `extensao-gateway-ocelot/evidencias/gateway-ocelot.txt` |

**Observação honesta sobre a contagem de testes:** o roteiro publicado fala em *6 testes
aprovados*; o arquivo `test_api_contract.py` da versão atual do repositório da disciplina tem
**7** testes, e todos passam. A diferença é da versão do laboratório, não do ambiente.

**Observação sobre a coleção Bruno:** a importação `Import Collection → OpenAPI` é uma ação da
interface gráfica do Bruno e não pôde ser executada por linha de comando. A coleção em
`evidencias/bruno/` foi escrita no formato nativo `.bru`, cobre as mesmas requisições pedidas
pelo roteiro, é versionável em Git e ainda carrega asserts executáveis — basta abrir a pasta com
`Open Collection`.

---

## 2. Nota comparativa: contrato explícito × contrato gerado × execução

Dados extraídos programaticamente em `evidencias/comparacao-contratos.txt`.

Os três artefatos descrevem a **mesma** API, mas não dizem a mesma coisa. Onde eles concordam é
onde o teste automatizado obriga; onde divergem é onde ninguém está olhando.

### Onde concordam (e por que concordam)

`openapi: 3.1.0`, os dois caminhos, `operationId`, o conjunto `required` de
`PedidoElegibilidade`, `additionalProperties: false`, o `pattern ^\d{11}$` do CPF, a descrição do
`202` e o header `Location`. Isso **não é coincidência**: o teste
`test_application_and_explicit_contract_agree_on_operations_and_models` compara justamente esses
pontos e falha se divergirem. A concordância é uma propriedade testada, não uma boa intenção.

### Onde divergem

| Aspecto | Contrato explícito (`openapi.yaml`) | Contrato gerado (`app.openapi()`) | Execução real |
|---|---|---|---|
| `tags`, `servers`, `contact`, `description` | presentes | ausentes | irrelevante para o cliente HTTP |
| Exemplos no `requestBody` e nas respostas | presentes | ausentes | os exemplos funcionam de verdade (o teste faz `POST` com o exemplo e recebe 202) |
| Respostas do `GET /elegibilidades/{protocolo}` | `200`, `404` | `200`, `404`, **`422`** | o `422` do GET existe no papel, mas a aplicação usa um handler próprio e devolve o formato `ErroAPI` |
| Schemas | 4 (`PedidoElegibilidade`, `ElegibilidadeAceita`, `DetalheErro`, `ErroAPI`) | 6 — inclui `HTTPValidationError` e `ValidationError` | **nunca são devolvidos**: o `@app.exception_handler(RequestValidationError)` substitui o corpo padrão do FastAPI |
| Rotas servidas | 2 | 2 | **4** — `/health/live` e `/health/ready` respondem, mas estão marcadas `include_in_schema=False` e não aparecem em nenhum dos dois contratos |

### O que essa comparação ensina

1. **O contrato gerado descreve o código; o contrato explícito descreve o acordo.** O gerado
   herda ruído do framework (`ValidationError`, `422` no GET) e perde intenção (tags, exemplos,
   servidor). Publicar o gerado como se fosse o acordo entrega ao consumidor detalhes que a
   plataforma não pretende sustentar.
2. **Divergência silenciosa é a regra, não a exceção.** Duas linhas de código
   (`include_in_schema=False` e um `exception_handler`) já produziram rotas fora do contrato e
   schemas que o contrato promete mas a execução nunca devolve — sem nenhum erro em lugar nenhum.
3. **Só a execução prova o comportamento.** O contrato diz que `cpf` casa com `^\d{11}$`; a
   execução mostra o corpo exato do `422` (`codigo`, `mensagem`, `detalhes[].campo`), que é o que
   o consumidor realmente vai programar.
4. **Lint, teste e chamada real cobrem camadas diferentes:** o Spectral valida o *documento*, o
   pytest valida a *coerência* entre documento e aplicação, e o Bruno/curl valida a *resposta*.
   Nenhum dos três substitui os outros dois.

---

## 3. Falha deliberada do Spectral (documentada)

**Alteração:** em uma cópia do contrato (`evidencias/openapi-experimento.yaml`), o exemplo de
mídia `paths./elegibilidades.post.requestBody.content.application/json.examples.pedidoValido.value.cpf`
foi mudado de `'12345678901'` para `'123'`. Apenas o exemplo de mídia mudou; o `pattern` do
schema permaneceu `^\d{11}$`.

**Saída obtida** (`evidencias/spectral-experimento.txt`):

```text
 35:23  error  oas3-valid-media-example  "cpf" property must match pattern "^\d{11}$"
        paths./elegibilidades.post.requestBody.content.application/json.examples.pedidoValido.value.cpf

✖ 1 problem (1 error, 0 warnings, 0 infos, 0 hints)
```

Exit code **1** — que aqui é o resultado esperado: o roteiro pede que o lint *reprove*.

**Por que o contrato alterado falha antes de chamar a API:** o Spectral não executa nada. Ele lê
o documento e verifica uma propriedade interna de coerência — o exemplo declarado precisa
satisfazer o schema declarado no mesmo documento. A contradição está inteira dentro do arquivo,
então é detectável sem servidor, sem rede e sem dados. Esse é o valor prático do contrato
explícito: ele é verificável em CI, antes do deploy e antes do consumidor.

**Por que o servidor continua rejeitando o mesmo valor:** o servidor nunca leu o `openapi.yaml`.
A validação em execução vem do modelo Pydantic `PedidoElegibilidade`, cujo campo `cpf` tem
`pattern=r"^\d{11}$"`. Documento e código carregam a mesma regra **em dois lugares diferentes** —
por isso `POST` com `cpf: "123"` continua devolvendo `422` mesmo com o contrato adulterado
(evidência 5 em `respostas-http.txt`). É exatamente essa duplicação que o teste de coerência
existe para vigiar: alterar um lado sem o outro é a forma mais comum de o contrato virar ficção.

---

## 4. Extensão: gateway Ocelot

Três projetos .NET (`ClienteService` :5001, `ProdutoService` :5002, `OcelotGateway` :4000) com
roteamento declarado em `ocelot.json`. Resultado capturado em
`extensao-gateway-ocelot/evidencias/gateway-ocelot.txt`:

- `GET http://localhost:4000/api/clientes` → `200` com os dois clientes;
- `GET http://localhost:4000/api/produtos` → `200` com os dois produtos;
- `GET http://localhost:4000/api/inexistente` → `404` do próprio gateway, porque a rota não está
  declarada.

O ponto arquitetural: o consumidor conhece **uma** origem (`:4000`) e um vocabulário de caminho
(`/api/...`); as portas `5001` e `5002` e a topologia interna ficam invisíveis. Trocar o host, a
porta ou dividir um serviço vira mudança de configuração, não quebra de cliente. E — ligando com
o estudo de caso — isso é **política técnica de fronteira**: o `ocelot.json` roteia, mas não sabe
nem poderia saber traduzir um código TISS. Essa é a fronteira entre gateway e adaptador.

Ajuste necessário em relação ao roteiro: o SDK .NET 9 já inclui `ocelot.json` como *content* por
padrão; declarar o `<Content Include="ocelot.json">` manualmente causa
`error NETSDK1022: Itens 'Content' duplicados`. O `.csproj` do repositório usa o comportamento
padrão do SDK.

---

## 5. Respostas às questões exploratórias

**1. O que o `202` permite que o provedor altere sem quebrar o consumidor?**
O `202` diz "aceitei e vou processar", não "decidi". Isso libera o provedor para mudar tudo o que
acontece *depois* do aceite sem tocar no contrato: o tempo de processamento, a ordem das etapas,
o parceiro consultado, o protocolo usado com esse parceiro (REST hoje, fila amanhã), a
quantidade de tentativas e até a máquina que processa. O consumidor programou contra "recebi um
protocolo e sei onde consultar" — nada disso muda. Se a mesma operação respondesse `200` com a
decisão, cada uma dessas mudanças viraria mudança de contrato.

**2. Por que o header `Location` é superior à convenção de URL do lado do consumidor?**
Porque move a autoridade sobre o endereço do recurso para quem realmente a tem: o servidor. Se o
consumidor monta `"/elegibilidades/" + protocolo` no próprio código, ele fixou uma regra de
roteamento do provedor dentro do cliente, e essa regra vira contrato implícito — versionar
caminhos, mudar prefixo, mover o recurso para outro host ou introduzir um gateway quebra todos os
clientes ao mesmo tempo. Com `Location`, o servidor **diz** onde o recurso está e pode mudar essa
resposta a qualquer momento. É também a diferença entre um cliente que segue links e um cliente
que adivinha.

**3. Qual divergência entre OpenAPI e aplicação os testes atuais não detectam?**
Várias, e a comparação da seção 2 mostra três concretas:

- **Rotas servidas mas não declaradas:** `/health/live` e `/health/ready` respondem e não estão
  em contrato nenhum (`include_in_schema=False`). Nenhum teste verifica "toda rota servida está
  declarada".
- **Respostas declaradas e nunca produzidas:** o contrato gerado promete `422` no
  `GET /elegibilidades/{protocolo}` e os schemas `HTTPValidationError` / `ValidationError`, que o
  handler customizado impede de acontecer.
- **Semântica dos campos:** os testes comparam `required`, `operationId` e o header do `202`, mas
  não comparam `pattern`, `minLength`, `maxLength`, `description` nem os códigos de erro entre os
  dois contratos. Eu poderia relaxar `cpf` para qualquer string no Pydantic e manter `^\d{11}$` no
  YAML: os 7 testes continuariam verdes.
- Além disso, nada testa o **contrato explícito contra a resposta real** — só contra o gerado.

**4. Quando seria necessária chave de idempotência?**
Assim que a repetição de uma mesma intenção deixar de ser inofensiva. Concretamente: (a) quando o
cliente puder repetir o `POST` após timeout ou perda de resposta e a plataforma não puder criar
dois pedidos de exame para o mesmo paciente; (b) quando existir retry automático em qualquer
ponto do caminho (cliente, gateway, biblioteca HTTP); (c) quando a entrega passar a ser por fila
*at-least-once*; (d) quando um parceiro externo notificar por webhook, porque webhook é reenviado
por definição. Hoje a oficina não precisa dela — cada `POST` cria um protocolo novo, e isso é
aceitável só porque nada acontece fora da memória do processo. Os requisitos que o ADR-002
precisa registrar antes de introduzir a chave estão na Decisão 5 do estudo de caso.

**5. Que parte funcionaria diferente com duas instâncias e memória separada?**
A recuperação. `POST` na instância A grava o protocolo no dicionário `_elegibilidades` de A; o
`GET` que cair na instância B devolve `404 elegibilidade_nao_encontrada` — a resposta certa para
o código, e completamente errada para o negócio, porque o pedido existe. O `202` e o `Location`
continuariam corretos, e é justamente isso que torna a falha traiçoeira: o contrato é honrado,
mas com probabilidade ~50 % o recurso "desaparece" a cada consulta. Some-se a isso a perda total
de estado a cada reinício ou reciclagem de pod. A correção não é *sticky session* — é mover o
estado para fora do processo (banco compartilhado), o que é exatamente o assunto do incremento
seguinte.
