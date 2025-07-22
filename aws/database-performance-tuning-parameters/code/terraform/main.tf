# Main Terraform configuration for database performance tuning recipe
# This configuration implements comprehensive PostgreSQL performance optimization using RDS Parameter Groups

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for caller identity
data "aws_caller_identity" "current" {}

# Data source for current region
data "aws_region" "current" {}

# VPC for isolated database testing environment
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-vpc-${random_string.suffix.result}"
    Type = "Performance Tuning VPC"
  })
}

# Internet Gateway for VPC (needed for NAT Gateway)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-igw-${random_string.suffix.result}"
  })
}

# Private subnets for RDS instances (Multi-AZ deployment)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}-${random_string.suffix.result}"
    Type = "Private Subnet"
    AZ   = data.aws_availability_zones.available.names[count.index]
  })
}

# Public subnet for NAT Gateway (if needed for VPC endpoints or external access)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.100.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-public-subnet-${random_string.suffix.result}"
    Type = "Public Subnet"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-nat-eip-${random_string.suffix.result}"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway for outbound internet access from private subnets
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-nat-gateway-${random_string.suffix.result}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-public-rt-${random_string.suffix.result}"
  })
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-private-rt-${random_string.suffix.result}"
  })
}

# Route table associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group for RDS instances
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-${random_string.suffix.result}"
  vpc_id      = aws_vpc.main.id
  description = "Security group for performance tuning RDS instances"

  # PostgreSQL access from VPC
  ingress {
    description = "PostgreSQL access from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # PostgreSQL access from allowed external CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "PostgreSQL access from allowed CIDR"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-rds-sg-${random_string.suffix.result}"
    Type = "RDS Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DB Subnet Group for RDS
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-subnet-group-${random_string.suffix.result}"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-subnet-group-${random_string.suffix.result}"
    Type = "DB Subnet Group"
  })
}

# Custom DB Parameter Group for PostgreSQL performance tuning
resource "aws_db_parameter_group" "postgres_tuned" {
  family      = var.parameter_group_family
  name        = "${var.project_name}-postgres-tuned-${random_string.suffix.result}"
  description = "Performance-tuned parameter group for PostgreSQL"

  # Memory-related parameters optimized for the instance size
  parameter {
    name         = "shared_buffers"
    value        = "${var.shared_buffers_mb}MB"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "work_mem"
    value        = "${var.work_mem_mb}MB"
    apply_method = "immediate"
  }

  parameter {
    name         = "maintenance_work_mem"
    value        = "${var.maintenance_work_mem_mb}MB"
    apply_method = "immediate"
  }

  parameter {
    name         = "effective_cache_size"
    value        = "${var.effective_cache_size_gb}GB"
    apply_method = "immediate"
  }

  # Connection parameters
  parameter {
    name         = "max_connections"
    value        = var.max_connections
    apply_method = "pending-reboot"
  }

  # Query optimization parameters
  parameter {
    name         = "random_page_cost"
    value        = var.random_page_cost
    apply_method = "immediate"
  }

  parameter {
    name         = "seq_page_cost"
    value        = "1.0"
    apply_method = "immediate"
  }

  parameter {
    name         = "effective_io_concurrency"
    value        = var.effective_io_concurrency
    apply_method = "immediate"
  }

  # Statistics and planner parameters
  parameter {
    name         = "default_statistics_target"
    value        = "500"
    apply_method = "immediate"
  }

  parameter {
    name         = "constraint_exclusion"
    value        = "partition"
    apply_method = "immediate"
  }

  parameter {
    name         = "cpu_tuple_cost"
    value        = "0.01"
    apply_method = "immediate"
  }

  parameter {
    name         = "cpu_index_tuple_cost"
    value        = "0.005"
    apply_method = "immediate"
  }

  # Logging parameters for monitoring slow queries
  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_checkpoints"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  # Checkpoint and WAL optimization
  parameter {
    name         = "checkpoint_completion_target"
    value        = "0.9"
    apply_method = "immediate"
  }

  parameter {
    name         = "wal_buffers"
    value        = "16MB"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "checkpoint_timeout"
    value        = "15min"
    apply_method = "immediate"
  }

  # Advanced parameters for analytical workloads
  parameter {
    name         = "from_collapse_limit"
    value        = "20"
    apply_method = "immediate"
  }

  parameter {
    name         = "join_collapse_limit"
    value        = "20"
    apply_method = "immediate"
  }

  parameter {
    name         = "geqo_threshold"
    value        = "15"
    apply_method = "immediate"
  }

  parameter {
    name         = "geqo_effort"
    value        = "8"
    apply_method = "immediate"
  }

  # Parallel query parameters (PostgreSQL 9.6+)
  parameter {
    name         = "max_parallel_workers_per_gather"
    value        = "2"
    apply_method = "immediate"
  }

  parameter {
    name         = "max_parallel_workers"
    value        = "4"
    apply_method = "immediate"
  }

  parameter {
    name         = "parallel_tuple_cost"
    value        = "0.1"
    apply_method = "immediate"
  }

  parameter {
    name         = "parallel_setup_cost"
    value        = "1000"
    apply_method = "immediate"
  }

  # Autovacuum optimization for high-write workloads
  parameter {
    name         = "autovacuum_vacuum_scale_factor"
    value        = "0.1"
    apply_method = "immediate"
  }

  parameter {
    name         = "autovacuum_analyze_scale_factor"
    value        = "0.05"
    apply_method = "immediate"
  }

  parameter {
    name         = "autovacuum_work_mem"
    value        = "256MB"
    apply_method = "immediate"
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-postgres-tuned-${random_string.suffix.result}"
    Type = "Performance Tuned Parameter Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name_prefix        = "${var.project_name}-rds-monitoring-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-rds-monitoring-role-${random_string.suffix.result}"
    Type = "RDS Monitoring Role"
  })
}

