# Main Terraform configuration for Aurora database migration infrastructure
# This file creates all resources needed for minimal downtime database migration using DMS and Aurora

# Get current AWS account ID and available AZs
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random password for Aurora master user
resource "random_password" "aurora_master_password" {
  length  = 16
  special = true
}

# Generate random suffix for resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Calculate resource suffix
  suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Database Migration"
  }
}

# ========================================
# VPC and Networking
# ========================================

# Create VPC for database migration infrastructure
resource "aws_vpc" "migration_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "migration_igw" {
  vpc_id = aws_vpc.migration_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Private subnets for Aurora and DMS
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.migration_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Public subnets for NAT gateways
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.migration_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_eips" {
  count = length(aws_subnet.public_subnets)

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.migration_igw]
}

# NAT Gateways for private subnet internet access
resource "aws_nat_gateway" "nat_gateways" {
  count = length(aws_subnet.public_subnets)

  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.migration_igw]
}

# Route table for public subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.migration_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.migration_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

# Route tables for private subnets
resource "aws_route_table" "private_rts" {
  count = length(aws_subnet.private_subnets)

  vpc_id = aws_vpc.migration_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateways[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_subnet_associations" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private_subnet_associations" {
  count = length(aws_subnet.private_subnets)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rts[count.index].id
}

# ========================================
# Security Groups
# ========================================

# Security group for Aurora database
resource "aws_security_group" "aurora_sg" {
  name_prefix = "${local.name_prefix}-aurora-"
  vpc_id      = aws_vpc.migration_vpc.id
  description = "Security group for Aurora database cluster"

  # Allow inbound connections from DMS
  ingress {
    description     = "MySQL/Aurora access from DMS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.dms_sg.id]
  }

  # Allow inbound connections from specified CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "Database access from allowed networks"
      from_port   = var.aurora_engine == "aurora-mysql" ? 3306 : 5432
      to_port     = var.aurora_engine == "aurora-mysql" ? 3306 : 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
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
    Name = "${local.name_prefix}-aurora-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for DMS replication instance
resource "aws_security_group" "dms_sg" {
  name_prefix = "${local.name_prefix}-dms-"
  vpc_id      = aws_vpc.migration_vpc.id
  description = "Security group for DMS replication instance"

  # Allow outbound connections to Aurora
  egress {
    description = "MySQL/Aurora access to target database"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow outbound connections to source database
  egress {
    description = "Access to source database"
    from_port   = var.source_db_port
    to_port     = var.source_db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTPS for AWS API calls
  egress {
    description = "HTTPS outbound for AWS API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ========================================
# IAM Roles for DMS
# ========================================

# IAM role for DMS VPC management
resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy to DMS VPC role
resource "aws_iam_role_policy_attachment" "dms_vpc_role_policy" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# IAM role for DMS CloudWatch logs
resource "aws_iam_role" "dms_cloudwatch_role" {
  name = "dms-cloudwatch-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy to DMS CloudWatch role
resource "aws_iam_role_policy_attachment" "dms_cloudwatch_role_policy" {
  role       = aws_iam_role.dms_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# ========================================
# Aurora Database Cluster
# ========================================

# Aurora DB subnet group
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "${local.name_prefix}-aurora-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-subnet-group"
  })
}

# Aurora cluster parameter group
resource "aws_rds_cluster_parameter_group" "aurora_cluster_pg" {
  family = var.aurora_engine == "aurora-mysql" ? "aurora-mysql8.0" : "aurora-postgresql14"
  name   = "${local.name_prefix}-cluster-pg-${local.suffix}"

  # Optimization parameters for migration performance
  dynamic "parameter" {
    for_each = var.aurora_engine == "aurora-mysql" ? [
      { name = "innodb_buffer_pool_size", value = "{DBInstanceClassMemory*3/4}" },
      { name = "max_connections", value = "1000" },
      { name = "innodb_flush_log_at_trx_commit", value = "2" },
      { name = "sync_binlog", value = "0" },
    ] : []
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Store Aurora master password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "aurora_master_password" {
  name                    = "${local.name_prefix}-aurora-master-password-${local.suffix}"
  description             = "Master password for Aurora cluster"
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "aurora_master_password" {
  secret_id     = aws_secretsmanager_secret.aurora_master_password.id
  secret_string = random_password.aurora_master_password.result
}

# Aurora database cluster
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier              = "${local.name_prefix}-cluster-${local.suffix}"
  engine                         = var.aurora_engine
  engine_version                 = var.aurora_engine_version
  database_name                  = var.aurora_database_name
  master_username                = var.aurora_master_username
  master_password                = random_password.aurora_master_password.result
  backup_retention_period        = var.aurora_backup_retention_period
  preferred_backup_window        = var.aurora_backup_window
  preferred_maintenance_window   = var.aurora_maintenance_window
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_cluster_pg.name
  db_subnet_group_name           = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids         = [aws_security_group.aurora_sg.id]
  storage_encrypted              = var.enable_encryption
  kms_key_id                     = var.enable_encryption ? aws_kms_key.aurora_encryption[0].arn : null
  
  # Enable CloudWatch logs exports
  enabled_cloudwatch_logs_exports = var.enable_cloudwatch_logs ? (
    var.aurora_engine == "aurora-mysql" ? ["error", "general", "slowquery"] : ["postgresql"]
  ) : []

  # Enable backtrack for MySQL (not available for PostgreSQL)
  backtrack_window = var.aurora_engine == "aurora-mysql" ? 72 : null

  # Enable deletion protection in production
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment != "prod" ? true : false
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-cluster"
    Purpose = "migration-target"
  })

  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role_policy]
}

# Aurora cluster instances
resource "aws_rds_cluster_instance" "aurora_primary" {
  identifier                      = "${local.name_prefix}-primary-${local.suffix}"
  cluster_identifier              = aws_rds_cluster.aurora_cluster.id
  instance_class                  = var.aurora_instance_class
  engine                         = var.aurora_engine
  engine_version                 = var.aurora_engine_version
  publicly_accessible           = false
  performance_insights_enabled   = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval            = 60
  monitoring_role_arn           = aws_iam_role.aurora_monitoring_role.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary"
    Role = "primary"
  })
}

resource "aws_rds_cluster_instance" "aurora_reader" {
  identifier                      = "${local.name_prefix}-reader-${local.suffix}"
  cluster_identifier              = aws_rds_cluster.aurora_cluster.id
  instance_class                  = var.aurora_instance_class
  engine                         = var.aurora_engine
  engine_version                 = var.aurora_engine_version
  publicly_accessible           = false
  performance_insights_enabled   = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  monitoring_interval            = 60
  monitoring_role_arn           = aws_iam_role.aurora_monitoring_role.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-reader"
    Role = "reader"
  })
}

# KMS key for Aurora encryption
resource "aws_kms_key" "aurora_encryption" {
  count = var.enable_encryption ? 1 : 0

  description             = "KMS key for Aurora cluster encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-encryption-key"
  })
}

