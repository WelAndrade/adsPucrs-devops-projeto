# DevOps na Prática — Projeto Final

**Disciplina:** DevOps na Prática — PUCRS ADS  
**Repositório:** [github.com/WelAndrade/adsPucrs-devops-projeto](https://github.com/WelAndrade/adsPucrs-devops-projeto)

---

## Seção 1 — Documentação de Planejamento

### a) Descrição do Projeto, Objetivos e Requisitos

Este projeto tem como objetivo a construção de uma pipeline DevOps completa, cobrindo as práticas de integração contínua, entrega contínua, infraestrutura como código, containerização, orquestração, monitoramento e segurança.

A aplicação base é um servidor HTTP escrito em Go que expõe o endpoint `/health`. Ela é intencionalmente simples: o foco do projeto não é a complexidade da aplicação, mas a maturidade do processo de entrega — automação, rastreabilidade, segurança e infraestrutura reproduzível.

**Objetivos:**

- Configurar um repositório com versionamento e controle de qualidade integrados
- Implementar pipeline de CI que valide o código a cada push, sem intervenção manual
- Provisionar infraestrutura na AWS de forma declarativa e reproduzível com Terraform
- Containerizar a aplicação com Docker e publicar imagens no ECR
- Orquestrar o container com ECS no EC2, com deploy automatizado via CD
- Monitorar logs da aplicação em tempo real com CloudWatch
- Garantir segurança no pipeline com análise estática (SonarCloud), scan de imagem (Trivy) e testes DAST (OWASP ZAP)

**Requisitos funcionais:**

| Requisito | Descrição |
|-----------|-----------|
| RF01 | A aplicação deve responder `200 OK` com JSON `{"status":"ok"}` em `GET /health` |
| RF02 | A porta de escuta deve ser configurável via variável de ambiente `PORT` (padrão: 8080) |

**Requisitos não-funcionais:**

| Requisito | Descrição |
|-----------|-----------|
| RNF01 | Todo código merged na `main` deve ter passado pelo pipeline de CI |
| RNF02 | A infraestrutura deve ser provisionada exclusivamente via Terraform |
| RNF03 | Toda infraestrutura deve utilizar recursos elegíveis ao AWS Free Tier |
| RNF04 | Credenciais e configurações sensíveis nunca devem ser commitadas no repositório |
| RNF05 | Nenhuma imagem com vulnerabilidade CRITICAL ou HIGH deve chegar à produção |
| RNF06 | O deploy em produção só ocorre após o CI passar com sucesso |

---

### b) Plano de Integração Contínua

O pipeline de CI é executado automaticamente via GitHub Actions a cada `push` e `pull_request` na branch `main`, com dois jobs independentes executados em paralelo.

**Job 1 — `test` (validação da aplicação)**

| Etapa | Ferramenta | O que verifica |
|-------|-----------|---------------|
| Checkout | `actions/checkout@v4` | Clona o código com histórico completo (`fetch-depth: 0`) |
| Setup Go | `actions/setup-go@v5` | Instala Go 1.22 com cache de módulos |
| Vet | `go vet ./...` | Erros de compilação e construções suspeitas |
| Test | `go test -coverprofile=coverage.out ./...` | Testes unitários com coleta de cobertura |
| SonarCloud | `sonarqube-scan-action@v6` | Análise estática de código e cobertura de testes |

**Job 2 — `infra-validate` (validação da infraestrutura)**

| Etapa | Ferramenta | O que verifica |
|-------|-----------|---------------|
| Checkout | `actions/checkout@v4` | Clona o código |
| Setup Terraform | `hashicorp/setup-terraform@v3` | Instala Terraform 1.7 |
| Format check | `terraform fmt -check -recursive` | Formatação consistente dos `.tf` |
| Init | `terraform init -backend=false` | Inicializa providers sem backend |
| Validate | `terraform validate` | Sintaxe e referências dos recursos |

**Fluxo de proteção da branch:**

```
push/PR → CI executa → ambos os jobs passam → merge permitido
                     → qualquer job falha   → merge bloqueado
```

---

### c) Especificação Detalhada da Infraestrutura

Toda a infraestrutura é provisionada na AWS com Terraform, permanecendo dentro do AWS Free Tier.

**Visão geral da arquitetura:**

```
Internet
    │
    ▼
[Internet Gateway]
    │
    ▼
[VPC 10.0.0.0/16]
    │
    └── [Subnet Pública 10.0.1.0/24 — us-east-1a]
            │
            ▼
        [Security Group]  ← 22/tcp (SSH), 8080/tcp (app)
            │
            ▼
        [EC2 t2.micro]  ← AMI ECS-Optimized + IAM Instance Profile
            │
        [ECS Agent]  ← registra a instância no cluster
            │
            ▼
        [ECS Cluster: devops-pucrs-dev]
            │
            ▼
        [ECS Service]  ← desired_count=1, launch_type=EC2
            │
            ▼
        [Task Definition]  ← imagem ECR:sha, network_mode=host
            │
            ├── porta 8080 → Internet
            └── logs → [CloudWatch: /devops-pucrs/dev/app]

[ECR Repository]  ← imagens Docker, lifecycle: últimas 3
[IAM Role EC2]    ← CloudWatch + ECR + ECS agent
[IAM Role ECS]    ← task execution (pull image + logs)
```

**Recursos provisionados:**

| Recurso | Tipo AWS | Configuração | Free Tier |
|---------|----------|-------------|-----------|
| VPC | `aws_vpc` | CIDR `10.0.0.0/16`, DNS habilitado | Sempre gratuito |
| Subnet pública | `aws_subnet` | CIDR `10.0.1.0/24`, `us-east-1a` | Sempre gratuito |
| Internet Gateway | `aws_internet_gateway` | Associado à VPC | Sempre gratuito |
| Route Table | `aws_route_table` | Rota `0.0.0.0/0` via IGW | Sempre gratuito |
| Security Group | `aws_security_group` | Ingress: 22/tcp, 8080/tcp | Sempre gratuito |
| Key Pair | `aws_key_pair` | Chave pública SSH local | Sempre gratuito |
| EC2 | `aws_instance` | `t2.micro`, AMI ECS-Optimized (Amazon Linux 2) | 750h/mês (12 meses) |
| ECR | `aws_ecr_repository` | Scan on push, lifecycle: últimas 3 imagens | 500MB/mês gratuito |
| CloudWatch Log Group | `aws_cloudwatch_log_group` | `/devops-pucrs/dev/app`, retenção 7 dias | 5GB/mês gratuito |
| ECS Cluster | `aws_ecs_cluster` | `devops-pucrs-dev` | Gratuito |
| ECS Task Definition | `aws_ecs_task_definition` | `host` network, porta 8080, logs CloudWatch | Gratuito |
| ECS Service | `aws_ecs_service` | `desired_count=1`, launch type EC2 | Gratuito |
| IAM Role (EC2) | `aws_iam_role` | CloudWatch + ECR + ECS agent | Gratuito |
| IAM Role (ECS exec) | `aws_iam_role` | Task execution (pull + logs) | Gratuito |

**Módulos Terraform:**

| Arquivo | Responsabilidade |
|---------|-----------------|
| `main.tf` | Provider AWS, versões, locals compartilhados |
| `variables.tf` | Variáveis configuráveis |
| `network.tf` | VPC, subnet, internet gateway, route table |
| `security.tf` | Security group |
| `compute.tf` | EC2 (AMI ECS-Optimized), key pair, user_data |
| `ecr.tf` | ECR repository e lifecycle policy |
| `ecs.tf` | Cluster, task definition e service ECS |
| `iam.tf` | Roles e políticas para EC2 e ECS |
| `monitoring.tf` | CloudWatch log group |
| `outputs.tf` | IP público da EC2 e URL do ECR |

---

## Seção 2 — Pipeline de Integração Contínua (CI)

### a) Configuração do Repositório de Código

**Repositório:** [github.com/WelAndrade/adsPucrs-devops-projeto](https://github.com/WelAndrade/adsPucrs-devops-projeto)

- Branch principal: `main` com branch protection habilitada
- CI obrigatório antes de qualquer merge
- Commits assinados com GPG
- `.gitignore` exclui: `.tfstate`, `.tfvars`, binários Go, `.env`

**Estrutura do repositório:**

```
adsPucrs-devops-projeto/
├── .github/
│   └── workflows/
│       ├── ci.yml              # pipeline de CI
│       └── cd.yml              # pipeline de CD
├── app/
│   ├── main.go                 # servidor HTTP
│   ├── main_test.go            # testes unitários
│   ├── go.mod                  # módulo Go
│   └── Dockerfile              # build multi-stage
├── infra/
│   ├── main.tf                 # provider e configuração base
│   ├── variables.tf            # variáveis de entrada
│   ├── network.tf              # VPC e rede
│   ├── security.tf             # security groups
│   ├── compute.tf              # EC2 (AMI ECS-Optimized)
│   ├── ecr.tf                  # container registry
│   ├── ecs.tf                  # cluster, task definition, service
│   ├── iam.tf                  # roles e políticas
│   ├── monitoring.tf           # CloudWatch log group
│   ├── outputs.tf              # outputs (IP, URL ECR)
│   └── terraform.tfvars.example
├── docker-compose.yml          # execução local
├── sonar-project.properties    # configuração SonarCloud
├── .gitignore
└── README.md
```

---

### b) Implementação do Pipeline de CI

**Arquivo:** `.github/workflows/ci.yml`

O CI valida código e infraestrutura a cada push. O job `test` coleta cobertura de código e envia para o SonarCloud, que realiza análise estática (SAST) e quality gate.

**SonarCloud** está integrado via `sonarqube-scan-action@v6` e configurado em `sonar-project.properties`:

```properties
sonar.projectKey=adsPucrs-devops-projeto
sonar.organization=welandrade
sonar.sources=app
sonar.go.coverage.reportPaths=coverage.out
```

**Testes automatizados (`app/main_test.go`):**

```
TestHealthHandler → verifica que GET /health retorna HTTP 200
```

---

## Seção 3 — Scripts de Infraestrutura como Código

### a) Provisionamento com Terraform

**Ferramenta:** Terraform >= 1.6 com provider AWS ~> 5.0  
**Estado:** local (`.tfstate` gerado localmente, ignorado pelo `.gitignore`)

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
cd infra
terraform init
terraform plan
terraform apply

# obter outputs
terraform output instance_public_ip
terraform output ecr_repository_url

# destruir (evitar custos)
terraform destroy
```

---

## Seção 4 — Entrega Contínua (CD)

### Pipeline de CD

**Arquivo:** `.github/workflows/cd.yml`

O pipeline de CD é disparado automaticamente quando o CI conclui com sucesso na branch `main` (trigger `workflow_run`). Isso garante que nenhum deploy ocorre sem validação prévia do código e da infraestrutura.

**Etapas do pipeline:**

| Etapa | Ferramenta | O que faz |
|-------|-----------|-----------|
| Checkout | `actions/checkout@v4` | Clona o commit exato que passou no CI |
| AWS Credentials | `configure-aws-credentials@v4` | Autentica na AWS via secrets |
| ECR Login | `amazon-ecr-login@v2` | Autentica no container registry |
| Build | `docker build` | Constrói a imagem com tag `sha` e `latest` |
| Trivy Scan | `trivy-action@0.30.0` | Bloqueia o deploy se encontrar CRITICAL/HIGH |
| Push ECR | `docker push` | Publica ambas as tags no ECR |
| Deploy ECS | `aws ecs` CLI | Atualiza a task definition com a nova imagem e aguarda estabilização |
| Smoke Test | `curl` | Valida que `GET /health` retorna 200 após o deploy |
| OWASP ZAP | `action-baseline@v0.14.0` | Executa scan de segurança DAST na aplicação em execução |

**Fluxo completo:**

```
push → main
  │
  ▼
CI (go test + terraform validate + SonarCloud)
  │ sucesso
  ▼
CD: build Docker → Trivy scan → push ECR
  │ sem vulnerabilidades CRITICAL/HIGH
  ▼
ECS: nova task definition → update-service → wait stable
  │ serviço estabilizado
  ▼
Smoke test (curl /health)
  │
  ▼
OWASP ZAP baseline scan
```

**Secrets necessários no GitHub:**

| Secret | Descrição |
|--------|-----------|
| `AWS_ACCESS_KEY_ID` | Credencial AWS para ECR e ECS |
| `AWS_SECRET_ACCESS_KEY` | Credencial AWS |
| `EC2_HOST` | IP público da EC2 (output do Terraform) |

---

## Seção 5 — Containerização e Orquestração

### Dockerfile

**Arquivo:** `app/Dockerfile`

Build multi-stage para minimizar o tamanho da imagem:

```dockerfile
# Stage 1: compilação
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Stage 2: imagem final (sem SO, sem runtime)
FROM scratch
COPY --from=builder /app/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

A imagem final parte de `scratch` (imagem vazia), resultando em menos de 10MB — sem shell, sem sistema operacional, superfície de ataque mínima.

### Execução local com Docker

```bash
# build manual
docker build -t devops-pucrs app/

# executar
docker run -d --name app -p 8080:8080 devops-pucrs

# validar
curl http://localhost:8080/health

# parar
docker stop app && docker rm app
```

### Execução local com Docker Compose

**Arquivo:** `docker-compose.yml`

```bash
# subir
docker compose up -d

# validar
curl http://localhost:8080/health

# parar
docker compose down
```

O Docker Compose permite subir o ambiente completo com um único comando, padronizando o ambiente de desenvolvimento local.

### Orquestração com ECS

Em produção, o container é gerenciado pelo **Amazon ECS** com launch type EC2:

- **ECS Cluster:** agrupa os recursos de computação
- **Task Definition:** especifica imagem (SHA), porta 8080, configuração de logs e role de execução
- **ECS Service:** mantém `desired_count=1`, reinicia automaticamente em caso de falha, aplica rolling updates sem downtime

O deploy é feito atualizando a task definition com a nova imagem (tag SHA) e chamando `aws ecs update-service`. O pipeline aguarda `services-stable` antes de prosseguir para o smoke test.

---

## Seção 6 — Monitoramento e Logging

### CloudWatch Logs

Os logs da aplicação são enviados diretamente para o **Amazon CloudWatch Logs** via driver `awslogs` configurado na task definition do ECS:

```json
"logConfiguration": {
  "logDriver": "awslogs",
  "options": {
    "awslogs-group": "/devops-pucrs/dev/app",
    "awslogs-region": "us-east-1"
  }
}
```

| Configuração | Valor |
|-------------|-------|
| Log Group | `/devops-pucrs/dev/app` |
| Retenção | 7 dias |
| Região | `us-east-1` |

A instância EC2 possui uma IAM Role com `CloudWatchLogsFullAccess`, permitindo que o agente ECS escreva os logs sem credenciais adicionais.

**Consultar logs:**

```bash
# últimas entradas
aws logs tail /devops-pucrs/dev/app --follow

# filtrar por período
aws logs filter-log-events \
  --log-group-name /devops-pucrs/dev/app \
  --start-time $(date -d '1 hour ago' +%s000)
```

---

## Seção 7 — Segurança em DevOps

A segurança está integrada em múltiplas etapas do pipeline, seguindo o modelo shift-left:

### Análise Estática de Código — SAST (SonarCloud)

Executada no CI a cada push. O SonarCloud analisa o código Go em busca de vulnerabilidades, code smells e mede a cobertura de testes.

- **Ferramenta:** SonarCloud (sonarqube-scan-action@v6)
- **Quando:** job `test` do CI
- **Configuração:** `sonar-project.properties`

### Scan de Imagem de Container (Trivy)

Executado no CD após o build da imagem, antes do push para o ECR. Bloqueia o pipeline se encontrar vulnerabilidades de severidade CRITICAL ou HIGH.

- **Ferramenta:** Trivy (trivy-action@0.30.0)
- **Quando:** CD — após build, antes do push
- **Severidades bloqueantes:** CRITICAL, HIGH (`exit-code: 1`)

### Testes de Segurança em Aplicação — DAST (OWASP ZAP)

Executado no CD após o deploy bem-sucedido, com a aplicação rodando em produção. Realiza um baseline scan em busca de vulnerabilidades web comuns (OWASP Top 10).

- **Ferramenta:** OWASP ZAP (action-baseline@v0.14.0)
- **Quando:** CD — após smoke test
- **Modo:** baseline (não invasivo)
- **Resultado:** relatório gerado como artefato, falhas não bloqueiam o deploy

### Gestão de Segredos

| Segredo | Onde armazenado |
|---------|----------------|
| AWS Access Key ID | GitHub Actions Secrets |
| AWS Secret Access Key | GitHub Actions Secrets |
| IP da EC2 | GitHub Actions Secrets |
| Chave SSH | Removida do pipeline (ECS não usa SSH para deploy) |

Nenhuma credencial é commitada no repositório. O `.gitignore` exclui `.tfvars`, `.env` e qualquer arquivo de configuração local.

---

## Fluxograma Completo do Pipeline DevOps

```
┌─────────────────────────────────────────────────────────────┐
│                        DESENVOLVEDOR                        │
│                    git push → main                          │
└───────────────────────────┬─────────────────────────────────┘
                            │
              ┌─────────────▼─────────────┐
              │       GitHub Actions CI    │
              │                           │
              │  ┌──────────┐ ┌─────────┐ │
              │  │   test   │ │  infra  │ │
              │  │          │ │validate │ │
              │  │ go vet   │ │         │ │
              │  │ go test  │ │ tf fmt  │ │
              │  │ sonar    │ │ tf init │ │
              │  │ cloud    │ │ tf val  │ │
              │  └────┬─────┘ └────┬────┘ │
              └───────┼────────────┼──────┘
                      │  ambos OK  │
              ┌────────▼────────────▼──────┐
              │       GitHub Actions CD    │
              │                           │
              │  Build Docker image       │
              │         │                 │
              │  Trivy scan ──FAIL──► ✗   │
              │         │ OK              │
              │  Push ECR (sha + latest)  │
              │         │                 │
              │  ECS: nova task def       │
              │  update-service           │
              │  wait services-stable     │
              │         │                 │
              │  Smoke test /health       │
              │         │                 │
              │  OWASP ZAP baseline       │
              └──────────┬────────────────┘
                         │
              ┌──────────▼────────────────┐
              │      AWS — Produção       │
              │                          │
              │  EC2 t2.micro            │
              │  └── ECS Agent           │
              │       └── Container app  │
              │            └── :8080     │
              │                          │
              │  CloudWatch Logs         │
              │  ECR (registry)          │
              └──────────────────────────┘
```

---

## Como Executar — Passo a Passo

### Pré-requisitos

| Ferramenta | Versão mínima | Verificar |
|------------|--------------|---------|
| Go | 1.22 | `go version` |
| Docker | 24.x | `docker version` |
| Docker Compose | 2.x | `docker compose version` |
| Terraform | 1.6 | `terraform version` |
| AWS CLI | 2.x | `aws --version` |

### 1. Clonar o repositório

```bash
git clone https://github.com/WelAndrade/adsPucrs-devops-projeto.git
cd adsPucrs-devops-projeto
```

### 2. Rodar a aplicação localmente (Go)

```bash
cd app
go run .
curl localhost:8080/health
# {"status":"ok"}
```

### 3. Executar os testes

```bash
cd app
go test ./...
go vet ./...
```

### 4. Rodar com Docker

```bash
docker build -t devops-pucrs app/
docker run -d --name app -p 8080:8080 devops-pucrs
curl http://localhost:8080/health
docker stop app && docker rm app
```

### 5. Rodar com Docker Compose

```bash
docker compose up -d
curl http://localhost:8080/health
docker compose down
```

### 6. Provisionar a infraestrutura (AWS)

```bash
# configurar credenciais AWS
aws configure

# copiar e editar variáveis
cp infra/terraform.tfvars.example infra/terraform.tfvars

# provisionar
cd infra
terraform init
terraform plan
terraform apply

# outputs
terraform output instance_public_ip   # IP para o secret EC2_HOST
terraform output ecr_repository_url  # URL do ECR
```

### 7. Configurar secrets no GitHub

Após o `terraform apply`, adicionar no repositório GitHub (Settings → Secrets → Actions):

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Key ID do usuário IAM |
| `AWS_SECRET_ACCESS_KEY` | Secret do usuário IAM |
| `EC2_HOST` | Output `instance_public_ip` do Terraform |

### 8. Disparar o pipeline completo

```bash
# qualquer push na main dispara CI → CD
git commit --allow-empty -m "trigger pipeline"
git push origin main
```

### 9. Consultar logs em produção

```bash
aws logs tail /devops-pucrs/dev/app --follow
```

### 10. Destruir a infraestrutura (evitar custos)

```bash
cd infra && terraform destroy
```

---

## Tecnologias Utilizadas

| Tecnologia | Versão | Função |
|------------|--------|--------|
| Go | 1.22 | Linguagem da aplicação |
| Docker | 24.x | Containerização (build multi-stage → scratch) |
| Docker Compose | 2.x | Orquestração local |
| Terraform | >= 1.6 | Infraestrutura como Código |
| GitHub Actions | — | Pipelines de CI e CD |
| SonarCloud | — | SAST — análise estática e cobertura |
| Trivy | 0.30.0 | Scan de vulnerabilidades em imagens |
| OWASP ZAP | 0.14.0 | DAST — testes de segurança em aplicação |
| AWS EC2 | t2.micro | Compute (host do ECS Agent) |
| AWS ECS | EC2 launch type | Orquestração de containers |
| AWS ECR | — | Container registry |
| AWS CloudWatch | — | Logging centralizado |
| AWS VPC | — | Rede isolada |
| AWS IAM | — | Controle de acesso e permissões |
