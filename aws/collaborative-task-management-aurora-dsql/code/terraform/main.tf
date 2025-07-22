# Real-Time Collaborative Task Management Infrastructure
# Aurora DSQL + EventBridge + Lambda + CloudWatch
# 
# This configuration creates a serverless, multi-region task management system
# with strong consistency, event-driven architecture, and comprehensive monitoring.

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming if not provided
resource "random_string" "suffix" {
  count   = var.random_suffix == "" ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

locals {
  # Compute resource names with consistent naming convention
  random_suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix[0].result
  
  dsql_cluster_name    = var.dsql_cluster_name != "" ? var.dsql_cluster_name : "${var.project_name}-cluster-${local.random_suffix}"
  event_bus_name       = var.event_bus_name != "" ? var.event_bus_name : "${var.project_name}-events-${local.random_suffix}"
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-processor-${local.random_suffix}"
  log_group_name       = "/aws/lambda/${local.lambda_function_name}"
  
  # Database configuration
  db_password = var.db_password != "" ? var.db_password : random_password.db_password[0].result
  
  # Common tags for all resources
  common_tags = merge(
    var.enable_cost_allocation_tags ? {
      CostCenter    = var.project_name
      Application   = "task-management"
      Component     = "serverless"
      Owner         = data.aws_caller_identity.current.user_id
    } : {},
    {
      Environment   = var.environment
      Project       = var.project_name
      ManagedBy     = "terraform"
      Recipe        = "real-time-collaborative-task-management-aurora-dsql-eventbridge"
      LastUpdated   = formatdate("YYYY-MM-DD", timestamp())
    }
  )
}

# Generate secure random password for database if not provided
resource "random_password" "db_password" {
  count   = var.db_password == "" ? 1 : 0
  length  = 16
  special = true
}

# Store database password securely in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.dsql_cluster_name}-credentials"
  description = "Database credentials for Aurora DSQL cluster"
  
  # Enable automatic rotation every 30 days for enhanced security
  rotation_rules {
    automatically_after_days = 30
  }

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = local.db_password
  })
}

# ===============================================================================
# AURORA POSTGRESQL SERVERLESS V2 MULTI-REGION CLUSTER CONFIGURATION
# ===============================================================================

# Aurora PostgreSQL Global Cluster for multi-region active-active capabilities
# Provides distributed SQL with strong consistency and automatic scaling
resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier   = local.dsql_cluster_name
  engine                     = "aurora-postgresql"
  engine_version             = "15.4"
  storage_encrypted          = var.enable_database_encryption
  deletion_protection        = var.dsql_deletion_protection
  
  tags = merge(local.common_tags, {
    Name = "${local.dsql_cluster_name}-global"
    Type = "aurora-postgresql-global-cluster"
  })
}

# Primary Aurora PostgreSQL Serverless v2 cluster
# Provides serverless scaling with active-active multi-region support
resource "aws_rds_cluster" "primary" {
  cluster_identifier     = "${local.dsql_cluster_name}-primary"
  engine                = "aurora-postgresql"
  engine_version        = "15.4"
  database_name         = "taskmanagement"
  master_username       = var.db_username
  manage_master_user_password = true
  
  # Serverless v2 configuration for automatic scaling
  engine_mode = "provisioned"
  
  # Security configuration with encryption at rest
  storage_encrypted               = var.enable_database_encryption
  deletion_protection            = var.dsql_deletion_protection
  backup_retention_period        = 7
  preferred_backup_window        = "07:00-09:00"
  preferred_maintenance_window   = "sun:09:00-sun:11:00"
  
  # Performance and monitoring configuration
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.dsql_monitoring[0].arn : null
  
  # Network configuration for VPC deployment
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  
  # Enable automated minor version upgrades
  auto_minor_version_upgrade = true
  
  # Configure for global cluster
  global_cluster_identifier = aws_rds_global_cluster.main.id
  
  # Enable enhanced logging
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  tags = merge(local.common_tags, {
    Name   = "${local.dsql_cluster_name}-primary"
    Region = "primary"
    Type   = "aurora-postgresql-cluster"
  })

  depends_on = [aws_rds_global_cluster.main]
}

