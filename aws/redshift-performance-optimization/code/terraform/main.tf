# Generate random password for Redshift cluster
resource "random_password" "redshift_master_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Ensure password meets Redshift requirements
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

# Store the password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "redshift_credentials" {
  name                    = "${var.cluster_identifier}-credentials"
  description             = "Redshift cluster master credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.cluster_identifier}-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "redshift_credentials" {
  secret_id = aws_secretsmanager_secret.redshift_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.redshift_master_password.result
    endpoint = aws_redshift_cluster.performance_cluster.endpoint
    port     = aws_redshift_cluster.performance_cluster.port
    database = var.database_name
  })
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC for Redshift cluster
resource "aws_vpc" "redshift_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_identifier}-vpc"
  }
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "redshift_igw" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "${var.cluster_identifier}-igw"
  }
}

# Private subnets for Redshift cluster
resource "aws_subnet" "redshift_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.redshift_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.cluster_identifier}-private-subnet-${count.index + 1}"
  }
}

# Route table for private subnets
resource "aws_route_table" "redshift_private_rt" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "${var.cluster_identifier}-private-rt"
  }
}

# Route table associations for private subnets
resource "aws_route_table_association" "redshift_private_rta" {
  count          = length(aws_subnet.redshift_private_subnets)
  subnet_id      = aws_subnet.redshift_private_subnets[count.index].id
  route_table_id = aws_route_table.redshift_private_rt.id
}

# Subnet group for Redshift cluster
resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = aws_subnet.redshift_private_subnets[*].id

  tags = {
    Name = "${var.cluster_identifier}-subnet-group"
  }
}

# Security group for Redshift cluster
resource "aws_security_group" "redshift_sg" {
  name_prefix = "${var.cluster_identifier}-sg"
  vpc_id      = aws_vpc.redshift_vpc.id
  description = "Security group for Redshift cluster"

  # Redshift port access from allowed CIDR blocks
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Redshift access from allowed CIDR blocks"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.cluster_identifier}-sg"
  }
}

# Custom parameter group for optimized WLM configuration
resource "aws_redshift_parameter_group" "optimized_wlm" {
  family = "redshift-1.0"
  name   = "${var.cluster_identifier}-optimized-wlm"

  # Enable automatic WLM with concurrency scaling
  parameter {
    name  = "wlm_json_configuration"
    value = jsonencode([
      {
        query_group                = []
        query_group_wild_card      = 0
        user_group                 = []
        user_group_wild_card       = 0
        concurrency_scaling        = "auto"
        auto_wlm                   = true
      }
    ])
  }

  # Enable query monitoring rules for performance optimization
  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }

  tags = {
    Name = "${var.cluster_identifier}-optimized-wlm"
  }
}

# IAM role for Redshift to access other AWS services
resource "aws_iam_role" "redshift_role" {
  name = "${var.cluster_identifier}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_identifier}-role"
  }
}

# Attach S3 read access policy to Redshift role
resource "aws_iam_role_policy_attachment" "redshift_s3_readonly" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# S3 bucket for audit logging (if enabled)
resource "aws_s3_bucket" "redshift_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = "${var.cluster_identifier}-audit-logs-${random_password.redshift_master_password.id}"

  tags = {
    Name = "${var.cluster_identifier}-audit-logs"
  }
}

resource "aws_s3_bucket_versioning" "redshift_logs_versioning" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.redshift_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "redshift_logs_encryption" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.redshift_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "redshift_logs_pab" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.redshift_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Redshift cluster
resource "aws_redshift_cluster" "performance_cluster" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = random_password.redshift_master_password.result
  node_type          = var.node_type
  number_of_nodes    = var.number_of_nodes

  # Network configuration
  db_subnet_group_name   = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids = [aws_security_group.redshift_sg.id]
  publicly_accessible    = false

  # Performance configuration
  cluster_parameter_group_name = aws_redshift_parameter_group.optimized_wlm.name
  iam_roles                    = [aws_iam_role.redshift_role.arn]

  # Backup and maintenance
  automated_snapshot_retention_period = 7
  preferred_maintenance_window         = "sun:03:00-sun:04:00"
  skip_final_snapshot                  = true

  # Logging configuration
  dynamic "logging" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable        = true
      bucket_name   = aws_s3_bucket.redshift_logs[0].bucket
      s3_key_prefix = "redshift-logs/"
    }
  }

  # Enhanced VPC routing for better performance
  enhanced_vpc_routing = true

  tags = {
    Name = var.cluster_identifier
  }

  depends_on = [
    aws_redshift_parameter_group.optimized_wlm,
    aws_iam_role_policy_attachment.redshift_s3_readonly
  ]
}

