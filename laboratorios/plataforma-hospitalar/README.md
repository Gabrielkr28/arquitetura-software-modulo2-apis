# Laboratorio: plataforma hospitalar (modulo 2 - APIs)

API FastAPI com duas operacoes publicas de elegibilidade, contrato OpenAPI 3.1 explicito,
regras de lint Spectral e testes de contrato com TestClient. Dados apenas em memoria.

Base: `laboratorios/plataforma-hospitalar/` do repositorio da disciplina
(https://github.com/marco-mendes/arquitetura-software), com as dependencias reduzidas ao
escopo do modulo 2.

## Preparacao (Windows / PowerShell)

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install --upgrade pip
.venv\Scripts\python.exe -m pip install -e ".[dev]"
```

## Execucao

```powershell
.venv\Scripts\python.exe -m uvicorn hospital.api.main:app --reload
```

Swagger UI em http://127.0.0.1:8000/docs

## Testes de contrato

```powershell
.venv\Scripts\python.exe -m pytest tests/test_api_contract.py -q
```

## Lint do contrato

```powershell
npx @stoplight/spectral-cli@6.16.1 lint contratos/openapi.yaml
```
