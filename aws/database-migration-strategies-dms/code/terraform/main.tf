# AWS Database Migration Service (DMS) Infrastructure
# This configuration creates a complete DMS setup for database migration
# including replication instances, endpoints, tasks, and monitoring

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment   = var.environment
      Project       = var.project_name
      ManagedBy     = "terraform"
      Owner         = var.owner
      CostCenter    = var.cost_center
      Service       = "DMS"
    }
  }
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# VPC data source
data "aws_vpc" "main" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# Default VPC if none specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Subnet data sources
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  # Prefer database/private subnets if available
  dynamic "filter" {
    for_each = length(var.subnet_ids) == 0 ? [1] : []
    content {
      name   = "tag:Type"
      values = ["database", "Database", "private", "Private"]
    }
  }
}

# Local values for computed resources
locals {
  vpc_id                    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids               = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids
  replication_instance_id  = "${var.project_name}-dms-instance-${var.environment}-${random_id.suffix.hex}"
  subnet_group_id         = "${var.project_name}-dms-subnet-group-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = {
    Name        = var.project_name
    Environment = var.environment
    Service     = "DMS"
  }
}

#############################################
# KMS Key for DMS Encryption
#############################################

resource "aws_kms_key" "dms" {
  count = var.create_kms_key ? 1 : 0
  
  description             = "KMS key for DMS encryption - ${var.project_name}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow DMS service"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dms-kms-key"
  })
}

resource "aws_kms_alias" "dms" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.project_name}-dms-${var.environment}-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.dms[0].key_id
}

#############################################
# S3 Bucket for DMS Logs and Migration Data
#############################################

resource "aws_s3_bucket" "dms_migration_logs" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = "${var.project_name}-dms-logs-${var.environment}-${random_id.suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dms-logs"
  })
}

resource "aws_s3_bucket_versioning" "dms_migration_logs" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.dms_migration_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dms_migration_logs" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.dms_migration_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dms_migration_logs" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.dms_migration_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#############################################
# Security Group for DMS Replication Instance
#############################################

resource "aws_security_group" "dms_replication_instance" {
  name_prefix = "${var.project_name}-dms-replication-"
  vpc_id      = local.vpc_id
  description = "Security group for DMS replication instance"

  # Ingress rules for source database connections
  dynamic "ingress" {
    for_each = var.source_database_ports
    content {
      description = "Access to source database on port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.source_database_cidr_blocks
    }
  }

  # Ingress rules for target database connections
  dynamic "ingress" {
    for_each = var.target_database_ports
    content {
      description = "Access to target database on port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.target_database_cidr_blocks
    }
  }

  # Egress rules - allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dms-replication-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#############################################
# CloudWatch Log Group for DMS
#############################################

resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${local.replication_instance_id}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dms-logs"
  })
}

#############################################
# IAM Roles for DMS
#############################################

# IAM assume role policy document for DMS
data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      identifiers = ["dms.amazonaws.com"]
      type        = "Service"
    }
  }
}

# DMS VPC Role - Required for VPC access
resource "aws_iam_role" "dms_vpc_role" {
  count              = var.create_dms_vpc_role ? 1 : 0
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  description        = "AWS DMS VPC management role"

  tags = merge(local.common_tags, {
    Name = "dms-vpc-role"
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role" {
  count      = var.create_dms_vpc_role ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
  role       = aws_iam_role.dms_vpc_role[0].name
}

# DMS CloudWatch Logs Role - Required for logging
resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  count              = var.create_dms_cloudwatch_logs_role ? 1 : 0
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  description        = "AWS DMS CloudWatch Logs role"

  tags = merge(local.common_tags, {
    Name = "dms-cloudwatch-logs-role"
  })
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role" {
  count      = var.create_dms_cloudwatch_logs_role ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
  role       = aws_iam_role.dms_cloudwatch_logs_role[0].name
}

# DMS Access for Endpoint Role - Required for S3/Kinesis endpoints
resource "aws_iam_role" "dms_access_for_endpoint" {
  count              = var.create_dms_access_for_endpoint_role ? 1 : 0
  name               = "dms-access-for-endpoint"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  description        = "AWS DMS endpoint access role"

  tags = merge(local.common_tags, {
    Name = "dms-access-for-endpoint"
  })
}

# Policy for S3 and KMS access
data "aws_iam_policy_document" "dms_endpoint_access_policy" {
  count = var.create_dms_access_for_endpoint_role ? 1 : 0
  
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListAllMyBuckets"
    ]
    resources = [
      var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].arn : "arn:aws:s3:::${var.s3_bucket_name}",
      var.create_s3_bucket ? "${aws_s3_bucket.dms_migration_logs[0].arn}/*" : "arn:aws:s3:::${var.s3_bucket_name}/*"
    ]
  }

  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*"]
  }
}

