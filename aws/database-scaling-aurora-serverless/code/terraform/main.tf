# Aurora Serverless v2 Database Scaling Infrastructure
# This configuration creates a complete Aurora Serverless v2 cluster with automatic scaling,
# monitoring, and best-practice security configurations.

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Standardized naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  cluster_id  = "${var.cluster_identifier}-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
      Recipe      = "database-scaling-strategies-aurora-serverless"
    },
    var.additional_tags
  )
}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for existing VPC (if using existing infrastructure)
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

# Data source for existing subnets (if using existing infrastructure)
data "aws_subnets" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [var.existing_vpc_id]
  }
  
  filter {
    name   = "subnet-id"
    values = var.existing_subnet_ids
  }
}

# VPC for Aurora cluster (created only if not using existing VPC)
resource "aws_vpc" "aurora_vpc" {
  count = var.use_existing_vpc ? 0 : 1
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for new VPC
resource "aws_internet_gateway" "aurora_igw" {
  count = var.use_existing_vpc ? 0 : 1
  
  vpc_id = aws_vpc.aurora_vpc[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Private subnets for Aurora cluster (created only if not using existing VPC)
resource "aws_subnet" "aurora_private" {
  count = var.use_existing_vpc ? 0 : length(var.private_subnet_cidrs)
  
  vpc_id            = aws_vpc.aurora_vpc[0].id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Route table for private subnets
resource "aws_route_table" "aurora_private" {
  count = var.use_existing_vpc ? 0 : 1
  
  vpc_id = aws_vpc.aurora_vpc[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "aurora_private" {
  count = var.use_existing_vpc ? 0 : length(aws_subnet.aurora_private)
  
  subnet_id      = aws_subnet.aurora_private[count.index].id
  route_table_id = aws_route_table.aurora_private[0].id
}

# Security group for Aurora Serverless cluster
resource "aws_security_group" "aurora_sg" {
  name_prefix = "${local.name_prefix}-aurora-sg"
  description = "Security group for Aurora Serverless cluster"
  vpc_id      = var.use_existing_vpc ? var.existing_vpc_id : aws_vpc.aurora_vpc[0].id

  # Inbound rule for MySQL/Aurora access
  ingress {
    description = "MySQL/Aurora access from allowed CIDR blocks"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Outbound rule for all traffic (required for Aurora communication)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DB subnet group for Aurora cluster
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name = "${local.cluster_id}-subnet-group"
  description = "Subnet group for Aurora Serverless cluster"
  subnet_ids = var.use_existing_vpc ? var.existing_subnet_ids : aws_subnet.aurora_private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-subnet-group"
  })
}

# Custom DB cluster parameter group for Aurora Serverless optimization
resource "aws_rds_cluster_parameter_group" "aurora_params" {
  family      = "aurora-mysql8.0"
  name        = "${local.cluster_id}-cluster-params"
  description = "Custom parameter group for Aurora Serverless cluster"

  # Optimizations for Aurora Serverless v2
  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-cluster-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Aurora Serverless v2 cluster
resource "aws_rds_cluster" "aurora_serverless" {
  cluster_identifier = local.cluster_id
  engine             = "aurora-mysql"
  engine_version     = var.engine_version
  database_name      = var.database_name
  
  # Master credentials
  master_username = var.master_username
  master_password = var.master_password
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]
  
  # Serverless v2 scaling configuration
  serverlessv2_scaling_configuration {
    max_capacity = var.serverless_max_capacity
    min_capacity = var.serverless_min_capacity
  }
  
  # Backup and maintenance configuration
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  
  # CloudWatch logs configuration
  enabled_cloudwatch_logs_exports = var.enable_cloudwatch_logs ? var.enabled_cloudwatch_logs_exports : []
  
  # Parameter group
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_params.name
  
  # Security and protection settings
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.cluster_id}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  # Storage encryption (always enabled for security)
  storage_encrypted = true
  
  # Apply changes immediately for demo purposes
  apply_immediately = true

  tags = merge(local.common_tags, {
    Name = local.cluster_id
    Type = "Aurora-Serverless-v2"
  })

  depends_on = [
    aws_db_subnet_group.aurora_subnet_group,
    aws_rds_cluster_parameter_group.aurora_params
  ]
}

# Aurora Serverless v2 writer instance
resource "aws_rds_cluster_instance" "aurora_writer" {
  identifier         = "${local.cluster_id}-writer"
  cluster_identifier = aws_rds_cluster.aurora_serverless.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora_serverless.engine
  engine_version     = aws_rds_cluster.aurora_serverless.engine_version
  
  # Performance monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn
  
  # Instance promotion tier for failover
  promotion_tier = 1
  
  # Apply changes immediately
  apply_immediately = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-writer"
    Role = "Writer"
  })

  depends_on = [aws_rds_cluster.aurora_serverless]
}

# Aurora Serverless v2 read replica (optional)
resource "aws_rds_cluster_instance" "aurora_reader" {
  count = var.create_read_replica ? 1 : 0
  
  identifier         = "${local.cluster_id}-reader"
  cluster_identifier = aws_rds_cluster.aurora_serverless.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora_serverless.engine
  engine_version     = aws_rds_cluster.aurora_serverless.engine_version
  
  # Performance monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn
  
  # Instance promotion tier for failover (lower priority than writer)
  promotion_tier = 2
  
  # Apply changes immediately
  apply_immediately = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-reader"
    Role = "Reader"
  })

  depends_on = [
    aws_rds_cluster.aurora_serverless,
    aws_rds_cluster_instance.aurora_writer
  ]
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name_prefix = "${local.name_prefix}-rds-monitoring"
  description = "IAM role for RDS enhanced monitoring"

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
    Name = "${local.name_prefix}-rds-monitoring-role"
  })
}

