# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and tagging
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  common_tags = merge(var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  })
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnets if not specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# KMS key for backup encryption (primary region)
resource "aws_kms_key" "backup_key" {
  description             = "KMS key for RDS backup encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-key-${local.name_suffix}"
  })
}

# KMS key alias for primary region
resource "aws_kms_alias" "backup_key_alias" {
  name          = "alias/${local.name_prefix}-backup-key-${local.name_suffix}"
  target_key_id = aws_kms_key.backup_key.key_id
}

# KMS key for backup encryption (DR region)
resource "aws_kms_key" "dr_backup_key" {
  provider = aws.dr
  
  description             = "KMS key for RDS backup encryption - DR region"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-backup-key-${local.name_suffix}"
  })
}

# KMS key alias for DR region
resource "aws_kms_alias" "dr_backup_key_alias" {
  provider = aws.dr
  
  name          = "alias/${local.name_prefix}-dr-backup-key-${local.name_suffix}"
  target_key_id = aws_kms_key.dr_backup_key.key_id
}

# Security group for RDS instance
resource "aws_security_group" "rds_sg" {
  name_prefix = "${local.name_prefix}-rds-${local.name_suffix}"
  vpc_id      = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  
  description = "Security group for RDS instance"
  
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "MySQL/Aurora"
  }
  
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "PostgreSQL"
  }
  
  ingress {
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SQL Server"
  }
  
  ingress {
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Oracle"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg-${local.name_suffix}"
  })
}

# DB subnet group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${local.name_prefix}-subnet-group-${local.name_suffix}"
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet-group-${local.name_suffix}"
  })
}

# RDS instance with backup configuration
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db-${local.name_suffix}"
  
  # Engine configuration
  engine         = var.db_engine
  engine_version = data.aws_rds_engine_version.main.version
  instance_class = var.db_instance_class
  
  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  storage_type          = var.db_storage_type
  storage_encrypted     = var.enable_storage_encryption
  kms_key_id           = var.enable_storage_encryption ? aws_kms_key.backup_key.arn : null
  
  # Database configuration
  db_name  = var.db_engine == "postgres" ? "postgres" : "mysql"
  username = var.db_username
  password = var.db_password
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  
  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window            = var.backup_window
  maintenance_window       = var.maintenance_window
  copy_tags_to_snapshot    = true
  delete_automated_backups = false
  
  # Security configuration
  deletion_protection = var.enable_deletion_protection
  
  # Monitoring configuration
  enabled_cloudwatch_logs_exports = local.log_exports[var.db_engine]
  monitoring_interval             = 60
  monitoring_role_arn            = aws_iam_role.rds_monitoring.arn
  
  # Performance Insights
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.backup_key.arn
  performance_insights_retention_period = 7
  
  # Final snapshot configuration
  final_snapshot_identifier = "${local.name_prefix}-final-snapshot-${local.name_suffix}"
  skip_final_snapshot       = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-${local.name_suffix}"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring
  ]
}

# Data source for RDS engine version
data "aws_rds_engine_version" "main" {
  engine = var.db_engine
}

# Local values for CloudWatch log exports by engine
locals {
  log_exports = {
    mysql      = ["error", "general", "slow"]
    postgres   = ["postgresql"]
    oracle-ee  = ["alert", "audit", "trace", "listener"]
    oracle-se2 = ["alert", "audit", "trace", "listener"]
    sqlserver-ee = ["error"]
    sqlserver-se = ["error"]
    sqlserver-ex = ["error"]
    sqlserver-web = ["error"]
  }
}

# IAM role for RDS monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-monitoring-role-${local.name_suffix}"
  })
}

# IAM role policy attachment for RDS monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM role for AWS Backup service
resource "aws_iam_role" "backup_role" {
  name = "${local.name_prefix}-backup-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-role-${local.name_suffix}"
  })
}

# IAM role policy attachments for AWS Backup
resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# AWS Backup vault (primary region)
resource "aws_backup_vault" "main" {
  name        = "${local.name_prefix}-backup-vault-${local.name_suffix}"
  kms_key_arn = var.enable_backup_encryption ? aws_kms_key.backup_key.arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-vault-${local.name_suffix}"
  })
}