resource "aws_iam_role_policy" "dms_endpoint_access_policy" {
  count  = var.create_dms_access_for_endpoint_role ? 1 : 0
  name   = "dms-endpoint-access-policy"
  role   = aws_iam_role.dms_access_for_endpoint[0].id
  policy = data.aws_iam_policy_document.dms_endpoint_access_policy[0].json
}

#############################################
# DMS Replication Subnet Group
#############################################

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_description = var.subnet_group_description
  replication_subnet_group_id          = local.subnet_group_id
  subnet_ids                          = local.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dms-subnet-group"
  })

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_role
  ]
}

#############################################
# DMS Replication Instance
#############################################

resource "aws_dms_replication_instance" "main" {
  allocated_storage            = var.allocated_storage
  apply_immediately            = var.apply_immediately
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  availability_zone            = var.availability_zone
  engine_version               = var.engine_version
  kms_key_arn                  = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
  multi_az                     = var.multi_az
  network_type                 = var.network_type
  preferred_maintenance_window = var.preferred_maintenance_window
  publicly_accessible          = var.publicly_accessible
  replication_instance_class   = var.replication_instance_class
  replication_instance_id      = local.replication_instance_id
  replication_subnet_group_id  = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids       = [aws_security_group.dms_replication_instance.id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dms-replication-instance"
  })

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_role,
    aws_iam_role_policy_attachment.dms_cloudwatch_logs_role,
    aws_cloudwatch_log_group.dms
  ]

  timeouts {
    create = "40m"
    update = "30m"
    delete = "30m"
  }
}

#############################################
# DMS Source Endpoint
#############################################

resource "aws_dms_endpoint" "source" {
  count = var.create_source_endpoint ? 1 : 0
  
  endpoint_id         = "${var.project_name}-source-${var.environment}-${random_id.suffix.hex}"
  endpoint_type       = "source"
  engine_name         = var.source_engine_name
  server_name         = var.source_server_name
  port                = var.source_port
  database_name       = var.source_database_name
  username            = var.source_username
  password            = var.source_password
  ssl_mode            = var.source_ssl_mode
  certificate_arn     = var.source_certificate_arn
  kms_key_arn         = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
  
  # Secrets Manager integration (optional)
  secrets_manager_arn                = var.source_secrets_manager_arn
  secrets_manager_access_role_arn    = var.source_secrets_manager_access_role_arn
  
  extra_connection_attributes = var.source_extra_connection_attributes

  # PostgreSQL specific settings
  dynamic "postgres_settings" {
    for_each = var.source_engine_name == "postgres" || var.source_engine_name == "aurora-postgresql" ? [1] : []
    content {
      database_mode                = var.postgres_database_mode
      ddl_artifacts_schema         = var.postgres_ddl_artifacts_schema
      execute_timeout              = var.postgres_execute_timeout
      fail_tasks_on_lob_truncation = var.postgres_fail_tasks_on_lob_truncation
      heartbeat_enable             = var.postgres_heartbeat_enable
      heartbeat_frequency          = var.postgres_heartbeat_frequency
      heartbeat_schema             = var.postgres_heartbeat_schema
      max_file_size               = var.postgres_max_file_size
      plugin_name                 = var.postgres_plugin_name
      slot_name                   = var.postgres_slot_name
    }
  }

  # MySQL specific settings
  dynamic "mysql_settings" {
    for_each = var.source_engine_name == "mysql" || var.source_engine_name == "aurora" || var.source_engine_name == "mariadb" ? [1] : []
    content {
      after_connect_script    = var.mysql_after_connect_script
      clean_source_metadata_on_mismatch = var.mysql_clean_source_metadata_on_mismatch
      events_poll_interval    = var.mysql_events_poll_interval
      max_file_size          = var.mysql_max_file_size
      parallel_load_threads  = var.mysql_parallel_load_threads
      server_timezone        = var.mysql_server_timezone
      target_db_type         = var.mysql_target_db_type
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-source-endpoint"
    Type = "Source"
  })
}

