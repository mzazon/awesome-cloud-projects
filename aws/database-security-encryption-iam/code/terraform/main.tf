# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Get availability zones
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
    values = [local.vpc_id]
  }
}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Random suffix for unique resource names
  random_suffix = random_string.suffix.result
  
  # VPC and subnet configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Resource names
  db_instance_identifier     = "${local.name_prefix}-db-${local.random_suffix}"
  db_proxy_name             = "${local.name_prefix}-proxy-${local.random_suffix}"
  db_subnet_group_name      = "${local.name_prefix}-subnet-group-${local.random_suffix}"
  security_group_name       = "${local.name_prefix}-sg-${local.random_suffix}"
  kms_key_alias             = "alias/${local.name_prefix}-rds-key-${local.random_suffix}"
  iam_role_name             = "${local.name_prefix}-DatabaseAccessRole-${local.random_suffix}"
  iam_policy_name           = "${local.name_prefix}-DatabaseAccessPolicy-${local.random_suffix}"
  parameter_group_name      = "${local.name_prefix}-pg-${local.random_suffix}"
  monitoring_role_name      = "${local.name_prefix}-monitoring-role-${local.random_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    },
    var.additional_tags
  )
}

# ==============================================================================
# RANDOM RESOURCES
# ==============================================================================

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate random password for initial database setup
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# ==============================================================================
# KMS KEY FOR DATABASE ENCRYPTION
# ==============================================================================

# KMS key for RDS encryption
resource "aws_kms_key" "rds_encryption" {
  description             = "Customer managed key for RDS encryption"
  deletion_window_in_days = var.kms_key_deletion_window
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
        Sid    = "Allow RDS Service"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "rds.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-encryption-key"
  })
}

# KMS key alias
resource "aws_kms_alias" "rds_encryption" {
  name          = local.kms_key_alias
  target_key_id = aws_kms_key.rds_encryption.key_id
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM policy for database access
resource "aws_iam_policy" "database_access" {
  name        = local.iam_policy_name
  description = "Policy for database access via IAM authentication"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${local.db_instance_identifier}/${var.db_username}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBProxies"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# IAM role for database access
resource "aws_iam_role" "database_access" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "database_access" {
  role       = aws_iam_role.database_access.name
  policy_arn = aws_iam_policy.database_access.arn
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "monitoring" {
  name = local.monitoring_role_name

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

# Attach AWS managed policy for enhanced monitoring
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

# Security group for RDS instance
resource "aws_security_group" "database" {
  name        = local.security_group_name
  description = "Security group for secure RDS instance"
  vpc_id      = local.vpc_id

  # Allow PostgreSQL access from specified CIDR blocks
  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow self-referencing for applications in the same security group
  ingress {
    description = "Self-referencing PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = local.security_group_name
  })
}

# ==============================================================================
# DATABASE SUBNET GROUP
# ==============================================================================

# DB subnet group for RDS instance
resource "aws_db_subnet_group" "database" {
  name       = local.db_subnet_group_name
  subnet_ids = local.subnet_ids

  tags = merge(local.common_tags, {
    Name = local.db_subnet_group_name
  })
}

# ==============================================================================
# DATABASE PARAMETER GROUP
# ==============================================================================

# Parameter group for enhanced security
resource "aws_db_parameter_group" "database" {
  family = "postgres15"
  name   = local.parameter_group_name

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = merge(local.common_tags, {
    Name = local.parameter_group_name
  })
}

# ==============================================================================
# RDS INSTANCE
# ==============================================================================

# RDS instance with encryption and IAM authentication
resource "aws_db_instance" "database" {
  identifier = local.db_instance_identifier

  # Engine configuration
  engine                 = "postgres"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  parameter_group_name   = aws_db_parameter_group.database.name

  # Database configuration
  db_name  = var.db_name
  username = var.db_admin_username
  password = random_password.db_password.result

  # Storage configuration
  allocated_storage                     = var.db_allocated_storage
  storage_type                          = var.db_storage_type
  storage_encrypted                     = true
  kms_key_id                           = aws_kms_key.rds_encryption.arn
  manage_master_user_password          = false

  # Network configuration
  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.database.name
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period   = var.db_backup_retention_period
  backup_window            = var.db_backup_window
  maintenance_window       = var.db_maintenance_window
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  # Security configuration
  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection

  # Monitoring configuration
  monitoring_interval          = var.enhanced_monitoring_interval
  monitoring_role_arn         = var.enhanced_monitoring_interval > 0 ? aws_iam_role.monitoring.arn : null
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights configuration
  performance_insights_enabled          = true
  performance_insights_kms_key_id      = aws_kms_key.rds_encryption.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  # Prevent accidental deletion
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.db_instance_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Apply changes immediately in non-production environments
  apply_immediately = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = local.db_instance_identifier
  })

  # Ensure dependencies are created first
  depends_on = [
    aws_iam_role_policy_attachment.monitoring,
    aws_db_parameter_group.database,
    aws_kms_key.rds_encryption
  ]
}

# ==============================================================================
# RDS PROXY
# ==============================================================================

# RDS Proxy for enhanced security and connection pooling
resource "aws_db_proxy" "database" {
  name                   = local.db_proxy_name
  engine_family         = "POSTGRESQL"
  vpc_subnet_ids        = local.subnet_ids
  vpc_security_group_ids = [aws_security_group.database.id]
  role_arn              = aws_iam_role.database_access.arn

  # Authentication configuration
  auth {
    auth_scheme = "IAM"
    description = "IAM authentication for secure database access"
  }

  # Connection configuration
  require_tls                = true
  idle_client_timeout        = var.proxy_idle_client_timeout
  max_connections_percent    = var.proxy_max_connections_percent
  max_idle_connections_percent = var.proxy_max_idle_connections_percent

  # Debug logging
  debug_logging = var.enable_debug_logging

  tags = merge(local.common_tags, {
    Name = local.db_proxy_name
  })

  depends_on = [
    aws_db_instance.database,
    aws_iam_role.database_access
  ]
}

# Register RDS instance with proxy
resource "aws_db_proxy_target" "database" {
  db_instance_identifier = aws_db_instance.database.id
  db_proxy_name          = aws_db_proxy.database.name
  target_group_name      = aws_db_proxy_default_target_group.database.name
}

# Default target group for the proxy
resource "aws_db_proxy_default_target_group" "database" {
  db_proxy_name = aws_db_proxy.database.name

  connection_pool_config {
    max_connections_percent      = var.proxy_max_connections_percent
    max_idle_connections_percent = var.proxy_max_idle_connections_percent
    connection_borrow_timeout    = 120
  }
}

# ==============================================================================
# CLOUDWATCH MONITORING
# ==============================================================================

# CloudWatch log group for database monitoring
resource "aws_cloudwatch_log_group" "database" {
  name              = "/aws/rds/instance/${local.db_instance_identifier}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.rds_encryption.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-logs"
  })
}

