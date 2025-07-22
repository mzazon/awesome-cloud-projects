# AWS Database Migration Service (DMS) Variables
# This file defines all input variables for the DMS infrastructure

#############################################
# General Configuration
#############################################

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project - used for resource naming and tagging"
  type        = string
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 32
    error_message = "Project name must be between 1 and 32 characters."
  }
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing and resource allocation"
  type        = string
  default     = "engineering"
}

#############################################
# VPC and Network Configuration
#############################################

variable "vpc_id" {
  description = "VPC ID where DMS resources will be created. If empty, uses default VPC"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for DMS replication subnet group (minimum 2 subnets in different AZs)"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.subnet_ids) == 0 || length(var.subnet_ids) >= 2
    error_message = "If subnet_ids is provided, must contain at least 2 subnet IDs."
  }
}

variable "subnet_group_description" {
  description = "Description for the DMS replication subnet group"
  type        = string
  default     = "DMS replication subnet group for database migration"
}

#############################################
# Security Group Configuration
#############################################

variable "source_database_ports" {
  description = "List of source database ports to allow access"
  type        = list(number)
  default     = [3306, 5432, 1433, 1521] # MySQL, PostgreSQL, SQL Server, Oracle
}

variable "target_database_ports" {
  description = "List of target database ports to allow access"
  type        = list(number)
  default     = [3306, 5432, 1433, 1521]
}