#############################################
# DMS Target Endpoint  
#############################################

resource "aws_dms_endpoint" "target" {
  count = var.create_target_endpoint ? 1 : 0
  
  endpoint_id         = "${var.project_name}-target-${var.environment}-${random_id.suffix.hex}"
  endpoint_type       = "target"
  engine_name         = var.target_engine_name
  server_name         = var.target_server_name
  port                = var.target_port
  database_name       = var.target_database_name
  username            = var.target_username
  password            = var.target_password
  ssl_mode            = var.target_ssl_mode
  certificate_arn     = var.target_certificate_arn
  kms_key_arn         = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
  
  # Secrets Manager integration (optional)
  secrets_manager_arn                = var.target_secrets_manager_arn
  secrets_manager_access_role_arn    = var.target_secrets_manager_access_role_arn
  
  extra_connection_attributes = var.target_extra_connection_attributes
  
  # S3 specific settings
  dynamic "s3_settings" {
    for_each = var.target_engine_name == "s3" ? [1] : []
    content {
      bucket_name                    = var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].id : var.s3_bucket_name
      bucket_folder                  = var.s3_bucket_folder
      compression_type               = var.s3_compression_type
      csv_delimiter                  = var.s3_csv_delimiter
      csv_row_delimiter             = var.s3_csv_row_delimiter
      data_format                   = var.s3_data_format
      server_side_encryption_kms_key_id = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
      service_access_role_arn       = var.create_dms_access_for_endpoint_role ? aws_iam_role.dms_access_for_endpoint[0].arn : var.existing_dms_access_for_endpoint_role_arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-target-endpoint"
    Type = "Target"
  })
}

#############################################
# DMS Replication Task
#############################################

resource "aws_dms_replication_task" "main" {
  count = var.create_replication_task ? 1 : 0
  
  replication_task_id       = "${var.project_name}-task-${var.environment}-${random_id.suffix.hex}"
  migration_type            = var.migration_type
  replication_instance_arn  = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn       = var.create_source_endpoint ? aws_dms_endpoint.source[0].endpoint_arn : var.existing_source_endpoint_arn
  target_endpoint_arn       = var.create_target_endpoint ? aws_dms_endpoint.target[0].endpoint_arn : var.existing_target_endpoint_arn
  table_mappings            = var.table_mappings
  replication_task_settings = var.replication_task_settings
  
  # CDC settings
  cdc_start_position = var.cdc_start_position
  cdc_start_time     = var.cdc_start_time
  
  start_replication_task = var.start_replication_task

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-replication-task"
  })

  depends_on = [
    aws_dms_replication_instance.main,
    aws_dms_endpoint.source,
    aws_dms_endpoint.target
  ]
}

#############################################
# CloudWatch Metric Alarms for DMS Monitoring
#############################################

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "dms_cpu_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-dms-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors DMS replication instance CPU utilization"
  alarm_actions       = var.alarm_notification_arn != "" ? [var.alarm_notification_arn] : []

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }

  tags = local.common_tags
}

# Freeable Memory Alarm
resource "aws_cloudwatch_metric_alarm" "dms_freeable_memory" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-dms-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "This metric monitors DMS replication instance freeable memory"
  alarm_actions       = var.alarm_notification_arn != "" ? [var.alarm_notification_arn] : []

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }

  tags = local.common_tags
}

# Replication Lag Alarm (only for CDC tasks)
resource "aws_cloudwatch_metric_alarm" "dms_replication_lag" {
  count = var.enable_cloudwatch_alarms && var.migration_type != "full-load" && var.create_replication_task ? 1 : 0
  
  alarm_name          = "${var.project_name}-dms-replication-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CDCLatencySource"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replication_lag_alarm_threshold
  alarm_description   = "This metric monitors DMS replication lag"
  alarm_actions       = var.alarm_notification_arn != "" ? [var.alarm_notification_arn] : []

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
    ReplicationTaskIdentifier     = aws_dms_replication_task.main[0].replication_task_id
  }

  tags = local.common_tags
}