# Aurora Serverless v2 instance for primary cluster
resource "aws_rds_cluster_instance" "primary" {
  identifier         = "${local.dsql_cluster_name}-primary-instance"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  
  # Serverless v2 scaling configuration
  performance_insights_enabled = true
  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.dsql_monitoring[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.dsql_cluster_name}-primary-instance"
    Type = "aurora-postgresql-serverless-instance"
  })
}

# Secondary Aurora PostgreSQL cluster for multi-region setup
resource "aws_rds_cluster" "secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  cluster_identifier = "${local.dsql_cluster_name}-secondary"
  engine            = "aurora-postgresql"
  engine_version    = "15.4"
  
  # Inherit security settings from primary cluster
  storage_encrypted               = var.enable_database_encryption
  deletion_protection            = var.dsql_deletion_protection
  backup_retention_period        = 7
  preferred_backup_window        = "07:00-09:00"
  preferred_maintenance_window   = "sun:09:00-sun:11:00"
  
  # Performance monitoring configuration
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.dsql_monitoring_secondary[0].arn : null
  
  # Network configuration for secondary region
  db_subnet_group_name   = aws_db_subnet_group.secondary[0].name
  vpc_security_group_ids = [aws_security_group.aurora_secondary[0].id]
  
  auto_minor_version_upgrade = true
  
  # Link to global cluster for multi-region replication
  global_cluster_identifier = aws_rds_global_cluster.main.id
  
  # Enable enhanced logging
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  tags = merge(local.common_tags, {
    Name   = "${local.dsql_cluster_name}-secondary"
    Region = "secondary"
    Type   = "aurora-postgresql-cluster"
  })

  depends_on = [
    aws_rds_global_cluster.main,
    aws_rds_cluster.primary
  ]
}

# Aurora Serverless v2 instance for secondary cluster
resource "aws_rds_cluster_instance" "secondary" {
  count      = var.enable_multi_region_deployment ? 1 : 0
  provider   = aws.secondary
  
  identifier         = "${local.dsql_cluster_name}-secondary-instance"
  cluster_identifier = aws_rds_cluster.secondary[0].id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.secondary[0].engine
  engine_version     = aws_rds_cluster.secondary[0].engine_version
  
  performance_insights_enabled = true
  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.dsql_monitoring_secondary[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.dsql_cluster_name}-secondary-instance"
    Type = "aurora-postgresql-serverless-instance"
  })
}

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_availability_zones" "secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  state    = "available"
}

# ===============================================================================
# NETWORKING CONFIGURATION
# ===============================================================================

# VPC for Aurora cluster deployment in primary region
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
    Type = "vpc"
  })
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
    Type = "internet-gateway"
  })
}

# Private subnets for Aurora cluster in primary region
resource "aws_subnet" "private" {
  count = 2
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "private-subnet"
  })
}

# Public subnets for NAT Gateway in primary region
resource "aws_subnet" "public" {
  count = 2
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Type = "public-subnet"
  })
}

# NAT Gateway for private subnet internet access
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip"
    Type = "elastic-ip"
  })
  
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-gateway"
    Type = "nat-gateway"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# Route tables for private and public subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
    Type = "route-table"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
    Type = "route-table"
  })
}

# Route table associations
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# DB subnet group for Aurora cluster
resource "aws_db_subnet_group" "main" {
  name       = "${local.dsql_cluster_name}-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  
  tags = merge(local.common_tags, {
    Name = "${local.dsql_cluster_name}-subnet-group"
    Type = "db-subnet-group"
  })
}

# Security group for Aurora cluster
resource "aws_security_group" "aurora" {
  name        = "${local.dsql_cluster_name}-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.main.id
  
  # Allow inbound PostgreSQL connections from Lambda security group
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "PostgreSQL access from Lambda functions"
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.dsql_cluster_name}-sg"
    Type = "security-group"
  })
}

# Security group for Lambda functions
resource "aws_security_group" "lambda" {
  name        = "${local.lambda_function_name}-sg"
  description = "Security group for task processor Lambda functions"
  vpc_id      = aws_vpc.main.id
  
  # Allow all outbound traffic (for Aurora, EventBridge, Secrets Manager access)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-sg"
    Type = "security-group"
  })
}

