variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "doc-management"
}

variable "user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
  default     = "DocManagement-UserPool"
}

variable "policy_store_name" {
  description = "Name for the Verified Permissions Policy Store"
  type        = string
  default     = "DocManagement-PolicyStore"
}

variable "api_name" {
  description = "Name for the API Gateway"
  type        = string
  default     = "DocManagement-API"
}

variable "documents_table_name" {
  description = "Name for the DynamoDB documents table"
  type        = string
  default     = "Documents"
}

variable "lambda_authorizer_name" {
  description = "Name for the Lambda authorizer function"
  type        = string
  default     = "DocManagement-Authorizer"
}

variable "lambda_business_name" {
  description = "Name for the Lambda business logic function"
  type        = string
  default     = "DocManagement-Business"
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 256
}

variable "api_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "prod"
}

variable "cognito_password_policy" {
  description = "Cognito User Pool password policy configuration"
  type = object({
    minimum_length    = number
    require_lowercase = bool
    require_numbers   = bool
    require_symbols   = bool
    require_uppercase = bool
  })
  default = {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
}

variable "authorizer_result_ttl" {
  description = "TTL for Lambda authorizer results in seconds"
  type        = number
  default     = 300
}

variable "create_test_users" {
  description = "Whether to create test users for demonstration"
  type        = bool
  default     = true
}

variable "test_user_passwords" {
  description = "Passwords for test users"
  type = object({
    admin_password    = string
    manager_password  = string
    employee_password = string
  })
  default = {
    admin_password    = "AdminPass123!"
    manager_password  = "ManagerPass123!"
    employee_password = "EmployeePass123!"
  }
  sensitive = true
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

variable "cedar_policies" {
  description = "Cedar policy definitions"
  type = object({
    view_policy = object({
      description = string
      statement   = string
    })
    edit_policy = object({
      description = string
      statement   = string
    })
    delete_policy = object({
      description = string
      statement   = string
    })
  })
  default = {
    view_policy = {
      description = "Allow document viewing based on department or management role"
      statement   = "permit(principal, action == Action::\"ViewDocument\", resource) when { principal.department == resource.department || principal.role == \"Manager\" || principal.role == \"Admin\" };"
    }
    edit_policy = {
      description = "Allow document editing for owners, department managers, or admins"
      statement   = "permit(principal, action == Action::\"EditDocument\", resource) when { (principal.sub == resource.owner) || (principal.role == \"Manager\" && principal.department == resource.department) || principal.role == \"Admin\" };"
    }
    delete_policy = {
      description = "Allow document deletion for admins only"
      statement   = "permit(principal, action == Action::\"DeleteDocument\", resource) when { principal.role == \"Admin\" };"
    }
  }
}