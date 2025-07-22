# AWS Database Migration Service Infrastructure
# This file creates the complete infrastructure for AWS DMS migration solution

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Random password for RDS if not provided
resource "random_password" "rds_password" {
  count   = var.rds_password == "" ? 1 : 0
  length  = 16
  special = true
}

# Random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming
locals {
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  rds_password = var.rds_password != "" ? var.rds_password : random_password.rds_password[0].result
}

# VPC and Networking Resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = var.dms_publicly_accessible

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-subnet-1"
  })
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = var.rds_publicly_accessible

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-subnet-2"
  })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-rt"
  })
}

resource "aws_route_table_association" "subnet_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnet_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.main.id
}

# Security Groups
resource "aws_security_group" "dms" {
  name        = "${local.name_prefix}-dms-sg"
  description = "Security group for DMS replication instance"
  vpc_id      = aws_vpc.main.id

  # Outbound rules for database connectivity
  egress {
    description = "Oracle database access"
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "PostgreSQL database access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "MySQL database access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "SQL Server database access"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-dms-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS target database"
  vpc_id      = aws_vpc.main.id

  # Inbound rule for DMS access
  ingress {
    description     = "DMS access to PostgreSQL"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
  }

  # Inbound rule for external access (if required)
  dynamic "ingress" {
    for_each = var.rds_publicly_accessible ? [1] : []
    content {
      description = "External PostgreSQL access"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# IAM Roles for DMS
resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"

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

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role_policy" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  name = "dms-cloudwatch-logs-role"

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

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role_policy" {
  role       = aws_iam_role.dms_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

resource "aws_iam_role" "dms_access_for_endpoint" {
  name = "dms-access-for-endpoint"

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

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "dms_access_for_endpoint_policy" {
  role       = aws_iam_role.dms_access_for_endpoint.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSRedshiftS3Role"
}

# DMS Subnet Group
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_description = "Subnet group for DMS replication instance"
  replication_subnet_group_id          = "${local.name_prefix}-dms-subnet-group"
  subnet_ids                           = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-dms-subnet-group"
  })

  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role_policy]
}

# DMS Replication Instance
resource "aws_dms_replication_instance" "main" {
  replication_instance_class   = var.dms_replication_instance_class
  replication_instance_id      = "${local.name_prefix}-dms-instance"
  allocated_storage            = var.dms_allocated_storage
  engine_version               = var.dms_engine_version
  multi_az                     = var.dms_multi_az
  publicly_accessible          = var.dms_publicly_accessible
  replication_subnet_group_id  = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids       = [aws_security_group.dms.id]

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-dms-instance"
  })
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
  })
}

# RDS Target Database
resource "aws_db_instance" "target" {
  identifier             = "${local.name_prefix}-target-db"
  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  storage_type           = "gp2"
  storage_encrypted      = true
  
  db_name  = "postgres"
  username = var.rds_username
  password = local.rds_password
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  publicly_accessible    = var.rds_publicly_accessible
  deletion_protection    = var.enable_deletion_protection
  
  skip_final_snapshot = true
  
  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-target-db"
  })
}

# Default Table Mappings (if not provided)
locals {
  default_table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "1"
        object-locator = {
          schema-name = "HR"
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
          schema-name = "HR"
        }
        rule-action = "rename"
        value       = "hr_schema"
      }
    ]
  })

  default_task_settings = jsonencode({
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
      TargetTablePrepMode           = "DROP_AND_CREATE"
      CreatePkAfterFullLoad         = false
      StopTaskCachedChangesApplied  = false
      StopTaskCachedChangesNotApplied = false
      MaxFullLoadSubTasks           = 8
      TransactionConsistencyTimeout = 600
      CommitRate                    = 10000
    }
    Logging = {
      EnableLogging = var.enable_cloudwatch_logs
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
      CloudWatchLogGroup  = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.dms_logs[0].name : null
      CloudWatchLogStream = null
    }
    ErrorBehavior = {
      DataErrorPolicy               = "LOG_ERROR"
      DataTruncationErrorPolicy     = "LOG_ERROR"
      DataErrorEscalationPolicy     = "SUSPEND_TABLE"
      DataErrorEscalationCount      = 0
      TableErrorPolicy              = "SUSPEND_TABLE"
      TableErrorEscalationPolicy    = "STOP_TASK"
      TableErrorEscalationCount     = 0
      RecoverableErrorCount         = -1
      RecoverableErrorInterval      = 5
      RecoverableErrorThrottling    = true
      RecoverableErrorThrottlingMax = 1800
      RecoverableErrorStopRetryAfterThrottlingMax = false
      ApplyErrorDeletePolicy        = "IGNORE_RECORD"
      ApplyErrorInsertPolicy        = "LOG_ERROR"
      ApplyErrorUpdatePolicy        = "LOG_ERROR"
      ApplyErrorEscalationPolicy    = "LOG_ERROR"
      ApplyErrorEscalationCount     = 0
      ApplyErrorFailOnTruncationDdl = false
      FullLoadIgnoreConflicts       = true
      FailOnTransactionConsistencyBreached = false
      FailOnNoTablesCaptured        = true
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
  })
}

