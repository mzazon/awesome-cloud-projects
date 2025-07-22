# Cost-Aware MemoryDB Lifecycle Management Infrastructure
# This Terraform configuration creates a comprehensive cost optimization system
# for MemoryDB workloads using EventBridge Scheduler and Lambda automation

# Data Sources for AWS Account and Region Information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate unique suffix for resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source for default VPC (when use_default_vpc is true)
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

# Data source for default VPC subnets
data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Data source for default security group
data "aws_security_group" "default" {
  count = var.use_default_vpc ? 1 : 0

  vpc_id = data.aws_vpc.default[0].id
  name   = "default"
}

# Local values for resource naming and configuration
locals {
  cluster_name           = "${var.resource_prefix}-${random_string.suffix.result}"
  lambda_function_name   = "${var.resource_prefix}-optimizer-${random_string.suffix.result}"
  scheduler_group_name   = "${var.resource_prefix}-schedules-${random_string.suffix.result}"
  lambda_role_name       = "${var.resource_prefix}-lambda-role-${random_string.suffix.result}"
  scheduler_role_name    = "${var.resource_prefix}-scheduler-role-${random_string.suffix.result}"
  subnet_group_name      = "${var.resource_prefix}-subnet-group-${random_string.suffix.result}"
  budget_name            = "${var.resource_prefix}-budget-${random_string.suffix.result}"

  # VPC and subnet configuration
  vpc_id     = var.use_default_vpc ? data.aws_vpc.default[0].id : var.vpc_id
  subnet_ids = var.use_default_vpc ? data.aws_subnets.default[0].ids : var.subnet_ids

  # Common tags for all resources
  common_tags = {
    Name                = "${var.resource_prefix}-${random_string.suffix.result}"
    Environment         = var.environment
    CostOptimization    = "enabled"
    AutomatedScaling    = "true"
    BusinessHours       = "8am-6pm-weekdays"
  }
}

# Security Group for MemoryDB Cluster
resource "aws_security_group" "memorydb" {
  name_prefix = "${local.cluster_name}-sg-"
  description = "Security group for MemoryDB cluster with cost optimization"
  vpc_id      = local.vpc_id

  # Redis port access from allowed CIDR blocks
  ingress {
    description = "Redis port access"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # All outbound traffic allowed
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# MemoryDB Subnet Group
resource "aws_memorydb_subnet_group" "main" {
  name       = local.subnet_group_name
  subnet_ids = local.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-subnet-group"
  })
}

# MemoryDB Cluster for Cost-Aware Scaling
resource "aws_memorydb_cluster" "main" {
  cluster_name          = local.cluster_name
  node_type             = var.memorydb_node_type
  num_shards            = var.memorydb_num_shards
  num_replicas_per_shard = var.memorydb_num_replicas_per_shard
  
  # Security and Network Configuration
  security_group_ids = [aws_security_group.memorydb.id]
  subnet_group_name  = aws_memorydb_subnet_group.main.name
  
  # Maintenance Configuration
  maintenance_window = var.memorydb_maintenance_window
  
  # Enable automatic failover if replicas are configured
  auto_minor_version_upgrade = true
  
  # Snapshot Configuration for Data Protection
  snapshot_retention_limit = 3
  snapshot_window         = "05:00-07:00"
  
  # Enable deletion protection in production environments
  final_snapshot_name = var.enable_deletion_protection ? "${local.cluster_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = merge(local.common_tags, {
    Name         = local.cluster_name
    CostProfile  = "variable-scaling"
    ScalingType  = "automated"
  })

  depends_on = [aws_memorydb_subnet_group.main]
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.lambda_role_name
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

  tags = merge(local.common_tags, {
    Name = "${local.lambda_role_name}"
    Role = "lambda-execution"
  })
}

# IAM Policy for Lambda Cost Optimization Functions
resource "aws_iam_policy" "lambda_cost_optimizer_policy" {
  name        = "${local.lambda_role_name}-policy"
  description = "Policy for MemoryDB cost optimization Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "memorydb:DescribeClusters",
          "memorydb:ModifyCluster",
          "memorydb:DescribeSubnetGroups",
          "memorydb:DescribeParameterGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:GetDimensionValues",
          "budgets:ViewBudget"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.lambda_role_name}-policy"
  })
}

# Attach Lambda Execution Policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach Custom Cost Optimizer Policy
resource "aws_iam_role_policy_attachment" "lambda_cost_optimizer" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_cost_optimizer_policy.arn
}

# Lambda Function Source Code
resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py"
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    log_level = var.lambda_log_level
  })

  lifecycle {
    # Recreate file when template variables change
    replace_triggered_by = [
      var.lambda_log_level
    ]
  }
}

# Lambda Function Package
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_function.zip"
  
  depends_on = [local_file.lambda_source]
}

# Lambda Function for Cost Optimization
resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  memory_size     = var.lambda_memory_size
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  description = "Cost-aware MemoryDB cluster lifecycle management"

  environment {
    variables = {
      LOG_LEVEL        = var.lambda_log_level
      CLUSTER_NAME     = local.cluster_name
      COST_NAMESPACE   = "MemoryDB/CostOptimization"
    }
  }

  tags = merge(local.common_tags, {
    Name     = local.lambda_function_name
    Function = "cost-optimization"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_cost_optimizer,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# CloudWatch Log Group for Lambda Function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-logs"
  })
}

