# Arquitetura de Software — Módulo 2 (APIs)

Entregáveis do módulo 2 da disciplina de Arquitetura de Software: a resolução do **estudo de
caso** (integração hospital ↔ operadora ↔ laboratório) e a execução completa da **oficina de
ferramentas** (FastAPI, OpenAPI 3.1, Spectral, pytest/TestClient, Bruno e a extensão com gateway
Ocelot em .NET).

**Autor:** Gabriel Krzizanowski · **Data:** 29 de agosto de 2026
**Material da disciplina:** <https://marco-mendes.github.io/arquitetura-software/>
**Laboratório de origem:** <https://github.com/marco-mendes/arquitetura-software> (`laboratorios/plataforma-hospitalar`)

---

## Entregável 1 — Estudo de caso

| Documento | Conteúdo |
|---|---|
| [`docs/estudo-de-caso-modulo-2.md`](docs/estudo-de-caso-modulo-2.md) | Resolução das cinco decisões, com justificativa, consequência assumida e evidência que mudaria a escolha |
| [`docs/ADR-002-integracao-com-parceiros.md`](docs/ADR-002-integracao-com-parceiros.md) | ADR-002 do incremento 2: alternativas registradas, consequências, pré-condições para mensageria e gatilhos de revisão |

Resumo das escolhas:

| Decisão | Escolha |
|---|---|
| 1. Pedido ao laboratório | Contrato oficial SOAP/TISS consumido por **adaptador (ACL)** |
| 2. Tradução TISS | No **adaptador**, não no gateway |
| 3. `matricula_plano` ↔ id da operadora | Pertence à **operadora** (implementado no adaptador dela) |
| 4. Aviso de exame pronto | **Webhook** + reconciliação; polling adaptativo como contingência |
| 5. Antes de mensageria idempotente | Registrar chave de negócio, retenção e comportamento de duplicidade |

## Entregável 2 — Oficina de ferramentas

| Item | Onde |
|---|---|
| Aplicação FastAPI + contrato + testes | [`laboratorios/plataforma-hospitalar/`](laboratorios/plataforma-hospitalar) |
| Evidências de execução | [`laboratorios/plataforma-hospitalar/evidencias/`](laboratorios/plataforma-hospitalar/evidencias) |
| Coleção Bruno | [`laboratorios/plataforma-hospitalar/evidencias/bruno/`](laboratorios/plataforma-hospitalar/evidencias/bruno) |
| Extensão gateway Ocelot (.NET) | [`extensao-gateway-ocelot/`](extensao-gateway-ocelot) |
| Notas, comparação de contratos e respostas às questões | [`docs/oficina-notas.md`](docs/oficina-notas.md) |

### Evidências obrigatórias

| Arquivo | Resultado |
|---|---|
| `evidencias/spectral-valido.txt` | `No results with a severity of 'error' found!` |
| `evidencias/spectral-experimento.txt` | 1 erro `oas3-valid-media-example` (falha deliberada) |
| `evidencias/testes-contrato.txt` | 7 passed |
| `evidencias/respostas-http.txt` | 202 + `Location`, 200, 422 (`dados_invalidos`), 422 (campo extra), 422 (cpf inválido), 404 |
| `evidencias/comparacao-contratos.txt` | Diferenças entre contrato explícito e contrato gerado |
| `extensao-gateway-ocelot/evidencias/gateway-ocelot.txt` | 200 nas duas rotas via gateway `:4000` |

---

## Como reproduzir

### Laboratório (Python 3.11+)

```powershell
cd laboratorios\plataforma-hospitalar
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install --upgrade pip
.venv\Scripts\python.exe -m pip install -e ".[dev]"
.venv\Scripts\python.exe -m pytest tests/test_api_contract.py -q
npx @stoplight/spectral-cli@6.16.1 lint contratos/openapi.yaml
.venv\Scripts\python.exe -m uvicorn hospital.api.main:app --reload
```

Swagger UI: <http://127.0.0.1:8000/docs>

Ou, para regerar todas as evidências de uma vez:

```powershell
.\scripts\executar-oficina.ps1
```

### Extensão gateway (.NET 8+)

Em três terminais:

```powershell
dotnet run --project extensao-gateway-ocelot\ClienteService --urls=http://localhost:5001
```

```powershell
dotnet run --project extensao-gateway-ocelot\ProdutoService --urls=http://localhost:5002
```

```powershell
dotnet run --project extensao-gateway-ocelot\OcelotGateway --urls=http://localhost:4000
```

E então:

```powershell
Invoke-RestMethod http://localhost:4000/api/clientes
```

---

## Estrutura

```text
.
├── docs/
│   ├── estudo-de-caso-modulo-2.md        # entregável 1 (versão Markdown)
│   ├── estudo-de-caso-modulo-2.docx      # entregável 1 (Word)
│   ├── ADR-002-integracao-com-parceiros.md
│   └── oficina-notas.md                  # nota comparativa + questões exploratórias
├── laboratorios/plataforma-hospitalar/
│   ├── contratos/openapi.yaml            # contrato explícito OpenAPI 3.1
│   ├── src/hospital/api/                 # aplicação FastAPI
│   ├── tests/test_api_contract.py        # testes de contrato
│   └── evidencias/                       # saídas capturadas + coleção Bruno
├── extensao-gateway-ocelot/
│   ├── ClienteService/  ProdutoService/  OcelotGateway/
│   └── evidencias/gateway-ocelot.txt
└── scripts/executar-oficina.ps1
```

## Créditos

O código do laboratório (`src/hospital`, `contratos/openapi.yaml`, `tests/test_api_contract.py`,
`.spectral.yaml`) vem do repositório da disciplina, com as dependências do `pyproject.toml`
reduzidas ao escopo do módulo 2. As evidências, a coleção Bruno, a extensão Ocelot, os scripts e
todos os documentos em `docs/` são deste repositório.
