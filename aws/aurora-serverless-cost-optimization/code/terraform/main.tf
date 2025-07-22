# Aurora Serverless v2 Cost Optimization Infrastructure
# This file contains the main infrastructure resources for Aurora Serverless v2 with intelligent cost optimization

# Data sources for existing infrastructure
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

# Get VPC information (either provided or default)
data "aws_vpc" "selected" {
  id = local.vpc_id
}

# Get subnets in the VPC if not specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  # Resource naming
  cluster_name = "${var.cluster_name_prefix}-${random_id.suffix.hex}"
  
  # VPC and networking
  vpc_id = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  use_existing_vpc = var.vpc_id != null && length(var.subnet_ids) > 0
  
  # Common tags
  common_tags = merge(
    {
      Name        = local.cluster_name
      Environment = var.environment
      Project     = "Aurora Serverless v2 Cost Optimization"
    },
    var.additional_tags
  )
}

# KMS key for Aurora encryption
resource "aws_kms_key" "aurora" {
  description             = "KMS key for Aurora Serverless v2 encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-kms-key"
    }
  )
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${local.cluster_name}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

# Security group for Aurora cluster
resource "aws_security_group" "aurora" {
  name_prefix = "${local.cluster_name}-aurora-"
  description = "Security group for Aurora Serverless v2 cluster"
  vpc_id      = local.vpc_id

  # PostgreSQL access from allowed CIDR blocks
  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-aurora-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# DB subnet group for Aurora cluster (only if not using existing VPC setup)
resource "aws_db_subnet_group" "aurora" {
  count       = local.use_existing_vpc ? 0 : 1
  name        = "${local.cluster_name}-subnet-group"
  description = "Subnet group for Aurora Serverless v2 cluster"
  subnet_ids  = local.subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-subnet-group"
    }
  )
}

# Custom cluster parameter group for cost optimization
resource "aws_rds_cluster_parameter_group" "aurora_cost_optimized" {
  family      = "aurora-postgresql15"
  name        = "${local.cluster_name}-cluster-params"
  description = "Aurora Serverless v2 cost optimization parameters"

  # Enable pg_stat_statements for query performance monitoring
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  # Increase query size tracking for better monitoring
  parameter {
    name  = "track_activity_query_size"
    value = "2048"
  }

  # Log DDL statements for monitoring
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  # Log slow queries (1 second threshold)
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Optimize for cost-aware workloads
  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }

  # Enable auto explain for expensive queries
  parameter {
    name  = "auto_explain.log_min_duration"
    value = "5000"
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Aurora Serverless v2 cluster
resource "aws_rds_cluster" "aurora_serverless_v2" {
  cluster_identifier     = local.cluster_name
  engine                = "aurora-postgresql"
  engine_version        = "15.4"
  database_name         = "postgres"
  master_username       = var.master_username
  master_password       = var.manage_master_user_password ? null : var.master_password
  manage_master_user_password = var.manage_master_user_password

  # Serverless v2 scaling configuration
  serverlessv2_scaling_configuration {
    max_capacity = var.serverless_max_capacity
    min_capacity = var.serverless_min_capacity
  }

  # Network and security configuration
  vpc_security_group_ids = [aws_security_group.aurora.id]
  db_subnet_group_name   = local.use_existing_vpc ? null : aws_db_subnet_group.aurora[0].name
  
  # Backup and maintenance configuration
  backup_retention_period   = var.backup_retention_period
  preferred_backup_window   = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  
  # Security and monitoring
  storage_encrypted               = true
  kms_key_id                     = aws_kms_key.aurora.arn
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_cost_optimized.name
  
  # Performance and logging
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # Performance Insights
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id      = var.enable_performance_insights ? aws_kms_key.aurora.arn : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null

  # Deletion protection for production
  deletion_protection = var.environment == "production" ? true : false
  skip_final_snapshot = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${local.cluster_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.aurora_logs
  ]
}

# CloudWatch log group for Aurora logs
resource "aws_cloudwatch_log_group" "aurora_logs" {
  name              = "/aws/rds/cluster/${local.cluster_name}/postgresql"
  retention_in_days = 7
  kms_key_id       = aws_kms_key.aurora.arn

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-logs"
    }
  )
}