resource "aws_kms_alias" "aurora_encryption" {
  count = var.enable_encryption ? 1 : 0

  name          = "alias/${local.name_prefix}-aurora-encryption"
  target_key_id = aws_kms_key.aurora_encryption[0].key_id
}

# IAM role for Aurora monitoring
resource "aws_iam_role" "aurora_monitoring_role" {
  name = "${local.name_prefix}-aurora-monitoring-role-${local.suffix}"

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

resource "aws_iam_role_policy_attachment" "aurora_monitoring_role_policy" {
  role       = aws_iam_role.aurora_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ========================================
# DMS Resources
# ========================================

# DMS subnet group
resource "aws_dms_replication_subnet_group" "dms_subnet_group" {
  allocated_storage                   = var.dms_allocated_storage
  apply_immediately                   = true
  auto_minor_version_upgrade         = false
  availability_zone                  = data.aws_availability_zones.available.names[0]
  engine_version                     = "3.4.7"
  multi_az                           = var.dms_multi_az
  publicly_accessible               = var.dms_publicly_accessible
  replication_instance_class         = var.dms_replication_instance_class
  replication_instance_id            = "${local.name_prefix}-replication-instance-${local.suffix}"
  replication_subnet_group_id        = aws_dms_replication_subnet_group.dms_subnet_group.id
  vpc_security_group_ids             = [aws_security_group.dms_sg.id]

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-replication-instance"
    Purpose = "database-migration"
  })

  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role_policy]
}

# DMS replication subnet group
resource "aws_dms_replication_subnet_group" "dms_subnet_group" {
  replication_subnet_group_description = "DMS subnet group for migration"
  replication_subnet_group_id          = "${local.name_prefix}-dms-subnet-group"
  subnet_ids                           = aws_subnet.private_subnets[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dms-subnet-group"
  })
}

