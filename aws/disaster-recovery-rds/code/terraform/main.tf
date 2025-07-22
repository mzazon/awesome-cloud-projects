# Get current AWS account information
data "aws_caller_identity" "current" {}

data "aws_region" "primary" {}

data "aws_region" "secondary" {
  provider = aws.secondary
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique resource names
  replica_name      = "${var.resource_name_prefix}-replica-${random_id.suffix.hex}"
  topic_name        = "${var.resource_name_prefix}-notifications-${random_id.suffix.hex}"
  lambda_name       = "${var.resource_name_prefix}-manager-${random_id.suffix.hex}"
  dashboard_name    = var.dashboard_name != "" ? var.dashboard_name : "${var.resource_name_prefix}-dashboard-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = "RDS Disaster Recovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Get source database information
data "aws_db_instance" "source" {
  db_instance_identifier = var.source_db_identifier
}

# ==============================================================================
# SNS TOPICS FOR NOTIFICATIONS
# ==============================================================================

# Primary region SNS topic
resource "aws_sns_topic" "primary_notifications" {
  name         = local.topic_name
  display_name = "RDS DR Notifications - Primary"
  
  tags = local.common_tags
}

# Secondary region SNS topic
resource "aws_sns_topic" "secondary_notifications" {
  provider     = aws.secondary
  name         = local.topic_name
  display_name = "RDS DR Notifications - Secondary"
  
  tags = local.common_tags
}

# Email subscription for primary topic (if enabled)
resource "aws_sns_topic_subscription" "primary_email" {
  count     = var.enable_email_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.primary_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Email subscription for secondary topic (if enabled)
resource "aws_sns_topic_subscription" "secondary_email" {
  count     = var.enable_email_notifications && var.notification_email != "" ? 1 : 0
  provider  = aws.secondary
  topic_arn = aws_sns_topic.secondary_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# CROSS-REGION READ REPLICA
# ==============================================================================

resource "aws_db_instance" "read_replica" {
  provider = aws.secondary
  
  # Basic configuration
  identifier = local.replica_name
  
  # Replica configuration
  replicate_source_db = data.aws_db_instance.source.arn
  
  # Instance configuration (use source config if not specified)
  instance_class = var.replica_instance_class != null ? var.replica_instance_class : data.aws_db_instance.source.instance_class
  multi_az       = var.replica_multi_az
  
  # Storage configuration
  storage_encrypted = var.replica_storage_encrypted
  
  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window
  
  # Security configuration
  deletion_protection = var.enable_deletion_protection
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.replica_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  # Performance Insights
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  
  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn
  
  # Enable automated backups
  backup_retention_period = var.backup_retention_period
  
  tags = merge(local.common_tags, {
    Name    = local.replica_name
    Purpose = "DisasterRecovery"
    Type    = "ReadReplica"
  })
  
  depends_on = [
    aws_iam_role.rds_enhanced_monitoring
  ]
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# Enhanced monitoring role for RDS
resource "aws_iam_role" "rds_enhanced_monitoring" {
  provider = aws.secondary
  name     = "${local.replica_name}-enhanced-monitoring"
  
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
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  provider   = aws.secondary
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${local.lambda_name}-role"
  
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
  
  tags = local.common_tags
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution" {
  name = "${local.lambda_name}-policy"
  role = aws_iam_role.lambda_execution.id
  
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
          aws_sns_topic.primary_notifications.arn,
          aws_sns_topic.secondary_notifications.arn
        ]
      }
    ]
  })
}

# ==============================================================================
# LAMBDA FUNCTION FOR DISASTER RECOVERY AUTOMATION
# ==============================================================================

# Create Lambda function ZIP file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/dr_manager.zip"
  
  source {
    content = templatefile("${path.module}/dr_manager.py.tpl", {
      primary_topic_arn   = aws_sns_topic.primary_notifications.arn
      secondary_topic_arn = aws_sns_topic.secondary_notifications.arn
    })
    filename = "dr_manager.py"
  }
}

# Lambda function
resource "aws_lambda_function" "dr_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "dr_manager.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      PRIMARY_TOPIC_ARN   = aws_sns_topic.primary_notifications.arn
      SECONDARY_TOPIC_ARN = aws_sns_topic.secondary_notifications.arn
      SOURCE_DB_ID        = var.source_db_identifier
      REPLICA_DB_ID       = local.replica_name
    }
  }
  
  tags = local.common_tags
  
  depends_on = [
    aws_iam_role_policy.lambda_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "lambda_primary" {
  topic_arn = aws_sns_topic.primary_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.dr_manager.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_manager.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.primary_notifications.arn
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

# Primary database CPU alarm
resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  alarm_name          = "${var.source_db_identifier}-HighCPU"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors primary database CPU utilization"
  alarm_actions       = [aws_sns_topic.primary_notifications.arn]
  
  dimensions = {
    DBInstanceIdentifier = var.source_db_identifier
  }
  
  tags = local.common_tags
}

# Replica lag alarm
resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.replica_name}-ReplicaLag"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.replica_lag_threshold
  alarm_description   = "This metric monitors read replica lag"
  alarm_actions       = [aws_sns_topic.secondary_notifications.arn]
  
  dimensions = {
    DBInstanceIdentifier = local.replica_name
  }
  
  tags = local.common_tags
  
  depends_on = [aws_db_instance.read_replica]
}

# Primary database connections alarm
resource "aws_cloudwatch_metric_alarm" "primary_connections" {
  alarm_name          = "${var.source_db_identifier}-DatabaseConnections"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "This metric monitors primary database connections"
  alarm_actions       = [aws_sns_topic.primary_notifications.arn]
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    DBInstanceIdentifier = var.source_db_identifier
  }
  
  tags = local.common_tags
}

# Replica CPU alarm
resource "aws_cloudwatch_metric_alarm" "replica_cpu" {
  provider            = aws.secondary
  alarm_name          = "${local.replica_name}-HighCPU"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors read replica CPU utilization"
  alarm_actions       = [aws_sns_topic.secondary_notifications.arn]
  
  dimensions = {
    DBInstanceIdentifier = local.replica_name
  }
  
  tags = local.common_tags
  
  depends_on = [aws_db_instance.read_replica]
}

# ==============================================================================
# CLOUDWATCH DASHBOARD
# ==============================================================================

resource "aws_cloudwatch_dashboard" "rds_dr" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = local.dashboard_name
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.source_db_identifier, { "region" = var.primary_region }],
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.replica_name, { "region" = var.secondary_region }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.primary_region
          title   = "Database CPU Utilization"
          period  = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", local.replica_name, { "region" = var.secondary_region }]
          ]
          view   = "timeSeries"
          stacked = false
          region = var.secondary_region
          title  = "Read Replica Lag (seconds)"
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.source_db_identifier, { "region" = var.primary_region }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", local.replica_name, { "region" = var.secondary_region }]
          ]
          view   = "timeSeries"
          stacked = false
          region = var.primary_region
          title  = "Database Connections"
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.source_db_identifier, { "region" = var.primary_region }],
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", local.replica_name, { "region" = var.secondary_region }]
          ]
          view   = "timeSeries"
          stacked = false
          region = var.primary_region
          title  = "Read Latency (seconds)"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.source_db_identifier, { "region" = var.primary_region }]
          ]
          view   = "timeSeries"
          stacked = false
          region = var.primary_region
          title  = "Write Latency (seconds)"
          period = 300
        }
      }
    ]
  })
  
  tags = local.common_tags
  
  depends_on = [aws_db_instance.read_replica]
}