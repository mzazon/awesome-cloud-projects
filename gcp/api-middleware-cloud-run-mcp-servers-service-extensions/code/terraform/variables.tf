# Variables for API Middleware with Cloud Run MCP Servers and Service Extensions
# Configure these variables to customize your deployment

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Run and Vertex AI."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "mcp-middleware"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Run Configuration
variable "mcp_server_config" {
  description = "Configuration for MCP server Cloud Run services"
  type = object({
    memory              = string
    cpu                 = string
    min_instances       = number
    max_instances       = number
    concurrency         = number
    timeout_seconds     = number
    allow_unauthenticated = bool
  })
  default = {
    memory              = "512Mi"
    cpu                 = "1"
    min_instances       = 0
    max_instances       = 10
    concurrency         = 100
    timeout_seconds     = 300
    allow_unauthenticated = true
  }
}

variable "middleware_config" {
  description = "Configuration for main API middleware Cloud Run service"
  type = object({
    memory              = string
    cpu                 = string
    min_instances       = number
    max_instances       = number
    concurrency         = number
    timeout_seconds     = number
    allow_unauthenticated = bool
  })
  default = {
    memory              = "1Gi"
    cpu                 = "2"
    min_instances       = 0
    max_instances       = 20
    concurrency         = 100
    timeout_seconds     = 300
    allow_unauthenticated = true
  }
}

# Container Images
variable "container_images" {
  description = "Container images for each service"
  type = object({
    content_analyzer   = string
    request_router     = string
    response_enhancer  = string
    api_middleware     = string
  })
  default = {
    content_analyzer   = "gcr.io/cloudrun/hello"  # Placeholder - replace with actual images
    request_router     = "gcr.io/cloudrun/hello"  # Placeholder - replace with actual images
    response_enhancer  = "gcr.io/cloudrun/hello"  # Placeholder - replace with actual images
    api_middleware     = "gcr.io/cloudrun/hello"  # Placeholder - replace with actual images
  }
}

# Vertex AI Configuration
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (must support Gemini models)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must support Gemini models."
  }
}

variable "gemini_model" {
  description = "Gemini model to use for AI processing"
  type        = string
  default     = "gemini-pro"
  validation {
    condition     = contains(["gemini-pro", "gemini-pro-vision"], var.gemini_model)
    error_message = "Gemini model must be either 'gemini-pro' or 'gemini-pro-vision'."
  }
}

# Cloud Endpoints Configuration
variable "endpoints_config" {
  description = "Configuration for Cloud Endpoints"
  type = object({
    title       = string
    description = string
    version     = string
  })
  default = {
    title       = "Intelligent API Middleware Gateway"
    description = "AI-powered API gateway using MCP servers"
    version     = "1.0.0"
  }
}

# Security Configuration
variable "cors_config" {
  description = "CORS configuration for all services"
  type = object({
    allow_origins      = list(string)
    allow_methods      = list(string)
    allow_headers      = list(string)
    allow_credentials  = bool
  })
  default = {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    allow_headers     = ["*"]
    allow_credentials = true
  }
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable enhanced monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for Cloud Run services"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

# Networking Configuration
variable "ingress" {
  description = "Ingress settings for Cloud Run services"
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    ], var.ingress)
    error_message = "Ingress must be one of the valid Cloud Run ingress settings."
  }
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "mcp-middleware"
    managed-by  = "terraform"
    environment = "dev"
  }
}

# Service Account Configuration
variable "create_service_account" {
  description = "Whether to create a custom service account for Cloud Run services"
  type        = bool
  default     = true
}

variable "service_account_roles" {
  description = "IAM roles to assign to the service account"
  type        = list(string)
  default = [
    "roles/aiplatform.user",
    "roles/run.invoker",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ]
}