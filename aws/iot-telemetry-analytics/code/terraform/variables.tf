# Variables for IoT Analytics Pipeline Infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "iot-analytics-pipeline"
}

variable "random_suffix" {
  description = "Random suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

# IoT Analytics Configuration
variable "iot_analytics_channel_retention_unlimited" {
  description = "Whether to set unlimited retention for IoT Analytics channel"
  type        = bool
  default     = true
}

variable "iot_analytics_datastore_retention_unlimited" {
  description = "Whether to set unlimited retention for IoT Analytics datastore"
  type        = bool
  default     = true
}

variable "iot_analytics_dataset_schedule" {
  description = "Schedule expression for IoT Analytics dataset"
  type        = string
  default     = "rate(1 hour)"
}

variable "temperature_filter_min" {
  description = "Minimum temperature threshold for filtering"
  type        = number
  default     = 0
}

variable "temperature_filter_max" {
  description = "Maximum temperature threshold for filtering"
  type        = number
  default     = 100
}

variable "device_location" {
  description = "Device location to add as metadata"
  type        = string
  default     = "factory_floor_1"
}

variable "device_type" {
  description = "Device type to add as metadata"
  type        = string
  default     = "temperature_sensor"
}

# Kinesis Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis Data Stream"
  type        = number
  default     = 1
}

variable "kinesis_retention_period" {
  description = "Retention period for Kinesis Data Stream in hours"
  type        = number
  default     = 24
}

# Timestream Configuration
variable "timestream_memory_retention_hours" {
  description = "Memory store retention period in hours"
  type        = number
  default     = 24
}

variable "timestream_magnetic_retention_days" {
  description = "Magnetic store retention period in days"
  type        = number
  default     = 365
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 128
}

# IoT Topic Configuration
variable "iot_topic_name" {
  description = "IoT topic name for sensor data"
  type        = string
  default     = "topic/sensor/data"
}

variable "iot_rule_description" {
  description = "Description for IoT rule"
  type        = string
  default     = "Route sensor data to IoT Analytics and Kinesis"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}