# Variables for API Gateway Module

variable "api_id" {
  description = "ID of the API Gateway REST API"
  type        = string
}

variable "lambda_arn" {
  description = "ARN of the Lambda function to integrate with"
  type        = string
}

variable "lambda_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "region" {
  description = "AWS region for the API Gateway"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
  default     = "prod"
}

variable "enable_logging" {
  description = "Enable CloudWatch logging for API Gateway"
  type        = bool
  default     = true
}

variable "api_key_required" {
  description = "Whether API key is required for endpoints"
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

variable "cors_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "throttle_rate_limit" {
  description = "Request rate limit for API Gateway throttling"
  type        = number
  default     = 1000
}

variable "throttle_burst_limit" {
  description = "Burst limit for API Gateway throttling"
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Tags to apply to API Gateway resources"
  type        = map(string)
  default     = {}
}