# Main Terraform configuration for containerized web application with App Runner and RDS
# This deploys a complete infrastructure including VPC, RDS, ECR, App Runner, and monitoring

# Data sources for AWS account information and availability zones
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Combine default and additional tags
  common_tags = merge(
    var.default_tags,
    var.additional_tags,
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  )
}

# VPC and Networking Resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
    Type = "VPC"
  })
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
    Type = "InternetGateway"
  })
}

# Public subnets for NAT gateways
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "PublicSubnet"
    AZ   = data.aws_availability_zones.available.names[count.index]
  })
}

# Private subnets for RDS
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "PrivateSubnet"
    AZ   = data.aws_availability_zones.available.names[count.index]
  })
}

# Elastic IPs for NAT gateways
resource "aws_eip" "nat" {
  count = length(var.public_subnet_cidrs)

  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
    Type = "NATGatewayEIP"
  })
}

# NAT gateways for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gw-${count.index + 1}"
    Type = "NATGateway"
  })
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
    Type = "PublicRouteTable"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
    Type = "PrivateRouteTable"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security group for App Runner VPC connector
resource "aws_security_group" "apprunner" {
  name_prefix = "${local.name_prefix}-apprunner-"
  description = "Security group for App Runner VPC connector"
  vpc_id      = aws_vpc.main.id

  # Outbound traffic to RDS
  egress {
    description     = "Database access"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  # Outbound HTTPS traffic for external API calls
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound HTTP traffic for external API calls
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-sg"
    Type = "SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for RDS instance
resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.main.id

  # Inbound PostgreSQL traffic from App Runner
  ingress {
    description     = "PostgreSQL from App Runner"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.apprunner.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
    Type = "SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# VPC Connector for App Runner to access VPC resources
resource "aws_apprunner_vpc_connector" "main" {
  vpc_connector_name = "${local.name_prefix}-vpc-connector"
  subnets           = aws_subnet.private[*].id
  security_groups   = [aws_security_group.apprunner.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-connector"
    Type = "AppRunnerVPCConnector"
  })
}

# KMS key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${local.name_prefix} resources"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
    Type = "KMSKey"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}-key"
  target_key_id = aws_kms_key.main.key_id
}

# ECR Repository for container images
resource "aws_ecr_repository" "main" {
  name                 = "${local.name_prefix}-app-${local.name_suffix}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_image_scan
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = aws_kms_key.main.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-repo"
    Type = "ECRRepository"
  })
}

# ECR lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# DB Subnet Group for RDS
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
    Type = "DBSubnetGroup"
  })
}

# Random password for RDS (if not using managed master user password)
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# RDS PostgreSQL instance
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db-${local.name_suffix}"
  
  # Engine configuration
  engine              = "postgres"
  engine_version      = var.db_engine_version
  instance_class      = var.db_instance_class
  
  # Database configuration
  db_name  = "webapp"
  username = "postgres"
  password = random_password.db_password.result
  
  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  storage_type         = var.db_storage_type
  storage_encrypted    = var.db_storage_encrypted
  kms_key_id          = var.db_storage_encrypted ? aws_kms_key.main.arn : null
  
  # Networking configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  
  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  
  # High availability and monitoring
  multi_az               = var.db_multi_az
  monitoring_interval    = 60
  monitoring_role_arn    = aws_iam_role.rds_enhanced_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  # Security
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = true
  
  # Performance insights
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.main.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database"
    Type = "RDSInstance"
  })

  depends_on = [
    aws_db_subnet_group.main,
    aws_security_group.rds
  ]
}

# Secrets Manager secret for database credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.name_prefix}-db-credentials-${local.name_suffix}"
  description = "Database credentials for ${local.name_prefix} application"
  kms_key_id  = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-secret"
    Type = "SecretsManagerSecret"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db_password.result
    host     = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# IAM role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role-${local.name_suffix}"

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
    Type = "IAMRole"
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM role for App Runner instance (task role)
resource "aws_iam_role" "apprunner_instance_role" {
  name = "${local.name_prefix}-apprunner-instance-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-instance-role"
    Type = "IAMRole"
  })
}

# IAM policy for App Runner to access Secrets Manager
resource "aws_iam_role_policy" "apprunner_secrets_policy" {
  name = "${local.name_prefix}-apprunner-secrets-policy"
  role = aws_iam_role.apprunner_instance_role.id

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
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# IAM role for App Runner service (access role for ECR)
resource "aws_iam_role" "apprunner_access_role" {
  name = "${local.name_prefix}-apprunner-access-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-access-role"
    Type = "IAMRole"
  })
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  role       = aws_iam_role.apprunner_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# CloudWatch Log Group for App Runner application logs
resource "aws_cloudwatch_log_group" "apprunner_application" {
  name              = "/aws/apprunner/${local.name_prefix}-app-${local.name_suffix}/application"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-app-logs"
    Type = "CloudWatchLogGroup"
  })
}

