# Main Terraform configuration for Database Disaster Recovery with Read Replicas
# This configuration creates a comprehensive disaster recovery setup with automated failover

# Data sources to get current AWS account and region information
data "aws_caller_identity" "current" {}

data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "dr" {
  provider = aws.dr
}

# Random password generator for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Random password for database master user (if not using AWS Secrets Manager)
resource "random_password" "master_password" {
  count   = var.manage_master_user_password ? 0 : 1
  length  = 16
  special = true
}

# ============================================================================
# NETWORKING - Get default VPC and subnets if not provided
# ============================================================================

# Primary region networking
data "aws_vpc" "primary" {
  provider = aws.primary
  id       = var.vpc_id_primary != "" ? var.vpc_id_primary : null
  default  = var.vpc_id_primary == "" ? true : null
}

data "aws_subnets" "primary" {
  provider = aws.primary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.primary.names
  }
}

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

# DR region networking
data "aws_vpc" "dr" {
  provider = aws.dr
  id       = var.vpc_id_dr != "" ? var.vpc_id_dr : null
  default  = var.vpc_id_dr == "" ? true : null
}

data "aws_subnets" "dr" {
  provider = aws.dr
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dr.id]
  }
  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.dr.names
  }
}

data "aws_availability_zones" "dr" {
  provider = aws.dr
  state    = "available"
}

# ============================================================================
# S3 BUCKET FOR CONFIGURATION AND LOGS
# ============================================================================

resource "aws_s3_bucket" "dr_config" {
  provider = aws.primary
  bucket   = var.s3_bucket_name != "" ? var.s3_bucket_name : "dr-config-bucket-${random_id.suffix.hex}"

  tags = merge(var.additional_tags, {
    Name    = "DR Configuration Bucket"
    Purpose = "DisasterRecovery"
  })
}

