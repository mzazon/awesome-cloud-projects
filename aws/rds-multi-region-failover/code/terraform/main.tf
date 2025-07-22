# Main Terraform configuration for RDS Multi-AZ Cross-Region Failover
# This creates a production-ready RDS setup with Multi-AZ deployment in primary region
# and cross-region read replica for disaster recovery

# Data sources to fetch current AWS account and region information
data "aws_caller_identity" "current" {}

data "aws_region" "primary" {
  provider = aws
}

data "aws_region" "secondary" {
  provider = aws.secondary
}

# Generate random password for RDS master user
resource "random_password" "db_master_password" {
  length  = 16
  special = true
  
  # Ensure password complexity for financial security requirements
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Store database password securely in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name        = "financial-db-password-${random_id.suffix.hex}"
  description = "Master password for financial RDS database"
  
  replica {
    region = var.secondary_region
  }
  
  tags = {
    Name = "financial-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_master_password.result
}

# === PRIMARY REGION RESOURCES ===

# Security group for RDS instances in primary region
resource "aws_security_group" "rds_primary" {
  name_prefix = "financial-db-primary-"
  vpc_id      = var.primary_vpc_id
  description = "Security group for financial RDS primary database"

  # PostgreSQL access from allowed CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "PostgreSQL access from ${ingress.value}"
    }
  }

  # Allow outbound traffic for replication and backups
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "financial-db-primary-sg"
  }
}

# DB subnet group for primary region
resource "aws_db_subnet_group" "primary" {
  name       = "financial-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = var.primary_subnet_ids
  
  tags = {
    Name = "financial-db-subnet-group-primary"
  }
}

# Custom parameter group for PostgreSQL optimization
resource "aws_db_parameter_group" "financial_db" {
  family      = "postgres15"
  name        = "financial-db-params-${random_id.suffix.hex}"
  description = "Financial DB optimized parameters for high availability"

  # Enable comprehensive logging for audit and troubleshooting
  parameter {
    name  = "log_statement"
    value = "all"
  }

  # Track slow queries for performance monitoring
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Optimize checkpoint timing for better failover performance
  parameter {
    name  = "checkpoint_completion_target"
    value = "0.9"
  }

  # Enable connection logging for security auditing
  parameter {
    name  = "log_connections"
    value = "1"
  }

  # Enable disconnection logging for security auditing
  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "financial-db-parameter-group"
  }
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "financial-rds-monitoring-role-${random_id.suffix.hex}"

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

  tags = {
    Name = "financial-rds-monitoring-role"
  }
}

# Attach the AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Primary Multi-AZ RDS instance
resource "aws_db_instance" "primary" {
  identifier = "financial-db-${random_id.suffix.hex}"
  
  # Engine configuration
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  
  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2  # Allow auto-scaling up to 2x
  storage_type          = "gp3"
  storage_encrypted     = true
  
  # Database configuration
  db_name  = "financialdb"
  username = var.db_master_username
  password = random_password.db_master_password.result
  
  # High availability configuration
  multi_az = true
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.rds_primary.id]
  publicly_accessible    = false
  
  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  copy_tags_to_snapshot  = true
  delete_automated_backups = false
  
  # Maintenance configuration
  maintenance_window         = var.db_maintenance_window
  auto_minor_version_upgrade = true
  
  # Monitoring configuration
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  # Performance Insights configuration
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  
  # Security configuration
  deletion_protection = var.enable_deletion_protection
  
  # Parameter group
  parameter_group_name = aws_db_parameter_group.financial_db.name
  
  # Enable CloudWatch logs exports
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # Ensure proper dependency order
  depends_on = [
    aws_db_subnet_group.primary,
    aws_security_group.rds_primary,
    aws_db_parameter_group.financial_db,
    aws_iam_role_policy_attachment.rds_monitoring
  ]

  tags = {
    Name = "financial-db-primary"
    Role = "primary"
  }
}

# === SECONDARY REGION RESOURCES ===

