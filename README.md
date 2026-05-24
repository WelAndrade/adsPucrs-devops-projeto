# DevOps na Prática — Projeto Final

**Disciplina:** DevOps na Prática — PUCRS ADS  
**Repositório:** [github.com/SEU_USUARIO/adsPucrs-devops-projeto](https://github.com/SEU_USUARIO/adsPucrs-devops-projeto)

---

## Seção 1 — Documentação de Planejamento

### a) Descrição do Projeto, Objetivos e Requisitos

Este projeto tem como objetivo a construção de uma pipeline DevOps completa, cobrindo as práticas de integração contínua, entrega contínua, infraestrutura como código e containerização.

A aplicação escolhida como base é um servidor HTTP escrito em Go que expõe um endpoint `/health`. Ela é intencionalmente simples: o foco do projeto não é a complexidade da aplicação, mas sim a maturidade do processo de entrega — automação, rastreabilidade e infraestrutura reproduzível.

**Objetivos:**

- Configurar um repositório de código com versionamento e controle de qualidade integrados
- Implementar uma pipeline de CI que valide o código a cada push, sem intervenção manual
- Provisionar infraestrutura na AWS de forma declarativa, versionada e reproduzível com Terraform
- Preparar a base para containerização e entrega contínua (Fase 2)

**Requisitos funcionais:**

| Requisito | Descrição |
|-----------|-----------|
| RF01 | A aplicação deve responder `200 OK` com JSON `{"status":"ok"}` no endpoint `GET /health` |
| RF02 | A porta de escuta deve ser configurável via variável de ambiente `PORT` (padrão: 8080) |

**Requisitos não-funcionais:**

| Requisito | Descrição |
|-----------|-----------|
| RNF01 | Todo código merged na branch `main` deve ter passado pelo pipeline de CI |
| RNF02 | A infraestrutura deve ser provisionada exclusivamente via Terraform (sem ações manuais no console AWS) |
| RNF03 | Toda infraestrutura deve utilizar recursos elegíveis ao AWS Free Tier |
| RNF04 | Credenciais e configurações de ambiente nunca devem ser commitadas no repositório |

---

### b) Plano de Integração Contínua

O pipeline de CI é executado automaticamente via GitHub Actions a cada `push` e `pull_request` direcionados à branch `main`. Ele é composto por dois jobs independentes, executados em paralelo:

**Job 1 — `test` (validação da aplicação)**

| Etapa | Ferramenta | O que verifica |
|-------|-----------|---------------|
| Checkout | `actions/checkout@v4` | Clona o código do commit atual |
| Setup Go | `actions/setup-go@v5` | Instala Go 1.22 com cache de módulos |
| Vet | `go vet ./...` | Erros de compilação e construções suspeitas |
| Test | `go test ./...` | Execução dos testes automatizados unitários |

**Job 2 — `infra-validate` (validação da infraestrutura)**

| Etapa | Ferramenta | O que verifica |
|-------|-----------|---------------|
| Checkout | `actions/checkout@v4` | Clona o código do commit atual |
| Setup Terraform | `hashicorp/setup-terraform@v3` | Instala Terraform 1.7 |
| Format check | `terraform fmt -check -recursive` | Formatação consistente dos arquivos `.tf` |
| Init | `terraform init -backend=false` | Inicializa providers sem configurar backend |
| Validate | `terraform validate` | Valida sintaxe e referências dos recursos |

**Fluxo de proteção da branch:**

```
push/PR → CI executa → ambos os jobs passam → merge permitido
                     → qualquer job falha   → merge bloqueado
```

A branch `main` deve ser configurada no GitHub como branch protegida, exigindo que o CI passe antes de qualquer merge.

**Critérios de qualidade da pipeline:**

- Nenhum merge direto na `main` sem pipeline verde
- Testes devem cobrir os handlers da aplicação
- Infraestrutura deve ser válida sintaticamente antes de qualquer `apply`

---

### c) Especificação Detalhada da Infraestrutura Necessária

Toda a infraestrutura é provisionada na AWS com Terraform. Os recursos foram escolhidos com critério para permanecer dentro do AWS Free Tier.

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
    └── [Subnet Pública 10.0.1.0/24]
            │
            ▼
        [Security Group]  ← portas 22 (SSH) e 8080 (app)
            │
            ▼
        [EC2 t2.micro]  ← Docker instalado via user_data
            │
        [Key Pair SSH]

[ECR Repository]  ← registry para imagens Docker (usado na Fase 2)
```

**Recursos provisionados:**

| Recurso | Tipo AWS | Configuração | Free Tier |
|---------|----------|-------------|-----------|
| VPC | `aws_vpc` | CIDR `10.0.0.0/16`, DNS habilitado | Sempre gratuito |
| Subnet pública | `aws_subnet` | CIDR `10.0.1.0/24`, `us-east-1a`, IP público automático | Sempre gratuito |
| Internet Gateway | `aws_internet_gateway` | Associado à VPC | Sempre gratuito |
| Route Table | `aws_route_table` | Rota `0.0.0.0/0` via IGW | Sempre gratuito |
| Security Group | `aws_security_group` | Ingress: 22/tcp, 8080/tcp — Egress: all | Sempre gratuito |
| Key Pair | `aws_key_pair` | Chave pública SSH local | Sempre gratuito |
| EC2 | `aws_instance` | `t2.micro`, Amazon Linux 2023, Docker via `user_data` | 750h/mês (12 meses) |
| ECR | `aws_ecr_repository` | Scan on push, lifecycle: mantém últimas 3 imagens | 500MB/mês gratuito |

**Região:** `us-east-1` (us-east-1a)

**Ferramenta:** Terraform >= 1.6 com provider AWS ~> 5.0

**Estado do Terraform:** local (arquivo `terraform.tfstate` gerado localmente, ignorado pelo `.gitignore`)

**Módulos e arquivos Terraform:**

| Arquivo | Responsabilidade |
|---------|-----------------|
| `main.tf` | Provider AWS, versões, locals compartilhados |
| `variables.tf` | Variáveis configuráveis (região, tipo de instância, etc.) |
| `network.tf` | VPC, subnet, internet gateway, route table |
| `security.tf` | Security group da aplicação |
| `compute.tf` | EC2, key pair, user_data com instalação do Docker |
| `ecr.tf` | ECR repository e lifecycle policy |
| `outputs.tf` | IP público da EC2 e URL do ECR |

---

## Seção 2 — Pipeline de Integração Contínua (CI)

### a) Configuração do Repositório de Código

**Repositório:** [github.com/SEU_USUARIO/adsPucrs-devops-projeto](https://github.com/SEU_USUARIO/adsPucrs-devops-projeto)

O repositório foi criado no GitHub com a seguinte configuração:

- Branch principal: `main`
- Branch protection habilitada: CI obrigatório antes de merge
- `.gitignore` configurado para excluir: state do Terraform (`.tfstate`), variáveis locais (`.tfvars`), binários Go e arquivos de ambiente

**Estrutura do repositório:**

```
adsPucrs-devops-projeto/
├── .github/
│   └── workflows/
│       └── ci.yml          # pipeline de CI
├── app/
│   ├── main.go             # servidor HTTP
│   ├── main_test.go        # testes unitários
│   └── go.mod              # módulo Go
├── infra/
│   ├── main.tf             # provider e configuração base
│   ├── variables.tf        # variáveis de entrada
│   ├── network.tf          # VPC e rede
│   ├── security.tf         # security groups
│   ├── compute.tf          # EC2 e key pair
│   ├── ecr.tf              # container registry
│   ├── outputs.tf          # outputs (IP, URL ECR)
│   └── terraform.tfvars.example  # template de configuração local
├── .gitignore
└── README.md
```

---

### b) Implementação do Pipeline de CI com GitHub Actions

**Arquivo:** `.github/workflows/ci.yml`  
**Repositório:** [github.com/SEU_USUARIO/adsPucrs-devops-projeto](https://github.com/SEU_USUARIO/adsPucrs-devops-projeto)

O pipeline é declarado em YAML e executado nos runners gratuitos do GitHub (`ubuntu-latest`). Não requer nenhuma infraestrutura adicional para a etapa de CI.

**Triggers:**
```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

**Jobs:**

`test` — executa `go vet` e `go test` no diretório `app/`. Usa cache de módulos Go para reduzir tempo de execução em execuções subsequentes.

`infra-validate` — executa `terraform fmt -check`, `terraform init -backend=false` e `terraform validate` no diretório `infra/`. O flag `-backend=false` evita a necessidade de credenciais AWS no CI durante a fase de validação.

Os dois jobs rodam em paralelo e são independentes. A pipeline completa é concluída quando ambos passam.

**Testes automatizados (`app/main_test.go`):**

O arquivo de teste cobre o handler `/health` usando o pacote `net/http/httptest` da biblioteca padrão do Go. Não há dependências externas de teste.

```
TestHealthHandler → verifica que GET /health retorna HTTP 200
```

---

## Seção 3 — Scripts de Infraestrutura como Código

### a) Scripts para Provisionamento de Infraestrutura

**Ferramenta:** Terraform >= 1.6  
**Repositório:** [github.com/SEU_USUARIO/adsPucrs-devops-projeto](https://github.com/SEU_USUARIO/adsPucrs-devops-projeto) — diretório `infra/`

Os scripts Terraform provisionam toda a infraestrutura AWS necessária para hospedar a aplicação. O `user_data` da EC2 instala o Docker automaticamente na primeira inicialização da instância, preparando o ambiente para a containerização na Fase 2 sem necessidade de intervenção manual.

**Lifecycle policy do ECR** — mantém apenas as 3 imagens mais recentes, evitando acúmulo no free tier de 500MB.

**Como provisionar:**

```bash
# 1. copiar e editar as variáveis locais
cp infra/terraform.tfvars.example infra/terraform.tfvars

# 2. inicializar o Terraform
cd infra && terraform init

# 3. revisar o plano de execução
terraform plan

# 4. aplicar a infraestrutura
terraform apply

# 5. obter o IP público da EC2
terraform output instance_public_ip
```

**Como destruir (evitar custos):**

```bash
cd infra && terraform destroy
```

---

## Como Executar — Passo a Passo Completo

### Pré-requisitos

| Ferramenta | Versão mínima | Verificar |
|------------|--------------|---------|
| Go | 1.22 | `go version` |
| Terraform | 1.6 | `terraform version` |
| AWS CLI | 2.x | `aws --version` |
| Git | qualquer | `git --version` |

### 1. Clonar o repositório

```bash
git clone https://github.com/SEU_USUARIO/adsPucrs-devops-projeto.git
cd adsPucrs-devops-projeto
```

### 2. Rodar a aplicação localmente

```bash
cd app
go run .
# em outro terminal:
curl localhost:8080/health
# {"status":"ok"}
```

### 3. Executar os testes

```bash
cd app
go test ./...
go vet ./...
```

### 4. Configurar credenciais AWS

```bash
aws configure
# AWS Access Key ID: [sua chave]
# AWS Secret Access Key: [seu secret]
# Default region name: us-east-1
# Default output format: json
```

### 5. Gerar chave SSH (se ainda não tiver)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

### 6. Configurar variáveis do Terraform

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
# edite infra/terraform.tfvars conforme necessário
```

### 7. Provisionar a infraestrutura

```bash
cd infra
terraform init
terraform plan      # revise os recursos antes de criar
terraform apply     # confirme com "yes"
```

O output ao final mostra:
- `instance_public_ip` — IP para acessar a EC2
- `ecr_repository_url` — URL do registry (usado na Fase 2)

### 8. Validar a EC2

```bash
# aguarde ~2 minutos para o user_data instalar o Docker
ssh -i ~/.ssh/id_rsa ec2-user@$(cd infra && terraform output -raw instance_public_ip)

# dentro da EC2, verificar Docker:
docker --version
```

### 9. Destruir a infraestrutura (evitar custos)

```bash
cd infra
terraform destroy
```

---

## Tecnologias Utilizadas

| Tecnologia | Versão | Função |
|------------|--------|--------|
| Go | 1.22 | Linguagem da aplicação |
| Terraform | >= 1.6 | Infraestrutura como Código |
| GitHub Actions | — | Pipeline de CI |
| AWS EC2 | t2.micro | Servidor de aplicação |
| AWS ECR | — | Container registry |
| AWS VPC | — | Rede isolada |
| Docker | latest | Runtime de containers (Fase 2) |
