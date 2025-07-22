# Input variables for the secure API configuration management infrastructure
# These variables allow customization of the deployment while maintaining security best practices

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "secure-api"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "Service name must contain only lowercase letters, numbers, and hyphens."
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

variable "container_image" {
  description = "Container image URI for the API application"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "api_gateway_name" {
  description = "Name for the API Gateway"
  type        = string
  default     = "secure-api-gateway"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.api_gateway_name))
    error_message = "API Gateway name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation (requires Pub/Sub topic)"
  type        = bool
  default     = false
}

variable "secret_rotation_period" {
  description = "Secret rotation period in seconds (minimum 3600s for 1 hour)"
  type        = string
  default     = "2592000s" # 30 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.secret_rotation_period))
    error_message = "Rotation period must be in seconds format (e.g., '3600s')."
  }
}

variable "container_resources" {
  description = "Resource limits for the Cloud Run container"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "1"
    memory = "512Mi"
  }
  validation {
    condition = contains(["1", "2", "4", "8"], var.container_resources.cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
  }
}

variable "scaling_config" {
  description = "Scaling configuration for Cloud Run service"
  type = object({
    min_instances = number
    max_instances = number
  })
  default = {
    min_instances = 0
    max_instances = 10
  }
  validation {
    condition     = var.scaling_config.min_instances >= 0 && var.scaling_config.max_instances > var.scaling_config.min_instances
    error_message = "Min instances must be >= 0 and max instances must be > min instances."
  }
}

variable "ingress_traffic" {
  description = "Ingress traffic setting for Cloud Run service"
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    ], var.ingress_traffic)
    error_message = "Ingress traffic must be a valid Cloud Run ingress setting."
  }
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Enable audit logging for Secret Manager operations"
  type        = bool
  default     = true
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for private network access"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of existing VPC connector (if enable_vpc_connector is true)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "secure-api"
    managed-by  = "terraform"
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}