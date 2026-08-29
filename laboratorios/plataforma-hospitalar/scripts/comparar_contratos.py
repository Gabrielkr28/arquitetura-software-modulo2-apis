import json, sys
from pathlib import Path
import yaml
sys.path.insert(0, "src")
from hospital.api.main import app

explicito = yaml.safe_load(Path("contratos/openapi.yaml").read_text(encoding="utf-8"))
gerado = app.openapi()

def resumo(doc, nome):
    print(f"### {nome}")
    print("  openapi:", doc.get("openapi"))
    print("  info keys:", sorted(doc.get("info", {}).keys()))
    print("  tem 'tags' no topo:", "tags" in doc)
    print("  tem 'servers':", "servers" in doc)
    print("  paths:", sorted(doc.get("paths", {})))
    post = doc["paths"]["/elegibilidades"]["post"]
    print("  post.operationId:", post.get("operationId"))
    print("  post.tags:", post.get("tags"))
    print("  post.description presente:", bool(post.get("description")))
    print("  post.requestBody tem examples:",
          "examples" in post["requestBody"]["content"]["application/json"])
    print("  post.responses:", sorted(post["responses"]))
    r202 = post["responses"]["202"]
    print("  202.description:", r202.get("description"))
    print("  202 tem headers.Location:", "Location" in r202.get("headers", {}))
    print("  202 tem examples:",
          "examples" in r202.get("content", {}).get("application/json", {}))
    get = doc["paths"]["/elegibilidades/{protocolo}"]["get"]
    print("  get.responses:", sorted(get["responses"]))
    esquema = doc["components"]["schemas"]["PedidoElegibilidade"]
    print("  PedidoElegibilidade.required:", sorted(esquema["required"]))
    print("  PedidoElegibilidade.additionalProperties:",
          esquema.get("additionalProperties"))
    print("  cpf.pattern:", esquema["properties"]["cpf"].get("pattern"))
    print()

resumo(explicito, "Contrato EXPLICITO (contratos/openapi.yaml)")
resumo(gerado, "Contrato GERADO (app.openapi())")

print("### Schemas presentes")
print("  explicito:", sorted(explicito["components"]["schemas"]))
print("  gerado   :", sorted(gerado["components"]["schemas"]))
print()
print("### Caminhos so no gerado (rotas fora do contrato publicado)")
print(" ", sorted(set(gerado["paths"]) - set(explicito["paths"])))