# Security group for RDS read replica in secondary region
resource "aws_security_group" "rds_secondary" {
  provider = aws.secondary
  
  name_prefix = "financial-db-secondary-"
  vpc_id      = var.secondary_vpc_id
  description = "Security group for financial RDS read replica"

  # PostgreSQL access from allowed CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "PostgreSQL access from ${ingress.value}"
    }
  }

  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "financial-db-secondary-sg"
  }
}

# DB subnet group for secondary region
resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary
  
  name       = "financial-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = var.secondary_subnet_ids
  
  tags = {
    Name = "financial-db-subnet-group-secondary"
  }
}

# IAM role for RDS enhanced monitoring in secondary region
resource "aws_iam_role" "rds_monitoring_secondary" {
  provider = aws.secondary
  
  name = "financial-rds-monitoring-role-${random_id.suffix.hex}"

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

  tags = {
    Name = "financial-rds-monitoring-role-secondary"
  }
}

# Attach the AWS managed policy for RDS enhanced monitoring in secondary region
resource "aws_iam_role_policy_attachment" "rds_monitoring_secondary" {
  provider = aws.secondary
  
  role       = aws_iam_role.rds_monitoring_secondary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Cross-region read replica
resource "aws_db_instance" "replica" {
  provider = aws.secondary
  
  identifier = "financial-db-replica-${random_id.suffix.hex}"
  
  # Replica configuration
  replicate_source_db = aws_db_instance.primary.arn
  
  # Instance configuration
  instance_class = var.db_instance_class
  
  # Storage configuration (inherited from primary but can be overridden)
  storage_encrypted = true
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.rds_secondary.id]
  publicly_accessible    = false
  
  # Monitoring configuration
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring_secondary.arn
  
  # Performance Insights configuration
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  
  # Security configuration
  deletion_protection = var.enable_deletion_protection
  
  # Enable CloudWatch logs exports
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # Ensure proper dependency order
  depends_on = [
    aws_db_instance.primary,
    aws_db_subnet_group.secondary,
    aws_security_group.rds_secondary,
    aws_iam_role_policy_attachment.rds_monitoring_secondary
  ]

  tags = {
    Name = "financial-db-replica"
    Role = "replica"
  }
}

# === AUTOMATED BACKUP REPLICATION ===

# Automated backup replication to secondary region
resource "aws_db_instance_automated_backups_replication" "replica" {
  count = var.enable_automated_backup_replication ? 1 : 0
  
  provider = aws.secondary
  
  source_db_instance_arn = aws_db_instance.primary.arn
  
  # Backup configuration for replication
  backup_retention_period = var.backup_replication_retention_period
  
  depends_on = [aws_db_instance.primary]
}

# === SNS TOPICS FOR NOTIFICATIONS ===

# SNS topic for database alerts in primary region
resource "aws_sns_topic" "db_alerts_primary" {
  name = "financial-db-alerts-primary-${random_id.suffix.hex}"
  
  tags = {
    Name = "financial-db-alerts-primary"
  }
}

# SNS topic for database alerts in secondary region
resource "aws_sns_topic" "db_alerts_secondary" {
  provider = aws.secondary
  
  name = "financial-db-alerts-secondary-${random_id.suffix.hex}"
  
  tags = {
    Name = "financial-db-alerts-secondary"
  }
}

