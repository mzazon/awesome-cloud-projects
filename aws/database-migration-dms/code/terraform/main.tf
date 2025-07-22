# Data sources for existing infrastructure
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get subnets for the VPC
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # VPC and subnet configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids
  
  # Common tags
  common_tags = merge(
    {
      Project     = "DatabaseMigration"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "database-migration-aws-dms"
    },
    var.additional_tags
  )
}

# KMS key for DMS encryption
resource "aws_kms_key" "dms" {
  count = var.enable_kms_encryption && var.kms_key_id == "" ? 1 : 0
  
  description             = "KMS key for DMS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-key-${local.name_suffix}"
  })
}

resource "aws_kms_alias" "dms" {
  count = var.enable_kms_encryption && var.kms_key_id == "" ? 1 : 0
  
  name          = "alias/${local.name_prefix}-dms-${local.name_suffix}"
  target_key_id = aws_kms_key.dms[0].key_id
}

# IAM roles and policies for DMS
data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

# DMS VPC role
resource "aws_iam_role" "dms_vpc_role" {
  count = length(aws_iam_role.dms_vpc_role) == 0 ? 1 : 0
  
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role" {
  count = length(aws_iam_role.dms_vpc_role) > 0 ? 1 : 0
  
  role       = aws_iam_role.dms_vpc_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS CloudWatch logs role
resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  count = length(aws_iam_role.dms_cloudwatch_logs_role) == 0 ? 1 : 0
  
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role" {
  count = length(aws_iam_role.dms_cloudwatch_logs_role) > 0 ? 1 : 0
  
  role       = aws_iam_role.dms_cloudwatch_logs_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# CloudWatch Log Group for DMS
resource "aws_cloudwatch_log_group" "dms" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/dms/tasks/${local.name_prefix}-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  kms_key_id = var.enable_kms_encryption ? (
    var.kms_key_id != "" ? var.kms_key_id : aws_kms_key.dms[0].arn
  ) : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-logs-${local.name_suffix}"
  })
}

# SNS topic for DMS notifications
resource "aws_sns_topic" "dms_notifications" {
  count = var.notification_email != "" ? 1 : 0
  
  name              = "${local.name_prefix}-dms-notifications-${local.name_suffix}"
  kms_master_key_id = var.enable_kms_encryption ? (
    var.kms_key_id != "" ? var.kms_key_id : aws_kms_key.dms[0].arn
  ) : null

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "dms_email" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.dms_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# DMS subnet group
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_description = "DMS subnet group for ${local.name_prefix}"
  replication_subnet_group_id          = "${local.name_prefix}-subnet-group-${local.name_suffix}"
  subnet_ids                           = local.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-subnet-group-${local.name_suffix}"
  })

  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role]
}

# DMS replication instance
resource "aws_dms_replication_instance" "main" {
  replication_instance_id   = "${local.name_prefix}-rep-instance-${local.name_suffix}"
  replication_instance_class = var.replication_instance_class
  
  allocated_storage            = var.allocated_storage
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  multi_az                     = var.multi_az
  publicly_accessible          = var.publicly_accessible
  replication_subnet_group_id  = aws_dms_replication_subnet_group.main.replication_subnet_group_id
  
  kms_key_arn = var.enable_kms_encryption ? (
    var.kms_key_id != "" ? var.kms_key_id : aws_kms_key.dms[0].arn
  ) : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-replication-instance-${local.name_suffix}"
  })

  depends_on = [
    aws_dms_replication_subnet_group.main,
    aws_iam_role_policy_attachment.dms_cloudwatch_logs_role
  ]
}

# Source endpoint
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${local.name_prefix}-source-${local.name_suffix}"
  endpoint_type = "source"
  engine_name   = var.source_engine
  
  server_name   = var.source_server_name
  port          = var.source_port
  database_name = var.source_database_name
  username      = var.source_username
  password      = var.source_password
  ssl_mode      = var.source_ssl_mode

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-source-endpoint-${local.name_suffix}"
    Type = "Source"
  })
}

