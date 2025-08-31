# =============================================================================
# Variables for Knowledge Management Assistant with Bedrock Agents
# =============================================================================
# This file defines all configurable variables for the Terraform deployment.
# Modify these values to customize the deployment for your environment.
# =============================================================================

# =============================================================================
# General Configuration Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in format: us-east-1, eu-west-1, etc."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "knowledge-management-assistant"
  
  validation {
    condition     = length(var.project_name) > 3 && length(var.project_name) < 50
    error_message = "Project name must be between 3 and 50 characters."
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

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "knowledge-management-assistant"
    Environment = "dev"
    ManagedBy   = "terraform"
    Recipe      = "bedrock-knowledge-assistant"
    Owner       = "DevOps"
  }
}

# =============================================================================
# S3 Configuration Variables
# =============================================================================

variable "bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with random string)"
  type        = string
  default     = "knowledge-docs"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must follow S3 naming conventions: lowercase, numbers, hyphens only."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket for document history"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption must be either AES256 or aws:kms."
  }
}

# =============================================================================
# Bedrock Configuration Variables
# =============================================================================

variable "knowledge_base_name" {
  description = "Name for the Bedrock Knowledge Base"
  type        = string
  default     = "enterprise-knowledge-base"
  
  validation {
    condition     = length(var.knowledge_base_name) > 0 && length(var.knowledge_base_name) <= 100
    error_message = "Knowledge base name must be between 1 and 100 characters."
  }
}

variable "agent_name" {
  description = "Name for the Bedrock Agent"
  type        = string
  default     = "knowledge-assistant"
  
  validation {
    condition     = length(var.agent_name) > 0 && length(var.agent_name) <= 100
    error_message = "Agent name must be between 1 and 100 characters."
  }
}

variable "foundation_model" {
  description = "Foundation model for the Bedrock Agent"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  
  validation {
    condition = can(regex("^anthropic\\.|^amazon\\.|^ai21\\.|^cohere\\.|^meta\\.|^mistral\\.", var.foundation_model))
    error_message = "Foundation model must be a valid Bedrock model ARN."
  }
}

variable "embedding_model" {
  description = "Embedding model for the Knowledge Base"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
  
  validation {
    condition = can(regex("^amazon\\.titan-embed", var.embedding_model))
    error_message = "Embedding model must be a valid Titan embedding model."
  }
}

variable "agent_instruction" {
  description = "Instructions for the Bedrock Agent behavior"
  type        = string
  default     = <<EOF
You are a helpful enterprise knowledge management assistant powered by Amazon Bedrock. Your role is to help employees find accurate information from company documents, policies, and procedures. Always provide specific, actionable answers and cite sources when possible. If you cannot find relevant information in the knowledge base, clearly state that and suggest alternative resources or contacts. Maintain a professional tone while being conversational and helpful. When providing policy information, always mention if employees should verify with HR for the most current version.
EOF
  
  validation {
    condition     = length(var.agent_instruction) > 50 && length(var.agent_instruction) <= 4000
    error_message = "Agent instruction must be between 50 and 4000 characters."
  }
}

variable "agent_idle_session_ttl" {
  description = "Idle session TTL for Bedrock Agent in seconds"
  type        = number
  default     = 1800
  
  validation {
    condition     = var.agent_idle_session_ttl >= 60 && var.agent_idle_session_ttl <= 3600
    error_message = "Agent idle session TTL must be between 60 and 3600 seconds."
  }
}

# =============================================================================
# OpenSearch Serverless Configuration Variables
# =============================================================================

variable "opensearch_collection_name" {
  description = "Name for OpenSearch Serverless collection (will be suffixed with random string)"
  type        = string
  default     = "kb-collection"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.opensearch_collection_name))
    error_message = "Collection name must be 3-32 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vector_index_name" {
  description = "Name for the vector index in OpenSearch"
  type        = string
  default     = "knowledge-index"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,254}$", var.vector_index_name))
    error_message = "Vector index name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# =============================================================================
# Knowledge Base Data Source Configuration Variables
# =============================================================================

variable "chunking_strategy" {
  description = "Chunking strategy for document processing"
  type        = string
  default     = "FIXED_SIZE"
  
  validation {
    condition     = contains(["FIXED_SIZE", "NONE"], var.chunking_strategy)
    error_message = "Chunking strategy must be either FIXED_SIZE or NONE."
  }
}

