# Oracle to PostgreSQL Database Migration Infrastructure with AWS DMS

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  project_name = "${var.project_name}-${random_id.suffix.hex}"
  common_tags = {
    Project     = "OracleToPostgreSQLMigration"
    Environment = var.environment
    Owner       = var.owner
  }
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

#------------------------------------------------------------------------------
# VPC and Networking Configuration
#------------------------------------------------------------------------------

# Create VPC for migration infrastructure
resource "aws_vpc" "migration_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

# Create internet gateway for VPC
resource "aws_internet_gateway" "migration_igw" {
  vpc_id = aws_vpc.migration_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

# Create subnets in different availability zones
resource "aws_subnet" "migration_subnet" {
  count             = 2
  vpc_id            = aws_vpc.migration_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-subnet-${count.index + 1}"
  })
}

# Create route table for private subnets
resource "aws_route_table" "migration_rt" {
  vpc_id = aws_vpc.migration_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-rt"
  })
}

# Associate route table with subnets
resource "aws_route_table_association" "migration_rta" {
  count          = length(aws_subnet.migration_subnet)
  subnet_id      = aws_subnet.migration_subnet[count.index].id
  route_table_id = aws_route_table.migration_rt.id
}

# Security group for Aurora PostgreSQL
resource "aws_security_group" "aurora_sg" {
  name_prefix = "${local.project_name}-aurora-"
  vpc_id      = aws_vpc.migration_vpc.id

  ingress {
    description = "PostgreSQL from DMS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-aurora-sg"
  })
}

# Security group for DMS replication instance
resource "aws_security_group" "dms_sg" {
  name_prefix = "${local.project_name}-dms-"
  vpc_id      = aws_vpc.migration_vpc.id

  # Allow outbound connections to Oracle (configure as needed)
  egress {
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to Oracle server IP in production
  }

  # Allow outbound connections to PostgreSQL
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow HTTPS for AWS services
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-dms-sg"
  })
}

#------------------------------------------------------------------------------
# IAM Roles and Policies for DMS
#------------------------------------------------------------------------------

# DMS VPC Role
resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role-${random_id.suffix.hex}"

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

# Attach DMS VPC management policy
resource "aws_iam_role_policy_attachment" "dms_vpc_role_policy" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS CloudWatch Logs Role
resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  name = "dms-cloudwatch-logs-role-${random_id.suffix.hex}"

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

# Attach DMS CloudWatch logs policy
resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role_policy" {
  role       = aws_iam_role.dms_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# Enhanced monitoring role for Aurora
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "rds-monitoring-role-${random_id.suffix.hex}"

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

# Attach enhanced monitoring policy
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring_policy" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#------------------------------------------------------------------------------
# Aurora PostgreSQL Target Database
#------------------------------------------------------------------------------

# DB subnet group for Aurora
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "${local.project_name}-aurora-subnet-group"
  subnet_ids = aws_subnet.migration_subnet[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-aurora-subnet-group"
  })
}

# Aurora PostgreSQL cluster
resource "aws_rds_cluster" "aurora_postgresql" {
  cluster_identifier              = "${local.project_name}-aurora-cluster"
  engine                         = "aurora-postgresql"
  engine_version                 = var.aurora_engine_version
  database_name                  = "postgres"
  master_username                = var.aurora_master_username
  master_password                = var.aurora_master_password
  port                          = 5432
  
  db_subnet_group_name           = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids         = [aws_security_group.aurora_sg.id]
  
  backup_retention_period        = var.aurora_backup_retention_period
  preferred_backup_window        = var.aurora_preferred_backup_window
  preferred_maintenance_window   = var.aurora_preferred_maintenance_window
  
  storage_encrypted              = true
  kms_key_id                    = aws_kms_key.migration_kms_key.arn
  
  skip_final_snapshot           = true
  deletion_protection           = false

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-aurora-cluster"
  })

  depends_on = [
    aws_iam_role_policy_attachment.rds_enhanced_monitoring_policy
  ]
}

# Aurora PostgreSQL instance
resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier                   = "${local.project_name}-aurora-instance-1"
  cluster_identifier          = aws_rds_cluster.aurora_postgresql.id
  instance_class              = var.aurora_instance_class
  engine                      = aws_rds_cluster.aurora_postgresql.engine
  engine_version              = aws_rds_cluster.aurora_postgresql.engine_version
  
  performance_insights_enabled = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  
  monitoring_interval         = var.monitoring_interval
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring.arn

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-aurora-instance-1"
  })
}

#------------------------------------------------------------------------------
# AWS DMS Components
#------------------------------------------------------------------------------

# DMS subnet group
resource "aws_dms_replication_subnet_group" "dms_subnet_group" {
  replication_subnet_group_description = "DMS subnet group for migration"
  replication_subnet_group_id          = "${local.project_name}-dms-subnet-group"
  subnet_ids                           = aws_subnet.migration_subnet[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-dms-subnet-group"
  })
}

# DMS replication instance
resource "aws_dms_replication_instance" "migration_instance" {
  allocated_storage            = var.dms_allocated_storage
  auto_minor_version_upgrade   = true
  engine_version              = var.dms_engine_version
  multi_az                    = var.dms_multi_az
  publicly_accessible         = var.dms_publicly_accessible
  replication_instance_class   = var.dms_replication_instance_class
  replication_instance_id      = "${local.project_name}-replication-instance"
  
  replication_subnet_group_id  = aws_dms_replication_subnet_group.dms_subnet_group.id
  vpc_security_group_ids       = [aws_security_group.dms_sg.id]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-replication-instance"
  })

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_role_policy
  ]
}

