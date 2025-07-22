# main.tf - Multi-AZ Database Deployment Infrastructure

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets across multiple AZs
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Generate random suffix for unique resource names
resource "random_id" "cluster_suffix" {
  byte_length = 3
}

# Generate random password for database master user
resource "random_password" "master_password" {
  length  = 20
  special = true
  
  # Exclude characters that can cause issues with database connections
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store database password in AWS Systems Manager Parameter Store
resource "aws_ssm_parameter" "db_password" {
  name        = "/rds/${local.cluster_identifier}/master-password"
  description = "Master password for Multi-AZ RDS cluster"
  type        = "SecureString"
  value       = random_password.master_password.result
  
  tags = merge(var.default_tags, {
    Name = "${local.cluster_identifier}-master-password"
  })
}

# Store database connection information in Parameter Store
resource "aws_ssm_parameter" "db_username" {
  name        = "/rds/${local.cluster_identifier}/master-username"
  description = "Master username for Multi-AZ RDS cluster"
  type        = "String"
  value       = var.db_master_username
  
  tags = merge(var.default_tags, {
    Name = "${local.cluster_identifier}-master-username"
  })
}

# Local values for consistent naming
locals {
  cluster_identifier = "${var.project_name}-${var.environment}-${random_id.cluster_suffix.hex}"
  
  # Use provided AZs or default to first three available
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Common tags for all resources
  common_tags = merge(var.default_tags, {
    ClusterIdentifier = local.cluster_identifier
    Engine           = var.db_engine
    Environment      = var.environment
  })
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.cluster_identifier}-monitoring-role"
  
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
    Name = "${local.cluster_identifier}-monitoring-role"
  })
}

# Attach AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Security group for RDS cluster
resource "aws_security_group" "rds_cluster" {
  name_prefix = "${local.cluster_identifier}-sg"
  description = "Security group for Multi-AZ RDS cluster"
  vpc_id      = data.aws_vpc.default.id
  
  # Ingress rules for database access
  ingress {
    description = "PostgreSQL access from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
  
  ingress {
    description = "MySQL access from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
  
  # Egress rules
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-security-group"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# DB subnet group spanning multiple AZs
resource "aws_db_subnet_group" "rds_cluster" {
  name       = "${local.cluster_identifier}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-subnet-group"
  })
}

# DB cluster parameter group for optimized settings
resource "aws_rds_cluster_parameter_group" "rds_cluster" {
  family      = var.db_engine == "aurora-postgresql" ? "aurora-postgresql15" : "aurora-mysql8.0"
  name        = "${local.cluster_identifier}-cluster-params"
  description = "Parameter group for Multi-AZ ${var.db_engine} cluster"
  
  # PostgreSQL-specific parameters
  dynamic "parameter" {
    for_each = var.db_engine == "aurora-postgresql" ? [1] : []
    content {
      name  = "log_statement"
      value = "all"
    }
  }
  
  dynamic "parameter" {
    for_each = var.db_engine == "aurora-postgresql" ? [1] : []
    content {
      name  = "log_min_duration_statement"
      value = "1000"
    }
  }
  
  dynamic "parameter" {
    for_each = var.db_engine == "aurora-postgresql" ? [1] : []
    content {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
  }
  
  # MySQL-specific parameters
  dynamic "parameter" {
    for_each = var.db_engine == "aurora-mysql" ? [1] : []
    content {
      name  = "slow_query_log"
      value = "1"
    }
  }
  
  dynamic "parameter" {
    for_each = var.db_engine == "aurora-mysql" ? [1] : []
    content {
      name  = "long_query_time"
      value = "1"
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-cluster-parameter-group"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# KMS key for encryption
resource "aws_kms_key" "rds_encryption" {
  count = var.enable_storage_encryption ? 1 : 0
  
  description             = "KMS key for RDS cluster encryption"
  deletion_window_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-kms-key"
  })
}

resource "aws_kms_alias" "rds_encryption" {
  count = var.enable_storage_encryption ? 1 : 0
  
  name          = "alias/${local.cluster_identifier}-rds-key"
  target_key_id = aws_kms_key.rds_encryption[0].key_id
}

# Multi-AZ RDS Cluster
resource "aws_rds_cluster" "main" {
  cluster_identifier              = local.cluster_identifier
  engine                         = var.db_engine
  engine_version                 = var.db_engine_version
  database_name                  = var.db_name
  master_username                = var.db_master_username
  master_password                = random_password.master_password.result
  
  # Network and security configuration
  availability_zones             = local.availability_zones
  vpc_security_group_ids        = [aws_security_group.rds_cluster.id]
  db_subnet_group_name          = aws_db_subnet_group.rds_cluster.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.rds_cluster.name
  
  # Backup and maintenance configuration
  backup_retention_period       = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  
  # Encryption and security
  storage_encrypted = var.enable_storage_encryption
  kms_key_id       = var.enable_storage_encryption ? aws_kms_key.rds_encryption[0].arn : null
  deletion_protection = var.enable_deletion_protection
  
  # Monitoring and logging
  enabled_cloudwatch_logs_exports = var.cloudwatch_log_exports
  
  # Skip final snapshot for development/testing
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.cluster_identifier}-final-snapshot" : null
  
  tags = merge(local.common_tags, {
    Name = local.cluster_identifier
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring
  ]
}

# Writer (Primary) DB Instance
resource "aws_rds_cluster_instance" "writer" {
  identifier              = "${local.cluster_identifier}-writer"
  cluster_identifier      = aws_rds_cluster.main.id
  instance_class          = var.db_instance_class
  engine                  = aws_rds_cluster.main.engine
  engine_version          = aws_rds_cluster.main.engine_version
  
  # Performance monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id = var.enable_performance_insights && var.enable_storage_encryption ? aws_kms_key.rds_encryption[0].arn : null
  
  # Enhanced monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-writer"
    Role = "writer"
  })
}

# Reader DB Instance 1
resource "aws_rds_cluster_instance" "reader_1" {
  identifier              = "${local.cluster_identifier}-reader-1"
  cluster_identifier      = aws_rds_cluster.main.id
  instance_class          = var.db_instance_class
  engine                  = aws_rds_cluster.main.engine
  engine_version          = aws_rds_cluster.main.engine_version
  
  # Performance monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id = var.enable_performance_insights && var.enable_storage_encryption ? aws_kms_key.rds_encryption[0].arn : null
  
  # Enhanced monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-reader-1"
    Role = "reader"
  })
}

