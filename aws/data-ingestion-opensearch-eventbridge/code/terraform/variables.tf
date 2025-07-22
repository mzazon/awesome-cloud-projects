# Variables for AWS automated data ingestion pipelines infrastructure

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "data-ingestion"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# OpenSearch Domain Configuration
variable "opensearch_domain_name" {
  description = "Name for the OpenSearch domain"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.opensearch_domain_name == "" || can(regex("^[a-z0-9-]+$", var.opensearch_domain_name))
    error_message = "OpenSearch domain name must contain only lowercase letters, numbers, and hyphens, or be empty for auto-generation."
  }
}

variable "opensearch_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.3"
  
  validation {
    condition     = can(regex("^(OpenSearch|Elasticsearch)_[0-9]+\\.[0-9]+$", var.opensearch_version))
    error_message = "Version must be in format 'OpenSearch_X.Y' or 'Elasticsearch_X.Y'."
  }
}

variable "opensearch_instance_type" {
  description = "Instance type for OpenSearch cluster nodes"
  type        = string
  default     = "t3.small.search"
  
  validation {
    condition     = can(regex("\\.(search)$", var.opensearch_instance_type))
    error_message = "Instance type must end with '.search' for OpenSearch domains."
  }
}

variable "opensearch_instance_count" {
  description = "Number of instances in the OpenSearch cluster"
  type        = number
  default     = 1
  
  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 20
    error_message = "Instance count must be between 1 and 20."
  }
}

variable "opensearch_ebs_volume_size" {
  description = "Size of EBS volumes for OpenSearch cluster (in GB)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.opensearch_ebs_volume_size >= 10 && var.opensearch_ebs_volume_size <= 16384
    error_message = "EBS volume size must be between 10 and 16384 GB."
  }
}

variable "opensearch_ebs_volume_type" {
  description = "Type of EBS volumes for OpenSearch cluster"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.opensearch_ebs_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2."
  }
}

# OpenSearch Ingestion Pipeline Configuration
variable "pipeline_name" {
  description = "Name for the OpenSearch Ingestion pipeline"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.pipeline_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.pipeline_name))
    error_message = "Pipeline name must contain only letters, numbers, and hyphens, or be empty for auto-generation."
  }
}

variable "pipeline_min_units" {
  description = "Minimum capacity for the ingestion pipeline (in ICUs)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.pipeline_min_units >= 1 && var.pipeline_min_units <= 96
    error_message = "Pipeline minimum units must be between 1 and 96."
  }
}

variable "pipeline_max_units" {
  description = "Maximum capacity for the ingestion pipeline (in ICUs)"
  type        = number
  default     = 4
  
  validation {
    condition     = var.pipeline_max_units >= 1 && var.pipeline_max_units <= 96
    error_message = "Pipeline maximum units must be between 1 and 96."
  }
}

# S3 Configuration
variable "data_bucket_name" {
  description = "Name for the S3 data bucket"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.data_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.data_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, dots, and hyphens, or be empty for auto-generation."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 data bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which S3 objects expire (0 to disable)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 0 && var.s3_lifecycle_expiration_days <= 3650
    error_message = "S3 lifecycle expiration days must be between 0 and 3650."
  }
}

# EventBridge Scheduler Configuration
variable "schedule_group_name" {
  description = "Name for the EventBridge Scheduler schedule group"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.schedule_group_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.schedule_group_name))
    error_message = "Schedule group name must contain only letters, numbers, hyphens, and underscores, or be empty for auto-generation."
  }
}

variable "pipeline_start_schedule" {
  description = "Cron expression for starting the pipeline (UTC timezone)"
  type        = string
  default     = "cron(0 8 * * ? *)"  # 8 AM UTC daily
  
  validation {
    condition     = can(regex("^(cron|rate)\\(", var.pipeline_start_schedule))
    error_message = "Schedule expression must start with 'cron(' or 'rate('."
  }
}

variable "pipeline_stop_schedule" {
  description = "Cron expression for stopping the pipeline (UTC timezone)"
  type        = string
  default     = "cron(0 18 * * ? *)"  # 6 PM UTC daily
  
  validation {
    condition     = can(regex("^(cron|rate)\\(", var.pipeline_stop_schedule))
    error_message = "Schedule expression must start with 'cron(' or 'rate('."
  }
}

variable "enable_pipeline_scheduling" {
  description = "Enable automatic pipeline start/stop scheduling"
  type        = bool
  default     = true
}

variable "schedule_timezone" {
  description = "Timezone for schedule expressions"
  type        = string
  default     = "UTC"
}

# Monitoring and Logging Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for OpenSearch domain"
  type        = bool
  default     = true
}

variable "log_types" {
  description = "List of log types to enable for OpenSearch domain"
  type        = list(string)
  default     = ["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS", "ES_APPLICATION_LOGS"]
  
  validation {
    condition = alltrue([
      for log_type in var.log_types : contains([
        "INDEX_SLOW_LOGS", 
        "SEARCH_SLOW_LOGS", 
        "ES_APPLICATION_LOGS", 
        "AUDIT_LOGS"
      ], log_type)
    ])
    error_message = "Log types must be from: INDEX_SLOW_LOGS, SEARCH_SLOW_LOGS, ES_APPLICATION_LOGS, AUDIT_LOGS."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Retention period for CloudWatch logs (in days)"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention value."
  }
}

# Security Configuration
variable "opensearch_master_user_name" {
  description = "Master username for OpenSearch domain (leave empty to disable)"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = var.opensearch_master_user_name == "" || length(var.opensearch_master_user_name) >= 1
    error_message = "Master username must be at least 1 character or empty to disable."
  }
}

variable "opensearch_master_user_password" {
  description = "Master password for OpenSearch domain (leave empty to disable)"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = var.opensearch_master_user_password == "" || length(var.opensearch_master_user_password) >= 8
    error_message = "Master password must be at least 8 characters or empty to disable."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access OpenSearch domain"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # WARNING: This allows access from anywhere - restrict in production
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All elements must be valid CIDR blocks."
  }
}

# Data Processing Configuration
variable "data_source_prefixes" {
  description = "List of S3 object key prefixes to include in data processing"
  type        = list(string)
  default     = ["logs/", "metrics/", "events/"]
  
  validation {
    condition     = length(var.data_source_prefixes) > 0
    error_message = "At least one data source prefix must be specified."
  }
}

variable "opensearch_index_template" {
  description = "Index name template for OpenSearch (supports date patterns)"
  type        = string
  default     = "application-logs-%{yyyy.MM.dd}"
  
  validation {
    condition     = length(var.opensearch_index_template) > 0
    error_message = "Index template cannot be empty."
  }
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable spot instances for OpenSearch cluster (where supported)"
  type        = bool
  default     = false
}

variable "delete_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}