# Secondary region VPC and networking (if multi-region enabled)
resource "aws_vpc" "secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-vpc-secondary"
    Type   = "vpc"
    Region = "secondary"
  })
}

resource "aws_internet_gateway" "secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  vpc_id = aws_vpc.secondary[0].id
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-igw-secondary"
    Type   = "internet-gateway"
    Region = "secondary"
  })
}

resource "aws_subnet" "private_secondary" {
  count    = var.enable_multi_region_deployment ? 2 : 0
  provider = aws.secondary
  
  vpc_id            = aws_vpc.secondary[0].id
  cidr_block        = "10.1.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.secondary[0].names[count.index]
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-private-subnet-secondary-${count.index + 1}"
    Type   = "private-subnet"
    Region = "secondary"
  })
}

resource "aws_subnet" "public_secondary" {
  count    = var.enable_multi_region_deployment ? 2 : 0
  provider = aws.secondary
  
  vpc_id                  = aws_vpc.secondary[0].id
  cidr_block              = "10.1.${count.index + 10}.0/24"
  availability_zone       = data.aws_availability_zones.secondary[0].names[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-public-subnet-secondary-${count.index + 1}"
    Type   = "public-subnet"
    Region = "secondary"
  })
}

resource "aws_eip" "nat_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-nat-eip-secondary"
    Type   = "elastic-ip"
    Region = "secondary"
  })
  
  depends_on = [aws_internet_gateway.secondary[0]]
}

resource "aws_nat_gateway" "secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  allocation_id = aws_eip.nat_secondary[0].id
  subnet_id     = aws_subnet.public_secondary[0].id
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-nat-gateway-secondary"
    Type   = "nat-gateway"
    Region = "secondary"
  })
  
  depends_on = [aws_internet_gateway.secondary[0]]
}

resource "aws_route_table" "private_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  vpc_id = aws_vpc.secondary[0].id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.secondary[0].id
  }
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-private-rt-secondary"
    Type   = "route-table"
    Region = "secondary"
  })
}

resource "aws_route_table" "public_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  vpc_id = aws_vpc.secondary[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary[0].id
  }
  
  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-public-rt-secondary"
    Type   = "route-table"
    Region = "secondary"
  })
}

resource "aws_route_table_association" "private_secondary" {
  count    = var.enable_multi_region_deployment ? 2 : 0
  provider = aws.secondary
  
  subnet_id      = aws_subnet.private_secondary[count.index].id
  route_table_id = aws_route_table.private_secondary[0].id
}

resource "aws_route_table_association" "public_secondary" {
  count    = var.enable_multi_region_deployment ? 2 : 0
  provider = aws.secondary
  
  subnet_id      = aws_subnet.public_secondary[count.index].id
  route_table_id = aws_route_table.public_secondary[0].id
}

resource "aws_db_subnet_group" "secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  name       = "${local.dsql_cluster_name}-subnet-group-secondary"
  subnet_ids = aws_subnet.private_secondary[*].id
  
  tags = merge(local.common_tags, {
    Name   = "${local.dsql_cluster_name}-subnet-group-secondary"
    Type   = "db-subnet-group"
    Region = "secondary"
  })
}

resource "aws_security_group" "aurora_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  name        = "${local.dsql_cluster_name}-sg-secondary"
  description = "Security group for Aurora PostgreSQL cluster in secondary region"
  vpc_id      = aws_vpc.secondary[0].id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_secondary[0].id]
    description     = "PostgreSQL access from Lambda functions"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name   = "${local.dsql_cluster_name}-sg-secondary"
    Type   = "security-group"
    Region = "secondary"
  })
}

resource "aws_security_group" "lambda_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  name        = "${local.lambda_function_name}-sg-secondary"
  description = "Security group for task processor Lambda functions in secondary region"
  vpc_id      = aws_vpc.secondary[0].id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-sg-secondary"
    Type   = "security-group"
    Region = "secondary"
  })
}

# IAM role for Aurora DSQL enhanced monitoring
resource "aws_iam_role" "dsql_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  name  = "${local.dsql_cluster_name}-monitoring-role"

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