# Reader DB Instance 2
resource "aws_rds_cluster_instance" "reader_2" {
  identifier              = "${local.cluster_identifier}-reader-2"
  cluster_identifier      = aws_rds_cluster.main.id
  instance_class          = var.db_instance_class
  engine                  = aws_rds_cluster.main.engine
  engine_version          = aws_rds_cluster.main.engine_version
  
  # Performance monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id = var.enable_performance_insights && var.enable_storage_encryption ? aws_kms_key.rds_encryption[0].arn : null
  
  # Enhanced monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-reader-2"
    Role = "reader"
  })
}

# Store database endpoints in Parameter Store
resource "aws_ssm_parameter" "writer_endpoint" {
  name        = "/rds/${local.cluster_identifier}/writer-endpoint"
  description = "Writer endpoint for Multi-AZ RDS cluster"
  type        = "String"
  value       = aws_rds_cluster.main.endpoint
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-writer-endpoint"
  })
}

resource "aws_ssm_parameter" "reader_endpoint" {
  name        = "/rds/${local.cluster_identifier}/reader-endpoint"
  description = "Reader endpoint for Multi-AZ RDS cluster"
  type        = "String"
  value       = aws_rds_cluster.main.reader_endpoint
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-reader-endpoint"
  })
}

# SNS topic for database alerts (optional)
resource "aws_sns_topic" "db_alerts" {
  count = var.create_sns_topic ? 1 : 0
  
  name = "${local.cluster_identifier}-alerts"
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-alerts"
  })
}

# SNS topic subscription (if email provided)
resource "aws_sns_topic_subscription" "db_alerts_email" {
  count = var.create_sns_topic && var.sns_endpoint != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.db_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_endpoint
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.cluster_identifier}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_utilization_alarm_threshold
  alarm_description   = "This metric monitors RDS cluster CPU utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.db_alerts[0].arn] : []
  
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-high-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_connections" {
  alarm_name          = "${local.cluster_identifier}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.database_connections_alarm_threshold
  alarm_description   = "This metric monitors RDS cluster database connections"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.db_alerts[0].arn] : []
  
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-high-connections-alarm"
  })
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "rds_monitoring" {
  dashboard_name = "${local.cluster_identifier}-monitoring"
  
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
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "FreeableMemory", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Multi-AZ Cluster Performance Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier],
            [".", "WriteLatency", ".", "."],
            [".", "ReadThroughput", ".", "."],
            [".", "WriteThroughput", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Database I/O Performance"
          period  = 300
        }
      }
    ]
  })
}

# Manual snapshot for baseline (optional)
resource "aws_db_cluster_snapshot" "baseline" {
  count = var.environment == "prod" ? 1 : 0
  
  db_cluster_identifier          = aws_rds_cluster.main.cluster_identifier
  db_cluster_snapshot_identifier = "${local.cluster_identifier}-baseline-snapshot"
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-baseline-snapshot"
    Type = "baseline"
  })
  
  depends_on = [
    aws_rds_cluster_instance.writer,
    aws_rds_cluster_instance.reader_1,
    aws_rds_cluster_instance.reader_2
  ]
}