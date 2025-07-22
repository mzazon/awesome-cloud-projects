# =============================================================================
# Variables for Database Monitoring Dashboards with CloudWatch
# =============================================================================

# =============================================================================
# GENERAL CONFIGURATION
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "random_suffix" {
  description = "Random suffix for resource names. If empty, a random one will be generated."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# RDS DATABASE CONFIGURATION
# =============================================================================

variable "db_instance_identifier" {
  description = "The name of the RDS instance"
  type        = string
  default     = "monitoring-demo"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.db_instance_identifier))
    error_message = "DB instance identifier must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "db_engine" {
  description = "The database engine"
  type        = string
  default     = "mysql"

  validation {
    condition = contains([
      "mysql", "postgres", "mariadb", "oracle-ee", "oracle-ee-cdb", "oracle-se2",
      "oracle-se2-cdb", "sqlserver-ee", "sqlserver-se", "sqlserver-ex", "sqlserver-web"
    ], var.db_engine)
    error_message = "DB engine must be a valid RDS engine type."
  }
}

variable "db_engine_version" {
  description = "The engine version to use"
  type        = string
  default     = "8.0.35"
}

variable "db_instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.", var.db_instance_class))
    error_message = "DB instance class must start with 'db.'."
  }
}

variable "db_allocated_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_max_allocated_storage" {
  description = "Maximum storage for autoscaling (0 to disable)"
  type        = number
  default     = 100

  validation {
    condition     = var.db_max_allocated_storage >= 0 && var.db_max_allocated_storage <= 65536
    error_message = "Max allocated storage must be between 0 and 65536 GB."
  }
}

variable "db_storage_type" {
  description = "One of 'standard' (magnetic), 'gp2', 'gp3' or 'io1'"
  type        = string
  default     = "gp2"

  validation {
    condition     = contains(["standard", "gp2", "gp3", "io1", "io2"], var.db_storage_type)
    error_message = "Storage type must be standard, gp2, gp3, io1, or io2."
  }
}

variable "db_storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted"
  type        = bool
  default     = true
}

variable "db_name" {
  description = "The name of the database to create when the DB instance is created"
  type        = string
  default     = "monitoringdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "db_username" {
  description = "Username for the master DB user"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_username))
    error_message = "Database username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "db_publicly_accessible" {
  description = "Bool to control if instance is publicly accessible"
  type        = bool
  default     = false
}

# =============================================================================
# RDS BACKUP CONFIGURATION
# =============================================================================

variable "db_backup_retention_period" {
  description = "The days to retain backups for"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "db_backup_window" {
  description = "The daily time range (in UTC) during which automated backups are created"
  type        = string
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.db_backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

# =============================================================================
# RDS MONITORING CONFIGURATION
# =============================================================================

variable "db_monitoring_interval" {
  description = "The interval, in seconds, between points when Enhanced Monitoring metrics are collected"
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.db_monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

variable "db_performance_insights_enabled" {
  description = "Specifies whether Performance Insights are enabled"
  type        = bool
  default     = true
}

variable "db_performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data"
  type        = number
  default     = 7

  validation {
    condition = contains([7, 731], var.db_performance_insights_retention_period) || (
      var.db_performance_insights_retention_period % 31 == 0 &&
      var.db_performance_insights_retention_period >= 31 &&
      var.db_performance_insights_retention_period <= 731
    )
    error_message = "Performance Insights retention period must be 7, 731, or a multiple of 31 between 31 and 731."
  }
}

variable "db_enabled_cloudwatch_logs_exports" {
  description = "Set of log types to enable for exporting to CloudWatch logs"
  type        = list(string)
  default     = ["error", "general", "slow_query"]

  validation {
    condition = alltrue([
      for log_type in var.db_enabled_cloudwatch_logs_exports :
      contains(["error", "general", "slow_query"], log_type)
    ])
    error_message = "For MySQL, valid log types are: error, general, slow_query."
  }
}

# =============================================================================
# RDS MAINTENANCE CONFIGURATION
# =============================================================================

variable "db_maintenance_window" {
  description = "The window to perform maintenance in"
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.db_maintenance_window))
    error_message = "Maintenance window must be in format ddd:hh24:mi-ddd:hh24:mi."
  }
}

variable "db_auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically to the DB instance during the maintenance window"
  type        = bool
  default     = true
}

variable "db_apply_immediately" {
  description = "Specifies whether any database modifications are applied immediately, or during the next maintenance window"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "If the DB instance should have deletion protection enabled"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB instance is deleted"
  type        = bool
  default     = true
}

# =============================================================================
# SNS CONFIGURATION
# =============================================================================

variable "sns_topic_name" {
  description = "Name of the SNS topic for database alerts"
  type        = string
  default     = "database-alerts"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]*$", var.sns_topic_name))
    error_message = "SNS topic name must start with alphanumeric character and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "alert_email" {
  description = "Email address for database alerts (leave empty to skip email subscription)"
  type        = string
  default     = ""

  validation {
    condition = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

# =============================================================================
# CLOUDWATCH DASHBOARD CONFIGURATION
# =============================================================================

variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  type        = string
  default     = "DatabaseMonitoring"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]*$", var.dashboard_name))
    error_message = "Dashboard name must start with alphanumeric character and contain only alphanumeric characters, hyphens, and underscores."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - CPU
# =============================================================================