resource "aws_iam_role_policy_attachment" "dsql_monitoring" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.dsql_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM role for Aurora DSQL enhanced monitoring in secondary region
resource "aws_iam_role" "dsql_monitoring_secondary" {
  count    = var.enable_enhanced_monitoring && var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  name     = "${local.dsql_cluster_name}-monitoring-role-secondary"

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

resource "aws_iam_role_policy_attachment" "dsql_monitoring_secondary" {
  count      = var.enable_enhanced_monitoring && var.enable_multi_region_deployment ? 1 : 0
  provider   = aws.secondary
  role       = aws_iam_role.dsql_monitoring_secondary[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ===============================================================================
# EVENTBRIDGE CONFIGURATION
# ===============================================================================

# Custom EventBridge event bus for task management events
# Provides event-driven architecture with flexible routing and filtering
resource "aws_cloudwatch_event_bus" "task_events" {
  name = local.event_bus_name

  tags = merge(local.common_tags, {
    Name = local.event_bus_name
    Type = "eventbridge-bus"
  })
}

# Custom EventBridge event bus in secondary region
resource "aws_cloudwatch_event_bus" "task_events_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  name     = local.event_bus_name

  tags = merge(local.common_tags, {
    Name   = local.event_bus_name
    Type   = "eventbridge-bus"
    Region = "secondary"
  })
}

# EventBridge rule for task processing events
# Routes task creation, update, and completion events to Lambda processor
resource "aws_cloudwatch_event_rule" "task_processing" {
  name           = "${local.lambda_function_name}-processing-rule"
  description    = "Route task management events to Lambda processor"
  event_bus_name = aws_cloudwatch_event_bus.task_events.name
  state          = "ENABLED"

  # Event pattern for task management events
  event_pattern = jsonencode({
    source        = ["task.management"]
    detail-type   = ["Task Created", "Task Updated", "Task Completed"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-processing-rule"
    Type = "eventbridge-rule"
  })
}

# EventBridge rule in secondary region
resource "aws_cloudwatch_event_rule" "task_processing_secondary" {
  count          = var.enable_multi_region_deployment ? 1 : 0
  provider       = aws.secondary
  name           = "${local.lambda_function_name}-processing-rule"
  description    = "Route task management events to Lambda processor"
  event_bus_name = aws_cloudwatch_event_bus.task_events_secondary[0].name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source        = ["task.management"]
    detail-type   = ["Task Created", "Task Updated", "Task Completed"]
  })

  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-processing-rule"
    Type   = "eventbridge-rule"
    Region = "secondary"
  })
}

# EventBridge targets to route events to Lambda functions
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule           = aws_cloudwatch_event_rule.task_processing.name
  event_bus_name = aws_cloudwatch_event_bus.task_events.name
  target_id      = "TaskProcessorLambda"
  arn            = aws_lambda_function.task_processor.arn

  # Configure retry policy for resilient event processing
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }

  # Route failed events to dead letter queue if enabled
  dead_letter_config {
    arn = var.enable_dead_letter_queue ? aws_sqs_queue.task_dlq[0].arn : null
  }
}

resource "aws_cloudwatch_event_target" "lambda_target_secondary" {
  count          = var.enable_multi_region_deployment ? 1 : 0
  provider       = aws.secondary
  rule           = aws_cloudwatch_event_rule.task_processing_secondary[0].name
  event_bus_name = aws_cloudwatch_event_bus.task_events_secondary[0].name
  target_id      = "TaskProcessorLambda"
  arn            = aws_lambda_function.task_processor_secondary[0].arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }

  dead_letter_config {
    arn = var.enable_dead_letter_queue && var.enable_multi_region_deployment ? aws_sqs_queue.task_dlq_secondary[0].arn : null
  }
}

# ===============================================================================
# LAMBDA FUNCTION CONFIGURATION
# ===============================================================================