# Target endpoint
resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${local.name_prefix}-target-${local.name_suffix}"
  endpoint_type = "target"
  engine_name   = var.target_engine
  
  server_name   = var.target_server_name
  port          = var.target_port
  database_name = var.target_database_name
  username      = var.target_username
  password      = var.target_password
  ssl_mode      = var.target_ssl_mode

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-target-endpoint-${local.name_suffix}"
    Type = "Target"
  })
}

# Table mappings configuration
locals {
  table_mappings = jsonencode({
    rules = concat(
      [
        {
          rule-type = "selection"
          rule-id   = "1"
          rule-name = "include-tables"
          object-locator = {
            schema-name = var.schema_name_pattern
            table-name  = var.table_name_pattern
          }
          rule-action = "include"
          filters     = []
        }
      ],
      var.add_table_prefix != "" ? [
        {
          rule-type = "transformation"
          rule-id   = "2"
          rule-name = "add-prefix"
          rule-target = "table"
          object-locator = {
            schema-name = var.schema_name_pattern
            table-name  = var.table_name_pattern
          }
          rule-action = "add-prefix"
          value       = var.add_table_prefix
        }
      ] : []
    )
  })

  # DMS task settings
  task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema                 = ""
      SupportLobs                  = true
      FullLobMode                  = false
      LobChunkSize                 = 0
      LimitedSizeLobMode          = true
      LobMaxSize                   = 32
      InlineLobMaxSize            = 0
      LoadMaxFileSize             = 0
      ParallelLoadThreads         = var.parallel_load_threads
      ParallelLoadBufferSize      = 0
      BatchApplyEnabled           = var.batch_apply_enabled
      TaskRecoveryTableEnabled    = false
      ParallelApplyThreads        = 0
      ParallelApplyBufferSize     = 0
      ParallelApplyQueuesPerThread = 0
    }
    
    FullLoadSettings = {
      TargetTablePrepMode                = var.target_table_prep_mode
      CreatePkAfterFullLoad             = false
      StopTaskCachedChangesApplied      = false
      StopTaskCachedChangesNotApplied   = false
      MaxFullLoadSubTasks               = var.max_full_load_sub_tasks
      TransactionConsistencyTimeout     = 600
      CommitRate                        = 10000
    }
    
    Logging = var.enable_cloudwatch_logs ? {
      EnableLogging = true
      LogComponents = [
        {
          Id       = "SOURCE_UNLOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "TARGET_LOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "SOURCE_CAPTURE"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "TARGET_APPLY"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    } : {
      EnableLogging = false
    }
    
    ControlTablesSettings = {
      ControlSchema               = ""
      HistoryTimeslotInMinutes   = 5
      HistoryTableEnabled        = false
      SuspendedTablesTableEnabled = false
      StatusTableEnabled         = false
    }
    
    StreamBufferSettings = {
      StreamBufferCount       = 3
      StreamBufferSizeInMB   = 8
      CtrlStreamBufferSizeInMB = 5
    }
    
    ChangeProcessingDdlHandlingPolicy = {
      HandleSourceTableDropped    = true
      HandleSourceTableTruncated  = true
      HandleSourceTableAltered    = true
    }
    
    ErrorBehavior = {
      DataErrorPolicy                        = "LOG_ERROR"
      DataTruncationErrorPolicy             = "LOG_ERROR"
      DataErrorEscalationPolicy             = "SUSPEND_TABLE"
      DataErrorEscalationCount              = 0
      TableErrorPolicy                      = "SUSPEND_TABLE"
      TableErrorEscalationPolicy            = "STOP_TASK"
      TableErrorEscalationCount             = 0
      RecoverableErrorCount                 = -1
      RecoverableErrorInterval              = 5
      RecoverableErrorThrottling            = true
      RecoverableErrorThrottlingMax         = 1800
      RecoverableErrorStopRetryAfterThrottlingMax = true
      ApplyErrorDeletePolicy                = "IGNORE_RECORD"
      ApplyErrorInsertPolicy                = "LOG_ERROR"
      ApplyErrorUpdatePolicy                = "LOG_ERROR"
      ApplyErrorEscalationPolicy            = "LOG_ERROR"
      ApplyErrorEscalationCount             = 0
      ApplyErrorFailOnTruncationDdl         = false
      FullLoadIgnoreConflicts               = true
      FailOnTransactionConsistencyBreached  = false
      FailOnNoTablesCaptured                = true
    }
    
    ChangeProcessingTuning = {
      BatchApplyPreserveTransaction = true
      BatchApplyTimeoutMin         = 1
      BatchApplyTimeoutMax         = 30
      BatchApplyMemoryLimit        = 500
      BatchSplitSize               = 0
      MinTransactionSize           = 1000
      CommitTimeout                = 1
      MemoryLimitTotal             = 1024
      MemoryKeepTime               = 60
      StatementCacheSize           = 50
    }
    
    ValidationSettings = var.enable_data_validation ? {
      EnableValidation                = true
      ValidationMode                  = "ROW_LEVEL"
      ThreadCount                     = 5
      PartitionSize                   = 10000
      FailureMaxCount                 = 10000
      RecordFailureDelayInMinutes     = 5
      RecordSuspendDelayInMinutes     = 30
      MaxKeyColumnSize                = 8096
      TableFailureMaxCount            = 1000
      ValidationOnly                  = false
      HandleCollationDiff             = false
      RecordFailureDelayLimitInMinutes = 0
      SkipLobColumns                  = false
      ValidationPartialLobSize        = 0
      ValidationQueryCdcDelaySeconds  = 0
    } : null
    
    PostProcessingRules     = null
    CharacterSetSettings    = null
    LoopbackPreventionSettings = null
    BeforeImageSettings     = null
  })
}

