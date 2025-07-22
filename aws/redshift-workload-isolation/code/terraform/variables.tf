# General Configuration Variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "analytics-wlm"
}

# Redshift Cluster Configuration
variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster (if using existing cluster, leave empty to create new)"
  type        = string
  default     = ""
}

variable "create_redshift_cluster" {
  description = "Whether to create a new Redshift cluster (set to false if using existing)"
  type        = bool
  default     = true
}

variable "redshift_node_type" {
  description = "Node type for Redshift cluster"
  type        = string
  default     = "ra3.xlplus"
  
  validation {
    condition = contains([
      "dc2.large", "dc2.8xlarge", 
      "ra3.xlplus", "ra3.4xlarge", "ra3.16xlarge"
    ], var.redshift_node_type)
    error_message = "Node type must be a valid Redshift instance type."
  }
}

variable "redshift_cluster_type" {
  description = "Type of Redshift cluster (single-node or multi-node)"
  type        = string
  default     = "single-node"
  
  validation {
    condition     = contains(["single-node", "multi-node"], var.redshift_cluster_type)
    error_message = "Cluster type must be either single-node or multi-node."
  }
}

variable "redshift_number_of_nodes" {
  description = "Number of nodes in the cluster (only used for multi-node clusters)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.redshift_number_of_nodes >= 1 && var.redshift_number_of_nodes <= 128
    error_message = "Number of nodes must be between 1 and 128."
  }
}

variable "redshift_database_name" {
  description = "Name of the initial database in the Redshift cluster"
  type        = string
  default     = "analytics_db"
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster"
  type        = string
  default     = "admin"
}

variable "redshift_port" {
  description = "Port for the Redshift cluster"
  type        = number
  default     = 5439
}

# Networking Configuration
variable "vpc_id" {
  description = "VPC ID where resources will be created (if empty, will use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Redshift subnet group"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to Redshift cluster"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# WLM Configuration
variable "enable_wlm_monitoring" {
  description = "Enable CloudWatch monitoring for WLM queues"
  type        = bool
  default     = true
}

variable "wlm_dashboard_queue_concurrency" {
  description = "Query concurrency for BI dashboard queue"
  type        = number
  default     = 15
  
  validation {
    condition     = var.wlm_dashboard_queue_concurrency >= 1 && var.wlm_dashboard_queue_concurrency <= 50
    error_message = "Dashboard queue concurrency must be between 1 and 50."
  }
}

variable "wlm_analytics_queue_concurrency" {
  description = "Query concurrency for data science analytics queue"
  type        = number
  default     = 3
  
  validation {
    condition     = var.wlm_analytics_queue_concurrency >= 1 && var.wlm_analytics_queue_concurrency <= 50
    error_message = "Analytics queue concurrency must be between 1 and 50."
  }
}

variable "wlm_etl_queue_concurrency" {
  description = "Query concurrency for ETL processing queue"
  type        = number
  default     = 5
  
  validation {
    condition     = var.wlm_etl_queue_concurrency >= 1 && var.wlm_etl_queue_concurrency <= 50
    error_message = "ETL queue concurrency must be between 1 and 50."
  }
}

variable "wlm_dashboard_memory_percent" {
  description = "Memory percentage for BI dashboard queue"
  type        = number
  default     = 25
  
  validation {
    condition     = var.wlm_dashboard_memory_percent >= 1 && var.wlm_dashboard_memory_percent <= 99
    error_message = "Dashboard queue memory percent must be between 1 and 99."
  }
}

variable "wlm_analytics_memory_percent" {
  description = "Memory percentage for data science analytics queue"
  type        = number
  default     = 40
  
  validation {
    condition     = var.wlm_analytics_memory_percent >= 1 && var.wlm_analytics_memory_percent <= 99
    error_message = "Analytics queue memory percent must be between 1 and 99."
  }
}

variable "wlm_etl_memory_percent" {
  description = "Memory percentage for ETL processing queue"
  type        = number
  default     = 25
  
  validation {
    condition     = var.wlm_etl_memory_percent >= 1 && var.wlm_etl_memory_percent <= 99
    error_message = "ETL queue memory percent must be between 1 and 99."
  }
}

# Monitoring and Alerting Configuration
variable "notification_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.cpu_utilization_threshold >= 1 && var.cpu_utilization_threshold <= 100
    error_message = "CPU utilization threshold must be between 1 and 100."
  }
}

variable "queue_length_threshold" {
  description = "Queue length threshold for CloudWatch alarms"
  type        = number
  default     = 5
  
  validation {
    condition     = var.queue_length_threshold >= 1
    error_message = "Queue length threshold must be greater than 0."
  }
}

variable "queries_per_second_threshold" {
  description = "Minimum queries per second threshold for CloudWatch alarms"
  type        = number
  default     = 10
  
  validation {
    condition     = var.queries_per_second_threshold >= 1
    error_message = "Queries per second threshold must be greater than 0."
  }
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption at rest for Redshift cluster"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for Redshift encryption (if empty, uses AWS managed key)"
  type        = string
  default     = ""
}

variable "publicly_accessible" {
  description = "Whether the cluster should be publicly accessible"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip final snapshot when deleting cluster"
  type        = bool
  default     = true
}

# Backup and Maintenance Configuration
variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window for the cluster"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "automated_snapshot_retention_period" {
  description = "Automated snapshot retention period in days"
  type        = number
  default     = 1
  
  validation {
    condition     = var.automated_snapshot_retention_period >= 0 && var.automated_snapshot_retention_period <= 35
    error_message = "Automated snapshot retention period must be between 0 and 35 days."
  }
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}