# IAM role for Lambda function execution
# Provides necessary permissions for Aurora DSQL, EventBridge, CloudWatch, and Secrets Manager
resource "aws_iam_role" "lambda_execution" {
  name = "${local.lambda_function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Custom IAM policy for Lambda function with fine-grained permissions
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.lambda_function_name}-policy"
  description = "Custom policy for task management Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusterSnapshots",
          "rds:ListTagsForResource"
        ]
        Resource = [
          aws_rds_cluster.primary.arn,
          "${aws_rds_cluster.primary.arn}:*",
          var.enable_multi_region_deployment ? aws_rds_cluster.secondary[0].arn : aws_rds_cluster.primary.arn,
          var.enable_multi_region_deployment ? "${aws_rds_cluster.secondary[0].arn}:*" : "${aws_rds_cluster.primary.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_identifier}/${var.db_username}",
          var.enable_multi_region_deployment ? "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary[0].cluster_identifier}/${var.db_username}" : "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_identifier}/${var.db_username}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "events:DescribeEventBus",
          "events:ListRules"
        ]
        Resource = [
          aws_cloudwatch_event_bus.task_events.arn,
          var.enable_multi_region_deployment ? aws_cloudwatch_event_bus.task_events_secondary[0].arn : aws_cloudwatch_event_bus.task_events.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Attach AWS managed policies for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach AWS managed policy for VPC execution
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach AWS managed policy for X-Ray tracing if enabled
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Package Lambda function source code
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/task_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      db_secret_arn = aws_secretsmanager_secret.db_credentials.arn
      event_bus_name = local.event_bus_name
    })
    filename = "task_processor.py"
  }

  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Primary Lambda function for task processing
resource "aws_lambda_function" "task_processor" {
  filename                       = data.archive_file.lambda_package.output_path
  function_name                  = local.lambda_function_name
  role                          = aws_iam_role.lambda_execution.arn
  handler                       = "task_processor.lambda_handler"
  source_code_hash              = data.archive_file.lambda_package.output_base64sha256
  
  # Runtime configuration
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
  architectures = [var.lambda_architecture]
  
  # Performance configuration
  reserved_concurrent_executions = var.lambda_reserved_concurrency == -1 ? null : var.lambda_reserved_concurrency
  
  # Environment variables for database and EventBridge integration
  environment {
    variables = {
      DSQL_CLUSTER_ENDPOINT = aws_rds_cluster.primary.endpoint
      DSQL_CLUSTER_PORT     = aws_rds_cluster.primary.port
      DB_SECRET_ARN         = aws_secretsmanager_secret.db_credentials.arn
      EVENT_BUS_NAME        = local.event_bus_name
      AWS_REGION            = var.aws_region
      ENVIRONMENT           = var.environment
      LOG_LEVEL             = "INFO"
    }
  }

  # VPC configuration for database access
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Enable X-Ray tracing for distributed tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  # Dead letter queue configuration for failed invocations
  dead_letter_config {
    target_arn = var.enable_dead_letter_queue ? aws_sqs_queue.lambda_dlq[0].arn : null
  }

  # Logging configuration with structured JSON logging
  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
    log_group             = aws_cloudwatch_log_group.lambda_logs.name
  }

  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "lambda-function"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Secondary Lambda function for multi-region deployment
resource "aws_lambda_function" "task_processor_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  filename                       = data.archive_file.lambda_package.output_path
  function_name                  = local.lambda_function_name
  role                          = aws_iam_role.lambda_execution_secondary[0].arn
  handler                       = "task_processor.lambda_handler"
  source_code_hash              = data.archive_file.lambda_package.output_base64sha256
  
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
  architectures = [var.lambda_architecture]
  
  reserved_concurrent_executions = var.lambda_reserved_concurrency == -1 ? null : var.lambda_reserved_concurrency
  
  environment {
    variables = {
      DSQL_CLUSTER_ENDPOINT = var.enable_multi_region_deployment ? aws_rds_cluster.secondary[0].endpoint : aws_rds_cluster.primary.endpoint
      DSQL_CLUSTER_PORT     = var.enable_multi_region_deployment ? aws_rds_cluster.secondary[0].port : aws_rds_cluster.primary.port
      DB_SECRET_ARN         = aws_secretsmanager_secret.db_credentials_secondary[0].arn
      EVENT_BUS_NAME        = local.event_bus_name
      AWS_REGION            = var.secondary_region
      ENVIRONMENT           = var.environment
      LOG_LEVEL             = "INFO"
    }
  }

  # VPC configuration for database access in secondary region
  vpc_config {
    subnet_ids         = aws_subnet.private_secondary[*].id
    security_group_ids = [aws_security_group.lambda_secondary[0].id]
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  dead_letter_config {
    target_arn = var.enable_dead_letter_queue && var.enable_multi_region_deployment ? aws_sqs_queue.lambda_dlq_secondary[0].arn : null
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
    log_group             = aws_cloudwatch_log_group.lambda_logs_secondary[0].name
  }

  tags = merge(local.common_tags, {
    Name   = local.lambda_function_name
    Type   = "lambda-function"
    Region = "secondary"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_custom_policy_secondary[0],
    aws_iam_role_policy_attachment.lambda_basic_execution_secondary[0],
    aws_cloudwatch_log_group.lambda_logs_secondary[0]
  ]
}

# Lambda permissions to allow EventBridge to invoke functions
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.task_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.task_processing.arn
}

