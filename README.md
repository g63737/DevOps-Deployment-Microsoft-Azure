# Déploiement de Microservices sur Azure avec Docker et Terraform

Ce projet démontre comment déployer deux microservices (un en Python Flask et un en Java Spring Boot) sur Microsoft Azure en utilisant Docker pour la conteneurisation et Terraform pour la gestion de l'infrastructure.

## Table des matières

- [Prérequis](#prérequis)
- [Structure du projet](#structure-du-projet)
- [Partie 1 : Conteneurisation des applications](#partie-1--conteneurisation-des-applications)
- [Partie 2 : Pipeline CI](#partie-2--pipeline-ci)
- [Partie 3 : Infrastructure Azure avec Terraform](#partie-3--infrastructure-azure-avec-terraform)
- [Partie 4 : Automatisation du déploiement](#partie-4--automatisation-du-déploiement)
- [Description des fichiers Terraform](#description-des-fichiers-terraform)
- [Nettoyage des ressources](#nettoyage-des-ressources)

## Prérequis

- Docker et Docker Compose
- Git
- Azure CLI
- Terraform
- Un compte Azure avec des crédits disponibles
- GitLab Runner (pour l'exécution du pipeline CI/CD)

## Structure du projet

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

## Partie 1 : Conteneurisation des applications

### Service Python (Flask)

1. Créer le Dockerfile pour le service Python :

```bash
cd service-python-main
```

Le contenu du Dockerfile :
```dockerfile
# Utiliser une image officielle Python légère
FROM python:3.10-slim

# Définir le dossier de travail dans le conteneur
WORKDIR /app

# Copier uniquement les fichiers nécessaires
COPY requirements.txt app.py test_app.py /app/

RUN pip install -r requirements.txt
RUN python test_app.py

EXPOSE 5000

# Commande par défaut : exécute app.py
CMD ["python", "app.py"]
```

2. Construire l'image Docker :

```bash
docker build -t python-service:latest .
```

### Service Java (Spring Boot)

1. Créer le Dockerfile pour le service Java :

```bash
cd ../service-java-main
```

Le contenu du Dockerfile :
```dockerfile
# Étape 1 — Build du .jar avec Maven
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /app
COPY . .
RUN mvn clean compile test package 

# Étape 2 — Exécution avec une image Java plus légère
FROM eclipse-temurin:17-jdk-jammy

WORKDIR /app

# On récupère juste le .jar compilé depuis l'étape précédente
COPY --from=builder /app/target/*.jar app.jar

ENV FLASK_URL=http://container-python:5000

EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
```

2. Construire l'image Docker :

```bash
docker build -t java-service:latest .
```

### Configuration Docker Compose

Créer un fichier docker-compose.yml à la racine du projet :

```yaml
version: '3.9'

services:
  container-python:
    build:
      context: ./service-python-main/
    container-name: container-python
    ports:
      - "5000:5000"
    networks:
      - app-network

  container-java:
    build:
      context: ./service-java-main/
    container-name: container-java
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

### Lancer les services avec Docker Compose

```bash
docker-compose up -d
```

### Vérifier le fonctionnement des services

- Service Python : http://localhost:5000/api/message
  - Doit retourner : `{"message":"Hello from Flask!"}`
- Service Java : http://localhost:8080/proxy
  - Doit afficher : `Hello from Flask!`

## Partie 2 : Pipeline CI

Créer un fichier `.gitlab-ci.yml` à la racine du projet pour configurer le pipeline :

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
      expire_in: 1h  # L'artifact est supprimé après 1 heure

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
      - ./service-java-main/target/  # Conserver le dossier target
    expire_in: 1h  # L'artifact est supprimé après 1 heure

test_Java:
  stage: test
  image: maven:3.9.4-eclipse-temurin-17
  script:
    - cd ./service-java-main
    - mvn test
```

Ce pipeline complet effectue :
1. La compilation des services Python et Java
2. L'exécution des tests unitaires pour chaque service

## Partie 3 : Infrastructure Azure avec Terraform

Cette partie couvre la création manuelle des fichiers Terraform qui définiront notre infrastructure.

### Créer les fichiers Terraform

1. Créer un fichier `providers.tf` :

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

2. Créer un fichier `variables.tf` :

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

3. Créer un fichier `main.tf` :

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

4. Créer un fichier `outputs.tf` :

```hcl
output "container_registry_login_server" {
  description = "Adresse du registre ACR"
  value       = azurerm_container_registry.acr.login_server
}

output "web_app_url_java" {
  description = "URL complète de l'application java"
  value       = "https://${azurerm_linux_web_app.app-java.default_hostname}/proxy"
}

output "web_app_url_python" {
  description = "URL complète de l'application python"
  value       = "https://${azurerm_linux_web_app.app-python.default_hostname}/api/message"
}
```
## Description des fichiers Terraform

Notre infrastructure est définie par plusieurs fichiers Terraform, chacun ayant un rôle spécifique :

### providers.tf
Ce fichier configure le fournisseur Azure qui sera utilisé par Terraform :
- Spécifie la source du fournisseur `azurerm` et sa version exacte (4.26.0)
- Configure les fonctionnalités de base du fournisseur Azure
- Permet à Terraform de communiquer avec l'API Azure

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
Ce fichier définit toutes les variables qui seront utilisées dans la configuration :
- Emplacement Azure (région)
- Noms des différentes ressources (groupe de ressources, registre de conteneurs, etc.)
- Configuration des services (ports, noms des images Docker, etc.)
- Sert à centraliser les valeurs configurables et faciliter la réutilisation

Chaque variable est définie avec :
- Une description claire
- Un type (string, number, etc.)
- Une valeur par défaut qui sera utilisée si aucune valeur n'est fournie

### main.tf
Fichier principal qui définit toutes les ressources Azure à créer :
- Groupe de ressources : conteneur logique pour toutes les ressources Azure
- Azure Container Registry (ACR) : stocke les images Docker
- Identité managée : permet l'authentification sécurisée entre services
- Attribution de rôle : donne les permissions d'accès au registre
- Plan App Service : définit les caractéristiques du serveur (B1 = Basic)
- App Web Linux (x2) : déploie les deux applications conteneurisées
  - Configuration des conteneurs
  - Configuration des variables d'environnement
  - Configuration de l'identité
  - Configuration réseau

Ce fichier constitue le cœur de l'infrastructure et définit comment les services interagissent entre eux.

### outputs.tf
Ce fichier définit les informations qui seront affichées après le déploiement :
- URL du serveur de connexion du registre ACR
- URL complète de l'application Java
- URL complète de l'application Python

Ces informations sont essentielles pour accéder aux services déployés et vérifier leur bon fonctionnement.

Dans cette étape, nous avons préparé les fichiers Terraform pour définir l'infrastructure, mais nous ne déployons pas encore cette infrastructure. Le déploiement effectif avec Terraform sera réalisé dans la partie 4 avec l'automatisation CI/CD.

## Partie 4 : Automatisation du déploiement

Dans cette partie, nous automatisons le déploiement de l'infrastructure et des applications en intégrant les étapes Terraform et Docker dans notre pipeline CI/CD.

### Mise à jour du fichier .gitlab-ci.yml

Nous avons ajouté deux nouveaux stages au pipeline :
- `infrastructure` : pour déployer l'infrastructure Azure avec Terraform
- `deploy` : pour construire et déployer les images Docker

```yaml
# Ajout des stages infrastructure et deploy
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
### Configuration de l'infrastructure terraform

1. Image : Utilise l'image officielle de Terraform, avec une configuration personnalisée de l'entrypoint pour éviter les conflits avec GitLab CI.  

2. Variables d'environnement : Dans les paramètres CI/CD de GitLab, j'ai ajouté les variables suivantes :

- `ARM_CLIENT_ID` : ID client Azure pour l'authentification Terraform
- `ARM_CLIENT_SECRET` : Secret client Azure pour l'authentification Terraform
- `ARM_SUBSCRIPTION_ID` : ID de l'abonnement Azure 
- `ARM_TENANT_ID` : ID du tenant Azure
- `DOCKER_PASSWORD` : Mot de passe admin du registre ACR

Ces variables sont utilisées par le pipeline pour se connecter aux services Azure et déployer les ressources.

3. Commandes Terraform:
```
terraform init : Initialise le répertoire de travail  
terraform validate : Vérifie la syntaxe des fichiers de configuration  
terraform plan : Crée un plan d'exécution  
terraform apply --auto-approve : Applique le plan sans demander de confirmation  
```

### Configuration du GitLab Runner pour Docker-in-Docker

Pour exécuter Docker dans notre pipeline CI/CD, nous avons configuré un GitLab Runner avec Docker-in-Docker :

Sur Windows :
```bash
docker run -d ^
  --name gitlab-runner ^
  --restart always ^
  -v chemin_absolu_vers_la_configuration\gitlab-runner\config:/etc/gitlab-runner ^
  -v /var/run/docker.sock:/var/run/docker.sock ^
  gitlab/gitlab-runner:latest

docker run --rm ^
  -v chemin_absolu_vers_la_configuration\gitlab-runner\config:/etc/gitlab-runner ^
  gitlab/gitlab-runner register ^
    --non-interactive ^
    --url "https://git.esi-bru.be" ^
    --token "$RUNNER_TOKEN" ^
    --executor "docker" ^
    --docker-image alpine:latest ^
    --description "docker-runner" ^
    --docker-volumes /var/run/docker.sock:/var/run/docker.sock
```

### Connexion à Azure et déploiement

Grâce aux variables d'environnement configurées dans CI/CD, le pipeline peut :
1. Se connecter à Azure via Terraform
2. Déployer automatiquement l'infrastructure
3. Se connecter au registre ACR
4. Construire et pousser les images Docker
5. Les applications Web déployées utiliseront automatiquement ces images

## Vérification du déploiement

Une fois le pipeline terminé, les applications sont accessibles via les URLs suivantes (obtenues dans les sorties Terraform) :

```bash
# Service Python
https://mon-app-python-63737.azurewebsites.net/api/message
# Doit retourner : {"message":"Hello from Flask!"}

# Service Java
https://mon-app-java-63737.azurewebsites.net/proxy
# Doit retourner : Hello from Flask!
```

## Nettoyage des ressources

Pour économiser nos crédits Azure, il est utile de détuire l'infrastructure lorsqu'elle n'est plus nécessaire.  
Cependant, le shell n'a pas les fichiers de configuration terraform à jour car le déploiement a été effectuée dans la pipeline. Il faut donc aller manuellement supprimer le groupe de ressources sur le portail Azure.
