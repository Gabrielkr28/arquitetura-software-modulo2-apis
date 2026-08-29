var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/clientes", () => new[]
{
    new { Id = 1, Nome = "João Silva" },
    new { Id = 2, Nome = "Maria Oliveira" }
});

app.Run();