resource "aws_lambda_permission" "eventbridge_invoke_secondary" {
  count         = var.enable_multi_region_deployment ? 1 : 0
  provider      = aws.secondary
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.task_processor_secondary[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.task_processing_secondary[0].arn
}

# Provisioned concurrency configuration if enabled
resource "aws_lambda_provisioned_concurrency_config" "task_processor" {
  count                     = var.lambda_provisioned_concurrency > 0 ? 1 : 0
  function_name             = aws_lambda_function.task_processor.function_name
  provisioned_concurrent_executions = var.lambda_provisioned_concurrency
  qualifier                 = aws_lambda_function.task_processor.version
}

# ===============================================================================
# DEAD LETTER QUEUE CONFIGURATION
# ===============================================================================

# SQS dead letter queue for failed Lambda invocations
resource "aws_sqs_queue" "lambda_dlq" {
  count = var.enable_dead_letter_queue ? 1 : 0
  name  = "${local.lambda_function_name}-dlq"
  
  # Configure message retention and visibility timeout
  message_retention_seconds = 1209600  # 14 days
  visibility_timeout_seconds = 60
  
  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sqs"
  
  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-dlq"
    Type = "sqs-dlq"
  })
}

# SQS dead letter queue for EventBridge failed events
resource "aws_sqs_queue" "task_dlq" {
  count = var.enable_dead_letter_queue ? 1 : 0
  name  = "${local.event_bus_name}-dlq"
  
  message_retention_seconds = 1209600  # 14 days
  visibility_timeout_seconds = 60
  kms_master_key_id = "alias/aws/sqs"
  
  tags = merge(local.common_tags, {
    Name = "${local.event_bus_name}-dlq"
    Type = "sqs-dlq"
  })
}

# Secondary region dead letter queues
resource "aws_sqs_queue" "lambda_dlq_secondary" {
  count    = var.enable_dead_letter_queue && var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  name     = "${local.lambda_function_name}-dlq"
  
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 60
  kms_master_key_id = "alias/aws/sqs"
  
  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-dlq"
    Type   = "sqs-dlq"
    Region = "secondary"
  })
}

resource "aws_sqs_queue" "task_dlq_secondary" {
  count    = var.enable_dead_letter_queue && var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  name     = "${local.event_bus_name}-dlq"
  
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 60
  kms_master_key_id = "alias/aws/sqs"
  
  tags = merge(local.common_tags, {
    Name   = "${local.event_bus_name}-dlq"
    Type   = "sqs-dlq"
    Region = "secondary"
  })
}

# ===============================================================================
# CLOUDWATCH MONITORING CONFIGURATION
# ===============================================================================

# CloudWatch log group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  # Enable encryption at rest for log data
  kms_key_id = aws_kms_key.logs_encryption.arn

  tags = merge(local.common_tags, {
    Name = local.log_group_name
    Type = "cloudwatch-log-group"
  })
}

# CloudWatch log group for secondary region Lambda
resource "aws_cloudwatch_log_group" "lambda_logs_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs_encryption_secondary[0].arn

  tags = merge(local.common_tags, {
    Name   = local.log_group_name
    Type   = "cloudwatch-log-group"
    Region = "secondary"
  })
}

# KMS key for CloudWatch logs encryption
resource "aws_kms_key" "logs_encryption" {
  description             = "KMS key for CloudWatch logs encryption"
  deletion_window_in_days = 7
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableCloudWatchLogsAccess"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "logs_encryption" {
  name          = "alias/${local.lambda_function_name}-logs"
  target_key_id = aws_kms_key.logs_encryption.key_id
}