# AWS Backup vault (DR region)
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  
  name        = "${local.name_prefix}-dr-backup-vault-${local.name_suffix}"
  kms_key_arn = var.enable_backup_encryption ? aws_kms_key.dr_backup_key.arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-backup-vault-${local.name_suffix}"
  })
}

# AWS Backup plan
resource "aws_backup_plan" "main" {
  name = "${local.name_prefix}-backup-plan-${local.name_suffix}"
  
  # Daily backups rule
  rule {
    rule_name         = "DailyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 ? * * *)" # 5 AM UTC daily
    
    start_window_minutes      = 60
    completion_window_minutes = 120
    
    lifecycle {
      cold_storage_after = var.cold_storage_transition_days
      delete_after       = var.daily_backup_retention_days
    }
    
    recovery_point_tags = merge(local.common_tags, {
      BackupType = "Daily"
    })
    
    dynamic "copy_action" {
      for_each = var.enable_cross_region_replication ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.dr.arn
        
        lifecycle {
          delete_after = var.daily_backup_retention_days
        }
      }
    }
  }
  
  # Weekly backups rule
  rule {
    rule_name         = "WeeklyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 ? * SUN *)" # 3 AM UTC every Sunday
    
    start_window_minutes      = 60
    completion_window_minutes = 180
    
    lifecycle {
      cold_storage_after = var.cold_storage_transition_days * 2
      delete_after       = var.weekly_backup_retention_days
    }
    
    recovery_point_tags = merge(local.common_tags, {
      BackupType = "Weekly"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-plan-${local.name_suffix}"
  })
}

# AWS Backup selection
resource "aws_backup_selection" "main" {
  iam_role_arn = aws_iam_role.backup_role.arn
  name         = "${local.name_prefix}-backup-selection-${local.name_suffix}"
  plan_id      = aws_backup_plan.main.id
  
  resources = [
    aws_db_instance.main.arn
  ]
  
  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}

# Cross-region automated backup replication
resource "aws_db_instance_automated_backups_replication" "main" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  provider = aws.dr
  
  source_db_instance_arn = aws_db_instance.main.arn
  kms_key_id            = aws_kms_key.dr_backup_key.arn
  
  depends_on = [aws_db_instance.main]
}

# Manual snapshot for immediate protection
resource "aws_db_snapshot" "manual" {
  db_instance_identifier = aws_db_instance.main.id
  db_snapshot_identifier = "${local.name_prefix}-manual-snapshot-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-manual-snapshot-${local.name_suffix}"
    BackupType = "Manual"
  })
}

# SNS topic for backup notifications
resource "aws_sns_topic" "backup_notifications" {
  count = var.enable_backup_notifications ? 1 : 0
  
  name = "${local.name_prefix}-backup-notifications-${local.name_suffix}"
  
  kms_master_key_id = aws_kms_key.backup_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-notifications-${local.name_suffix}"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "backup_email" {
  count = var.enable_backup_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.backup_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failures" {
  count = var.enable_backup_notifications ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-backup-failures-${local.name_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors failed backup jobs"
  alarm_actions       = var.enable_backup_notifications ? [aws_sns_topic.backup_notifications[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-failures-${local.name_suffix}"
  })
}

# CloudWatch alarm for backup job completion
resource "aws_cloudwatch_metric_alarm" "backup_completion" {
  count = var.enable_backup_notifications ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-backup-completion-${local.name_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsCompleted"
  namespace           = "AWS/Backup"
  period              = "86400" # 24 hours
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors if daily backups are completing"
  alarm_actions       = var.enable_backup_notifications ? [aws_sns_topic.backup_notifications[0].arn] : []
  treat_missing_data  = "breaching"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-completion-${local.name_suffix}"
  })
}

# Backup vault access policy for cross-account sharing
resource "aws_backup_vault_policy" "main" {
  backup_vault_name = aws_backup_vault.main.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "backup:DescribeBackupVault",
          "backup:DescribeRecoveryPoint",
          "backup:ListRecoveryPointsByBackupVault",
          "backup:GetRecoveryPointRestoreMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for RDS logs
resource "aws_cloudwatch_log_group" "rds_logs" {
  for_each = toset(local.log_exports[var.db_engine])
  
  name              = "/aws/rds/instance/${aws_db_instance.main.id}/${each.value}"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.backup_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-logs-${each.value}-${local.name_suffix}"
  })
}