# CloudWatch Log Group for performance metrics
resource "aws_cloudwatch_log_group" "performance_metrics" {
  name              = "/aws/redshift/performance-metrics"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.cluster_identifier}-performance-metrics"
  }
}

# SNS topic for performance alerts
resource "aws_sns_topic" "performance_alerts" {
  name = "${var.cluster_identifier}-performance-alerts"

  tags = {
    Name = "${var.cluster_identifier}-performance-alerts"
  }
}

# SNS topic subscription for email notifications (if email provided)
resource "aws_sns_topic_subscription" "performance_alerts_email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.performance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarms for performance monitoring
resource "aws_cloudwatch_metric_alarm" "redshift_high_cpu" {
  alarm_name          = "${var.cluster_identifier}-high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors redshift cpu utilization"
  alarm_actions       = [aws_sns_topic.performance_alerts.arn]

  dimensions = {
    ClusterIdentifier = aws_redshift_cluster.performance_cluster.cluster_identifier
  }

  tags = {
    Name = "${var.cluster_identifier}-high-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "redshift_high_queue_length" {
  alarm_name          = "${var.cluster_identifier}-high-queue-length"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "QueueLength"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = var.queue_length_threshold
  alarm_description   = "This metric monitors redshift query queue length"
  alarm_actions       = [aws_sns_topic.performance_alerts.arn]

  dimensions = {
    ClusterIdentifier = aws_redshift_cluster.performance_cluster.cluster_identifier
  }

  tags = {
    Name = "${var.cluster_identifier}-high-queue-alarm"
  }
}

# CloudWatch Dashboard for Redshift performance monitoring
resource "aws_cloudwatch_dashboard" "redshift_performance" {
  dashboard_name = "${var.cluster_identifier}-performance-dashboard"

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
            ["AWS/Redshift", "CPUUtilization", "ClusterIdentifier", aws_redshift_cluster.performance_cluster.cluster_identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "HealthStatus", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Redshift Cluster Metrics"
          yAxis = {
            left = {
              min = 0
              max = 100
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
            ["AWS/Redshift", "QueueLength", "ClusterIdentifier", aws_redshift_cluster.performance_cluster.cluster_identifier],
            [".", "WLMQueueLength", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Query Queue Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}

# Lambda execution role for maintenance function
resource "aws_iam_role" "lambda_maintenance_role" {
  name = "${var.cluster_identifier}-lambda-maintenance-role"

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

  tags = {
    Name = "${var.cluster_identifier}-lambda-maintenance-role"
  }
}

# Lambda policy for Redshift access and logging
resource "aws_iam_policy" "lambda_maintenance_policy" {
  name        = "${var.cluster_identifier}-lambda-maintenance-policy"
  description = "Policy for Lambda maintenance function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.redshift_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "redshift:DescribeClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_maintenance_policy_attachment" {
  role       = aws_iam_role.lambda_maintenance_role.name
  policy_arn = aws_iam_policy.lambda_maintenance_policy.arn
}

# Package Lambda function code
data "archive_file" "lambda_maintenance_zip" {
  type        = "zip"
  output_path = "${path.module}/maintenance_function.zip"
  source {
    content = templatefile("${path.module}/maintenance_function.py", {
      secret_arn = aws_secretsmanager_secret.redshift_credentials.arn
      region     = var.aws_region
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for automated maintenance
resource "aws_lambda_function" "redshift_maintenance" {
  filename         = data.archive_file.lambda_maintenance_zip.output_path
  function_name    = "${var.cluster_identifier}-maintenance"
  role            = aws_iam_role.lambda_maintenance_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_maintenance_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout

  environment {
    variables = {
      SECRET_ARN = aws_secretsmanager_secret.redshift_credentials.arn
      AWS_REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.cluster_identifier}-maintenance"
  }

  depends_on = [aws_cloudwatch_log_group.lambda_maintenance_logs]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_maintenance_logs" {
  name              = "/aws/lambda/${var.cluster_identifier}-maintenance"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.cluster_identifier}-lambda-maintenance-logs"
  }
}

# EventBridge rule for scheduling maintenance
resource "aws_cloudwatch_event_rule" "maintenance_schedule" {
  name                = "${var.cluster_identifier}-maintenance-schedule"
  description         = "Trigger Redshift maintenance tasks on schedule"
  schedule_expression = var.maintenance_schedule

  tags = {
    Name = "${var.cluster_identifier}-maintenance-schedule"
  }
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_maintenance_target" {
  rule      = aws_cloudwatch_event_rule.maintenance_schedule.name
  target_id = "RedshiftMaintenanceTarget"
  arn       = aws_lambda_function.redshift_maintenance.arn
}

# Lambda permission for EventBridge to invoke function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redshift_maintenance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.maintenance_schedule.arn
}