variable "max_tokens" {
  description = "Maximum tokens per chunk for fixed-size chunking"
  type        = number
  default     = 300
  
  validation {
    condition     = var.max_tokens >= 20 && var.max_tokens <= 8192
    error_message = "Max tokens must be between 20 and 8192."
  }
}

variable "overlap_percentage" {
  description = "Overlap percentage between chunks"
  type        = number
  default     = 20
  
  validation {
    condition     = var.overlap_percentage >= 1 && var.overlap_percentage <= 99
    error_message = "Overlap percentage must be between 1 and 99."
  }
}

variable "inclusion_prefixes" {
  description = "S3 prefixes to include in data source"
  type        = list(string)
  default     = ["documents/"]
  
  validation {
    condition     = length(var.inclusion_prefixes) > 0
    error_message = "At least one inclusion prefix must be specified."
  }
}

# =============================================================================
# Lambda Configuration Variables
# =============================================================================

variable "lambda_function_name" {
  description = "Name for the Lambda function (will be suffixed with random string)"
  type        = string
  default     = "bedrock-agent-proxy"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.lambda_function_name))
    error_message = "Lambda function name must be 1-64 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period for Lambda function"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# =============================================================================
# API Gateway Configuration Variables
# =============================================================================

variable "api_name" {
  description = "Name for the API Gateway (will be suffixed with random string)"
  type        = string
  default     = "knowledge-management-api"
  
  validation {
    condition     = length(var.api_name) > 0 && length(var.api_name) <= 100
    error_message = "API name must be between 1 and 100 characters."
  }
}

variable "api_description" {
  description = "Description for the API Gateway"
  type        = string
  default     = "Knowledge Management Assistant API"
}

variable "api_endpoint_type" {
  description = "Endpoint type for API Gateway"
  type        = string
  default     = "REGIONAL"
  
  validation {
    condition     = contains(["EDGE", "REGIONAL", "PRIVATE"], var.api_endpoint_type)
    error_message = "API endpoint type must be EDGE, REGIONAL, or PRIVATE."
  }
}

variable "api_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_stage_name))
    error_message = "API stage name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "enable_api_gateway_logging" {
  description = "Enable CloudWatch logging for API Gateway"
  type        = bool
  default     = true
}

variable "api_log_retention_days" {
  description = "CloudWatch log retention period for API Gateway"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.api_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# =============================================================================
# Monitoring and Alerting Configuration Variables
# =============================================================================

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "lambda_error_threshold" {
  description = "Threshold for Lambda error alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_error_threshold > 0
    error_message = "Lambda error threshold must be greater than 0."
  }
}

variable "api_4xx_error_threshold" {
  description = "Threshold for API Gateway 4XX error alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.api_4xx_error_threshold > 0
    error_message = "API 4XX error threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

variable "alarm_period_seconds" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600], var.alarm_period_seconds)
    error_message = "Alarm period must be 60, 300, 900, or 3600 seconds."
  }
}

# =============================================================================
# Security Configuration Variables
# =============================================================================

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all applicable services"
  type        = bool
  default     = true
}

variable "enable_encryption_in_transit" {
  description = "Enable encryption in transit for all applicable services"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (optional, defaults to AWS managed keys)"
  type        = string
  default     = ""
}

variable "enable_cors" {
  description = "Enable CORS for API Gateway"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "Allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "Allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "Allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

# =============================================================================
# Cost Optimization Variables
# =============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features where applicable"
  type        = bool
  default     = true
}

variable "s3_storage_class" {
  description = "Default storage class for S3 objects"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA",
      "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE"
    ], var.s3_storage_class)
    error_message = "S3 storage class must be a valid storage class."
  }
}

# =============================================================================
# Development and Testing Variables
# =============================================================================

variable "create_sample_documents" {
  description = "Create sample documents in S3 for testing"
  type        = bool
  default     = true
}

variable "enable_debug_logging" {
  description = "Enable debug logging for Lambda function"
  type        = bool
  default     = false
}

variable "deploy_test_resources" {
  description = "Deploy additional resources for testing purposes"
  type        = bool
  default     = false
}