# DMS replication instance
resource "aws_dms_replication_instance" "dms_replication_instance" {
  allocated_storage                   = var.dms_allocated_storage
  apply_immediately                   = true
  auto_minor_version_upgrade         = false
  availability_zone                  = data.aws_availability_zones.available.names[0]
  engine_version                     = "3.4.7"
  multi_az                           = var.dms_multi_az
  publicly_accessible               = var.dms_publicly_accessible
  replication_instance_class         = var.dms_replication_instance_class
  replication_instance_id            = "${local.name_prefix}-replication-instance-${local.suffix}"
  replication_subnet_group_id        = aws_dms_replication_subnet_group.dms_subnet_group.id
  vpc_security_group_ids             = [aws_security_group.dms_sg.id]

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-replication-instance"
    Purpose = "database-migration"
  })

  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role_policy]
}

# DMS source endpoint
resource "aws_dms_endpoint" "source_endpoint" {
  endpoint_id   = "${local.name_prefix}-source-endpoint-${local.suffix}"
  endpoint_type = "source"
  engine_name   = var.source_db_engine
  server_name   = var.source_db_server_name
  port          = var.source_db_port
  username      = var.source_db_username
  password      = var.source_db_password
  database_name = var.source_db_name

  # Extra connection attributes for MySQL
  extra_connection_attributes = var.source_db_engine == "mysql" ? "heartbeatEnable=true;heartbeatFrequency=1" : ""

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-source-endpoint"
    Type = "source"
  })
}

# DMS target endpoint (Aurora)
resource "aws_dms_endpoint" "target_endpoint" {
  endpoint_id   = "${local.name_prefix}-target-endpoint-${local.suffix}"
  endpoint_type = "target"
  engine_name   = var.aurora_engine == "aurora-mysql" ? "aurora" : "aurora-postgresql"
  server_name   = aws_rds_cluster.aurora_cluster.endpoint
  port          = aws_rds_cluster.aurora_cluster.port
  username      = var.aurora_master_username
  password      = random_password.aurora_master_password.result
  database_name = var.aurora_database_name

  # Extra connection attributes for Aurora optimization
  extra_connection_attributes = var.aurora_engine == "aurora-mysql" ? "parallelLoadThreads=8;maxFileSize=512000" : ""

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-target-endpoint"
    Type = "target"
  })
}

# Table mappings for DMS task
locals {
  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "1"
        object-locator = {
          schema-name = "%"
          table-name  = "%"
        }
        rule-action = "include"
      },
      {
        rule-type   = "transformation"
        rule-id     = "2"
        rule-name   = "2"
        rule-target = "schema"
        object-locator = {
          schema-name = "%"
        }
        rule-action = "rename"
        value       = var.aurora_database_name
      }
    ]
  })

  task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema                = ""
      SupportLobs                 = true
      FullLobMode                 = false
      LobChunkSize                = 0
      LimitedSizeLobMode          = true
      LobMaxSize                  = 32
      InlineLobMaxSize            = 0
      LoadMaxFileSize             = 0
      ParallelLoadThreads         = 0
      ParallelLoadBufferSize      = 0
      BatchApplyEnabled           = true
      TaskRecoveryTableEnabled    = false
      ParallelApplyThreads        = 8
      ParallelApplyBufferSize     = 1000
      ParallelApplyQueuesPerThread = 4
    }
    FullLoadSettings = {
      TargetTablePrepMode                = "DROP_AND_CREATE"
      CreatePkAfterFullLoad             = false
      StopTaskCachedChangesApplied      = false
      StopTaskCachedChangesNotApplied   = false
      MaxFullLoadSubTasks               = 8
      TransactionConsistencyTimeout     = 600
      CommitRate                        = 10000
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        { Id = "SOURCE_UNLOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_LOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SOURCE_CAPTURE", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_APPLY", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TASK_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" }
      ]
      CloudWatchLogGroup  = null
      CloudWatchLogStream = null
    }
    ControlTablesSettings = {
      historyTimeslotInMinutes       = 5
      ControlSchema                  = ""
      HistoryTimeslotInMinutes       = 5
      HistoryTableEnabled            = false
      SuspendedTablesTableEnabled    = false
      StatusTableEnabled             = false
    }
    StreamBufferSettings = {
      StreamBufferCount      = 3
      StreamBufferSizeInMB   = 8
      CtrlStreamBufferSizeInMB = 5
    }
    ChangeProcessingDdlHandlingPolicy = {
      HandleSourceTableDropped    = true
      HandleSourceTableTruncated  = true
      HandleSourceTableAltered    = true
    }
    ErrorBehavior = {
      DataErrorPolicy                = "LOG_ERROR"
      DataTruncationErrorPolicy      = "LOG_ERROR"
      DataErrorEscalationPolicy      = "SUSPEND_TABLE"
      DataErrorEscalationCount       = 0
      TableErrorPolicy               = "SUSPEND_TABLE"
      TableErrorEscalationPolicy     = "STOP_TASK"
      TableErrorEscalationCount      = 0
      RecoverableErrorCount          = -1
      RecoverableErrorInterval       = 5
      RecoverableErrorThrottling     = true
      RecoverableErrorThrottlingMax  = 1800
      ApplyErrorDeletePolicy         = "IGNORE_RECORD"
      ApplyErrorInsertPolicy         = "LOG_ERROR"
      ApplyErrorUpdatePolicy         = "LOG_ERROR"
      ApplyErrorEscalationPolicy     = "LOG_ERROR"
      ApplyErrorEscalationCount      = 0
      FullLoadIgnoreConflicts        = true
    }
    ChangeProcessingTuning = {
      BatchApplyPreserveTransaction = true
      BatchApplyTimeoutMin          = 1
      BatchApplyTimeoutMax          = 30
      BatchApplyMemoryLimit         = 500
      BatchSplitSize                = 0
      MinTransactionSize            = 1000
      CommitTimeout                 = 1
      MemoryLimitTotal              = 1024
      MemoryKeepTime                = 60
      StatementCacheSize            = 50
    }
    ValidationSettings = {
      EnableValidation                    = var.enable_validation
      ValidationMode                      = "ROW_LEVEL"
      ThreadCount                         = 5
      PartitionSize                       = 10000
      FailureMaxCount                     = 10000
      RecordFailureDelayLimitInMinutes    = 0
      RecordSuspendDelayInMinutes         = 30
      MaxKeyColumnSize                    = 8096
      TableFailureMaxCount                = 1000
      ValidationOnly                      = false
      HandleCollationDiff                 = false
      RecordFailureDelayInMinutes         = 5
      SkipLobColumns                      = false
      ValidationPartialLobSize            = 0
      ValidationQueryCdcDelaySeconds      = 0
    }
  })
}

