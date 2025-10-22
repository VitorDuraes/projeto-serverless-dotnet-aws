# main.tf
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # A versão pode variar, mas isso é seguro
      version = "~> 5.0"
    }
    # ESTE É O BLOCO QUE FALTAVA
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}
provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "guestbook_table" {
  name         = "guestbook-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"
  attribute {
    name = "message_id"
    type = "S"
  }
}

# A "Identidade" da nossa função Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-guestbook-role"

  # Diz que o serviço "lambda.amazonaws.com" pode assumir esta role
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Anexa a política básica de logs (para vermos os 'prints' no CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Política customizada: Permite que nossa Lambda ACESSE o DynamoDB
resource "aws_iam_policy" "lambda_dynamo_policy" {
  name = "lambda-dynamodb-guestbook-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = ["dynamodb:Scan", "dynamodb:PutItem"], # Permite ler (Scan) e escrever (PutItem)
      Effect   = "Allow",
      Resource = aws_dynamodb_table.guestbook_table.arn # APENAS na tabela que criamos
    }]
  })
}

# Anexa a política do DynamoDB à nossa Role
resource "aws_iam_role_policy_attachment" "lambda_dynamo" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamo_policy.arn
}

resource "null_resource" "dotnet_publish" {

  # Este 'triggers' garante que, se o código C# mudar, ele recompila
  triggers = {
    # Lista todos os arquivos .cs do nosso projeto
    source_files_hash = filesha256("${path.module}/src/GuestbookLambda/Function.cs")
    project_file_hash = filesha256("${path.module}/src/GuestbookLambda/GuestbookLambda.csproj")
  }
  provisioner "local-exec" {
    # Compila em modo 'Release' e joga a saída na pasta './publish'
    # O '--self-contained false' e '/p:PublishSingleFile=true' não são estritamente necessários
    # para 'dotnet8' no Lambda, mas ajudam a manter o pacote pequeno.
    command = "dotnet publish -c Release -o ./publish ./src/GuestbookLambda/GuestbookLambda.csproj"
  }
}

# ATUALIZADO: Pacote da Lambda
# Agora, em vez de zipar um .py, zipamos o RESULTADO da compilação
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/publish" # Pega da pasta 'publish'
  output_path = "${path.module}/lambda_function.zip"

  # Garante que este passo SÓ rode DEPOIS que a compilação (null_resource) terminar
  depends_on = [null_resource.dotnet_publish]
}
resource "aws_lambda_function" "guestbook_lambda" {
  function_name    = "guestbook-function-dotnet"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # ATUALIZADO: O 'handler' do .NET
  # Formato: [NomeDoAssembly]::[Namespace.NomeDaClasse]::[NomeDoMetodo]
  handler = "GuestbookLambda::GuestbookLambda.Function::FunctionHandler"

  # ATUALIZADO: O 'runtime'
  runtime = "dotnet8" # Usando o runtime .NET 8

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.guestbook_table.name
    }
  }

  # Garante que a Lambda só seja criada/atualizada DEPOIS do zip
  depends_on = [data.archive_file.lambda_zip]
}
# Usamos o API Gateway v2 (HTTP), que é mais simples e barato
resource "aws_apigatewayv2_api" "guestbook_api" {
  name          = "guestbook-api"
  protocol_type = "HTTP"

  # Configuração de CORS (essencial!)
  # Diz ao API Gateway para responder a chamadas de outras origens
  cors_configuration {
    allow_origins = ["*"] # Permite qualquer site (nosso S3)
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

# Cria a "integração" entre o API Gateway e a Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.guestbook_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.guestbook_lambda.invoke_arn
}

# Rota para POST /messages
resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.guestbook_api.id
  route_key = "POST /messages"                                                     # Se baterem em POST /messages...
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}" #...chame nossa integração
}

# Rota para GET /messages
resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.guestbook_api.id
  route_key = "GET /messages"                                                      # Se baterem em GET /messages...
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}" #...chame nossa integração
}

# "Publica" a API (deploy)
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.guestbook_api.id
  name        = "$default" # O 'stage' padrão
  auto_deploy = true
}

# Permissão final: Autoriza o API Gateway a INVOCAR a função Lambda
resource "aws_lambda_permission" "api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guestbook_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Garante que SÓ esta API específica pode invocar a função
  source_arn = "${aws_apigatewayv2_api.guestbook_api.execution_arn}/*/*"
}
# Nome aleatório para o bucket (precisa ser globalmente único)
resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "aws_s3_bucket" "frontend_bucket" {
  # 'acl' foi depreciado, mas é simples para este exemplo.
  # Em produção, usaríamos 'aws_s3_bucket_ownership_control' e políticas mais restritivas."

  # Nome do bucket: "serverless-guestbook-" + 8 letras aleatórias
  bucket = "serverless-guestbook-${random_id.bucket_prefix.hex}"
}

# Configura o bucket para ser um site estático
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.frontend_bucket.id
  index_document {
    suffix = "index.html" # A página principal
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "ownership_controls" {
  bucket = aws_s3_bucket.frontend_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  # Garante que isso rode DEPOIS de desabilitar o bloqueio
  depends_on = [aws_s3_bucket_public_access_block.public_access]
}

# A política que torna o bucket público para leitura
resource "aws_s3_bucket_policy" "public_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "s3:GetObject",
      Effect    = "Allow",
      Principal = "*",                                     # Qualquer um
      Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*" # Pode ler qualquer arquivo
    }]
  })
  depends_on = [
    aws_s3_bucket_public_access_block.public_access,
    aws_s3_bucket_ownership_controls.ownership_controls
  ]
}
data "template_file" "index_html_template" {
  template = file("index.html")

  # Esta é a mágica. O data source agora "depende"
  # explicitamente do 'invoke_url' e SÓ vai rodar DEPOIS
  # que ele for criado.
  vars = {
    API_URL = aws_apigatewayv2_stage.default_stage.invoke_url
  }
}
# Faz o upload do nosso index.html para o S3
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend_bucket.id
  key          = "index.html"
  content_type = "text/html"

  # GARANTA QUE ESTA LINHA ESTEJA ASSIM:
  content = data.template_file.index_html_template.rendered

}

output "website_url" {
  description = "URL do site (frontend) no S3"
  value       = aws_s3_bucket_website_configuration.website_config.website_endpoint
}

output "api_url" {
  description = "URL base da API (backend) no API Gateway"
  value       = aws_apigatewayv2_stage.default_stage.invoke_url
}