# Writer instance for Aurora cluster
resource "aws_rds_cluster_instance" "writer" {
  identifier                   = "${local.cluster_name}-writer"
  cluster_identifier          = aws_rds_cluster.aurora_serverless_v2.id
  instance_class              = "db.serverless"
  engine                      = aws_rds_cluster.aurora_serverless_v2.engine
  engine_version              = aws_rds_cluster.aurora_serverless_v2.engine_version
  
  # High availability configuration
  promotion_tier = 1
  
  # Performance monitoring
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id      = var.enable_performance_insights ? aws_kms_key.aurora.arn : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  
  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  tags = merge(
    local.common_tags,
    {
      Name         = "${local.cluster_name}-writer"
      InstanceType = "Writer"
    }
  )
}

# Read replica instances (conditional creation)
resource "aws_rds_cluster_instance" "readers" {
  count = var.enable_read_replicas ? var.read_replica_count : 0
  
  identifier                   = "${local.cluster_name}-reader-${count.index + 1}"
  cluster_identifier          = aws_rds_cluster.aurora_serverless_v2.id
  instance_class              = "db.serverless"
  engine                      = aws_rds_cluster.aurora_serverless_v2.engine
  engine_version              = aws_rds_cluster.aurora_serverless_v2.engine_version
  
  # Reader configuration
  promotion_tier = count.index + 2
  
  # Performance monitoring
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id      = var.enable_performance_insights ? aws_kms_key.aurora.arn : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null
  
  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  tags = merge(
    local.common_tags,
    {
      Name         = "${local.cluster_name}-reader-${count.index + 1}"
      InstanceType = "Reader"
      ScalingTier  = count.index == 0 ? "Standard" : "Aggressive"
    }
  )
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name_prefix = "${local.cluster_name}-rds-monitoring-"
  
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

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution" {
  name_prefix = "${local.cluster_name}-lambda-"
  
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

  tags = local.common_tags
}