# IAM policy document for RDS monitoring role
data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

# Attach enhanced monitoring policy to role
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Generate random master password
resource "random_password" "master_password" {
  length  = 16
  special = true
}

# Store master password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}-db-password-${random_string.suffix.result}"
  description             = "Master password for performance tuning database"
  recovery_window_in_days = 7

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-db-password-${random_string.suffix.result}"
    Type = "Database Password Secret"
  })
}

# Store password value in secret
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.master_password.result
  })
}

# Primary RDS PostgreSQL instance with performance optimizations
resource "aws_db_instance" "primary" {
  identifier = "${var.project_name}-db-${random_string.suffix.result}"

  # Engine configuration
  engine               = "postgres"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  parameter_group_name = aws_db_parameter_group.postgres_tuned.name

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = var.enable_storage_encryption

  # Database configuration
  db_name  = "perftuning"
  username = "dbadmin"
  password = random_password.master_password.result

  # Network configuration
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = false
  port                   = 5432

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  copy_tags_to_snapshot  = true

  # Performance and monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

  # Enhanced features
  enabled_cloudwatch_logs_exports = ["postgresql"]
  deletion_protection             = var.enable_deletion_protection

  # Ensure parameter group changes trigger replacement only when necessary
  apply_immediately = false

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-primary-db-${random_string.suffix.result}"
    Type = "Primary Database"
    Role = "Performance Tuning Primary"
  })

  # Prevent accidental deletion during development
  lifecycle {
    ignore_changes = [
      password, # Password managed through Secrets Manager
    ]
  }

  depends_on = [
    aws_db_parameter_group.postgres_tuned,
    aws_iam_role_policy_attachment.rds_monitoring
  ]
}

# Read replica for read scaling and testing
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier = "${var.project_name}-db-replica-${random_string.suffix.result}"

  # Replica configuration
  replicate_source_db    = aws_db_instance.primary.identifier
  instance_class         = var.read_replica_instance_class
  parameter_group_name   = aws_db_parameter_group.postgres_tuned.name
  publicly_accessible    = false

  # Performance and monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

  # Enhanced features
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-replica-db-${random_string.suffix.result}"
    Type = "Read Replica"
    Role = "Performance Tuning Replica"
  })

  depends_on = [
    aws_db_instance.primary,
    aws_db_parameter_group.postgres_tuned
  ]
}

# CloudWatch Log Group for PostgreSQL logs
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${aws_db_instance.primary.identifier}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-postgresql-logs-${random_string.suffix.result}"
    Type = "Database Logs"
  })
}

# CloudWatch Dashboard for database performance monitoring
resource "aws_cloudwatch_dashboard" "database_performance" {
  dashboard_name = "${var.project_name}-database-performance-${random_string.suffix.result}"

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
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.primary.identifier],
            [".", "CPUUtilization", ".", "."],
            [".", "FreeableMemory", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Database Performance Overview"
          view   = "timeSeries"
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
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", aws_db_instance.primary.identifier],
            [".", "WriteIOPS", ".", "."],
            [".", "ReadThroughput", ".", "."],
            [".", "WriteThroughput", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Database I/O Performance"
          view   = "timeSeries"
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
          metrics = concat(
            [
              ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.primary.identifier, { "label" = "Primary DB Connections" }],
              [".", "CPUUtilization", ".", ".", { "label" = "Primary DB CPU %" }],
            ],
            var.create_read_replica ? [
              [".", "DatabaseConnections", ".", aws_db_instance.read_replica[0].identifier, { "label" = "Replica DB Connections" }],
              [".", "CPUUtilization", ".", ".", { "label" = "Replica DB CPU %" }]
            ] : []
          )
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Primary vs Replica Performance Comparison"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })

  depends_on = [aws_db_instance.primary]
}

# CloudWatch Alarms for database performance monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-db-high-cpu-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-high-cpu-alarm-${random_string.suffix.result}"
    Type = "Performance Alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_connections" {
  alarm_name          = "${var.project_name}-db-high-connections-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.max_connections * 0.8) # 80% of max connections
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-high-connections-alarm-${random_string.suffix.result}"
    Type = "Performance Alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_read_latency" {
  alarm_name          = "${var.project_name}-db-high-read-latency-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.1"
  alarm_description   = "This metric monitors RDS read latency"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-high-read-latency-alarm-${random_string.suffix.result}"
    Type = "Performance Alarm"
  })
}