# CloudWatch Log Group for App Runner service logs
resource "aws_cloudwatch_log_group" "apprunner_service" {
  name              = "/aws/apprunner/${local.name_prefix}-app-${local.name_suffix}/service"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-service-logs"
    Type = "CloudWatchLogGroup"
  })
}

# App Runner Service
resource "aws_apprunner_service" "main" {
  service_name = "${local.name_prefix}-app-${local.name_suffix}"

  source_configuration {
    image_repository {
      image_identifier      = "${aws_ecr_repository.main.repository_url}:${var.container_image_tag}"
      image_repository_type = "ECR"

      image_configuration {
        port = var.apprunner_port

        runtime_environment_variables = {
          NODE_ENV   = var.environment
          AWS_REGION = var.aws_region
          PORT       = var.apprunner_port
        }

        runtime_environment_secrets = {
          DB_SECRET_NAME = aws_secretsmanager_secret.db_credentials.name
        }
      }
    }

    auto_deployments_enabled = var.enable_auto_deployments
  }

  instance_configuration {
    cpu               = var.apprunner_cpu
    memory            = var.apprunner_memory
    instance_role_arn = aws_iam_role.apprunner_instance_role.arn
  }

  health_check_configuration {
    protocol                = "HTTP"
    path                   = var.apprunner_health_check_path
    interval               = var.apprunner_health_check_interval
    timeout                = var.apprunner_health_check_timeout
    healthy_threshold      = var.apprunner_health_check_healthy_threshold
    unhealthy_threshold    = var.apprunner_health_check_unhealthy_threshold
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.main.arn
    }
  }

  observability_configuration {
    observability_enabled   = true
    observability_configuration_arn = aws_apprunner_observability_configuration.main.arn
  }

  # Access role for ECR
  access_role_arn = aws_iam_role.apprunner_access_role.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-service"
    Type = "AppRunnerService"
  })

  depends_on = [
    aws_ecr_repository.main,
    aws_apprunner_vpc_connector.main,
    aws_cloudwatch_log_group.apprunner_application,
    aws_cloudwatch_log_group.apprunner_service,
    aws_secretsmanager_secret_version.db_credentials
  ]
}

# App Runner Observability Configuration
resource "aws_apprunner_observability_configuration" "main" {
  observability_configuration_name = "${local.name_prefix}-observability-${local.name_suffix}"

  trace_configuration {
    vendor = "AWSXRAY"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-observability-config"
    Type = "AppRunnerObservabilityConfiguration"
  })
}

# SNS Topic for CloudWatch Alarms (if email provided)
resource "aws_sns_topic" "alarms" {
  count = var.alarm_notification_email != "" ? 1 : 0

  name              = "${local.name_prefix}-alarms-${local.name_suffix}"
  display_name      = "CloudWatch Alarms for ${local.name_prefix}"
  kms_master_key_id = aws_kms_key.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alarms-topic"
    Type = "SNSTopic"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# CloudWatch Alarms for App Runner
resource "aws_cloudwatch_metric_alarm" "apprunner_cpu" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "${local.name_prefix}-apprunner-high-cpu"
  alarm_description = "App Runner service has high CPU utilization"
  
  metric_name = "CPUUtilization"
  namespace   = "AWS/AppRunner"
  statistic   = "Average"
  
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  
  dimensions = {
    ServiceName = aws_apprunner_service.main.service_name
  }

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-cpu-alarm"
    Type = "CloudWatchAlarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "apprunner_memory" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "${local.name_prefix}-apprunner-high-memory"
  alarm_description = "App Runner service has high memory utilization"
  
  metric_name = "MemoryUtilization"
  namespace   = "AWS/AppRunner"
  statistic   = "Average"
  
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  
  dimensions = {
    ServiceName = aws_apprunner_service.main.service_name
  }

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-memory-alarm"
    Type = "CloudWatchAlarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "apprunner_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "${local.name_prefix}-apprunner-high-latency"
  alarm_description = "App Runner service has high response latency"
  
  metric_name = "RequestLatency"
  namespace   = "AWS/AppRunner"
  statistic   = "Average"
  
  period              = 300
  evaluation_periods  = 2
  threshold           = 2000
  comparison_operator = "GreaterThanThreshold"
  
  dimensions = {
    ServiceName = aws_apprunner_service.main.service_name
  }

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apprunner-latency-alarm"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "${local.name_prefix}-rds-high-cpu"
  alarm_description = "RDS instance has high CPU utilization"
  
  metric_name = "CPUUtilization"
  namespace   = "AWS/RDS"
  statistic   = "Average"
  
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-cpu-alarm"
    Type = "CloudWatchAlarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "${local.name_prefix}-rds-high-connections"
  alarm_description = "RDS instance has high number of connections"
  
  metric_name = "DatabaseConnections"
  namespace   = "AWS/RDS"
  statistic   = "Average"
  
  period              = 300
  evaluation_periods  = 2
  threshold           = 40
  comparison_operator = "GreaterThanThreshold"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-connections-alarm"
    Type = "CloudWatchAlarm"
  })
}