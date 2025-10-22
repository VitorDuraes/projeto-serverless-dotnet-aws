# 🚀 Projeto: Aplicação "Serverless" .NET na AWS com Terraform

Este repositório contém o código-fonte completo para provisionar e implantar uma aplicação web "serverless" (sem servidor) na AWS. A infraestrutura é 100% gerenciada como Código (IaC) usando **Terraform**, e o backend é escrito em **.NET (C#)**.

O projeto é um "Livro de Visitas" (Guestbook) online, onde usuários podem postar mensagens e ver um feed ao vivo de todas as mensagens enviadas.

## 🎯 Arquitetura da Solução

Esta arquitetura é um pilar da computação em nuvem moderna. Ela é altamente escalável, resiliente e possui um custo baixíssimo (quase zero), pois só paga pelos recursos quando eles são realmente utilizados.

1.  **Frontend (S3):** Um site estático (HTML/CSS/JS) é hospedado em um **AWS S3 Bucket**, configurado para servir conteúdo web.
2.  **API (API Gateway):** Um **API Gateway** HTTP atua como a "porta de entrada" para nosso backend, recebendo requisições `GET` e `POST`.
3.  **Lógica (Lambda):** O API Gateway encaminha as requisições para uma função **AWS Lambda**. É aqui que nosso código **.NET (C#)** roda, processando a lógica de negócio.
4.  **Banco de Dados (DynamoDB):** A função Lambda salva e lê as mensagens de uma tabela **DynamoDB** (um banco de dados NoSQL gerenciado), garantindo persistência e velocidade.

## 💻 Stack de Tecnologias

- **Infraestrutura como Código:** Terraform
- **Cloud:** AWS (S3, API Gateway, Lambda, DynamoDB, IAM)
- **Backend:** .NET 8 (C#)
- **Frontend:** HTML, CSS, JavaScript

---

## 🛠️ Como Executar

Siga os passos abaixo para provisionar e implantar toda a aplicação do zero.

### Pré-requisitos

Antes de começar, garanta que você tenha:

- [Terraform CLI](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.0+)
- [AWS CLI](https://aws.amazon.com/pt/cli/) instalado e configurado com suas credenciais (`aws configure`).
- [.NET SDK](https://dotnet.microsoft.com/en-us/download) (v8.0+) instalado para compilar o código Lambda.

---

### 1. Clonar e Preparar

Primeiro, clone este repositório:

```bash
git clone [https://github.com/VitorDuraesUSUARIO/projeto-serverless-dotnet-aws.git](https://github.com/VitorDuraes/projeto-serverless-dotnet-aws.git)
cd projeto-serverless-dotnet-aws
```

### 2. Inicializar o Terraform

`terraform init`

### 3. Aplicar a Infraestrutura

`terraform apply`

## O processo inclui:

Executar dotnet publish localmente (via null_resource).

Zipar os artefatos da compilação.

Provisionar a tabela DynamoDB, a Role IAM, a função Lambda (com o .zip), o API Gateway e o S3 Bucket.

Renderizar o index.html substituindo a URL da API (usando data "template_file").

Fazer o upload do index.html processado para o S3.

Ao final, digite yes para aprovar. O processo levará alguns minutos.

## Como destuir tudo

`terraform destroy`
Digite `Yes` para confirmar, e o Terraform irá desmontar tudo o que ele construiu.