# Attach AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# SNS topic for CloudWatch alarms (optional)
resource "aws_sns_topic" "aurora_alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_notification_email != null ? 1 : 0
  
  name = "${local.name_prefix}-aurora-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-alerts"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "aurora_email_alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_notification_email != null ? 1 : 0
  
  topic_arn = aws_sns_topic.aurora_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# CloudWatch alarm for high ACU utilization
resource "aws_cloudwatch_metric_alarm" "aurora_high_acu" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.cluster_id}-high-acu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_acu_threshold
  alarm_description   = "This metric monitors Aurora Serverless ACU utilization for scaling alerts"
  alarm_actions       = var.alarm_notification_email != null ? [aws_sns_topic.aurora_alerts[0].arn] : []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_serverless.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-high-acu-alarm"
  })
}

# CloudWatch alarm for low ACU utilization (cost optimization)
resource "aws_cloudwatch_metric_alarm" "aurora_low_acu" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.cluster_id}-low-acu-utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "4"
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/RDS"
  period              = "900"
  statistic           = "Average"
  threshold           = var.low_acu_threshold
  alarm_description   = "This metric monitors Aurora Serverless ACU utilization for cost optimization"
  alarm_actions       = var.alarm_notification_email != null ? [aws_sns_topic.aurora_alerts[0].arn] : []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_serverless.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-low-acu-alarm"
  })
}

# CloudWatch alarm for database connections
resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.cluster_id}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Aurora database connections"
  alarm_actions       = var.alarm_notification_email != null ? [aws_sns_topic.aurora_alerts[0].arn] : []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_serverless.cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-connections-alarm"
  })
}

# CloudWatch Log Group for Aurora error logs (if not automatically created)
resource "aws_cloudwatch_log_group" "aurora_error_log" {
  count = var.enable_cloudwatch_logs && contains(var.enabled_cloudwatch_logs_exports, "error") ? 1 : 0
  
  name              = "/aws/rds/cluster/${local.cluster_id}/error"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-error-logs"
  })
}

# CloudWatch Log Group for Aurora general logs
resource "aws_cloudwatch_log_group" "aurora_general_log" {
  count = var.enable_cloudwatch_logs && contains(var.enabled_cloudwatch_logs_exports, "general") ? 1 : 0
  
  name              = "/aws/rds/cluster/${local.cluster_id}/general"
  retention_in_days = 3

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-general-logs"
  })
}

# CloudWatch Log Group for Aurora slow query logs
resource "aws_cloudwatch_log_group" "aurora_slowquery_log" {
  count = var.enable_cloudwatch_logs && contains(var.enabled_cloudwatch_logs_exports, "slowquery") ? 1 : 0
  
  name              = "/aws/rds/cluster/${local.cluster_id}/slowquery"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-slowquery-logs"
  })
}