// Define o serializador JSON padrão para a Lambda
[assembly: Amazon.Lambda.Core.LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace GuestbookLambda;

using System.Text.Json;
using System.Text.Json.Serialization;
using Amazon.Lambda.Core;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;

public class Function
{
    private static readonly AmazonDynamoDBClient _dynamoClient;
    private static readonly string _tableName;

    // Inicializador estático para configurar o cliente do DynamoDB
    static Function()
    {
        _dynamoClient = new AmazonDynamoDBClient();
        _tableName = Environment.GetEnvironmentVariable("TABLE_NAME") ?? "guestbook_table";
    }

    /// <summary>
    /// O handler principal da nossa API (GET e POST)
    /// </summary>
    public async Task<APIGatewayHttpApiV2ProxyResponse> FunctionHandler(APIGatewayHttpApiV2ProxyRequest request, ILambdaContext context)
    {
        context.Logger.LogLine($"Requisição recebida: {request.RequestContext.Http.Method}");

        // Roteamento simples baseado no método HTTP
        try
        {
            switch (request.RequestContext.Http.Method.ToUpper())
            {
                case "POST":
                    return await HandlePostRequest(request, context);
                case "GET":
                    return await HandleGetRequest(context);
                case "OPTIONS":
                    return HandleOptionsRequest(); // Para CORS
                default:
                    return CreateResponse(405, "Método não permitido");
            }
        }
        catch (Exception ex)
        {
            context.Logger.LogLine($"Erro: {ex.Message}");
            return CreateResponse(500, $"Erro interno: {ex.Message}");
        }
    }

    private async Task<APIGatewayHttpApiV2ProxyResponse> HandlePostRequest(APIGatewayHttpApiV2ProxyRequest request, ILambdaContext context)
    {
        // Deserializa o corpo da requisição
        var messageRequest = JsonSerializer.Deserialize<MessageRecord>(request.Body);
        if (messageRequest == null || string.IsNullOrEmpty(messageRequest.Message))
        {
            return CreateResponse(400, "Corpo da mensagem inválido.");
        }

        var item = new Dictionary<string, AttributeValue>
        {
            { "message_id", new AttributeValue { S = Guid.NewGuid().ToString() } },
            { "message", new AttributeValue { S = messageRequest.Message } },
            { "timestamp", new AttributeValue { N = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString() } }
        };

        // Salva no DynamoDB
        await _dynamoClient.PutItemAsync(new PutItemRequest
        {
            TableName = _tableName,
            Item = item
        });

        context.Logger.LogLine("Mensagem salva com sucesso.");
        return CreateResponse(201, JsonSerializer.Serialize(new { status = "sucesso" }));
    }

    private async Task<APIGatewayHttpApiV2ProxyResponse> HandleGetRequest(ILambdaContext context)
    {
        // Lê todas as mensagens (Scan)
        var scanResponse = await _dynamoClient.ScanAsync(new ScanRequest
        {
            TableName = _tableName
        });

        context.Logger.LogLine($"Encontradas {scanResponse.Items.Count} mensagens.");

        // Transforma os itens do DynamoDB em um formato JSON mais simples
        var messages = scanResponse.Items
            .Select(item => new
            {
                message_id = item["message_id"].S,
                message = item["message"].S,
                timestamp = long.Parse(item["timestamp"].N)
            })
            .OrderBy(m => m.timestamp) // Ordena por data
            .ToList();
        
        return CreateResponse(200, JsonSerializer.Serialize(messages));
    }

    // Resposta padrão para requisições OPTIONS (pré-verificação de CORS)
    private APIGatewayHttpApiV2ProxyResponse HandleOptionsRequest()
    {
        return CreateResponse(200, "");
    }

    // Helper para criar a resposta da API, incluindo cabeçalhos CORS
    private APIGatewayHttpApiV2ProxyResponse CreateResponse(int statusCode, string body)
    {
        return new APIGatewayHttpApiV2ProxyResponse
        {
            StatusCode = statusCode,
            Body = body,
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" },
                { "Access-Control-Allow-Origin", "*" }, // Permite qualquer origem
                { "Access-Control-Allow-Methods", "GET, POST, OPTIONS" },
                { "Access-Control-Allow-Headers", "Content-Type" }
            }
        };
    }
}

// Classe auxiliar para deserializar o JSON do POST
public class MessageRecord
{
    [JsonPropertyName("message")]
    public string Message { get; set; } = "";
}