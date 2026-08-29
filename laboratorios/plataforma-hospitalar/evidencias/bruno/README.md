# Colecao Bruno - plataforma hospitalar

Colecao no formato nativo do Bruno (arquivos `.bru`, versionaveis em Git), equivalente ao
resultado de `Import Collection -> OpenAPI` sobre `contratos/openapi.yaml` com base
`http://127.0.0.1:8000`. Foi escrita em arquivo porque a importacao do Bruno e uma acao de
interface grafica; o conteudo cobre as mesmas requisicoes pedidas na oficina e ainda carrega
asserts executaveis.

## Como usar

1. Suba a API: `.venv\Scripts\python.exe -m uvicorn hospital.api.main:app --reload`
2. No Bruno: `Open Collection` -> selecione esta pasta (`evidencias/bruno`).
3. Selecione o environment `local`.
4. Rode as requisicoes na ordem 01 -> 05. A 01 grava `protocolo` e `location` no environment,
   entao a 02 consulta exatamente o recurso criado.

## Requisicoes

| Seq | Requisicao | Resultado esperado |
|-----|-----------|--------------------|
| 01  | POST /elegibilidades (corpo valido)      | 202 + header `Location` + `situacao: recebida` |
| 02  | GET /elegibilidades/{{protocolo}}         | 200 com o mesmo corpo |
| 03  | POST /elegibilidades sem `cpf`            | 422 com `codigo = dados_invalidos` |
| 04  | POST /elegibilidades com campo extra      | 422 (contrato proibe propriedades adicionais) |
| 05  | GET /elegibilidades/protocolo-inexistente | 404 `elegibilidade_nao_encontrada` |

As respostas reais capturadas estao em `../respostas-http.txt`.