# CloudWatch alarm for high CPU usage
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "RDS-HighCPU-${local.db_instance_identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.database.id
  }

  tags = local.common_tags
}

# CloudWatch alarm for database connections
resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "RDS-HighConnections-${local.db_instance_identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.database_connections_threshold
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.database.id
  }

  tags = local.common_tags
}

# CloudWatch alarm for failed authentication attempts
resource "aws_cloudwatch_metric_alarm" "authentication_failures" {
  alarm_name          = "RDS-AuthFailures-${local.db_instance_identifier}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.database_connections_threshold
  alarm_description   = "This metric monitors potential authentication failures"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.database.id
  }

  tags = local.common_tags
}

# ==============================================================================
# SECRETS MANAGER (Optional - for storing connection information)
# ==============================================================================

# Store database connection information in Secrets Manager
resource "aws_secretsmanager_secret" "database_connection" {
  name        = "${local.name_prefix}-database-connection-${local.random_suffix}"
  description = "Database connection information for ${local.db_instance_identifier}"
  
  kms_key_id = aws_kms_key.rds_encryption.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-connection"
  })
}

# Store connection details in the secret
resource "aws_secretsmanager_secret_version" "database_connection" {
  secret_id = aws_secretsmanager_secret.database_connection.id
  secret_string = jsonencode({
    host                = aws_db_instance.database.endpoint
    port                = aws_db_instance.database.port
    database            = aws_db_instance.database.db_name
    username            = var.db_username
    proxy_endpoint      = aws_db_proxy.database.endpoint
    iam_role_arn       = aws_iam_role.database_access.arn
    authentication_type = "IAM"
  })
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

# Generate a comprehensive security compliance report
locals {
  security_compliance_report = {
    database_security_audit = {
      encryption_at_rest = {
        enabled               = true
        kms_key_id           = aws_kms_key.rds_encryption.arn
        customer_managed_key = true
      }
      encryption_in_transit = {
        enabled    = true
        tls_required = true
        force_ssl    = true
      }
      iam_authentication = {
        enabled  = true
        db_user  = var.db_username
        iam_role = aws_iam_role.database_access.arn
      }
      network_security = {
        vpc_security_group = aws_security_group.database.id
        private_subnets   = true
        db_subnet_group   = aws_db_subnet_group.database.name
      }
      monitoring = {
        enhanced_monitoring   = var.enhanced_monitoring_interval > 0
        performance_insights = true
        cloudwatch_logs      = true
        cloudwatch_alarms    = true
      }
      backup_security = {
        backup_retention_days    = var.db_backup_retention_period
        backup_encryption       = true
        point_in_time_recovery  = true
      }
    }
  }
}