variable "alarm_cpu_threshold" {
  description = "The value against which the CPU utilization is compared (percentage)"
  type        = number
  default     = 80

  validation {
    condition     = var.alarm_cpu_threshold >= 0 && var.alarm_cpu_threshold <= 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "alarm_cpu_evaluation_periods" {
  description = "The number of periods over which CPU data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_cpu_evaluation_periods >= 1 && var.alarm_cpu_evaluation_periods <= 1440
    error_message = "CPU evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_cpu_period" {
  description = "The period in seconds over which the CPU statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_cpu_period >= 60 && var.alarm_cpu_period % 60 == 0
    error_message = "CPU period must be at least 60 seconds and a multiple of 60."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - DATABASE CONNECTIONS
# =============================================================================

variable "alarm_connections_threshold" {
  description = "The value against which the database connections count is compared"
  type        = number
  default     = 50

  validation {
    condition     = var.alarm_connections_threshold >= 1
    error_message = "Connections threshold must be at least 1."
  }
}

variable "alarm_connections_evaluation_periods" {
  description = "The number of periods over which connections data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_connections_evaluation_periods >= 1 && var.alarm_connections_evaluation_periods <= 1440
    error_message = "Connections evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_connections_period" {
  description = "The period in seconds over which the connections statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_connections_period >= 60 && var.alarm_connections_period % 60 == 0
    error_message = "Connections period must be at least 60 seconds and a multiple of 60."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - STORAGE
# =============================================================================

variable "alarm_storage_threshold" {
  description = "The value against which the free storage space is compared (bytes)"
  type        = number
  default     = 2147483648 # 2 GB in bytes

  validation {
    condition     = var.alarm_storage_threshold >= 0
    error_message = "Storage threshold must be non-negative."
  }
}

variable "alarm_storage_evaluation_periods" {
  description = "The number of periods over which storage data is compared to the specified threshold"
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_storage_evaluation_periods >= 1 && var.alarm_storage_evaluation_periods <= 1440
    error_message = "Storage evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_storage_period" {
  description = "The period in seconds over which the storage statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_storage_period >= 60 && var.alarm_storage_period % 60 == 0
    error_message = "Storage period must be at least 60 seconds and a multiple of 60."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - MEMORY
# =============================================================================

variable "alarm_memory_threshold" {
  description = "The value against which the freeable memory is compared (bytes)"
  type        = number
  default     = 268435456 # 256 MB in bytes

  validation {
    condition     = var.alarm_memory_threshold >= 0
    error_message = "Memory threshold must be non-negative."
  }
}

variable "alarm_memory_evaluation_periods" {
  description = "The number of periods over which memory data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_memory_evaluation_periods >= 1 && var.alarm_memory_evaluation_periods <= 1440
    error_message = "Memory evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_memory_period" {
  description = "The period in seconds over which the memory statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_memory_period >= 60 && var.alarm_memory_period % 60 == 0
    error_message = "Memory period must be at least 60 seconds and a multiple of 60."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - DATABASE LOAD
# =============================================================================

variable "alarm_db_load_threshold" {
  description = "The value against which the database load is compared"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_db_load_threshold >= 0
    error_message = "Database load threshold must be non-negative."
  }
}

variable "alarm_db_load_evaluation_periods" {
  description = "The number of periods over which database load data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_db_load_evaluation_periods >= 1 && var.alarm_db_load_evaluation_periods <= 1440
    error_message = "Database load evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_db_load_period" {
  description = "The period in seconds over which the database load statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_db_load_period >= 60 && var.alarm_db_load_period % 60 == 0
    error_message = "Database load period must be at least 60 seconds and a multiple of 60."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - READ LATENCY
# =============================================================================

variable "alarm_read_latency_threshold" {
  description = "The value against which the read latency is compared (seconds)"
  type        = number
  default     = 0.2

  validation {
    condition     = var.alarm_read_latency_threshold >= 0
    error_message = "Read latency threshold must be non-negative."
  }
}

variable "alarm_read_latency_evaluation_periods" {
  description = "The number of periods over which read latency data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_read_latency_evaluation_periods >= 1 && var.alarm_read_latency_evaluation_periods <= 1440
    error_message = "Read latency evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_read_latency_period" {
  description = "The period in seconds over which the read latency statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_read_latency_period >= 60 && var.alarm_read_latency_period % 60 == 0
    error_message = "Read latency period must be at least 60 seconds and a multiple of 60."
  }
}

# =============================================================================
# CLOUDWATCH ALARMS CONFIGURATION - WRITE LATENCY
# =============================================================================

variable "alarm_write_latency_threshold" {
  description = "The value against which the write latency is compared (seconds)"
  type        = number
  default     = 0.2

  validation {
    condition     = var.alarm_write_latency_threshold >= 0
    error_message = "Write latency threshold must be non-negative."
  }
}

variable "alarm_write_latency_evaluation_periods" {
  description = "The number of periods over which write latency data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_write_latency_evaluation_periods >= 1 && var.alarm_write_latency_evaluation_periods <= 1440
    error_message = "Write latency evaluation periods must be between 1 and 1440."
  }
}

variable "alarm_write_latency_period" {
  description = "The period in seconds over which the write latency statistic is applied"
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_write_latency_period >= 60 && var.alarm_write_latency_period % 60 == 0
    error_message = "Write latency period must be at least 60 seconds and a multiple of 60."
  }
}