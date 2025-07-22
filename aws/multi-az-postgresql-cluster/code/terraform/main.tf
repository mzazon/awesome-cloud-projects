# High Availability PostgreSQL Cluster with Amazon RDS
# This configuration creates a production-ready PostgreSQL cluster with Multi-AZ,
# read replicas, cross-region disaster recovery, and comprehensive monitoring

# Data sources for existing infrastructure
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get VPC information
data "aws_vpc" "selected" {
  id      = var.vpc_id != "" ? var.vpc_id : null
  default = var.vpc_id == "" ? true : null
}

# Get subnet information
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Generate random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Generate secure master password if not provided
resource "random_password" "master_password" {
  count   = var.master_password == null ? 1 : 0
  length  = 16
  special = true
}

# Store database credentials in Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-${var.environment}-credentials-${random_password.suffix.result}"
  description = "PostgreSQL master credentials for RDS cluster"
  
  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password != null ? var.master_password : random_password.master_password[0].result
  })
}

# Create DB subnet group
resource "aws_db_subnet_group" "postgresql" {
  name       = "${var.project_name}-${var.environment}-subnet-group-${random_password.suffix.result}"
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids

  tags = {
    Name = "${var.project_name}-${var.environment}-subnet-group"
  }
}

# Create security group for RDS instances
resource "aws_security_group" "postgresql" {
  name_prefix = "${var.project_name}-${var.environment}-sg-"
  vpc_id      = data.aws_vpc.selected.id
  description = "Security group for PostgreSQL RDS instances"

  # PostgreSQL port access from within VPC
  ingress {
    description = "PostgreSQL access from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Self-referencing rule for internal communication
  ingress {
    description = "PostgreSQL access from security group"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-postgresql-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create custom parameter group for PostgreSQL optimization
resource "aws_db_parameter_group" "postgresql" {
  family = var.parameter_group_family
  name   = "${var.project_name}-${var.environment}-params-${random_password.suffix.result}"
  
  description = "Optimized PostgreSQL parameters for ${var.environment} environment"

  # Apply custom database parameters
  dynamic "parameter" {
    for_each = var.custom_db_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-parameter-group"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

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
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Create primary PostgreSQL instance with Multi-AZ
resource "aws_db_instance" "postgresql_primary" {
  identifier = "${var.project_name}-${var.environment}-primary-${random_password.suffix.result}"

  # Engine configuration
  engine              = "postgres"
  engine_version      = var.engine_version
  instance_class      = var.db_instance_class
  
  # Database configuration
  db_name  = var.db_name
  username = var.master_username
  password = var.master_password != null ? var.master_password : random_password.master_password[0].result

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_encrypted     = var.storage_encrypted
  kms_key_id           = var.kms_key_id != "" ? var.kms_key_id : null

  # High availability configuration
  multi_az = var.multi_az

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids = [aws_security_group.postgresql.id]
  publicly_accessible    = false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.postgresql.name

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window            = var.backup_window
  copy_tags_to_snapshot    = var.copy_tags_to_snapshot
  delete_automated_backups = false

  # Maintenance configuration
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Monitoring configuration
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                  = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  performance_insights_enabled         = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  enabled_cloudwatch_logs_exports      = var.enabled_cloudwatch_logs_exports

  # Security configuration
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = {
    Name = "${var.project_name}-${var.environment}-primary"
    Role = "Primary"
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring
  ]
}

# Create read replica in the same region
resource "aws_db_instance" "postgresql_read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier = "${var.project_name}-${var.environment}-read-replica-${random_password.suffix.result}"

  # Replica configuration
  replicate_source_db = aws_db_instance.postgresql_primary.identifier
  instance_class      = var.read_replica_instance_class

  # Network configuration
  publicly_accessible = false

  # Monitoring configuration
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                  = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  performance_insights_enabled         = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null

  # Security configuration
  skip_final_snapshot = var.skip_final_snapshot

  tags = {
    Name = "${var.project_name}-${var.environment}-read-replica"
    Role = "ReadReplica"
  }

  depends_on = [
    aws_db_instance.postgresql_primary
  ]
}

# Create cross-region read replica for disaster recovery
resource "aws_db_instance" "postgresql_dr_replica" {
  count    = var.create_cross_region_replica ? 1 : 0
  provider = aws.dr_region

  identifier = "${var.project_name}-${var.environment}-dr-replica-${random_password.suffix.result}"

  # Replica configuration
  replicate_source_db = aws_db_instance.postgresql_primary.arn
  instance_class      = var.read_replica_instance_class

  # Network configuration
  publicly_accessible = false

  # Monitoring configuration
  performance_insights_enabled         = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null

  # Security configuration
  skip_final_snapshot = var.skip_final_snapshot

  tags = {
    Name = "${var.project_name}-${var.environment}-dr-replica"
    Role = "DisasterRecoveryReplica"
  }

  depends_on = [
    aws_db_instance.postgresql_primary
  ]
}

# Enable automated backup replication to DR region
resource "aws_db_instance_automated_backups_replication" "postgresql" {
  count = var.create_cross_region_replica ? 1 : 0

  source_db_instance_arn = aws_db_instance.postgresql_primary.arn
  provider              = aws.dr_region

  depends_on = [
    aws_db_instance.postgresql_primary
  ]
}

# SNS topic for database alerts
resource "aws_sns_topic" "postgresql_alerts" {
  name = "${var.project_name}-${var.environment}-alerts-${random_password.suffix.result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-postgresql-alerts"
  }
}

# SNS topic subscription for email alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.postgresql_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.postgresql_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgresql_primary.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cpu-alarm"
  }
}

# CloudWatch alarm for database connections
resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.project_name}-${var.environment}-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.connection_threshold
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = [aws_sns_topic.postgresql_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgresql_primary.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-connections-alarm"
  }
}

