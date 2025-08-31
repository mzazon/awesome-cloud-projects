# Input variables for Service Catalog Portfolio with CloudFormation Templates

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "portfolio_name" {
  description = "Name for the Service Catalog portfolio"
  type        = string
  default     = "enterprise-infrastructure"
  validation {
    condition     = length(var.portfolio_name) > 0 && length(var.portfolio_name) <= 100
    error_message = "Portfolio name must be between 1 and 100 characters."
  }
}

variable "portfolio_description" {
  description = "Description for the Service Catalog portfolio"
  type        = string
  default     = "Enterprise infrastructure templates for development teams"
}

variable "portfolio_provider_name" {
  description = "Provider name for the Service Catalog portfolio"
  type        = string
  default     = "IT Infrastructure Team"
}

variable "s3_product_name" {
  description = "Name for the S3 bucket Service Catalog product"
  type        = string
  default     = "managed-s3-bucket"
  validation {
    condition     = length(var.s3_product_name) > 0 && length(var.s3_product_name) <= 100
    error_message = "S3 product name must be between 1 and 100 characters."
  }
}

variable "lambda_product_name" {
  description = "Name for the Lambda function Service Catalog product"
  type        = string
  default     = "serverless-function"
  validation {
    condition     = length(var.lambda_product_name) > 0 && length(var.lambda_product_name) <= 100
    error_message = "Lambda product name must be between 1 and 100 characters."
  }
}

variable "launch_role_name" {
  description = "Name for the Service Catalog launch role"
  type        = string
  default     = "ServiceCatalogLaunchRole"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.launch_role_name))
    error_message = "Launch role name must contain only alphanumeric characters and +=,.@_- symbols."
  }
}

variable "templates_bucket_prefix" {
  description = "Prefix for the S3 bucket storing CloudFormation templates"
  type        = string
  default     = "service-catalog-templates"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.templates_bucket_prefix))
    error_message = "Bucket prefix must be lowercase alphanumeric characters and hyphens, starting and ending with alphanumeric."
  }
}

variable "principal_arns" {
  description = "List of principal ARNs to grant access to the Service Catalog portfolio"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for arn in var.principal_arns : can(regex("^arn:aws:(iam|sts)::[0-9]{12}:(user|group|role)/.+", arn))
    ])
    error_message = "Principal ARNs must be valid IAM user, group, or role ARNs."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the CloudFormation templates S3 bucket"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for the CloudFormation templates S3 bucket"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}