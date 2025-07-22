# =============================================================================
# Database Monitoring Dashboards with CloudWatch
# =============================================================================
#
# This Terraform configuration creates:
# - RDS MySQL instance with enhanced monitoring
# - CloudWatch dashboard for database performance metrics
# - CloudWatch alarms for critical thresholds
# - SNS topic for alert notifications
# - IAM role for enhanced monitoring
#
# Based on the recipe: Database Monitoring Dashboards with CloudWatch
# =============================================================================

# Local values for resource naming and configuration
locals {
  # Generate a random suffix for unique resource names
  name_suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = "database-monitoring-dashboards"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Random password for database master user
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get the default VPC for the RDS instance
data "aws_vpc" "default" {
  default = true
}

# Get default VPC subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get the default security group
data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

# =============================================================================
# IAM ROLE FOR ENHANCED MONITORING
# =============================================================================

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "rds-monitoring-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach the AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# RDS DATABASE INSTANCE
# =============================================================================

# RDS MySQL instance with enhanced monitoring and Performance Insights
resource "aws_db_instance" "monitoring_demo" {
  # Basic configuration
  identifier     = "${var.db_instance_identifier}-${local.name_suffix}"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = var.db_storage_type
  storage_encrypted     = var.db_storage_encrypted

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  # Network configuration
  vpc_security_group_ids = [data.aws_security_group.default.id]
  publicly_accessible    = var.db_publicly_accessible

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  copy_tags_to_snapshot  = true

  # Monitoring configuration
  monitoring_interval                   = var.db_monitoring_interval
  monitoring_role_arn                  = aws_iam_role.rds_monitoring_role.arn
  performance_insights_enabled         = var.db_performance_insights_enabled
  performance_insights_retention_period = var.db_performance_insights_retention_period
  enabled_cloudwatch_logs_exports      = var.db_enabled_cloudwatch_logs_exports

  # Maintenance configuration
  maintenance_window         = var.db_maintenance_window
  auto_minor_version_upgrade = var.db_auto_minor_version_upgrade
  apply_immediately         = var.db_apply_immediately

  # Security configuration
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot

  # Tags
  tags = merge(local.common_tags, {
    Name = "${var.db_instance_identifier}-${local.name_suffix}"
  })

  # Ensure the monitoring role is ready before creating the database
  depends_on = [aws_iam_role_policy_attachment.rds_monitoring_policy]
}

# =============================================================================
# SNS TOPIC FOR ALERTS
# =============================================================================

# SNS topic for database alerts
resource "aws_sns_topic" "database_alerts" {
  name = "${var.sns_topic_name}-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.sns_topic_name}-${local.name_suffix}"
  })
}

# SNS topic subscription for email notifications (if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.database_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =============================================================================
# CLOUDWATCH DASHBOARD
# =============================================================================

# Comprehensive CloudWatch dashboard for database monitoring
resource "aws_cloudwatch_dashboard" "database_monitoring" {
  dashboard_name = "${var.dashboard_name}-${local.name_suffix}"

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
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "Database Performance Overview"
          period   = 300
          stat     = "Average"
          yAxis = {
            left = {
              min = 0
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
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "Storage and Latency Metrics"
          period   = 300
          stat     = "Average"
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
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "ReadThroughput", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "WriteThroughput", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "I/O Performance Metrics"
          period   = 300
          stat     = "Average"
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
            ["AWS/RDS", "DBLoad", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "DBLoadCPU", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "DBLoadNonCPU", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "Database Load Metrics"
          period   = 300
          stat     = "Average"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/RDS", "SwapUsage", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "BinLogDiskUsage", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "NetworkReceiveThroughput", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier],
            ["AWS/RDS", "NetworkTransmitThroughput", "DBInstanceIdentifier", aws_db_instance.monitoring_demo.identifier]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "System Resource Metrics"
          period   = 300
          stat     = "Average"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.dashboard_name}-${local.name_suffix}"
  })
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-HighCPU"
  alarm_description   = "High CPU utilization on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_cpu_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = var.alarm_cpu_period
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-HighCPU"
  })
}

# Database Connections Alarm
resource "aws_cloudwatch_metric_alarm" "high_connections" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-HighConnections"
  alarm_description   = "High database connections on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_connections_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = var.alarm_connections_period
  statistic           = "Average"
  threshold           = var.alarm_connections_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-HighConnections"
  })
}

# Free Storage Space Alarm
resource "aws_cloudwatch_metric_alarm" "low_storage" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-LowStorage"
  alarm_description   = "Low free storage space on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_storage_evaluation_periods
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = var.alarm_storage_period
  statistic           = "Average"
  threshold           = var.alarm_storage_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-LowStorage"
  })
}

# Freeable Memory Alarm
resource "aws_cloudwatch_metric_alarm" "low_memory" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-LowMemory"
  alarm_description   = "Low freeable memory on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_memory_evaluation_periods
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = var.alarm_memory_period
  statistic           = "Average"
  threshold           = var.alarm_memory_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-LowMemory"
  })
}

# Database Load Alarm
resource "aws_cloudwatch_metric_alarm" "high_db_load" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-HighDBLoad"
  alarm_description   = "High database load on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_db_load_evaluation_periods
  metric_name         = "DBLoad"
  namespace           = "AWS/RDS"
  period              = var.alarm_db_load_period
  statistic           = "Average"
  threshold           = var.alarm_db_load_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-HighDBLoad"
  })
}

# Read Latency Alarm
resource "aws_cloudwatch_metric_alarm" "high_read_latency" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-HighReadLatency"
  alarm_description   = "High read latency on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_read_latency_evaluation_periods
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = var.alarm_read_latency_period
  statistic           = "Average"
  threshold           = var.alarm_read_latency_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-HighReadLatency"
  })
}

# Write Latency Alarm
resource "aws_cloudwatch_metric_alarm" "high_write_latency" {
  alarm_name          = "${aws_db_instance.monitoring_demo.identifier}-HighWriteLatency"
  alarm_description   = "High write latency on ${aws_db_instance.monitoring_demo.identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_write_latency_evaluation_periods
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = var.alarm_write_latency_period
  statistic           = "Average"
  threshold           = var.alarm_write_latency_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.database_alerts.arn]
  ok_actions          = [aws_sns_topic.database_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.monitoring_demo.identifier
  }

  tags = merge(local.common_tags, {
    Name = "${aws_db_instance.monitoring_demo.identifier}-HighWriteLatency"
  })
}