# Oracle source endpoint
resource "aws_dms_endpoint" "oracle_source" {
  endpoint_id   = "oracle-source-endpoint-${random_id.suffix.hex}"
  endpoint_type = "source"
  engine_name   = "oracle"
  
  server_name   = var.oracle_server_name
  port          = var.oracle_port
  database_name = var.oracle_database_name
  username      = var.oracle_username
  password      = var.oracle_password

  extra_connection_attributes = "useLogminerReader=N;useBfile=Y"

  tags = merge(local.common_tags, {
    Name = "oracle-source-endpoint"
  })
}

# PostgreSQL target endpoint
resource "aws_dms_endpoint" "postgresql_target" {
  endpoint_id   = "postgresql-target-endpoint-${random_id.suffix.hex}"
  endpoint_type = "target"
  engine_name   = "postgres"
  
  server_name   = aws_rds_cluster.aurora_postgresql.endpoint
  port          = aws_rds_cluster.aurora_postgresql.port
  database_name = aws_rds_cluster.aurora_postgresql.database_name
  username      = aws_rds_cluster.aurora_postgresql.master_username
  password      = var.aurora_master_password

  tags = merge(local.common_tags, {
    Name = "postgresql-target-endpoint"
  })
}

# DMS replication task
resource "aws_dms_replication_task" "migration_task" {
  migration_type           = var.migration_type
  replication_instance_arn = aws_dms_replication_instance.migration_instance.replication_instance_arn
  replication_task_id      = "${local.project_name}-migration-task"
  
  source_endpoint_arn      = aws_dms_endpoint.oracle_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.postgresql_target.endpoint_arn

  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "1"
        object-locator = {
          schema-name = var.source_schema_name
          table-name  = "%"
        }
        rule-action = "include"
        filters     = []
      },
      {
        rule-type = "transformation"
        rule-id   = "2"
        rule-name = "2"
        rule-target = "schema"
        object-locator = {
          schema-name = var.source_schema_name
        }
        rule-action = "rename"
        value       = var.target_schema_name
      },
      {
        rule-type = "transformation"
        rule-id   = "3"
        rule-name = "3"
        rule-target = "table"
        object-locator = {
          schema-name = var.source_schema_name
          table-name  = "%"
        }
        rule-action = "convert-lowercase"
      }
    ]
  })

  replication_task_settings = jsonencode({
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
      BatchApplyEnabled           = false
      TaskRecoveryTableEnabled    = false
      ParallelApplyThreads        = 0
      ParallelApplyBufferSize     = 0
      ParallelApplyQueuesPerThread = 0
    }
    FullLoadSettings = {
      TargetTablePrepMode             = "DROP_AND_CREATE"
      CreatePkAfterFullLoad           = false
      StopTaskCachedChangesApplied    = false
      StopTaskCachedChangesNotApplied = false
      MaxFullLoadSubTasks             = 8
      TransactionConsistencyTimeout   = 600
      CommitRate                      = 10000
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        {
          Id       = "TRANSFORMATION"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "SOURCE_UNLOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "TARGET_LOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-migration-task"
  })
}

#------------------------------------------------------------------------------
# KMS Key for Encryption
#------------------------------------------------------------------------------

# KMS key for encryption
resource "aws_kms_key" "migration_kms_key" {
  description             = "KMS key for Oracle to PostgreSQL migration encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-kms-key"
  })
}

# KMS key alias
resource "aws_kms_alias" "migration_kms_alias" {
  name          = "alias/${local.project_name}-encryption-key"
  target_key_id = aws_kms_key.migration_kms_key.key_id
}

#------------------------------------------------------------------------------
# CloudWatch Monitoring and Alerting
#------------------------------------------------------------------------------

# SNS topic for notifications
resource "aws_sns_topic" "dms_alerts" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  name  = "${local.project_name}-dms-alerts"

  tags = local.common_tags
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "dms_email_alerts" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  topic_arn = aws_sns_topic.dms_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# CloudWatch alarm for replication lag
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.project_name}-replication-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLag"
  namespace           = "AWS/DMS"
  period              = 300
  statistic           = "Average"
  threshold           = var.replication_lag_threshold
  alarm_description   = "This metric monitors DMS replication lag"
  alarm_actions       = [aws_sns_topic.dms_alerts[0].arn]

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.migration_instance.replication_instance_id
    ReplicationTaskIdentifier     = aws_dms_replication_task.migration_task.replication_task_id
  }

  tags = local.common_tags
}

# CloudWatch alarm for task failures
resource "aws_cloudwatch_metric_alarm" "task_failure" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.project_name}-task-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ReplicationTaskFailure"
  namespace           = "AWS/DMS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors DMS task failures"
  alarm_actions       = [aws_sns_topic.dms_alerts[0].arn]

  dimensions = {
    ReplicationTaskIdentifier = aws_dms_replication_task.migration_task.replication_task_id
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups
#------------------------------------------------------------------------------

# CloudWatch log group for DMS
resource "aws_cloudwatch_log_group" "dms_log_group" {
  name              = "/aws/dms/${local.project_name}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-dms-logs"
  })
}