# DMS replication task
resource "aws_dms_replication_task" "migration_task" {
  migration_type           = var.migration_type
  replication_instance_arn = aws_dms_replication_instance.dms_replication_instance.replication_instance_arn
  replication_task_id      = "${local.name_prefix}-migration-task-${local.suffix}"
  source_endpoint_arn      = aws_dms_endpoint.source_endpoint.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target_endpoint.endpoint_arn
  table_mappings           = local.table_mappings
  replication_task_settings = local.task_settings

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-migration-task"
  })
}

# ========================================
# Route 53 Resources
# ========================================

# Route 53 private hosted zone for DNS cutover
resource "aws_route53_zone" "database_zone" {
  name = var.route53_zone_name

  vpc {
    vpc_id = aws_vpc.migration_vpc.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-zone"
  })
}

# Route 53 record for database endpoint (initially points to source)
resource "aws_route53_record" "database_record" {
  zone_id = aws_route53_zone.database_zone.zone_id
  name    = "${var.route53_record_name}.${var.route53_zone_name}"
  type    = "CNAME"
  ttl     = var.route53_record_ttl
  records = [var.source_db_server_name]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-record"
  })
}

# ========================================
# CloudWatch Resources
# ========================================

# CloudWatch log group for DMS
resource "aws_cloudwatch_log_group" "dms_logs" {
  name              = "/aws/dms/${local.name_prefix}-migration-task-${local.suffix}"
  retention_in_days = 7

  tags = local.common_tags
}

# CloudWatch dashboard for migration monitoring
resource "aws_cloudwatch_dashboard" "migration_dashboard" {
  dashboard_name = "${local.name_prefix}-migration-dashboard"

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
            ["AWS/DMS", "CDCLatencySource", "ReplicationInstanceIdentifier", aws_dms_replication_instance.dms_replication_instance.replication_instance_id],
            [".", "CDCLatencyTarget", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "DMS CDC Latency"
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
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.aurora_cluster.cluster_identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Aurora Cluster Performance"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "aurora_cpu_high" {
  alarm_name          = "${local.name_prefix}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Aurora cluster CPU utilization"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_cluster.cluster_identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dms_cdc_latency_high" {
  alarm_name          = "${local.name_prefix}-dms-cdc-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CDCLatencyTarget"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "60"
  alarm_description   = "This metric monitors DMS CDC latency to target"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.dms_replication_instance.replication_instance_id
  }

  tags = local.common_tags
}