# DMS replication task
resource "aws_dms_replication_task" "main" {
  replication_task_id       = "${local.name_prefix}-migration-task-${local.name_suffix}"
  migration_type            = var.migration_type
  replication_instance_arn  = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.target.endpoint_arn
  
  table_mappings            = local.table_mappings
  replication_task_settings = local.task_settings
  
  start_replication_task    = var.start_replication_task

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-migration-task-${local.name_suffix}"
  })

  depends_on = [
    aws_dms_replication_instance.main,
    aws_dms_endpoint.source,
    aws_dms_endpoint.target,
    aws_cloudwatch_log_group.dms
  ]
}

# DMS event subscription
resource "aws_dms_event_subscription" "main" {
  count = var.notification_email != "" ? 1 : 0
  
  name         = "${local.name_prefix}-dms-events-${local.name_suffix}"
  sns_topic_arn = aws_sns_topic.dms_notifications[0].arn
  
  source_type = "replication-task"
  source_ids  = [aws_dms_replication_task.main.replication_task_id]
  
  event_categories = [
    "failure",
    "creation",
    "deletion",
    "state change"
  ]
  
  enabled = true

  tags = local.common_tags

  depends_on = [aws_sns_topic_subscription.dms_email]
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "dms_task_failure" {
  alarm_name          = "${local.name_prefix}-dms-task-failure-${local.name_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplicationTaskStatus"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors DMS task failure status"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.dms_notifications[0].arn] : []

  dimensions = {
    ReplicationTaskIdentifier = aws_dms_replication_task.main.replication_task_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dms_high_latency" {
  alarm_name          = "${local.name_prefix}-dms-high-latency-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CDCLatencySource"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "300"
  alarm_description   = "This metric monitors DMS replication latency"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.dms_notifications[0].arn] : []

  dimensions = {
    ReplicationTaskIdentifier = aws_dms_replication_task.main.replication_task_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dms_low_memory" {
  alarm_name          = "${local.name_prefix}-dms-low-memory-${local.name_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1073741824" # 1GB in bytes
  alarm_description   = "This metric monitors DMS instance memory usage"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.dms_notifications[0].arn] : []

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }

  tags = local.common_tags
}