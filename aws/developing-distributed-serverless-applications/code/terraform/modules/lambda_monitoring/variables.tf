# Variables for Lambda Monitoring Module

variable "function_name" {
  description = "Name of the Lambda function to monitor"
  type        = string
}

variable "region" {
  description = "AWS region where the Lambda function is deployed"
  type        = string
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm state is triggered"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs to notify when alarm state returns to OK"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to monitoring resources"
  type        = map(string)
  default     = {}
}

variable "error_threshold" {
  description = "Threshold for Lambda error count alarm"
  type        = number
  default     = 5
}

variable "duration_threshold" {
  description = "Threshold for Lambda duration alarm (milliseconds)"
  type        = number
  default     = 10000
}

variable "concurrent_executions_threshold" {
  description = "Threshold for Lambda concurrent executions alarm"
  type        = number
  default     = 100
}