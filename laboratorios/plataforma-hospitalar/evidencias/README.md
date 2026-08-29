# Evidências da oficina — módulo 2 (APIs)

Saídas capturadas na execução de 29/08/2026 (Windows 11, Python 3.12.10, Node 18.20.7,
`@stoplight/spectral-cli@6.16.1`). Regeneráveis com `..\..\..\scripts\executar-oficina.ps1`.

| Arquivo | O que registra | Resultado |
|---|---|---|
| `testes-contrato.txt` | `pytest tests/test_api_contract.py -q` | **7 passed** |
| `spectral-valido.txt` | lint do contrato original | `No results with a severity of 'error' found!` (exit 0) |
| `spectral-experimento.txt` | lint da cópia adulterada | 1 erro `oas3-valid-media-example` (exit 1 — **falha esperada**) |
| `openapi-experimento.yaml` | cópia com `cpf: '123'` no exemplo de mídia | insumo da falha deliberada |
| `respostas-http.txt` | requisições reais contra o Uvicorn | 202 + `Location`, 200, 422 ×3, 404 |
| `comparacao-contratos.txt` | contrato explícito × contrato gerado | diferenças em tags, servers, exemplos, respostas e schemas |
| `bruno/` | coleção de consumidor versionada (5 requisições com asserts) | ver `bruno/README.md` |

A leitura desses arquivos está em [`../../../docs/oficina-notas.md`](../../../docs/oficina-notas.md).