# Secondary region KMS key for logs encryption
resource "aws_kms_key" "logs_encryption_secondary" {
  count       = var.enable_multi_region_deployment ? 1 : 0
  provider    = aws.secondary
  description = "KMS key for CloudWatch logs encryption in secondary region"
  deletion_window_in_days = 7
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableCloudWatchLogsAccess"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.secondary_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "logs_encryption_secondary" {
  count         = var.enable_multi_region_deployment ? 1 : 0
  provider      = aws.secondary
  name          = "alias/${local.lambda_function_name}-logs-secondary"
  target_key_id = aws_kms_key.logs_encryption_secondary[0].key_id
}

# CloudWatch alarms for Lambda function monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.task_processor.function_name
  }

  alarm_actions = compact([
    for endpoint in var.notification_endpoints : endpoint
  ])

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8)  # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors Lambda function duration"
  
  dimensions = {
    FunctionName = aws_lambda_function.task_processor.function_name
  }

  alarm_actions = compact([
    for endpoint in var.notification_endpoints : endpoint
  ])

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${local.lambda_function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function throttles"
  
  dimensions = {
    FunctionName = aws_lambda_function.task_processor.function_name
  }

  alarm_actions = compact([
    for endpoint in var.notification_endpoints : endpoint
  ])

  tags = local.common_tags
}

# CloudWatch dashboard for comprehensive monitoring
resource "aws_cloudwatch_dashboard" "task_management" {
  count          = var.create_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.task_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Function Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Events", "SuccessfulInvocations", "EventBusName", aws_cloudwatch_event_bus.task_events.name],
            [".", "FailedInvocations", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "EventBridge Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.lambda_logs.name}'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 100"
          region  = var.aws_region
          title   = "Recent Lambda Logs"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM resources for secondary region Lambda function
resource "aws_iam_role" "lambda_execution_secondary" {
  count    = var.enable_multi_region_deployment ? 1 : 0
  provider = aws.secondary
  name     = "${local.lambda_function_name}-execution-role-secondary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Secondary region database credentials secret
resource "aws_secretsmanager_secret" "db_credentials_secondary" {
  count       = var.enable_multi_region_deployment ? 1 : 0
  provider    = aws.secondary
  name        = "${local.dsql_cluster_name}-credentials-secondary"
  description = "Database credentials for Aurora DSQL cluster in secondary region"
  
  rotation_rules {
    automatically_after_days = 30
  }

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials_secondary" {
  count     = var.enable_multi_region_deployment ? 1 : 0
  provider  = aws.secondary
  secret_id = aws_secretsmanager_secret.db_credentials_secondary[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = local.db_password
  })
}

# Custom IAM policy for secondary region Lambda function
resource "aws_iam_policy" "lambda_policy_secondary" {
  count       = var.enable_multi_region_deployment ? 1 : 0
  provider    = aws.secondary
  name        = "${local.lambda_function_name}-policy-secondary"
  description = "Custom policy for task management Lambda function in secondary region"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusterSnapshots",
          "rds:ListTagsForResource"
        ]
        Resource = [
          aws_rds_cluster.secondary[0].arn,
          "${aws_rds_cluster.secondary[0].arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary[0].cluster_identifier}/${var.db_username}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "events:DescribeEventBus",
          "events:ListRules"
        ]
        Resource = [
          aws_cloudwatch_event_bus.task_events_secondary[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials_secondary[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach policies to secondary region Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy_secondary" {
  count      = var.enable_multi_region_deployment ? 1 : 0
  provider   = aws.secondary
  role       = aws_iam_role.lambda_execution_secondary[0].name
  policy_arn = aws_iam_policy.lambda_policy_secondary[0].arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_secondary" {
  count      = var.enable_multi_region_deployment ? 1 : 0
  provider   = aws.secondary
  role       = aws_iam_role.lambda_execution_secondary[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray_secondary" {
  count      = var.enable_xray_tracing && var.enable_multi_region_deployment ? 1 : 0
  provider   = aws.secondary
  role       = aws_iam_role.lambda_execution_secondary[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution_secondary" {
  count      = var.enable_multi_region_deployment ? 1 : 0
  provider   = aws.secondary
  role       = aws_iam_role.lambda_execution_secondary[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}