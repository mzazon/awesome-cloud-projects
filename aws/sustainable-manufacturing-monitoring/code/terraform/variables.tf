# Variables for sustainable manufacturing monitoring infrastructure

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "sustainable-manufacturing"
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

variable "asset_model_name" {
  description = "Name for the IoT SiteWise asset model"
  type        = string
  default     = "SustainableManufacturingModel"
}

variable "manufacturing_assets" {
  description = "List of manufacturing equipment assets to create"
  type = map(object({
    name        = string
    description = optional(string)
  }))
  default = {
    production_line_a = {
      name        = "Production_Line_A_Extruder"
      description = "Extrusion equipment for production line A"
    }
    production_line_b = {
      name        = "Production_Line_B_Injection_Molding"
      description = "Injection molding equipment for production line B"
    }
  }
}

variable "carbon_intensity_factors" {
  description = "Carbon intensity factors (kg CO2 per kWh) by AWS region"
  type        = map(number)
  default = {
    "us-east-1"      = 0.393  # Virginia
    "us-west-2"      = 0.295  # Oregon
    "eu-west-1"      = 0.316  # Ireland
    "ap-northeast-1" = 0.518  # Tokyo
    "us-east-2"      = 0.404  # Ohio
    "us-west-1"      = 0.290  # N. California
    "eu-central-1"   = 0.425  # Frankfurt
    "ap-southeast-1" = 0.530  # Singapore
  }
}

variable "sustainability_thresholds" {
  description = "Thresholds for sustainability alarms"
  type = object({
    high_carbon_emissions_threshold = number
    high_power_consumption_threshold = number
    evaluation_periods = number
    alarm_period = number
  })
  default = {
    high_carbon_emissions_threshold = 50.0
    high_power_consumption_threshold = 100.0
    evaluation_periods = 2
    alarm_period = 300
  }
}

variable "lambda_function_config" {
  description = "Configuration for Lambda function"
  type = object({
    runtime     = string
    timeout     = number
    memory_size = number
  })
  default = {
    runtime     = "python3.9"
    timeout     = 60
    memory_size = 256
  }
}

variable "reporting_schedule" {
  description = "Cron expression for automated sustainability reporting"
  type        = string
  default     = "cron(0 8 * * ? *)"  # Daily at 8 AM UTC
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "SustainableManufacturing"
    Environment = "dev"
    Owner       = "DevOps"
    Purpose     = "ESG-Monitoring"
  }
}