# IAM policy for Lambda Aurora management
resource "aws_iam_role_policy" "lambda_aurora_management" {
  name_prefix = "${local.cluster_name}-lambda-aurora-"
  role        = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:ModifyDBCluster",
          "rds:ModifyDBInstance",
          "rds:StartDBCluster",
          "rds:StopDBCluster",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:PutMetricData",
          "ce:GetUsageAndCosts",
          "budgets:ViewBudget",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Archive Lambda function code
data "archive_file" "cost_aware_scaler" {
  type        = "zip"
  output_path = "${path.module}/cost_aware_scaler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/cost_aware_scaler.py", {
      cluster_id = local.cluster_name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "auto_pause_resume" {
  type        = "zip"
  output_path = "${path.module}/auto_pause_resume.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/auto_pause_resume.py", {
      cluster_id  = local.cluster_name
      environment = var.environment
    })
    filename = "lambda_function.py"
  }
}

# Cost-aware scaling Lambda function
resource "aws_lambda_function" "cost_aware_scaler" {
  filename         = data.archive_file.cost_aware_scaler.output_path
  function_name    = "${local.cluster_name}-cost-aware-scaler"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.cost_aware_scaler.output_base64sha256

  environment {
    variables = {
      CLUSTER_ID = local.cluster_name
      REGION     = data.aws_region.current.name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-cost-aware-scaler"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_cost_aware_scaler
  ]
}

# Auto-pause/resume Lambda function
resource "aws_lambda_function" "auto_pause_resume" {
  filename         = data.archive_file.auto_pause_resume.output_path
  function_name    = "${local.cluster_name}-auto-pause-resume"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.auto_pause_resume.output_base64sha256

  environment {
    variables = {
      CLUSTER_ID  = local.cluster_name
      ENVIRONMENT = var.environment
      REGION      = data.aws_region.current.name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-auto-pause-resume"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_auto_pause_resume
  ]
}

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_cost_aware_scaler" {
  name              = "/aws/lambda/${local.cluster_name}-cost-aware-scaler"
  retention_in_days = 7
  kms_key_id       = aws_kms_key.aurora.arn

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_auto_pause_resume" {
  name              = "/aws/lambda/${local.cluster_name}-auto-pause-resume"
  retention_in_days = 7
  kms_key_id       = aws_kms_key.aurora.arn

  tags = local.common_tags
}

# EventBridge rules for scheduled scaling
resource "aws_cloudwatch_event_rule" "cost_aware_scaling" {
  name                = "${local.cluster_name}-cost-aware-scaling"
  description         = "Trigger cost-aware scaling for Aurora Serverless v2"
  schedule_expression = var.cost_aware_scaling_schedule

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "auto_pause_resume" {
  name                = "${local.cluster_name}-auto-pause-resume"
  description         = "Trigger auto-pause/resume for Aurora Serverless v2"
  schedule_expression = var.auto_pause_resume_schedule

  tags = local.common_tags
}

# EventBridge targets
resource "aws_cloudwatch_event_target" "cost_aware_scaling" {
  rule      = aws_cloudwatch_event_rule.cost_aware_scaling.name
  target_id = "CostAwareScalingTarget"
  arn       = aws_lambda_function.cost_aware_scaler.arn
}

resource "aws_cloudwatch_event_target" "auto_pause_resume" {
  rule      = aws_cloudwatch_event_rule.auto_pause_resume.name
  target_id = "AutoPauseResumeTarget"
  arn       = aws_lambda_function.auto_pause_resume.arn
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_cost_aware" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_aware_scaler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_aware_scaling.arn
}

resource "aws_lambda_permission" "allow_eventbridge_pause_resume" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_pause_resume.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_pause_resume.arn
}

# Cost monitoring resources (conditional)
resource "aws_sns_topic" "cost_alerts" {
  count            = var.enable_cost_monitoring ? 1 : 0
  name             = "${local.cluster_name}-cost-alerts"
  kms_master_key_id = aws_kms_key.aurora.arn

  tags = local.common_tags
}

# Email subscription for cost alerts (optional)
resource "aws_sns_topic_subscription" "cost_alerts_email" {
  count     = var.enable_cost_monitoring && var.cost_alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.cost_alerts[0].arn
  protocol  = "email"
  endpoint  = var.cost_alert_email
}

# CloudWatch alarms for cost monitoring
resource "aws_cloudwatch_metric_alarm" "high_acu_usage" {
  count = var.enable_cost_monitoring ? 1 : 0
  
  alarm_name          = "${local.cluster_name}-high-acu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "12"
  alarm_description   = "Alert when Aurora Serverless v2 ACU usage is high"
  alarm_actions       = [aws_sns_topic.cost_alerts[0].arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_serverless_v2.cluster_identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sustained_high_capacity" {
  count = var.enable_cost_monitoring ? 1 : 0
  
  alarm_name          = "${local.cluster_name}-sustained-high-capacity"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "4"
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/RDS"
  period              = "1800"
  statistic           = "Average"
  threshold           = "8"
  alarm_description   = "Alert when capacity remains high for extended period"
  alarm_actions       = [aws_sns_topic.cost_alerts[0].arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_serverless_v2.cluster_identifier
  }

  tags = local.common_tags
}

# AWS Budget for Aurora costs
resource "aws_budgets_budget" "aurora_monthly" {
  count = var.enable_cost_monitoring ? 1 : 0
  
  name         = "Aurora-Serverless-v2-Monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filters {
    service = ["Amazon Relational Database Service"]
    tag {
      key    = "Application"
      values = ["AuroraServerlessV2"]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.cost_alert_email != null ? [var.cost_alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts[0].arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.cost_alert_email != null ? [var.cost_alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts[0].arn]
  }
}