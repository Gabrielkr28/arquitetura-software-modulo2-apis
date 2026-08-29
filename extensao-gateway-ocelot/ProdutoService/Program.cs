var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/produtos", () => new[]
{
    new { Id = 1, Nome = "Produto A" },
    new { Id = 2, Nome = "Produto B" }
});

app.Run();