# DMS Source Endpoint
resource "aws_dms_endpoint" "source" {
  endpoint_id     = "${local.name_prefix}-source-endpoint"
  endpoint_type   = "source"
  engine_name     = var.source_db_engine
  server_name     = var.source_db_host
  port            = var.source_db_port
  username        = var.source_db_username
  password        = var.source_db_password
  database_name   = var.source_db_name
  
  tags = merge(var.common_tags, {
    Name         = "${local.name_prefix}-source-endpoint"
    EndpointType = "source"
  })
}

# DMS Target Endpoint
resource "aws_dms_endpoint" "target" {
  endpoint_id     = "${local.name_prefix}-target-endpoint"
  endpoint_type   = "target"
  engine_name     = var.rds_engine
  server_name     = aws_db_instance.target.address
  port            = aws_db_instance.target.port
  username        = var.rds_username
  password        = local.rds_password
  database_name   = aws_db_instance.target.db_name
  
  tags = merge(var.common_tags, {
    Name         = "${local.name_prefix}-target-endpoint"
    EndpointType = "target"
  })
}

# DMS Replication Task
resource "aws_dms_replication_task" "main" {
  replication_task_id       = "${local.name_prefix}-migration-task"
  replication_instance_arn  = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.target.endpoint_arn
  migration_type            = var.migration_type
  table_mappings            = var.table_mappings != "" ? var.table_mappings : local.default_table_mappings
  replication_task_settings = var.task_settings != "" ? var.task_settings : local.default_task_settings
  
  tags = merge(var.common_tags, {
    Name     = "${local.name_prefix}-migration-task"
    TaskType = var.migration_type
  })
}

# CloudWatch Resources
resource "aws_cloudwatch_log_group" "dms_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = var.cloudwatch_log_group
  retention_in_days = 7
  
  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-dms-logs"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "dms_monitoring" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-dms-monitoring"
  
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
            ["AWS/DMS", "FreeableMemory", "ReplicationInstanceIdentifier", aws_dms_replication_instance.main.replication_instance_id],
            [".", "CPUUtilization", ".", "."],
            [".", "NetworkTransmitThroughput", ".", "."],
            [".", "NetworkReceiveThroughput", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "DMS Replication Instance Metrics"
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
            ["AWS/DMS", "FullLoadThroughputBandwidthTarget", "ReplicationTaskIdentifier", aws_dms_replication_task.main.replication_task_id],
            [".", "FullLoadThroughputRowsTarget", ".", "."],
            [".", "CDCThroughputBandwidthTarget", ".", "."],
            [".", "CDCThroughputRowsTarget", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Migration Task Throughput"
        }
      }
    ]
  })
  
  tags = var.common_tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "dms_cpu_high" {
  alarm_name          = "${local.name_prefix}-dms-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors DMS replication instance CPU utilization"
  alarm_actions       = []
  
  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }
  
  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dms_memory_low" {
  alarm_name          = "${local.name_prefix}-dms-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "200000000"  # 200MB in bytes
  alarm_description   = "This metric monitors DMS replication instance memory usage"
  alarm_actions       = []
  
  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }
  
  tags = var.common_tags
}