<#
    Regera todas as evidencias da oficina de ferramentas do modulo 2.
    Uso: .\scripts\executar-oficina.ps1
    Requer: Python 3.11+, Node (npx) e curl.
#>

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$lab = Join-Path $raiz "laboratorios\plataforma-hospitalar"
Set-Location $lab

$python = Join-Path $lab ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    Write-Host "==> criando ambiente virtual" -ForegroundColor Cyan
    py -3.12 -m venv .venv
    & $python -m pip install --upgrade pip
    & $python -m pip install -e ".[dev]"
}

New-Item -ItemType Directory -Force evidencias | Out-Null

Write-Host "==> testes de contrato" -ForegroundColor Cyan
& $python -m pytest tests/test_api_contract.py -q 2>&1 | Tee-Object -FilePath evidencias\testes-contrato.txt
if ($LASTEXITCODE -ne 0) { throw "os testes de contrato falharam" }

Write-Host "==> lint do contrato original (deve passar)" -ForegroundColor Cyan
npx --yes @stoplight/spectral-cli@6.16.1 lint contratos/openapi.yaml 2>&1 | Tee-Object -FilePath evidencias\spectral-valido.txt
if ($LASTEXITCODE -ne 0) { throw "o contrato original deveria passar no lint" }

Write-Host "==> falha deliberada: exemplo de midia invalido (deve reprovar)" -ForegroundColor Cyan
Copy-Item contratos\openapi.yaml evidencias\openapi-experimento.yaml -Force
$conteudo = Get-Content evidencias\openapi-experimento.yaml
$conteudo[34] = $conteudo[34] -replace "12345678901", "123"
$conteudo | Set-Content evidencias\openapi-experimento.yaml -Encoding utf8
npx --yes @stoplight/spectral-cli@6.16.1 lint evidencias/openapi-experimento.yaml 2>&1 | Tee-Object -FilePath evidencias\spectral-experimento.txt
if ($LASTEXITCODE -eq 0) { throw "o exemplo invalido nao foi detectado" }

Write-Host "==> comparacao entre contrato explicito e contrato gerado" -ForegroundColor Cyan
& $python scripts\comparar_contratos.py 2>&1 | Tee-Object -FilePath evidencias\comparacao-contratos.txt

Write-Host "==> subindo a API para capturar respostas reais" -ForegroundColor Cyan
$servidor = Start-Process -FilePath $python `
    -ArgumentList "-m", "uvicorn", "hospital.api.main:app", "--host", "127.0.0.1", "--port", "8000" `
    -PassThru -WindowStyle Hidden
try {
    $pronto = $false
    foreach ($tentativa in 1..30) {
        Start-Sleep -Milliseconds 500
        try {
            Invoke-WebRequest "http://127.0.0.1:8000/health/live" -UseBasicParsing | Out-Null
            $pronto = $true
            break
        } catch { }
    }
    if (-not $pronto) { throw "a API nao subiu em 15 segundos" }

    $arquivo = "evidencias\respostas-http.txt"
    "=== Evidencias HTTP - coleta $(Get-Date -Format o) ===" | Set-Content $arquivo -Encoding utf8

    "--- POST /elegibilidades valido -> 202 + Location ---" | Add-Content $arquivo -Encoding utf8
    $post = curl.exe -s -i -X POST http://127.0.0.1:8000/elegibilidades `
        -H "Content-Type: application/json" `
        -d '{\"cpf\":\"12345678901\",\"codigo_operadora\":\"OPS-001\",\"matricula_plano\":\"MAT-2026-001\"}'
    $post | Add-Content $arquivo -Encoding utf8

    $protocolo = ($post | Select-String -Pattern "^location: /elegibilidades/(.+)$").Matches.Groups[1].Value.Trim()

    "`n--- GET no Location devolvido -> 200 ---" | Add-Content $arquivo -Encoding utf8
    curl.exe -s -i "http://127.0.0.1:8000/elegibilidades/$protocolo" | Add-Content $arquivo -Encoding utf8

    "`n--- POST sem cpf -> 422 dados_invalidos ---" | Add-Content $arquivo -Encoding utf8
    curl.exe -s -i -X POST http://127.0.0.1:8000/elegibilidades `
        -H "Content-Type: application/json" `
        -d '{\"codigo_operadora\":\"OPS-001\",\"matricula_plano\":\"MAT-2026-001\"}' | Add-Content $arquivo -Encoding utf8

    "`n--- POST com campo fora do contrato -> 422 ---" | Add-Content $arquivo -Encoding utf8
    curl.exe -s -i -X POST http://127.0.0.1:8000/elegibilidades `
        -H "Content-Type: application/json" `
        -d '{\"cpf\":\"12345678901\",\"codigo_operadora\":\"OPS-001\",\"matricula_plano\":\"MAT-2026-001\",\"campo_nao_contratado\":\"valor\"}' | Add-Content $arquivo -Encoding utf8

    "`n--- POST com cpf '123' (mesmo valor da falha deliberada do Spectral) -> 422 ---" | Add-Content $arquivo -Encoding utf8
    curl.exe -s -i -X POST http://127.0.0.1:8000/elegibilidades `
        -H "Content-Type: application/json" `
        -d '{\"cpf\":\"123\",\"codigo_operadora\":\"OPS-001\",\"matricula_plano\":\"MAT-2026-001\"}' | Add-Content $arquivo -Encoding utf8

    "`n--- GET protocolo inexistente -> 404 ---" | Add-Content $arquivo -Encoding utf8
    curl.exe -s -i http://127.0.0.1:8000/elegibilidades/protocolo-inexistente | Add-Content $arquivo -Encoding utf8

    "`n--- Contrato GERADO pela aplicacao (amostra de /openapi.json) ---" | Add-Content $arquivo -Encoding utf8
    (curl.exe -s http://127.0.0.1:8000/openapi.json).Substring(0, 400) | Add-Content $arquivo -Encoding utf8
}
finally {
    Stop-Process -Id $servidor.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "==> evidencias regeradas em $lab\evidencias" -ForegroundColor Green
