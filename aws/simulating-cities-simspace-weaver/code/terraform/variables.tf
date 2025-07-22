# Variables for Smart City Digital Twins Infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "enable_force_destroy" {
  description = "Enable force destroy for S3 buckets (use with caution in production)"
  type        = bool
  default     = true
}

variable "artifact_retention_days" {
  description = "Number of days to retain simulation artifacts in S3"
  type        = number
  default     = 30
  validation {
    condition     = var.artifact_retention_days >= 1 && var.artifact_retention_days <= 365
    error_message = "Artifact retention days must be between 1 and 365."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "lambda_log_level" {
  description = "Log level for Lambda functions"
  type        = string
  default     = "INFO"
  validation {
    condition     = can(regex("^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$", var.lambda_log_level))
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

variable "sensor_data_ttl_days" {
  description = "Time-to-live for sensor data in DynamoDB (0 to disable TTL)"
  type        = number
  default     = 90
  validation {
    condition     = var.sensor_data_ttl_days >= 0 && var.sensor_data_ttl_days <= 365
    error_message = "Sensor data TTL must be between 0 and 365 days."
  }
}

variable "simulation_compute_type" {
  description = "Compute type for simulation workers (when using alternative simulation services)"
  type        = string
  default     = "c5.large"
  validation {
    condition = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.simulation_compute_type))
    error_message = "Simulation compute type must be a valid EC2 instance type."
  }
}

variable "max_concurrent_simulations" {
  description = "Maximum number of concurrent simulations"
  type        = number
  default     = 5
  validation {
    condition     = var.max_concurrent_simulations >= 1 && var.max_concurrent_simulations <= 20
    error_message = "Max concurrent simulations must be between 1 and 20."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "sensor_types" {
  description = "List of supported sensor types for the smart city deployment"
  type        = list(string)
  default = [
    "traffic",
    "weather",
    "air_quality",
    "noise",
    "parking",
    "emergency",
    "utility_water",
    "utility_electric",
    "pedestrian"
  ]
  validation {
    condition     = length(var.sensor_types) > 0 && length(var.sensor_types) <= 20
    error_message = "Sensor types list must contain between 1 and 20 elements."
  }
}

variable "city_zones" {
  description = "Geographic zones within the smart city for sensor deployment"
  type = map(object({
    description = string
    latitude    = number
    longitude   = number
    radius_km   = number
  }))
  default = {
    downtown = {
      description = "Downtown business district"
      latitude    = 40.7589
      longitude   = -73.9851
      radius_km   = 2.0
    }
    residential = {
      description = "Main residential area"
      latitude    = 40.7505
      longitude   = -73.9934
      radius_km   = 3.5
    }
    industrial = {
      description = "Industrial and warehouse district"
      latitude    = 40.7282
      longitude   = -74.0776
      radius_km   = 1.8
    }
  }
}

variable "analytics_schedule" {
  description = "CloudWatch Events schedule expression for automated analytics"
  type        = string
  default     = "rate(15 minutes)"
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.analytics_schedule))
    error_message = "Analytics schedule must be a valid CloudWatch Events schedule expression."
  }
}

variable "simulation_parameters" {
  description = "Configuration parameters for city simulation"
  type = object({
    grid_size_meters    = number
    update_interval_sec = number
    max_entities        = number
    enable_weather      = bool
    enable_traffic      = bool
    enable_pedestrians  = bool
  })
  default = {
    grid_size_meters    = 100
    update_interval_sec = 30
    max_entities        = 10000
    enable_weather      = true
    enable_traffic      = true
    enable_pedestrians  = true
  }
  validation {
    condition = (
      var.simulation_parameters.grid_size_meters >= 10 &&
      var.simulation_parameters.grid_size_meters <= 1000 &&
      var.simulation_parameters.update_interval_sec >= 1 &&
      var.simulation_parameters.update_interval_sec <= 300 &&
      var.simulation_parameters.max_entities >= 100 &&
      var.simulation_parameters.max_entities <= 100000
    )
    error_message = "Simulation parameters must be within valid ranges."
  }
}

variable "iot_message_routing" {
  description = "IoT message routing configuration"
  type = object({
    batch_size           = number
    batch_window_seconds = number
    retry_attempts       = number
    dead_letter_enabled  = bool
  })
  default = {
    batch_size           = 10
    batch_window_seconds = 5
    retry_attempts       = 3
    dead_letter_enabled  = true
  }
  validation {
    condition = (
      var.iot_message_routing.batch_size >= 1 &&
      var.iot_message_routing.batch_size <= 100 &&
      var.iot_message_routing.batch_window_seconds >= 0 &&
      var.iot_message_routing.batch_window_seconds <= 300 &&
      var.iot_message_routing.retry_attempts >= 0 &&
      var.iot_message_routing.retry_attempts <= 10
    )
    error_message = "IoT message routing parameters must be within valid ranges."
  }
}

variable "cost_optimization" {
  description = "Cost optimization settings"
  type = object({
    use_spot_instances     = bool
    enable_auto_scaling    = bool
    scale_down_after_hours = bool
    reserved_capacity      = number
  })
  default = {
    use_spot_instances     = false
    enable_auto_scaling    = true
    scale_down_after_hours = true
    reserved_capacity      = 0
  }
  validation {
    condition     = var.cost_optimization.reserved_capacity >= 0 && var.cost_optimization.reserved_capacity <= 1000
    error_message = "Reserved capacity must be between 0 and 1000."
  }
}

variable "security_settings" {
  description = "Security configuration settings"
  type = object({
    encrypt_at_rest           = bool
    encrypt_in_transit        = bool
    enable_vpc_endpoints      = bool
    require_mfa_for_admin     = bool
    enable_guardduty          = bool
    enable_config_rules       = bool
    data_classification_level = string
  })
  default = {
    encrypt_at_rest           = true
    encrypt_in_transit        = true
    enable_vpc_endpoints      = false
    require_mfa_for_admin     = false
    enable_guardduty          = false
    enable_config_rules       = false
    data_classification_level = "internal"
  }
  validation {
    condition = can(regex("^(public|internal|confidential|restricted)$", var.security_settings.data_classification_level))
    error_message = "Data classification level must be one of: public, internal, confidential, restricted."
  }
}

variable "notification_settings" {
  description = "Notification and alerting configuration"
  type = object({
    enable_email_alerts    = bool
    enable_sms_alerts      = bool
    enable_slack_alerts    = bool
    alert_thresholds = object({
      error_rate_percent     = number
      response_time_ms       = number
      throughput_requests    = number
      cost_threshold_dollars = number
    })
  })
  default = {
    enable_email_alerts = false
    enable_sms_alerts   = false
    enable_slack_alerts = false
    alert_thresholds = {
      error_rate_percent     = 5.0
      response_time_ms       = 5000
      throughput_requests    = 1000
      cost_threshold_dollars = 100
    }
  }
  validation {
    condition = (
      var.notification_settings.alert_thresholds.error_rate_percent >= 0 &&
      var.notification_settings.alert_thresholds.error_rate_percent <= 100 &&
      var.notification_settings.alert_thresholds.response_time_ms >= 100 &&
      var.notification_settings.alert_thresholds.response_time_ms <= 60000 &&
      var.notification_settings.alert_thresholds.throughput_requests >= 1 &&
      var.notification_settings.alert_thresholds.cost_threshold_dollars >= 0
    )
    error_message = "Alert thresholds must be within valid ranges."
  }
}

# Optional variables for advanced features
variable "enable_data_lake" {
  description = "Enable data lake for long-term analytics storage"
  type        = bool
  default     = false
}

variable "enable_machine_learning" {
  description = "Enable machine learning components for predictive analytics"
  type        = bool
  default     = false
}

variable "enable_real_time_dashboard" {
  description = "Enable real-time dashboard components"
  type        = bool
  default     = false
}

variable "backup_configuration" {
  description = "Backup and disaster recovery configuration"
  type = object({
    enable_cross_region_backup = bool
    backup_retention_days      = number
    enable_automated_backups   = bool
    backup_window_utc         = string
  })
  default = {
    enable_cross_region_backup = false
    backup_retention_days      = 30
    enable_automated_backups   = true
    backup_window_utc         = "03:00-04:00"
  }
  validation {
    condition = (
      var.backup_configuration.backup_retention_days >= 1 &&
      var.backup_configuration.backup_retention_days <= 365 &&
      can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_configuration.backup_window_utc))
    )
    error_message = "Backup configuration must have valid retention days (1-365) and time window format (HH:MM-HH:MM)."
  }
}

# Tags for resource organization
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}