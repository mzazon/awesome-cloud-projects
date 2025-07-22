# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Data source for default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Data source for default subnets if not specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  # Use provided VPC or default VPC
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  
  # Use provided subnets or default subnets
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Generate cluster identifier
  cluster_identifier = var.redshift_cluster_identifier != "" ? var.redshift_cluster_identifier : "${var.project_name}-cluster-${random_string.suffix.result}"
  
  # Resource naming
  parameter_group_name = "${var.project_name}-wlm-pg-${random_string.suffix.result}"
  subnet_group_name    = "${var.project_name}-subnet-group-${random_string.suffix.result}"
  security_group_name  = "${var.project_name}-sg-${random_string.suffix.result}"
  sns_topic_name       = "${var.project_name}-alerts-${random_string.suffix.result}"
  
  # WLM Configuration with Query Monitoring Rules
  wlm_configuration = jsonencode([
    {
      user_group         = "bi-dashboard-group"
      query_group        = "dashboard"
      query_concurrency  = var.wlm_dashboard_queue_concurrency
      memory_percent_to_use = var.wlm_dashboard_memory_percent
      max_execution_time = 120000
      query_group_wild_card = 0
      rules = [
        {
          rule_name = "dashboard_timeout_rule"
          predicate = "query_execution_time > 120"
          action    = "abort"
        },
        {
          rule_name = "dashboard_cpu_rule"
          predicate = "query_cpu_time > 30"
          action    = "log"
        }
      ]
    },
    {
      user_group         = "data-science-group"
      query_group        = "analytics"
      query_concurrency  = var.wlm_analytics_queue_concurrency
      memory_percent_to_use = var.wlm_analytics_memory_percent
      max_execution_time = 7200000
      query_group_wild_card = 0
      rules = [
        {
          rule_name = "analytics_memory_rule"
          predicate = "query_temp_blocks_to_disk > 100000"
          action    = "log"
        },
        {
          rule_name = "analytics_nested_loop_rule"
          predicate = "nested_loop_join_row_count > 1000000"
          action    = "hop"
        }
      ]
    },
    {
      user_group         = "etl-process-group"
      query_group        = "etl"
      query_concurrency  = var.wlm_etl_queue_concurrency
      memory_percent_to_use = var.wlm_etl_memory_percent
      max_execution_time = 3600000
      query_group_wild_card = 0
      rules = [
        {
          rule_name = "etl_timeout_rule"
          predicate = "query_execution_time > 3600"
          action    = "abort"
        },
        {
          rule_name = "etl_scan_rule"
          predicate = "scan_row_count > 1000000000"
          action    = "log"
        }
      ]
    },
    {
      query_concurrency     = 2
      memory_percent_to_use = 10
      max_execution_time    = 1800000
      query_group_wild_card = 1
      rules = [
        {
          rule_name = "default_timeout_rule"
          predicate = "query_execution_time > 1800"
          action    = "abort"
        }
      ]
    }
  ])
}

###########################################
# Redshift Parameter Group with WLM Config
###########################################

# Custom parameter group for WLM configuration
resource "aws_redshift_parameter_group" "wlm_parameter_group" {
  name   = local.parameter_group_name
  family = "redshift-1.0"

  parameter {
    name  = "wlm_json_configuration"
    value = local.wlm_configuration
  }

  tags = merge(
    {
      Name        = local.parameter_group_name
      Description = "Parameter group for analytics workload isolation"
    },
    var.additional_tags
  )
}

###########################################
# Networking Resources
###########################################

# Security group for Redshift cluster
resource "aws_security_group" "redshift_sg" {
  name_prefix = "${local.security_group_name}-"
  vpc_id      = local.vpc_id
  description = "Security group for Redshift cluster with WLM"

  # Inbound rule for Redshift port
  ingress {
    description = "Redshift access from allowed CIDR blocks"
    from_port   = var.redshift_port
    to_port     = var.redshift_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Outbound rule for all traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = local.security_group_name
    },
    var.additional_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Redshift subnet group
resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name       = local.subnet_group_name
  subnet_ids = local.subnet_ids

  tags = merge(
    {
      Name = local.subnet_group_name
    },
    var.additional_tags
  )
}

###########################################
# IAM Resources for Enhanced Monitoring
###########################################

