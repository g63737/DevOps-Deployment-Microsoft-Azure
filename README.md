# Microservices Deployment on Azure with Docker and Terraform

This project demonstrates how to deploy two microservices (one in Python Flask and one in Java Spring Boot) on Microsoft Azure using Docker for containerization and Terraform for infrastructure management.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Part 1: Application Containerization](#part-1-application-containerization)
- [Part 2: CI Pipeline](#part-2-ci-pipeline)
- [Part 3: Azure Infrastructure with Terraform](#part-3-azure-infrastructure-with-terraform)
- [Part 4: Deployment Automation](#part-4-deployment-automation)
- [Terraform Files Description](#terraform-files-description)
- [Resource Cleanup](#resource-cleanup)

## Prerequisites

- Docker and Docker Compose
- Git
- Azure CLI
- Terraform
- An Azure account with available credits
- GitLab Runner (for CI/CD pipeline execution)

## Project Structure

```
.
├── .gitlab-ci.yml
├── docker-compose.yml
├── service-java-main
│   ├── Dockerfile
|   ├── .gitignore
│   ├── pom.xml
│   └── src/
├── service-python-main
│   ├── app.py
│   ├── Dockerfile
|   ├── .gitignore
│   ├── requirements.txt
│   └── test_app.py
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── providers.tf
```

## Part 1: Application Containerization

### Python Service (Flask)

1. Create the Dockerfile for the Python service:

```bash
cd service-python-main
```

Dockerfile content:
```dockerfile
# Use an official lightweight Python image
FROM python:3.10-slim

# Set the working directory in the container
WORKDIR /app

# Copy only necessary files
COPY requirements.txt app.py test_app.py /app/

RUN pip install -r requirements.txt
RUN python test_app.py

EXPOSE 5000

# Default command: run app.py
CMD ["python", "app.py"]
```

2. Build the Docker image:

```bash
docker build -t python-service:latest .
```

### Java Service (Spring Boot)

1. Create the Dockerfile for the Java service:

```bash
cd ../service-java-main
```

Dockerfile content:
```dockerfile
# Stage 1 — Build the .jar with Maven
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /app
COPY . .
RUN mvn clean compile test package 

# Stage 2 — Execution with a lighter Java image
FROM eclipse-temurin:17-jdk-jammy

WORKDIR /app

# Get only the compiled .jar from the previous stage
COPY --from=builder /app/target/*.jar app.jar

ENV FLASK_URL=http://container-python:5000

EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
```

2. Build the Docker image:

```bash
docker build -t java-service:latest .
```

### Docker Compose Configuration

Create a docker-compose.yml file at the project root:

```yaml
version: '3.9'

services:
  container-python:
    build:
      context: ./service-python-main/
    container_name: container-python
    ports:
      - "5000:5000"
    networks:
      - app-network

  container-java:
    build:
      context: ./service-java-main/
    container_name: container-java
    ports:
      - "8080:8080"
    environment:
      - FLASK_URL=http://container-python:5000
    depends_on:
      - container-python
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
```

### Launch Services with Docker Compose

```bash
docker-compose up -d
```

### Verify Service Functionality

- Python Service: http://localhost:5000/api/message
  - Should return: `{"message":"Hello from Flask!"}`
- Java Service: http://localhost:8080/proxy
  - Should display: `Hello from Flask!`

## Part 2: CI Pipeline

Create a `.gitlab-ci.yml` file at the project root to configure the pipeline:

```yaml
stages:
    - build
    - test
    - infrastructure
    - deploy

compile_python:
    stage: build
    image: python:3.9-slim
    script:
        - cd ./service-python-main
        - pip install -r requirements.txt
    artifacts:
      paths:
      - ./service-python-main 
      expire_in: 1h  # Artifact is deleted after 1 hour

test_python:
    stage: test
    image: python:3.9-slim
    script:
        - cd ./service-python-main
        - pip install -r requirements.txt
        - python test_app.py

compile_Java:
  stage: build
  image: maven:3.9.4-eclipse-temurin-17
  script:
    - cd ./service-java-main
    - mvn compile
  artifacts:
    paths:
      - ./service-java-main/target/  # Preserve the target folder
    expire_in: 1h  # Artifact is deleted after 1 hour

test_Java:
  stage: test
  image: maven:3.9.4-eclipse-temurin-17
  script:
    - cd ./service-java-main
    - mvn test
```

This complete pipeline performs:
1. Compilation of Python and Java services
2. Execution of unit tests for each service

## Part 3: Azure Infrastructure with Terraform

This part covers the manual creation of Terraform files that will define our infrastructure.

### Create Terraform Files

1. Create a `providers.tf` file:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.26.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

2. Create a `variables.tf` file:

```hcl
variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-microservices-app"
}

variable "acr_name" {
  description = "Name of the Azure Container Registry"
  type        = string
  default     = "myacrregistry63737"
}

variable "identity_name" {
  description = "Name of the user-assigned managed identity"
  type        = string
  default     = "container-app-identity"
}

variable "service_plan_name" {
  description = "Name of the App Service plan"
  type        = string
  default     = "appserviceplan"
}

variable "docker_image_python" {
  description = "Docker image name and tag"
  type        = string
  default     = "python-service:latest"
}

variable "web_app_port_python" {
  description = "Port on which the web app listens"
  type        = string
  default     = "5000"
}

variable "docker_image_java" {
  description = "Docker image name and tag"
  type        = string
  default     = "java-service:latest"
}

variable "web_app_port_java" {
  description = "Port on which the web app listens"
  type        = string
  default     = "8080"
}

variable "web_app_python" {
  description = "Name of the Web App"
  type        = string
  default     = "mon-app-python-63737"
}

variable "web_app_java" {
  description = "Name of the Web App"
  type        = string
  default     = "mon-app-java-63737"
}
```

3. Create a `main.tf` file:

```hcl
# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.identity.principal_id
}

resource "azurerm_user_assigned_identity" "identity" {
  name                = var.identity_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_service_plan" "app_service_plan" {
  name                = var.service_plan_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "app-python" {
  name                = var.web_app_python
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.app_service_plan.id
  site_config {
    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.identity.client_id

    application_stack {
      docker_image_name   = var.docker_image_python
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.identity.id]
  }

  app_settings = {
    WEBSITES_PORT = var.web_app_port_python
  }
}

resource "azurerm_linux_web_app" "app-java" {
  name                = var.web_app_java
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.app_service_plan.id
  site_config {
    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.identity.client_id

    application_stack {
      docker_image_name   = var.docker_image_java
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.identity.id]
  }

  app_settings = {
    WEBSITES_PORT = var.web_app_port_java
    FLASK_URL = "https://${azurerm_linux_web_app.app-python.default_hostname}"
  }
}
```

4. Create an `outputs.tf` file:

```hcl
output "container_registry_login_server" {
  description = "ACR registry address"
  value       = azurerm_container_registry.acr.login_server
}

output "web_app_url_java" {
  description = "Complete URL of the Java application"
  value       = "https://${azurerm_linux_web_app.app-java.default_hostname}/proxy"
}

output "web_app_url_python" {
  description = "Complete URL of the Python application"
  value       = "https://${azurerm_linux_web_app.app-python.default_hostname}/api/message"
}
```

## Terraform Files Description

Our infrastructure is defined by several Terraform files, each with a specific role:

### providers.tf
This file configures the Azure provider that will be used by Terraform:
- Specifies the source of the `azurerm` provider and its exact version (4.26.0)
- Configures basic Azure provider features
- Allows Terraform to communicate with the Azure API

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.26.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

### variables.tf
This file defines all variables that will be used in the configuration:
- Azure location (region)
- Names of different resources (resource group, container registry, etc.)
- Service configuration (ports, Docker image names, etc.)
- Centralizes configurable values and facilitates reuse

Each variable is defined with:
- A clear description
- A type (string, number, etc.)
- A default value that will be used if no value is provided

### main.tf
Main file that defines all Azure resources to create:
- Resource group: logical container for all Azure resources
- Azure Container Registry (ACR): stores Docker images
- Managed identity: enables secure authentication between services
- Role assignment: grants registry access permissions
- App Service plan: defines server characteristics (B1 = Basic)
- Linux Web App (x2): deploys both containerized applications
  - Container configuration
  - Environment variables configuration
  - Identity configuration
  - Network configuration

This file constitutes the infrastructure core and defines how services interact with each other.

### outputs.tf
This file defines information that will be displayed after deployment:
- ACR registry login server URL
- Complete Java application URL
- Complete Python application URL

This information is essential for accessing deployed services and verifying their proper functioning.

In this step, we prepared the Terraform files to define the infrastructure, but we haven't deployed this infrastructure yet. The actual deployment with Terraform will be performed in part 4 with CI/CD automation.

## Part 4: Deployment Automation

In this part, we automate infrastructure and application deployment by integrating Terraform and Docker steps into our CI/CD pipeline.

### Update .gitlab-ci.yml File

We added two new stages to the pipeline:
- `infrastructure`: to deploy Azure infrastructure with Terraform
- `deploy`: to build and deploy Docker images

```yaml
# Adding infrastructure and deploy stages
infrastructure_terraform:
  stage: infrastructure
  image:
    name: hashicorp/terraform:1.3.9
    entrypoint: [""]
  script:
    - cd ./terraform
    - terraform init
    - terraform apply --auto-approve
    
docker_build:
  stage: deploy
  image: docker:20.10.16
  services:
    - docker:20.10.16-dind
  before_script:
    - apk add --no-cache py3-pip gcc musl-dev python3-dev libffi-dev openssl-dev cargo make
    - pip install azure-cli
    - az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
    - az acr login --name myacrregistry63737
  script:
    - cd service-python-main
    - docker build -t myacrregistry63737.azurecr.io/python-service:latest .
    - docker push myacrregistry63737.azurecr.io/python-service:latest
    - cd ../service-java-main
    - docker build -t myacrregistry63737.azurecr.io/java-service:latest .
    - docker push myacrregistry63737.azurecr.io/java-service:latest
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
```

### Terraform Infrastructure Configuration

1. Image: Uses the official Terraform image, with a custom entrypoint configuration to avoid conflicts with GitLab CI.

2. Environment variables: In GitLab CI/CD settings, I added the following variables:

- `ARM_CLIENT_ID`: Azure client ID for Terraform authentication
- `ARM_CLIENT_SECRET`: Azure client secret for Terraform authentication
- `ARM_SUBSCRIPTION_ID`: Azure subscription ID
- `ARM_TENANT_ID`: Azure tenant ID
- `DOCKER_PASSWORD`: ACR registry admin password

These variables are used by the pipeline to connect to Azure services and deploy resources.

3. Terraform commands:
```
terraform init: Initializes the working directory
terraform validate: Checks configuration file syntax
terraform plan: Creates an execution plan
terraform apply --auto-approve: Applies the plan without asking for confirmation
```

### GitLab Runner Configuration for Docker-in-Docker

To run Docker in our CI/CD pipeline, we configured a GitLab Runner with Docker-in-Docker:

On Windows:
```bash
docker run -d ^
  --name gitlab-runner ^
  --restart always ^
  -v absolute_path_to_config\gitlab-runner\config:/etc/gitlab-runner ^
  -v /var/run/docker.sock:/var/run/docker.sock ^
  gitlab/gitlab-runner:latest

docker run --rm ^
  -v absolute_path_to_config\gitlab-runner\config:/etc/gitlab-runner ^
  gitlab/gitlab-runner register ^
    --non-interactive ^
    --url "https://git.esi-bru.be" ^
    --token "$RUNNER_TOKEN" ^
    --executor "docker" ^
    --docker-image alpine:latest ^
    --description "docker-runner" ^
    --docker-volumes /var/run/docker.sock:/var/run/docker.sock
```

### Azure Connection and Deployment

Thanks to the environment variables configured in CI/CD, the pipeline can:
1. Connect to Azure via Terraform
2. Automatically deploy the infrastructure
3. Connect to the ACR registry
4. Build and push Docker images
5. Deployed Web Apps will automatically use these images

## Deployment Verification

Once the pipeline is complete, applications are accessible via the following URLs (obtained from Terraform outputs):

```bash
# Python Service
https://mon-app-python-63737.azurewebsites.net/api/message
# Should return: {"message":"Hello from Flask!"}

# Java Service
https://mon-app-java-63737.azurewebsites.net/proxy
# Should return: Hello from Flask!
```

## Resource Cleanup

To save Azure credits, it's useful to destroy the infrastructure when it's no longer needed.
However, the shell doesn't have the updated terraform configuration files since deployment was performed in the pipeline. You must therefore manually delete the resource group on the Azure portal.