# CloudWatch alarm for read replica lag
resource "aws_cloudwatch_metric_alarm" "replica_lag_high" {
  count = var.create_read_replica ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replica_lag_threshold
  alarm_description   = "This metric monitors read replica lag"
  alarm_actions       = [aws_sns_topic.postgresql_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgresql_read_replica[0].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-replica-lag-alarm"
  }
}

# RDS event subscription for operational notifications
resource "aws_db_event_subscription" "postgresql_events" {
  name      = "${var.project_name}-${var.environment}-events"
  sns_topic = aws_sns_topic.postgresql_alerts.arn

  source_type = "db-instance"
  source_ids  = concat(
    [aws_db_instance.postgresql_primary.id],
    var.create_read_replica ? [aws_db_instance.postgresql_read_replica[0].id] : []
  )

  event_categories = [
    "availability",
    "backup",
    "configuration change",
    "creation",
    "deletion",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "notification",
    "recovery",
    "restoration"
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-event-subscription"
  }
}

# IAM role for RDS Proxy
resource "aws_iam_role" "rds_proxy" {
  count = var.create_rds_proxy ? 1 : 0

  name = "${var.project_name}-${var.environment}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-proxy-role"
  }
}

# IAM policy for RDS Proxy to access Secrets Manager
resource "aws_iam_role_policy" "rds_proxy_secrets" {
  count = var.create_rds_proxy ? 1 : 0

  name = "${var.project_name}-${var.environment}-rds-proxy-secrets-policy"
  role = aws_iam_role.rds_proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

# RDS Proxy for connection pooling
resource "aws_db_proxy" "postgresql" {
  count = var.create_rds_proxy ? 1 : 0

  name                   = "${var.project_name}-${var.environment}-proxy"
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = var.proxy_idle_client_timeout
  require_tls            = true
  role_arn              = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids        = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids
  vpc_security_group_ids = [aws_security_group.postgresql.id]

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-proxy"
  }

  depends_on = [
    aws_iam_role_policy.rds_proxy_secrets
  ]
}

# RDS Proxy target group
resource "aws_db_proxy_default_target_group" "postgresql" {
  count = var.create_rds_proxy ? 1 : 0

  db_proxy_name = aws_db_proxy.postgresql[0].name

  connection_pool_config {
    max_connections_percent      = var.proxy_max_connections_percent
    max_idle_connections_percent = 50
    session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
  }
}

# RDS Proxy target
resource "aws_db_proxy_target" "postgresql" {
  count = var.create_rds_proxy ? 1 : 0

  db_instance_identifier = aws_db_instance.postgresql_primary.id
  db_proxy_name          = aws_db_proxy.postgresql[0].name
  target_group_name      = aws_db_proxy_default_target_group.postgresql[0].name
}

# Create manual snapshot for baseline backup
resource "aws_db_snapshot" "initial_snapshot" {
  db_instance_identifier = aws_db_instance.postgresql_primary.id
  db_snapshot_identifier = "${var.project_name}-${var.environment}-initial-snapshot-${formatdate("YYYY-MM-DD", timestamp())}"

  tags = {
    Name = "${var.project_name}-${var.environment}-initial-snapshot"
    Type = "Manual"
  }

  depends_on = [
    aws_db_instance.postgresql_primary
  ]
}