# IAM role for Redshift enhanced monitoring (if needed)
resource "aws_iam_role" "redshift_monitoring_role" {
  count = var.enable_wlm_monitoring ? 1 : 0
  name  = "${var.project_name}-redshift-monitoring-role-${random_string.suffix.result}"

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

  tags = merge(
    {
      Name = "${var.project_name}-redshift-monitoring-role"
    },
    var.additional_tags
  )
}

# Attach CloudWatch policy to monitoring role
resource "aws_iam_role_policy_attachment" "redshift_monitoring_policy" {
  count      = var.enable_wlm_monitoring ? 1 : 0
  role       = aws_iam_role.redshift_monitoring_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

###########################################
# Redshift Cluster
###########################################

# Generate secure random password for Redshift master user
resource "random_password" "redshift_password" {
  count   = var.create_redshift_cluster ? 1 : 0
  length  = 16
  special = true
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "redshift_password" {
  count                   = var.create_redshift_cluster ? 1 : 0
  name                    = "${var.project_name}-redshift-password-${random_string.suffix.result}"
  description             = "Redshift cluster master password"
  recovery_window_in_days = 7

  tags = merge(
    {
      Name = "${var.project_name}-redshift-password"
    },
    var.additional_tags
  )
}

resource "aws_secretsmanager_secret_version" "redshift_password" {
  count     = var.create_redshift_cluster ? 1 : 0
  secret_id = aws_secretsmanager_secret.redshift_password[0].id
  secret_string = jsonencode({
    username = var.redshift_master_username
    password = random_password.redshift_password[0].result
  })
}

# Redshift cluster with WLM configuration
resource "aws_redshift_cluster" "analytics_cluster" {
  count = var.create_redshift_cluster ? 1 : 0

  cluster_identifier = local.cluster_identifier
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = random_password.redshift_password[0].result
  node_type          = var.redshift_node_type
  cluster_type       = var.redshift_cluster_type
  number_of_nodes    = var.redshift_cluster_type == "multi-node" ? var.redshift_number_of_nodes : null
  port               = var.redshift_port

  # Network configuration
  db_subnet_group_name   = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids = [aws_security_group.redshift_sg.id]
  publicly_accessible    = var.publicly_accessible

  # Parameter group with WLM configuration
  cluster_parameter_group_name = aws_redshift_parameter_group.wlm_parameter_group.name

  # Security configuration
  encrypted  = var.enable_encryption
  kms_key_id = var.kms_key_id != "" ? var.kms_key_id : null

  # Backup configuration
  automated_snapshot_retention_period = var.automated_snapshot_retention_period
  preferred_maintenance_window        = var.preferred_maintenance_window
  skip_final_snapshot                = var.skip_final_snapshot
  final_snapshot_identifier          = var.skip_final_snapshot ? null : "${local.cluster_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Enhanced monitoring
  enhanced_vpc_routing = true

  # Logging configuration
  logging {
    enable                = true
    s3_bucket_name        = aws_s3_bucket.redshift_logs.bucket
    s3_key_prefix         = "redshift-logs/"
    log_destination_type  = "s3"
    log_exports           = ["connectionlog", "useractivitylog", "userlog"]
  }

  tags = merge(
    {
      Name = local.cluster_identifier
    },
    var.additional_tags
  )

  depends_on = [
    aws_redshift_parameter_group.wlm_parameter_group,
    aws_s3_bucket_public_access_block.redshift_logs
  ]
}

###########################################
# S3 Bucket for Redshift Logs
###########################################

# S3 bucket for Redshift logging
resource "aws_s3_bucket" "redshift_logs" {
  bucket = "${var.project_name}-redshift-logs-${random_string.suffix.result}"

  tags = merge(
    {
      Name        = "${var.project_name}-redshift-logs"
      Description = "S3 bucket for Redshift audit logs"
    },
    var.additional_tags
  )
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "redshift_logs" {
  bucket = aws_s3_bucket.redshift_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "redshift_logs" {
  bucket = aws_s3_bucket.redshift_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "redshift_logs" {
  bucket = aws_s3_bucket.redshift_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for Redshift logging
resource "aws_s3_bucket_policy" "redshift_logs" {
  bucket = aws_s3_bucket.redshift_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Put bucket policy needed for audit logging"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::193672423079:user/logs"  # Redshift service account for us-east-1
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.redshift_logs.arn}/redshift-logs/*"
      },
      {
        Sid    = "Get bucket policy needed for audit logging"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::193672423079:user/logs"  # Redshift service account for us-east-1
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.redshift_logs.arn
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.redshift_logs]
}

# S3 bucket lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "redshift_logs" {
  bucket = aws_s3_bucket.redshift_logs.id

  rule {
    id     = "log_retention"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

###########################################
# SNS Topic for Alerts
###########################################

# SNS topic for CloudWatch alarms
resource "aws_sns_topic" "wlm_alerts" {
  count = var.enable_wlm_monitoring ? 1 : 0
  name  = local.sns_topic_name

  tags = merge(
    {
      Name = local.sns_topic_name
    },
    var.additional_tags
  )
}

# SNS topic policy
resource "aws_sns_topic_policy" "wlm_alerts" {
  count = var.enable_wlm_monitoring ? 1 : 0
  arn   = aws_sns_topic.wlm_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.wlm_alerts[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS subscription for email notifications (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_wlm_monitoring && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.wlm_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

###########################################
# CloudWatch Alarms for WLM Monitoring
###########################################

# CloudWatch alarm for high queue wait time
resource "aws_cloudwatch_metric_alarm" "high_queue_wait_time" {
  count = var.enable_wlm_monitoring ? 1 : 0

  alarm_name          = "RedshiftWLM-HighQueueWaitTime-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "QueueLength"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = var.queue_length_threshold
  alarm_description   = "This metric monitors redshift queue length"
  alarm_actions       = [aws_sns_topic.wlm_alerts[0].arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterIdentifier = var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].cluster_identifier : var.redshift_cluster_identifier
  }

  tags = merge(
    {
      Name = "RedshiftWLM-HighQueueWaitTime"
    },
    var.additional_tags
  )
}

# CloudWatch alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  count = var.enable_wlm_monitoring ? 1 : 0

  alarm_name          = "RedshiftWLM-HighCPUUtilization-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "This metric monitors redshift CPU utilization"
  alarm_actions       = [aws_sns_topic.wlm_alerts[0].arn]

  dimensions = {
    ClusterIdentifier = var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].cluster_identifier : var.redshift_cluster_identifier
  }

  tags = merge(
    {
      Name = "RedshiftWLM-HighCPUUtilization"
    },
    var.additional_tags
  )
}

# CloudWatch alarm for low query completion rate
resource "aws_cloudwatch_metric_alarm" "low_query_completion_rate" {
  count = var.enable_wlm_monitoring ? 1 : 0

  alarm_name          = "RedshiftWLM-LowQueryCompletionRate-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "QueriesCompletedPerSecond"
  namespace           = "AWS/Redshift"
  period              = "900"
  statistic           = "Sum"
  threshold           = var.queries_per_second_threshold
  alarm_description   = "This metric monitors redshift query completion rate"
  alarm_actions       = [aws_sns_topic.wlm_alerts[0].arn]

  dimensions = {
    ClusterIdentifier = var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].cluster_identifier : var.redshift_cluster_identifier
  }

  tags = merge(
    {
      Name = "RedshiftWLM-LowQueryCompletionRate"
    },
    var.additional_tags
  )
}

###########################################
# CloudWatch Dashboard
###########################################

# CloudWatch dashboard for WLM monitoring
resource "aws_cloudwatch_dashboard" "wlm_dashboard" {
  count          = var.enable_wlm_monitoring ? 1 : 0
  dashboard_name = "RedshiftWLM-${random_string.suffix.result}"

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
            ["AWS/Redshift", "QueueLength", "ClusterIdentifier", var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].cluster_identifier : var.redshift_cluster_identifier],
            [".", "QueriesCompletedPerSecond", ".", "."],
            [".", "CPUUtilization", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Redshift WLM Performance Metrics"
          view   = "timeSeries"
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
            ["AWS/Redshift", "DatabaseConnections", "ClusterIdentifier", var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].cluster_identifier : var.redshift_cluster_identifier],
            [".", "HealthStatus", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Cluster Health and Connections"
          view   = "timeSeries"
        }
      }
    ]
  })
}