resource "aws_s3_bucket_versioning" "dr_config" {
  count    = var.enable_s3_versioning ? 1 : 0
  provider = aws.primary
  bucket   = aws_s3_bucket.dr_config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr_config" {
  provider = aws.primary
  bucket   = aws_s3_bucket.dr_config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dr_config" {
  provider = aws.primary
  bucket   = aws_s3_bucket.dr_config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# RDS Enhanced Monitoring Role
resource "aws_iam_role" "rds_monitoring_role" {
  provider = aws.primary
  name     = "rds-monitoring-role-${random_id.suffix.hex}"

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

  tags = merge(var.additional_tags, {
    Name    = "RDS Monitoring Role"
    Purpose = "DisasterRecovery"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_role" {
  provider   = aws.primary
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Lambda Execution Role for DR Coordinator
resource "aws_iam_role" "lambda_execution_role" {
  provider = aws.primary
  name     = "lambda-execution-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name    = "Lambda Execution Role"
    Purpose = "DisasterRecovery"
  })
}

# Lambda policy for disaster recovery operations
resource "aws_iam_role_policy" "lambda_dr_policy" {
  provider = aws.primary
  name     = "lambda-dr-policy"
  role     = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:PromoteReadReplica",
          "rds:ModifyDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.primary_alerts.arn,
          aws_sns_topic.dr_alerts.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/disaster-recovery/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:GetHealthCheck",
          "route53:UpdateHealthCheck"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.dr_config.arn}/*"
      }
    ]
  })
}

# Copy the role to DR region for the replica promoter Lambda
resource "aws_iam_role" "lambda_execution_role_dr" {
  provider = aws.dr
  name     = "lambda-execution-role-dr-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name    = "Lambda Execution Role DR"
    Purpose = "DisasterRecovery"
  })
}

resource "aws_iam_role_policy" "lambda_dr_policy_dr" {
  provider = aws.dr
  name     = "lambda-dr-policy-dr"
  role     = aws_iam_role.lambda_execution_role_dr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:PromoteReadReplica",
          "rds:ModifyDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dr_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/disaster-recovery/*"
      }
    ]
  })
}

# ============================================================================
# DATABASE PARAMETER GROUP (OPTIMIZED FOR REPLICATION)
# ============================================================================

resource "aws_db_parameter_group" "mysql_replication_optimized" {
  count    = var.create_custom_parameter_group ? 1 : 0
  provider = aws.primary
  family   = var.parameter_group_family
  name     = "mysql-replication-optimized-${random_id.suffix.hex}"

  description = "Optimized parameters for cross-region replication"

  parameter {
    name  = "innodb_flush_log_at_trx_commit"
    value = "2"
  }

  parameter {
    name  = "sync_binlog"
    value = "0"
  }

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  tags = merge(var.additional_tags, {
    Name    = "MySQL Replication Optimized"
    Purpose = "DisasterRecovery"
  })
}

# ============================================================================
# DATABASE SUBNET GROUPS
# ============================================================================

resource "aws_db_subnet_group" "primary" {
  provider   = aws.primary
  name       = "dr-subnet-group-primary-${random_id.suffix.hex}"
  subnet_ids = length(var.subnet_ids_primary) > 0 ? var.subnet_ids_primary : data.aws_subnets.primary.ids

  tags = merge(var.additional_tags, {
    Name    = "Primary DB Subnet Group"
    Purpose = "DisasterRecovery"
  })
}

resource "aws_db_subnet_group" "dr" {
  provider   = aws.dr
  name       = "dr-subnet-group-dr-${random_id.suffix.hex}"
  subnet_ids = length(var.subnet_ids_dr) > 0 ? var.subnet_ids_dr : data.aws_subnets.dr.ids

  tags = merge(var.additional_tags, {
    Name    = "DR DB Subnet Group"
    Purpose = "DisasterRecovery"
  })
}

# ============================================================================
# RDS INSTANCES
# ============================================================================

# Primary RDS Database Instance
resource "aws_db_instance" "primary" {
  provider = aws.primary

  # Basic Configuration
  identifier     = "${var.project_name}-primary-${random_id.suffix.hex}"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage Configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = var.storage_encrypted
  kms_key_id           = var.kms_key_id != "" ? var.kms_key_id : null

  # Database Configuration
  db_name  = "primarydb"
  username = var.db_username
  password = var.manage_master_user_password ? null : random_password.master_password[0].result
  
  manage_master_user_password = var.manage_master_user_password

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary_db.id]
  publicly_accessible    = var.publicly_accessible

  # Backup Configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"
  
  # Skip final snapshot for testing (change for production)
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-primary-final-snapshot-${random_id.suffix.hex}"

  # Enhanced Features
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn            = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring_role.arn : null
  performance_insights_enabled   = var.enable_performance_insights
  enabled_cloudwatch_logs_exports = var.enable_cloudwatch_logs_exports

  # Parameter Group
  parameter_group_name = var.create_custom_parameter_group ? aws_db_parameter_group.mysql_replication_optimized[0].name : null

  # Security
  deletion_protection               = var.deletion_protection
  auto_minor_version_upgrade       = var.auto_minor_version_upgrade
  iam_database_authentication_enabled = var.enable_iam_database_authentication

  tags = merge(var.additional_tags, {
    Name    = "Primary Database"
    Purpose = "DisasterRecovery"
    Role    = "Primary"
  })

  # Ensure the monitoring role is created first
  depends_on = [aws_iam_role_policy_attachment.rds_monitoring_role]
}

# Cross-Region Read Replica
resource "aws_db_instance" "read_replica" {
  provider = aws.dr

  # Basic Configuration
  identifier              = "${var.project_name}-replica-${random_id.suffix.hex}"
  replicate_source_db     = aws_db_instance.primary.arn
  instance_class          = var.db_instance_class

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.dr.name
  vpc_security_group_ids = [aws_security_group.dr_db.id]
  publicly_accessible    = var.publicly_accessible

  # Enhanced Features
  monitoring_interval           = var.monitoring_interval
  monitoring_role_arn          = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring_role_dr.arn : null
  performance_insights_enabled = var.enable_performance_insights
  enabled_cloudwatch_logs_exports = var.enable_cloudwatch_logs_exports

  # Security
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  tags = merge(var.additional_tags, {
    Name    = "DR Read Replica"
    Purpose = "DisasterRecovery"
    Role    = "ReadReplica"
  })

  # Ensure dependencies are met
  depends_on = [
    aws_db_instance.primary,
    aws_iam_role_policy_attachment.rds_monitoring_role_dr
  ]
}

# RDS Enhanced Monitoring Role for DR region
resource "aws_iam_role" "rds_monitoring_role_dr" {
  provider = aws.dr
  name     = "rds-monitoring-role-dr-${random_id.suffix.hex}"

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

  tags = merge(var.additional_tags, {
    Name    = "RDS Monitoring Role DR"
    Purpose = "DisasterRecovery"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_role_dr" {
  provider   = aws.dr
  role       = aws_iam_role.rds_monitoring_role_dr.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

# Security group for primary database
resource "aws_security_group" "primary_db" {
  provider    = aws.primary
  name        = "primary-db-sg-${random_id.suffix.hex}"
  description = "Security group for primary RDS database"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "MySQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.additional_tags, {
    Name    = "Primary DB Security Group"
    Purpose = "DisasterRecovery"
  })
}

# Security group for DR database
resource "aws_security_group" "dr_db" {
  provider    = aws.dr
  name        = "dr-db-sg-${random_id.suffix.hex}"
  description = "Security group for DR RDS database"
  vpc_id      = data.aws_vpc.dr.id

  ingress {
    description = "MySQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.dr.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.additional_tags, {
    Name    = "DR DB Security Group"
    Purpose = "DisasterRecovery"
  })
}

# ============================================================================
# SNS TOPICS FOR ALERTING
# ============================================================================

# SNS topic in primary region
resource "aws_sns_topic" "primary_alerts" {
  provider = aws.primary
  name     = "dr-primary-alerts-${random_id.suffix.hex}"

  tags = merge(var.additional_tags, {
    Name    = "Primary Region Alerts"
    Purpose = "DisasterRecovery"
  })
}

# SNS topic in DR region
resource "aws_sns_topic" "dr_alerts" {
  provider = aws.dr
  name     = "dr-failover-alerts-${random_id.suffix.hex}"

  tags = merge(var.additional_tags, {
    Name    = "DR Region Alerts"
    Purpose = "DisasterRecovery"
  })
}

# SNS email subscription (if email provided)
resource "aws_sns_topic_subscription" "primary_email" {
  count    = var.notification_email != "" ? 1 : 0
  provider = aws.primary
  topic_arn = aws_sns_topic.primary_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_subscription" "dr_email" {
  count    = var.notification_email != "" ? 1 : 0
  provider = aws.dr
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# Primary database connection failure alarm
resource "aws_cloudwatch_metric_alarm" "primary_db_connection_failure" {
  provider = aws.primary

  alarm_name          = "${aws_db_instance.primary.identifier}-database-connection-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = var.connection_failure_threshold
  alarm_description   = "This metric monitors database connection failures"
  alarm_actions       = [aws_sns_topic.primary_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = merge(var.additional_tags, {
    Name    = "Primary DB Connection Failure"
    Purpose = "DisasterRecovery"
  })
}

# Primary database CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "primary_db_cpu" {
  provider = aws.primary

  alarm_name          = "${aws_db_instance.primary.identifier}-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors primary database CPU utilization"
  alarm_actions       = [aws_sns_topic.primary_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = merge(var.additional_tags, {
    Name    = "Primary DB High CPU"
    Purpose = "DisasterRecovery"
  })
}

# Read replica lag alarm
resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  provider = aws.dr

  alarm_name          = "${aws_db_instance.read_replica.identifier}-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replica_lag_threshold
  alarm_description   = "This metric monitors read replica lag"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.read_replica.identifier
  }

  tags = merge(var.additional_tags, {
    Name    = "Replica Lag High"
    Purpose = "DisasterRecovery"
  })
}

# DR database CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "dr_db_cpu" {
  provider = aws.dr

  alarm_name          = "${aws_db_instance.read_replica.identifier}-cpu-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors DR database CPU utilization"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.read_replica.identifier
  }

  tags = merge(var.additional_tags, {
    Name    = "DR DB High CPU"
    Purpose = "DisasterRecovery"
  })
}

# ============================================================================
# ROUTE 53 HEALTH CHECKS
# ============================================================================

# Health check for primary database (monitoring CloudWatch alarm)
resource "aws_route53_health_check" "primary_db" {
  count                           = var.create_health_checks ? 1 : 0
  fqdn                           = ""
  port                           = 0
  type                           = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_region        = var.primary_region
  cloudwatch_alarm_name          = aws_cloudwatch_metric_alarm.primary_db_connection_failure.alarm_name
  insufficient_data_health_status = "Failure"

  tags = merge(var.additional_tags, {
    Name    = "Primary DB Health Check"
    Purpose = "DisasterRecovery"
  })
}

# Health check for DR database (monitoring replica lag alarm)
resource "aws_route53_health_check" "dr_db" {
  count                           = var.create_health_checks ? 1 : 0
  fqdn                           = ""
  port                           = 0
  type                           = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_region        = var.dr_region
  cloudwatch_alarm_name          = aws_cloudwatch_metric_alarm.replica_lag.alarm_name
  insufficient_data_health_status = "Success"

  tags = merge(var.additional_tags, {
    Name    = "DR DB Health Check"
    Purpose = "DisasterRecovery"
  })
}

# ============================================================================
# LAMBDA FUNCTIONS FOR DISASTER RECOVERY AUTOMATION
# ============================================================================

# Archive Lambda function code for DR coordinator
data "archive_file" "dr_coordinator_zip" {
  type        = "zip"
  output_path = "/tmp/dr-coordinator.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/dr_coordinator.py", {
      dr_region = var.dr_region
      db_replica_id = aws_db_instance.read_replica.identifier
      dr_sns_arn = aws_sns_topic.dr_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# DR Coordinator Lambda Function
resource "aws_lambda_function" "dr_coordinator" {
  provider = aws.primary

  filename         = data.archive_file.dr_coordinator_zip.output_path
  function_name    = "dr-coordinator-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.dr_coordinator_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = var.lambda_timeout

  environment {
    variables = {
      DR_REGION     = var.dr_region
      DB_REPLICA_ID = aws_db_instance.read_replica.identifier
      DR_SNS_ARN    = aws_sns_topic.dr_alerts.arn
    }
  }

  dynamic "layers" {
    for_each = var.enable_lambda_insights ? ["arn:aws:lambda:${var.primary_region}:580247275435:layer:LambdaInsightsExtension:38"] : []
    content {
      layers = [layers.value]
    }
  }

  tags = merge(var.additional_tags, {
    Name    = "DR Coordinator"
    Purpose = "DisasterRecovery"
  })

  depends_on = [aws_iam_role_policy.lambda_dr_policy]
}

# Archive Lambda function code for replica promoter
data "archive_file" "replica_promoter_zip" {
  type        = "zip"
  output_path = "/tmp/replica-promoter.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/replica_promoter.py", {
      dr_region = var.dr_region
      dr_sns_arn = aws_sns_topic.dr_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Replica Promoter Lambda Function
resource "aws_lambda_function" "replica_promoter" {
  provider = aws.dr

  filename         = data.archive_file.replica_promoter_zip.output_path
  function_name    = "replica-promoter-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_execution_role_dr.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.replica_promoter_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = var.lambda_timeout

  environment {
    variables = {
      DR_REGION  = var.dr_region
      DR_SNS_ARN = aws_sns_topic.dr_alerts.arn
    }
  }

  dynamic "layers" {
    for_each = var.enable_lambda_insights ? ["arn:aws:lambda:${var.dr_region}:580247275435:layer:LambdaInsightsExtension:38"] : []
    content {
      layers = [layers.value]
    }
  }

  tags = merge(var.additional_tags, {
    Name    = "Replica Promoter"
    Purpose = "DisasterRecovery"
  })

  depends_on = [aws_iam_role_policy.lambda_dr_policy_dr]
}

# ============================================================================
# SNS LAMBDA INTEGRATION
# ============================================================================

# SNS subscription for DR coordinator Lambda
resource "aws_sns_topic_subscription" "lambda_coordinator" {
  provider = aws.primary
  topic_arn = aws_sns_topic.primary_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.dr_coordinator.arn
}

# Lambda permission for SNS to invoke DR coordinator
resource "aws_lambda_permission" "allow_sns_coordinator" {
  provider = aws.primary
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_coordinator.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.primary_alerts.arn
}

# ============================================================================
# EVENTBRIDGE RULES FOR RDS EVENT AUTOMATION
# ============================================================================

# EventBridge rule for RDS promotion events
resource "aws_cloudwatch_event_rule" "rds_promotion_events" {
  count    = var.enable_eventbridge_rules ? 1 : 0
  provider = aws.dr
  name        = "rds-promotion-events-${random_id.suffix.hex}"
  description = "Capture RDS promotion events for DR automation"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event"]
    detail = {
      eventName = ["promote-read-replica"]
    }
  })

  tags = merge(var.additional_tags, {
    Name    = "RDS Promotion Events"
    Purpose = "DisasterRecovery"
  })
}

# EventBridge target for replica promoter Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  count    = var.enable_eventbridge_rules ? 1 : 0
  provider = aws.dr
  rule      = aws_cloudwatch_event_rule.rds_promotion_events[0].name
  target_id = "ReplicaPromoterTarget"
  arn       = aws_lambda_function.replica_promoter.arn
}

# Lambda permission for EventBridge to invoke replica promoter
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_eventbridge_rules ? 1 : 0
  provider      = aws.dr
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.replica_promoter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_promotion_events[0].arn
}

# ============================================================================
# SYSTEMS MANAGER PARAMETERS FOR CONFIGURATION
# ============================================================================

# Store disaster recovery configuration in Systems Manager Parameter Store
resource "aws_ssm_parameter" "dr_config" {
  provider = aws.primary
  name     = "/disaster-recovery/configuration"
  type     = "String"
  value = jsonencode({
    primary_region       = var.primary_region
    dr_region           = var.dr_region
    primary_db_id       = aws_db_instance.primary.identifier
    replica_db_id       = aws_db_instance.read_replica.identifier
    primary_endpoint    = aws_db_instance.primary.endpoint
    replica_endpoint    = aws_db_instance.read_replica.endpoint
    s3_bucket          = aws_s3_bucket.dr_config.bucket
    lambda_coordinator = aws_lambda_function.dr_coordinator.function_name
    lambda_promoter    = aws_lambda_function.replica_promoter.function_name
  })

  tags = merge(var.additional_tags, {
    Name    = "DR Configuration"
    Purpose = "DisasterRecovery"
  })
}

# DR status parameter
resource "aws_ssm_parameter" "dr_status" {
  provider = aws.dr
  name     = "/disaster-recovery/failover-status"
  type     = "String"
  value = jsonencode({
    status    = "ready"
    timestamp = timestamp()
  })

  tags = merge(var.additional_tags, {
    Name    = "DR Status"
    Purpose = "DisasterRecovery"
  })
}

# ============================================================================
# DISASTER RECOVERY RUNBOOK STORED IN S3
# ============================================================================

resource "aws_s3_object" "dr_runbook" {
  provider = aws.primary
  bucket = aws_s3_bucket.dr_config.bucket
  key    = "dr-runbook.json"
  content = jsonencode({
    disaster_recovery_runbook = {
      version       = "1.0"
      primary_region = var.primary_region
      dr_region     = var.dr_region
      resources = {
        primary_db       = aws_db_instance.primary.identifier
        replica_db       = aws_db_instance.read_replica.identifier
        sns_primary      = aws_sns_topic.primary_alerts.arn
        sns_dr          = aws_sns_topic.dr_alerts.arn
        lambda_coordinator = aws_lambda_function.dr_coordinator.function_name
        lambda_promoter  = aws_lambda_function.replica_promoter.function_name
        s3_bucket       = aws_s3_bucket.dr_config.bucket
      }
      manual_failover_steps = [
        "1. Verify primary database is truly unavailable",
        "2. Check replica lag is minimal (< 5 minutes)",
        "3. Promote replica using: aws rds promote-read-replica --db-instance-identifier ${aws_db_instance.read_replica.identifier} --region ${var.dr_region}",
        "4. Wait for promotion to complete",
        "5. Update application connection strings",
        "6. Verify application functionality",
        "7. Update DNS records if needed"
      ]
      rollback_steps = [
        "1. Create new read replica from promoted instance",
        "2. Switch applications back to original region",
        "3. Verify data consistency",
        "4. Clean up temporary resources"
      ]
    }
  })
  content_type = "application/json"

  tags = merge(var.additional_tags, {
    Name    = "DR Runbook"
    Purpose = "DisasterRecovery"
  })
}

# Create Lambda function source files
resource "local_file" "dr_coordinator_source" {
  filename = "${path.module}/lambda_functions/dr_coordinator.py"
  content = <<EOF
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Disaster Recovery Coordinator Lambda Function
    Handles primary database failure detection and initiates failover
    """
    
    # Initialize AWS clients
    rds = boto3.client('rds', region_name=os.environ['DR_REGION'])
    sns = boto3.client('sns', region_name=os.environ['DR_REGION'])
    route53 = boto3.client('route53')
    ssm = boto3.client('ssm', region_name=os.environ['DR_REGION'])
    
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Parse CloudWatch alarm from SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message['AlarmName']
        
        logger.info(f"Processing alarm: {alarm_name}")
        
        # Check if this is a database connection failure
        if 'database-connection-failure' in alarm_name:
            # Initiate disaster recovery procedure
            replica_id = os.environ['DB_REPLICA_ID']
            
            logger.info(f"Initiating disaster recovery for replica: {replica_id}")
            
            # Check replica status before promotion
            try:
                replica_response = rds.describe_db_instances(
                    DBInstanceIdentifier=replica_id
                )
                replica_status = replica_response['DBInstances'][0]['DBInstanceStatus']
                
                logger.info(f"Replica status: {replica_status}")
                
                if replica_status == 'available':
                    logger.info(f"Promoting read replica {replica_id} to standalone instance")
                    
                    # Promote read replica
                    rds.promote_read_replica(
                        DBInstanceIdentifier=replica_id
                    )
                    
                    # Update parameter store with failover status
                    ssm.put_parameter(
                        Name='/disaster-recovery/failover-status',
                        Value=json.dumps({
                            'status': 'in-progress',
                            'timestamp': datetime.utcnow().isoformat(),
                            'replica_id': replica_id,
                            'triggered_by': alarm_name
                        }),
                        Type='String',
                        Overwrite=True
                    )
                    
                    # Send success notification
                    sns.publish(
                        TopicArn=os.environ['DR_SNS_ARN'],
                        Subject='Disaster Recovery Initiated',
                        Message=f'''Disaster Recovery Initiated

Primary database failure detected: {alarm_name}
Read replica {replica_id} promotion started.
Monitor for completion.

Timestamp: {datetime.utcnow().isoformat()}
'''
                    )
                    
                    logger.info(f"DR procedure initiated successfully for {replica_id}")
                    
                    return {
                        'statusCode': 200,
                        'body': json.dumps(f'DR procedure initiated for {replica_id}')
                    }
                else:
                    error_msg = f"Replica {replica_id} is not available for promotion: {replica_status}"
                    logger.error(error_msg)
                    
                    sns.publish(
                        TopicArn=os.environ['DR_SNS_ARN'],
                        Subject='Disaster Recovery Failed',
                        Message=f'Replica not ready for promotion: {replica_status}'
                    )
                    
                    return {
                        'statusCode': 400,
                        'body': json.dumps(error_msg)
                    }
                    
            except Exception as e:
                error_msg = f"Error checking replica status: {str(e)}"
                logger.error(error_msg)
                raise e
        else:
            logger.info(f"Alarm {alarm_name} does not trigger DR procedure")
            return {
                'statusCode': 200,
                'body': json.dumps(f'No action required for alarm: {alarm_name}')
            }
        
    except Exception as e:
        error_msg = f"Error in DR coordinator: {str(e)}"
        logger.error(error_msg)
        
        try:
            sns.publish(
                TopicArn=os.environ['DR_SNS_ARN'],
                Subject='Disaster Recovery Error',
                Message=f'Error in DR coordinator: {str(e)}'
            )
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_msg)
        }
EOF
}

resource "local_file" "replica_promoter_source" {
  filename = "${path.module}/lambda_functions/replica_promoter.py"
  content = <<EOF
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Replica Promoter Lambda Function
    Handles post-promotion tasks and DNS updates
    """
    
    # Initialize AWS clients
    rds = boto3.client('rds', region_name=os.environ['DR_REGION'])
    route53 = boto3.client('route53')
    ssm = boto3.client('ssm', region_name=os.environ['DR_REGION'])
    sns = boto3.client('sns', region_name=os.environ['DR_REGION'])
    
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Check if this is a promotion completion event
        if 'source' in event and event['source'] == 'aws.rds':
            detail = event['detail']
            
            if detail.get('eventName') == 'promote-read-replica' and detail.get('responseElements'):
                db_instance_id = detail['responseElements']['dBInstanceIdentifier']
                
                logger.info(f"Processing promotion completion for {db_instance_id}")
                
                # Wait for instance to be available
                try:
                    waiter = rds.get_waiter('db_instance_available')
                    waiter.wait(
                        DBInstanceIdentifier=db_instance_id,
                        WaiterConfig={'Delay': 30, 'MaxAttempts': 20}
                    )
                    
                    logger.info(f"Instance {db_instance_id} is now available")
                    
                    # Get promoted instance details
                    instance_response = rds.describe_db_instances(
                        DBInstanceIdentifier=db_instance_id
                    )
                    instance = instance_response['DBInstances'][0]
                    new_endpoint = instance['Endpoint']['Address']
                    
                    logger.info(f"New endpoint: {new_endpoint}")
                    
                    # Update parameter store
                    ssm.put_parameter(
                        Name='/disaster-recovery/failover-status',
                        Value=json.dumps({
                            'status': 'completed',
                            'timestamp': datetime.utcnow().isoformat(),
                            'new_endpoint': new_endpoint,
                            'db_instance_id': db_instance_id
                        }),
                        Type='String',
                        Overwrite=True
                    )
                    
                    # Send completion notification
                    sns.publish(
                        TopicArn=os.environ['DR_SNS_ARN'],
                        Subject='Disaster Recovery Completed',
                        Message=f'''Disaster Recovery Completed Successfully

New Database Endpoint: {new_endpoint}
Instance ID: {db_instance_id}
Completion Time: {datetime.utcnow().isoformat()}

Please update application configurations to use the new endpoint.

Next Steps:
1. Update application connection strings
2. Verify application functionality
3. Monitor database performance
4. Plan for potential rollback if needed
'''
                    )
                    
                    logger.info("Promotion completion processed successfully")
                    
                    return {
                        'statusCode': 200,
                        'body': json.dumps('Promotion completion processed successfully')
                    }
                    
                except Exception as e:
                    error_msg = f"Error waiting for instance availability: {str(e)}"
                    logger.error(error_msg)
                    raise e
            else:
                logger.info("Event is not a promotion completion")
                return {
                    'statusCode': 200,
                    'body': json.dumps('No action required for this event')
                }
        else:
            logger.info("Event is not from RDS")
            return {
                'statusCode': 200,
                'body': json.dumps('No action required for non-RDS event')
            }
        
    except Exception as e:
        error_msg = f"Error in replica promoter: {str(e)}"
        logger.error(error_msg)
        
        try:
            sns.publish(
                TopicArn=os.environ['DR_SNS_ARN'],
                Subject='Disaster Recovery Error',
                Message=f'Error in replica promoter: {str(e)}'
            )
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_msg)
        }
EOF
}