# Variables for Progressive Web Applications with AWS Amplify

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "pwa-amplify-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 30
    error_message = "Project name must be lowercase, alphanumeric with hyphens, and no more than 30 characters."
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

variable "app_name" {
  description = "Name of the Amplify application"
  type        = string
  default     = "progressive-web-app"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.app_name)) && length(var.app_name) <= 50
    error_message = "App name must be alphanumeric with hyphens and no more than 50 characters."
  }
}

variable "github_repository" {
  description = "GitHub repository URL for the application source code"
  type        = string
  default     = ""
  
  validation {
    condition     = var.github_repository == "" || can(regex("^https://github.com/[a-zA-Z0-9-_]+/[a-zA-Z0-9-_]+$", var.github_repository))
    error_message = "GitHub repository must be a valid GitHub URL or empty string."
  }
}

variable "github_branch" {
  description = "GitHub branch for automatic deployments"
  type        = string
  default     = "main"
}

variable "github_access_token" {
  description = "GitHub personal access token for repository access"
  type        = string
  default     = ""
  sensitive   = true
}

variable "amplify_domain" {
  description = "Custom domain for the Amplify application (optional)"
  type        = string
  default     = ""
}

variable "enable_auto_branch_creation" {
  description = "Enable automatic branch creation for feature branches"
  type        = bool
  default     = true
}

variable "enable_auto_build" {
  description = "Enable automatic builds on code commits"
  type        = bool
  default     = true
}

variable "enable_pull_request_preview" {
  description = "Enable pull request preview environments"
  type        = bool
  default     = true
}

variable "cognito_user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
  default     = "pwa-user-pool"
}

variable "cognito_user_pool_client_name" {
  description = "Name for the Cognito User Pool Client"
  type        = string
  default     = "pwa-user-pool-client"
}

variable "cognito_identity_pool_name" {
  description = "Name for the Cognito Identity Pool"
  type        = string
  default     = "pwa-identity-pool"
}

variable "appsync_api_name" {
  description = "Name for the AppSync GraphQL API"
  type        = string
  default     = "pwa-graphql-api"
}

variable "appsync_authentication_type" {
  description = "Authentication type for AppSync API"
  type        = string
  default     = "AMAZON_COGNITO_USER_POOLS"
  
  validation {
    condition     = contains(["API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT"], var.appsync_authentication_type)
    error_message = "Authentication type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT."
  }
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB table"
  type        = string
  default     = "TaskTable"
}

variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB table"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket (will be randomized for uniqueness)"
  type        = string
  default     = "pwa-storage-bucket"
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable server-side encryption for S3 bucket"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition     = contains(["nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Runtime must be one of the supported Lambda runtimes."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_monitoring" {
  description = "Enable enhanced monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for notifications and alerts"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}