variable "source_database_cidr_blocks" {
  description = "CIDR blocks for source database access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "target_database_cidr_blocks" {
  description = "CIDR blocks for target database access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

#############################################
# IAM Role Configuration
#############################################

variable "create_dms_vpc_role" {
  description = "Whether to create the dms-vpc-role IAM role (required for VPC access)"
  type        = bool
  default     = true
}

variable "create_dms_cloudwatch_logs_role" {
  description = "Whether to create the dms-cloudwatch-logs-role IAM role (required for logging)"
  type        = bool
  default     = true
}

variable "create_dms_access_for_endpoint_role" {
  description = "Whether to create the dms-access-for-endpoint IAM role (required for S3/Kinesis endpoints)"
  type        = bool
  default     = true
}

variable "existing_dms_access_for_endpoint_role_arn" {
  description = "ARN of existing dms-access-for-endpoint role (used if create_dms_access_for_endpoint_role is false)"
  type        = string
  default     = ""
}

#############################################
# KMS Encryption Configuration
#############################################

variable "create_kms_key" {
  description = "Whether to create a KMS key for DMS encryption"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of existing KMS key for DMS encryption (used if create_kms_key is false)"
  type        = string
  default     = ""
}

variable "kms_deletion_window_in_days" {
  description = "Number of days before the KMS key is deleted (7-30 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

#############################################
# S3 Configuration
#############################################

variable "create_s3_bucket" {
  description = "Whether to create an S3 bucket for DMS logs and migration data"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "Name of existing S3 bucket for migration data (used if create_s3_bucket is false)"
  type        = string
  default     = ""
}

#############################################
# CloudWatch Logs Configuration
#############################################

variable "log_retention_in_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

#############################################
# DMS Replication Instance Configuration
#############################################

variable "allocated_storage" {
  description = "The amount of storage (in gigabytes) to be initially allocated for the replication instance"
  type        = number
  default     = 100
  
  validation {
    condition     = var.allocated_storage >= 5 && var.allocated_storage <= 6144
    error_message = "Allocated storage must be between 5 and 6144 GB."
  }
}

variable "apply_immediately" {
  description = "Indicates whether the changes should be applied immediately or during the next maintenance window"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically during the maintenance window"
  type        = bool
  default     = true
}

variable "availability_zone" {
  description = "The EC2 Availability Zone that the replication instance will be created in (leave empty for automatic)"
  type        = string
  default     = ""
}

variable "engine_version" {
  description = "The engine version number of the replication instance"
  type        = string
  default     = "3.5.3" # Latest stable version as of 2025
}

variable "multi_az" {
  description = "Specifies if the replication instance is a multi-az deployment (recommended for production)"
  type        = bool
  default     = true
}

variable "network_type" {
  description = "The type of IP address protocol used by a replication instance"
  type        = string
  default     = "IPV4"
  
  validation {
    condition     = contains(["IPV4", "DUAL"], var.network_type)
    error_message = "Network type must be either IPV4 or DUAL."
  }
}

variable "preferred_maintenance_window" {
  description = "The weekly time range during which system maintenance can occur (UTC)"
  type        = string
  default     = "sun:03:00-sun:04:00"
  
  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "Maintenance window must be in format: ddd:hh24:mi-ddd:hh24:mi (UTC)."
  }
}

variable "publicly_accessible" {
  description = "Specifies the accessibility options for the replication instance (false recommended for production)"
  type        = bool
  default     = false
}

variable "replication_instance_class" {
  description = "The compute and memory capacity of the replication instance"
  type        = string
  default     = "dms.r6i.large"
  
  validation {
    condition = can(regex("^dms\\.(t3|c5|c6i|r5|r6i)\\.(micro|small|medium|large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge|24xlarge)$", var.replication_instance_class))
    error_message = "Replication instance class must be a valid DMS instance type (t3, c5, c6i, r5, r6i families)."
  }
}

#############################################
# Source Endpoint Configuration
#############################################

variable "create_source_endpoint" {
  description = "Whether to create a source endpoint"
  type        = bool
  default     = true
}

variable "source_engine_name" {
  description = "Type of engine for the source endpoint"
  type        = string
  default     = "postgres"
  
  validation {
    condition = contains([
      "aurora", "aurora-postgresql", "aurora-serverless", "aurora-postgresql-serverless",
      "azuredb", "azure-sql-managed-instance", "babelfish", "db2", "db2-zos", "docdb",
      "mariadb", "mongodb", "mysql", "oracle", "postgres", "sqlserver", "sybase"
    ], var.source_engine_name)
    error_message = "Invalid source engine name. See AWS DMS documentation for supported engines."
  }
}

variable "source_server_name" {
  description = "Host name of the source server"
  type        = string
  default     = ""
}

variable "source_port" {
  description = "Port used by the source endpoint database"
  type        = number
  default     = 5432
  
  validation {
    condition     = var.source_port > 0 && var.source_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "source_database_name" {
  description = "Name of the source endpoint database"
  type        = string
  default     = ""
}

variable "source_username" {
  description = "User name to be used to login to the source endpoint database"
  type        = string
  default     = ""
  sensitive   = true
}

variable "source_password" {
  description = "Password to be used to login to the source endpoint database"
  type        = string
  default     = ""
  sensitive   = true
}

variable "source_ssl_mode" {
  description = "SSL mode to use for the source connection"
  type        = string
  default     = "require"
  
  validation {
    condition     = contains(["none", "require", "verify-ca", "verify-full"], var.source_ssl_mode)
    error_message = "SSL mode must be one of: none, require, verify-ca, verify-full."
  }
}

variable "source_certificate_arn" {
  description = "ARN for the certificate for source endpoint"
  type        = string
  default     = ""
}

variable "source_secrets_manager_arn" {
  description = "Full ARN of the Secrets Manager secret for source endpoint"
  type        = string
  default     = ""
}

variable "source_secrets_manager_access_role_arn" {
  description = "ARN of the IAM role for Secrets Manager access for source endpoint"
  type        = string
  default     = ""
}

variable "source_extra_connection_attributes" {
  description = "Additional attributes associated with the source connection"
  type        = string
  default     = ""
}

variable "existing_source_endpoint_arn" {
  description = "ARN of existing source endpoint (used if create_source_endpoint is false)"
  type        = string
  default     = ""
}

#############################################
# PostgreSQL Specific Source Settings
#############################################

variable "postgres_database_mode" {
  description = "Specifies the default behavior of the replication's handling of PostgreSQL-compatible endpoints"
  type        = string
  default     = "default"
  
  validation {
    condition     = contains(["default", "babelfish"], var.postgres_database_mode)
    error_message = "PostgreSQL database mode must be either 'default' or 'babelfish'."
  }
}

variable "postgres_ddl_artifacts_schema" {
  description = "Sets the schema in which the operational DDL database artifacts are created"
  type        = string
  default     = "public"
}

variable "postgres_execute_timeout" {
  description = "Sets the client statement timeout for the PostgreSQL instance, in seconds"
  type        = number
  default     = 60
}

variable "postgres_fail_tasks_on_lob_truncation" {
  description = "When set to true, this value causes a task to fail if the actual size of a LOB column is greater than the specified LobMaxSize"
  type        = bool
  default     = false
}

variable "postgres_heartbeat_enable" {
  description = "The write-ahead log (WAL) heartbeat feature mimics a dummy transaction"
  type        = bool
  default     = false
}

variable "postgres_heartbeat_frequency" {
  description = "Sets the WAL heartbeat frequency (in minutes)"
  type        = number
  default     = 5
}

variable "postgres_heartbeat_schema" {
  description = "Sets the schema in which the heartbeat artifacts are created"
  type        = string
  default     = "public"
}

variable "postgres_max_file_size" {
  description = "Specifies the maximum size (in KB) of any .csv file used to transfer data to PostgreSQL"
  type        = number
  default     = 32768
}

variable "postgres_plugin_name" {
  description = "Specifies the plugin to use to create a replication slot"
  type        = string
  default     = "pglogical"
  
  validation {
    condition     = contains(["pglogical", "test_decoding"], var.postgres_plugin_name)
    error_message = "Plugin name must be either pglogical or test_decoding."
  }
}

variable "postgres_slot_name" {
  description = "Sets the name of a previously created logical replication slot for a CDC load of the PostgreSQL source instance"
  type        = string
  default     = ""
}

#############################################
# MySQL Specific Source Settings
#############################################

variable "mysql_after_connect_script" {
  description = "Specifies a script to run immediately after DMS connects to the endpoint"
  type        = string
  default     = ""
}

variable "mysql_clean_source_metadata_on_mismatch" {
  description = "Cleans and recreates table metadata information on the replication instance when a mismatch occurs"
  type        = bool
  default     = false
}

variable "mysql_events_poll_interval" {
  description = "Specifies how often to check the binary log for new changes/events when the database is idle"
  type        = number
  default     = 5
}

variable "mysql_max_file_size" {
  description = "Specifies the maximum size (in KB) of any .csv file used to transfer data to MySQL"
  type        = number
  default     = 32768
}

variable "mysql_parallel_load_threads" {
  description = "Improves performance when loading data into MySQL-compatible targets"
  type        = number
  default     = 1
}

variable "mysql_server_timezone" {
  description = "Specifies the time zone for the source MySQL database"
  type        = string
  default     = ""
}

variable "mysql_target_db_type" {
  description = "Specifies where to migrate source tables on the target"
  type        = string
  default     = "specific-database"
}

#############################################
# Target Endpoint Configuration
#############################################

variable "create_target_endpoint" {
  description = "Whether to create a target endpoint"
  type        = bool
  default     = true
}

variable "target_engine_name" {
  description = "Type of engine for the target endpoint"
  type        = string
  default     = "postgres"
  
  validation {
    condition = contains([
      "aurora", "aurora-postgresql", "aurora-serverless", "aurora-postgresql-serverless",
      "azuredb", "azure-sql-managed-instance", "babelfish", "docdb", "dynamodb",
      "elasticsearch", "kafka", "kinesis", "mariadb", "mongodb", "mysql", "neptune",
      "opensearch", "oracle", "postgres", "redshift", "redshift-serverless", "s3", "sqlserver"
    ], var.target_engine_name)
    error_message = "Invalid target engine name. See AWS DMS documentation for supported engines."
  }
}

variable "target_server_name" {
  description = "Host name of the target server"
  type        = string
  default     = ""
}

variable "target_port" {
  description = "Port used by the target endpoint database"
  type        = number
  default     = 5432
  
  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "target_database_name" {
  description = "Name of the target endpoint database"
  type        = string
  default     = ""
}

variable "target_username" {
  description = "User name to be used to login to the target endpoint database"
  type        = string
  default     = ""
  sensitive   = true
}

variable "target_password" {
  description = "Password to be used to login to the target endpoint database"
  type        = string
  default     = ""
  sensitive   = true
}

variable "target_ssl_mode" {
  description = "SSL mode to use for the target connection"
  type        = string
  default     = "require"
  
  validation {
    condition     = contains(["none", "require", "verify-ca", "verify-full"], var.target_ssl_mode)
    error_message = "SSL mode must be one of: none, require, verify-ca, verify-full."
  }
}

variable "target_certificate_arn" {
  description = "ARN for the certificate for target endpoint"
  type        = string
  default     = ""
}

variable "target_secrets_manager_arn" {
  description = "Full ARN of the Secrets Manager secret for target endpoint"
  type        = string
  default     = ""
}

variable "target_secrets_manager_access_role_arn" {
  description = "ARN of the IAM role for Secrets Manager access for target endpoint"
  type        = string
  default     = ""
}

variable "target_extra_connection_attributes" {
  description = "Additional attributes associated with the target connection"
  type        = string
  default     = ""
}

variable "existing_target_endpoint_arn" {
  description = "ARN of existing target endpoint (used if create_target_endpoint is false)"
  type        = string
  default     = ""
}

#############################################
# S3 Target Settings
#############################################

variable "s3_bucket_folder" {
  description = "S3 bucket folder for S3 target endpoint"
  type        = string
  default     = "dms-migration-data"
}

variable "s3_compression_type" {
  description = "Compression type for S3 target"
  type        = string
  default     = "GZIP"
  
  validation {
    condition     = contains(["NONE", "GZIP"], var.s3_compression_type)
    error_message = "S3 compression type must be either NONE or GZIP."
  }
}

variable "s3_csv_delimiter" {
  description = "CSV delimiter for S3 target"
  type        = string
  default     = ","
}

variable "s3_csv_row_delimiter" {
  description = "CSV row delimiter for S3 target"
  type        = string
  default     = "\\n"
}

variable "s3_data_format" {
  description = "Data format for S3 target"
  type        = string
  default     = "csv"
  
  validation {
    condition     = contains(["csv", "parquet"], var.s3_data_format)
    error_message = "S3 data format must be either csv or parquet."
  }
}

#############################################
# Replication Task Configuration
#############################################

variable "create_replication_task" {
  description = "Whether to create a replication task"
  type        = bool
  default     = true
}

variable "migration_type" {
  description = "Migration type for the replication task"
  type        = string
  default     = "full-load-and-cdc"
  
  validation {
    condition     = contains(["full-load", "cdc", "full-load-and-cdc"], var.migration_type)
    error_message = "Migration type must be one of: full-load, cdc, full-load-and-cdc."
  }
}

variable "cdc_start_position" {
  description = "Indicates when you want a change data capture (CDC) operation to start"
  type        = string
  default     = ""
}

variable "cdc_start_time" {
  description = "RFC3339 formatted date string or UNIX timestamp for the start of the Change Data Capture (CDC) operation"
  type        = string
  default     = ""
}

variable "start_replication_task" {
  description = "Whether to run or stop the replication task"
  type        = bool
  default     = false
}

variable "table_mappings" {
  description = "Escaped JSON string that contains the table mappings"
  type        = string
  default     = jsonencode({
    "rules" = [
      {
        "rule-type"   = "selection"
        "rule-id"     = "1"
        "rule-name"   = "1"
        "object-locator" = {
          "schema-name" = "%"
          "table-name"  = "%"
        }
        "rule-action" = "include"
      }
    ]
  })
}

variable "replication_task_settings" {
  description = "Escaped JSON string that contains the task settings"
  type        = string
  default     = jsonencode({
    "TargetMetadata" = {
      "TargetSchema"                 = ""
      "SupportLobs"                  = true
      "FullLobMode"                  = false
      "LobChunkSize"                 = 0
      "LimitedSizeLobMode"           = true
      "LobMaxSize"                   = 32
      "InlineLobMaxSize"             = 0
      "LoadMaxFileSize"              = 0
      "ParallelLoadThreads"          = 0
      "ParallelLoadBufferSize"       = 0
      "BatchApplyEnabled"            = false
      "TaskRecoveryTableEnabled"     = false
      "ParallelApplyThreads"         = 0
      "ParallelApplyBufferSize"      = 0
      "ParallelApplyQueuesPerThread" = 0
    }
    "FullLoadSettings" = {
      "TargetTablePrepMode"                 = "DROP_AND_CREATE"
      "CreatePkAfterFullLoad"               = false
      "StopTaskCachedChangesApplied"        = false
      "StopTaskCachedChangesNotApplied"     = false
      "MaxFullLoadSubTasks"                 = 8
      "TransactionConsistencyTimeout"       = 600
      "CommitRate"                          = 10000
    }
    "Logging" = {
      "EnableLogging" = true
      "LogComponents" = [
        {
          "Id"       = "TRANSFORMATION"
          "Severity" = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          "Id"       = "SOURCE_UNLOAD"
          "Severity" = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          "Id"       = "TARGET_LOAD"
          "Severity" = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          "Id"       = "SOURCE_CAPTURE"
          "Severity" = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          "Id"       = "TARGET_APPLY"
          "Severity" = "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    }
    "ControlTablesSettings" = {
      "historyTimeslotInMinutes"            = 5
      "ControlSchema"                       = ""
      "HistoryTimeslotInMinutes"            = 5
      "HistoryTableEnabled"                 = false
      "SuspendedTablesTableEnabled"         = false
      "StatusTableEnabled"                  = false
      "FullLoadExceptionTableEnabled"       = false
    }
    "StreamBufferSettings" = {
      "StreamBufferCount"      = 3
      "StreamBufferSizeInMB"   = 8
      "CtrlStreamBufferSizeInMB" = 5
    }
    "ChangeProcessingDdlHandlingPolicy" = {
      "HandleSourceTableDropped"   = true
      "HandleSourceTableTruncated" = true
      "HandleSourceTableAltered"   = true
    }
    "ErrorBehavior" = {
      "DataErrorPolicy"                = "LOG_ERROR"
      "DataTruncationErrorPolicy"      = "LOG_ERROR"
      "DataErrorEscalationPolicy"      = "SUSPEND_TABLE"
      "DataErrorEscalationCount"       = 0
      "TableErrorPolicy"               = "SUSPEND_TABLE"
      "TableErrorEscalationPolicy"     = "STOP_TASK"
      "TableErrorEscalationCount"      = 0
      "RecoverableErrorCount"          = -1
      "RecoverableErrorInterval"       = 5
      "RecoverableErrorThrottling"     = true
      "RecoverableErrorThrottlingMax"  = 1800
      "RecoverableErrorStopRetryAfterThrottlingMax" = true
      "ApplyErrorDeletePolicy"         = "IGNORE_RECORD"
      "ApplyErrorInsertPolicy"         = "LOG_ERROR"
      "ApplyErrorUpdatePolicy"         = "LOG_ERROR"
      "ApplyErrorEscalationPolicy"     = "LOG_ERROR"
      "ApplyErrorEscalationCount"      = 0
      "ApplyErrorFailOnTruncationDdl"  = false
      "FullLoadIgnoreConflicts"        = true
      "FailOnTransactionConsistencyBreached" = false
      "FailOnNoTablesCaptured"         = true
    }
    "ChangeProcessingTuning" = {
      "BatchApplyPreserveTransaction" = true
      "BatchApplyTimeoutMin"          = 1
      "BatchApplyTimeoutMax"          = 30
      "BatchApplyMemoryLimit"         = 500
      "BatchSplitSize"                = 0
      "MinTransactionSize"            = 1000
      "CommitTimeout"                 = 1
      "MemoryLimitTotal"              = 1024
      "MemoryKeepTime"                = 60
      "StatementCacheSize"            = 50
    }
    "ValidationSettings" = {
      "EnableValidation"                 = true
      "ValidationMode"                   = "ROW_LEVEL"
      "ThreadCount"                      = 5
      "PartitionSize"                    = 10000
      "FailureMaxCount"                  = 10000
      "RecordFailureDelayInMinutes"      = 5
      "RecordSuspendDelayInMinutes"      = 30
      "MaxKeyColumnSize"                 = 8096
      "TableFailureMaxCount"             = 1000
      "ValidationOnly"                   = false
      "HandleCollationDiff"              = false
      "RecordFailureDelayLimitInMinutes" = 0
      "SkipLobColumns"                   = false
      "ValidationPartialLobSize"         = 0
      "ValidationQueryCdcDelaySeconds"   = 0
    }
    "PostProcessingRules" = null
    "CharacterSetSettings" = null
    "LoopbackPreventionSettings" = null
    "BeforeImageSettings" = null
  })
}

#############################################
# CloudWatch Monitoring Configuration
#############################################

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for DMS monitoring"
  type        = bool
  default     = true
}

variable "alarm_notification_arn" {
  description = "ARN of SNS topic for alarm notifications"
  type        = string
  default     = ""
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 1 and 100."
  }
}

variable "memory_alarm_threshold" {
  description = "Freeable memory threshold for CloudWatch alarm (bytes)"
  type        = number
  default     = 134217728 # 128 MB
}

variable "replication_lag_alarm_threshold" {
  description = "Replication lag threshold for CloudWatch alarm (seconds)"
  type        = number
  default     = 300 # 5 minutes
}