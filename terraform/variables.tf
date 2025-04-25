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