# SNS topic subscription for email notifications (primary)
resource "aws_sns_topic_subscription" "db_alerts_email_primary" {
  count = var.sns_notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.db_alerts_primary.arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# SNS topic subscription for email notifications (secondary)
resource "aws_sns_topic_subscription" "db_alerts_email_secondary" {
  count = var.sns_notification_email != "" ? 1 : 0
  
  provider = aws.secondary
  
  topic_arn = aws_sns_topic.db_alerts_secondary.arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# === CLOUDWATCH ALARMS ===

# CloudWatch alarm for primary database connection failures
resource "aws_cloudwatch_metric_alarm" "primary_connection_failures" {
  alarm_name          = "financial-db-${random_id.suffix.hex}-connection-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.connection_failure_threshold
  alarm_description   = "This metric monitors database connection count"
  alarm_actions       = [aws_sns_topic.db_alerts_primary.arn]
  ok_actions          = [aws_sns_topic.db_alerts_primary.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.id
  }

  tags = {
    Name = "financial-db-connection-failures"
  }
}

# CloudWatch alarm for replica lag
resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  provider = aws.secondary
  
  alarm_name          = "financial-db-${random_id.suffix.hex}-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.replica_lag_threshold
  alarm_description   = "This metric monitors cross-region replica lag"
  alarm_actions       = [aws_sns_topic.db_alerts_secondary.arn]
  ok_actions          = [aws_sns_topic.db_alerts_secondary.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.id
  }

  tags = {
    Name = "financial-db-replica-lag"
  }
}

# CloudWatch alarm for primary database CPU utilization
resource "aws_cloudwatch_metric_alarm" "primary_cpu_utilization" {
  alarm_name          = "financial-db-${random_id.suffix.hex}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors database CPU utilization"
  alarm_actions       = [aws_sns_topic.db_alerts_primary.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.id
  }

  tags = {
    Name = "financial-db-cpu-utilization"
  }
}

# === ROUTE 53 CONFIGURATION ===

# Route 53 private hosted zone for database DNS
resource "aws_route53_zone" "database" {
  name = var.route53_hosted_zone_name
  
  # Create private hosted zone for internal access
  vpc {
    vpc_id = var.primary_vpc_id
  }
  
  # Add secondary region VPC if different
  dynamic "vpc" {
    for_each = var.secondary_vpc_id != var.primary_vpc_id ? [1] : []
    content {
      vpc_id     = var.secondary_vpc_id
      vpc_region = var.secondary_region
    }
  }

  tags = {
    Name = "financial-db-hosted-zone"
  }
}

# Route 53 health check for primary database
resource "aws_route53_health_check" "primary_db" {
  fqdn                            = aws_db_instance.primary.endpoint
  port                            = 5432
  type                            = "TCP"
  request_interval                = "30"
  failure_threshold               = var.health_check_failure_threshold
  cloudwatch_alarm_region         = var.primary_region
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.primary_connection_failures.alarm_name
  insufficient_data_health_status = "Failure"

  tags = {
    Name = "financial-db-primary-health-check"
  }
}

# Primary DNS record with failover routing
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.database.zone_id
  name    = var.dns_record_name
  type    = "CNAME"
  ttl     = var.dns_ttl

  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary_db.id
  records         = [aws_db_instance.primary.endpoint]
}

# Secondary DNS record with failover routing
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.database.zone_id
  name    = var.dns_record_name
  type    = "CNAME"
  ttl     = var.dns_ttl

  set_identifier = "secondary"
  failover_routing_policy {
    type = "SECONDARY"
  }

  records = [aws_db_instance.replica.endpoint]
}

# === IAM ROLES FOR CROSS-REGION PROMOTION ===

# IAM role for Lambda functions to handle promotion
resource "aws_iam_role" "rds_promotion_role" {
  name = "financial-rds-promotion-role-${random_id.suffix.hex}"

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

  tags = {
    Name = "financial-rds-promotion-role"
  }
}

# IAM policy for RDS promotion capabilities
resource "aws_iam_role_policy" "rds_promotion_policy" {
  name = "financial-rds-promotion-policy"
  role = aws_iam_role.rds_promotion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:PromoteReadReplica",
          "rds:DescribeDBInstances",
          "rds:ModifyDBInstance",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:ListResourceRecordSets",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Groups for RDS logs
resource "aws_cloudwatch_log_group" "rds_postgresql_primary" {
  name              = "/aws/rds/instance/${aws_db_instance.primary.id}/postgresql"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = {
    Name = "financial-db-primary-logs"
  }
}

resource "aws_cloudwatch_log_group" "rds_postgresql_secondary" {
  provider = aws.secondary
  
  name              = "/aws/rds/instance/${aws_db_instance.replica.id}/postgresql"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = {
    Name = "financial-db-secondary-logs"
  }
}