# IAM Role for EventBridge Scheduler
resource "aws_iam_role" "scheduler_execution_role" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  name = local.scheduler_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.scheduler_role_name
    Role = "scheduler-execution"
  })
}

# IAM Policy for EventBridge Scheduler
resource "aws_iam_policy" "scheduler_lambda_invoke_policy" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  name        = "${local.scheduler_role_name}-policy"
  description = "Policy for EventBridge Scheduler to invoke Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = aws_lambda_function.cost_optimizer.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.scheduler_role_name}-policy"
  })
}

# Attach Scheduler Policy
resource "aws_iam_role_policy_attachment" "scheduler_lambda_invoke" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  role       = aws_iam_role.scheduler_execution_role[0].name
  policy_arn = aws_iam_policy.scheduler_lambda_invoke_policy[0].arn
}

# EventBridge Scheduler Group
resource "aws_scheduler_schedule_group" "cost_optimization" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  name = local.scheduler_group_name

  tags = merge(local.common_tags, {
    Name    = local.scheduler_group_name
    Purpose = "cost-optimization-schedules"
  })
}

# Business Hours Start Schedule (Scale Up)
resource "aws_scheduler_schedule" "business_hours_start" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  name                         = "${local.cluster_name}-business-hours-start"
  group_name                   = aws_scheduler_schedule_group.cost_optimization[0].name
  description                  = "Scale up MemoryDB cluster for business hours performance"
  schedule_expression          = var.business_hours_start_cron
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.cost_optimizer.arn
    role_arn = aws_iam_role.scheduler_execution_role[0].arn

    input = jsonencode({
      cluster_name     = local.cluster_name
      action          = "scale_up"
      cost_threshold  = var.scale_up_cost_threshold
    })
  }

  depends_on = [aws_iam_role_policy_attachment.scheduler_lambda_invoke]
}

# Business Hours End Schedule (Scale Down)
resource "aws_scheduler_schedule" "business_hours_end" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  name                         = "${local.cluster_name}-business-hours-end"
  group_name                   = aws_scheduler_schedule_group.cost_optimization[0].name
  description                  = "Scale down MemoryDB cluster for cost optimization during off-hours"
  schedule_expression          = var.business_hours_end_cron
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.cost_optimizer.arn
    role_arn = aws_iam_role.scheduler_execution_role[0].arn

    input = jsonencode({
      cluster_name     = local.cluster_name
      action          = "scale_down"
      cost_threshold  = var.scale_down_cost_threshold
    })
  }

  depends_on = [aws_iam_role_policy_attachment.scheduler_lambda_invoke]
}

# Weekly Cost Analysis Schedule
resource "aws_scheduler_schedule" "weekly_analysis" {
  count = var.enable_scheduler_automation ? 1 : 0
  
  name                         = "${local.cluster_name}-weekly-cost-analysis"
  group_name                   = aws_scheduler_schedule_group.cost_optimization[0].name
  description                  = "Weekly MemoryDB cost analysis and optimization review"
  schedule_expression          = var.weekly_analysis_cron
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.cost_optimizer.arn
    role_arn = aws_iam_role.scheduler_execution_role[0].arn

    input = jsonencode({
      cluster_name     = local.cluster_name
      action          = "analyze"
      cost_threshold  = var.weekly_analysis_cost_threshold
    })
  }

  depends_on = [aws_iam_role_policy_attachment.scheduler_lambda_invoke]
}

# AWS Budget for MemoryDB Cost Monitoring
resource "aws_budgets_budget" "memorydb_cost_budget" {
  count = var.enable_cost_budget ? 1 : 0
  
  name         = local.budget_name
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = "2025-07-01_00:00"
  time_period_end   = "2025-12-31_00:00"

  cost_filters {
    service = ["Amazon MemoryDB for Redis"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold_actual
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.cost_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold_forecasted
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.cost_alert_email]
  }

  tags = merge(local.common_tags, {
    Name = local.budget_name
  })
}

# CloudWatch Dashboard for Cost Optimization Monitoring
resource "aws_cloudwatch_dashboard" "cost_optimization" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  dashboard_name = "${local.cluster_name}-cost-optimization"

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
            ["MemoryDB/CostOptimization", "WeeklyCost", "ClusterName", local.cluster_name],
            [".", "OptimizationAction", ".", "."]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "MemoryDB Cost Optimization Metrics"
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
            ["AWS/MemoryDB", "CPUUtilization", "ClusterName", local.cluster_name],
            [".", "NetworkBytesIn", ".", "."],
            [".", "NetworkBytesOut", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "MemoryDB Performance Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Cost Optimization Lambda Metrics"
        }
      }
    ]
  })

  depends_on = [aws_lambda_function.cost_optimizer]
}

# CloudWatch Alarm for Weekly Cost Threshold
resource "aws_cloudwatch_metric_alarm" "weekly_cost_high" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.cluster_name}-weekly-cost-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "WeeklyCost"
  namespace           = "MemoryDB/CostOptimization"
  period              = "604800"
  statistic           = "Average"
  threshold           = var.weekly_cost_alarm_threshold
  alarm_description   = "This metric monitors weekly MemoryDB costs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-weekly-cost-alarm"
  })
}

# CloudWatch Alarm for Lambda Function Errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.lambda_error_alarm_threshold
  alarm_description   = "This metric monitors Lambda function errors for cost optimization automation"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = local.lambda_function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-error-alarm"
  })

  depends_on = [aws_lambda_function.cost_optimizer]
}