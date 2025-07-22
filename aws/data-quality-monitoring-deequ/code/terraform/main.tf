# main.tf
# Main Terraform configuration for real-time data quality monitoring with Deequ on EMR

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnet if not specified
data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  vpc_id            = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_id         = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.default[0].ids[0]
  s3_bucket_name    = "${var.s3_bucket_name}-${random_id.suffix.hex}"
  cluster_name      = "${var.project_name}-${random_id.suffix.hex}"
  sns_topic_name    = "data-quality-alerts-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "real-time-data-quality-monitoring-deequ-emr"
  }
}

# =============================================================================
# S3 BUCKET FOR DATA STORAGE AND LOGS
# =============================================================================

# S3 bucket for data lake, logs, and scripts
resource "aws_s3_bucket" "data_bucket" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "DeeQu Data Quality Bucket"
    Type = "DataLake"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create S3 bucket directory structure
resource "aws_s3_object" "directories" {
  for_each = toset([
    "raw-data/",
    "quality-reports/",
    "logs/",
    "scripts/"
  ])

  bucket = aws_s3_bucket.data_bucket.id
  key    = each.value
  source = "/dev/null"

  tags = local.common_tags
}

# =============================================================================
# DEEQU BOOTSTRAP SCRIPT
# =============================================================================

# Bootstrap script for installing Deequ on EMR
resource "aws_s3_object" "deequ_bootstrap_script" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "scripts/install-deequ.sh"
  content = templatefile("${path.module}/scripts/install-deequ.sh", {
    deequ_version = var.deequ_version
  })
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "DeeQu Bootstrap Script"
    Type = "BootstrapScript"
  })
}

# Data quality monitoring Python application
resource "aws_s3_object" "quality_monitor_script" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "scripts/deequ-quality-monitor.py"
  content = templatefile("${path.module}/scripts/deequ-quality-monitor.py", {
    deequ_version = var.deequ_version
  })
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "DeeQu Quality Monitor Script"
    Type = "SparkApplication"
  })
}

# Sample data generation script
resource "aws_s3_object" "sample_data_script" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "scripts/generate-sample-data.py"
  content = file("${path.module}/scripts/generate-sample-data.py")
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "Sample Data Generation Script"
    Type = "DataGenerator"
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# EMR Service Role
resource "aws_iam_role" "emr_service_role" {
  name = "EMR_DefaultRole_${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "elasticmapreduce.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "EMR Service Role"
    Type = "ServiceRole"
  })
}

# Attach AWS managed policy to EMR service role
resource "aws_iam_role_policy_attachment" "emr_service_role_policy" {
  role       = aws_iam_role.emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# EMR EC2 Instance Profile Role
resource "aws_iam_role" "emr_ec2_role" {
  name = "EMR_EC2_DefaultRole_${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "EMR EC2 Instance Role"
    Type = "InstanceRole"
  })
}

# Attach AWS managed policy to EMR EC2 role
resource "aws_iam_role_policy_attachment" "emr_ec2_role_policy" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

# Additional policy for CloudWatch metrics and SNS
resource "aws_iam_role_policy" "emr_additional_permissions" {
  name = "EMRAdditionalPermissions_${random_id.suffix.hex}"
  role = aws_iam_role.emr_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.data_quality_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_bucket.arn,
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create EMR EC2 instance profile
resource "aws_iam_instance_profile" "emr_ec2_instance_profile" {
  name = "EMR_EC2_DefaultRole_${random_id.suffix.hex}"
  role = aws_iam_role.emr_ec2_role.name

  tags = merge(local.common_tags, {
    Name = "EMR EC2 Instance Profile"
    Type = "InstanceProfile"
  })
}

# =============================================================================
# SNS TOPIC FOR ALERTS
# =============================================================================

# SNS topic for data quality alerts
resource "aws_sns_topic" "data_quality_alerts" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name = "Data Quality Alerts Topic"
    Type = "AlertingTopic"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "data_quality_alerts" {
  arn = aws_sns_topic.data_quality_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.emr_ec2_role.arn
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.data_quality_alerts.arn
      }
    ]
  })
}

# SNS email subscription (only if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.data_quality_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Security group for EMR cluster
resource "aws_security_group" "emr_cluster" {
  name_prefix = "${var.project_name}-emr-"
  vpc_id      = local.vpc_id
  description = "Security group for EMR cluster"

  # Inbound rules for EMR communication
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "EMR web interface access"
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
    description = "Internal cluster communication"
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "EMR Cluster Security Group"
    Type = "SecurityGroup"
  })
}

# =============================================================================
# EMR CLUSTER
# =============================================================================

# EMR cluster for data quality monitoring
resource "aws_emr_cluster" "deequ_cluster" {
  name          = local.cluster_name
  release_label = var.emr_release_label
  applications  = ["Spark"]

  # Auto-termination configuration
  auto_termination_policy {
    idle_timeout = var.emr_auto_termination_timeout
  }

  # EC2 attributes
  ec2_attributes {
    subnet_id                         = local.subnet_id
    emr_managed_master_security_group = aws_security_group.emr_cluster.id
    emr_managed_slave_security_group  = aws_security_group.emr_cluster.id
    instance_profile                  = aws_iam_instance_profile.emr_ec2_instance_profile.arn
  }

  # Master instance group
  master_instance_group {
    instance_type = var.emr_instance_type
  }

  # Core instance group configuration
  dynamic "core_instance_group" {
    for_each = var.enable_spot_instances ? [] : [1]
    content {
      instance_type  = var.emr_instance_type
      instance_count = var.emr_instance_count - 1
    }
  }

  # Core instance fleet (for spot instances)
  dynamic "core_instance_fleet" {
    for_each = var.enable_spot_instances ? [1] : []
    content {
      target_on_demand_capacity = ceil((var.emr_instance_count - 1) * (100 - var.spot_instance_percentage) / 100)
      target_spot_capacity      = floor((var.emr_instance_count - 1) * var.spot_instance_percentage / 100)

      instance_type_configs {
        instance_type = var.emr_instance_type
      }
    }
  }

  # Service role
  service_role = aws_iam_role.emr_service_role.arn

  # Bootstrap actions
  bootstrap_action {
    path = "s3://${aws_s3_bucket.data_bucket.id}/scripts/install-deequ.sh"
    name = "Install DeeQu"
  }

  # Spark configuration
  configurations_json = jsonencode([
    {
      Classification = "spark-defaults"
      Properties     = var.spark_configurations
    }
  ])

  # Encryption configuration
  dynamic "encryption_configuration" {
    for_each = var.enable_encryption_at_rest || var.enable_encryption_in_transit ? [1] : []
    content {
      enable_at_rest_encryption    = var.enable_encryption_at_rest
      enable_in_transit_encryption = var.enable_encryption_in_transit
    }
  }

  # Logging
  log_uri = "s3://${aws_s3_bucket.data_bucket.id}/logs/"

  # Enable debugging
  enable_debugging = true

  # Prevent accidental termination in production
  termination_protection            = var.environment == "prod" ? true : false
  keep_job_flow_alive_when_no_steps = true

  tags = merge(local.common_tags, {
    Name = "DeeQu EMR Cluster"
    Type = "EMRCluster"
  })

  depends_on = [
    aws_iam_role_policy_attachment.emr_service_role_policy,
    aws_iam_role_policy_attachment.emr_ec2_role_policy,
    aws_iam_role_policy.emr_additional_permissions,
    aws_s3_object.deequ_bootstrap_script
  ]
}

# =============================================================================
# CLOUDWATCH DASHBOARD
# =============================================================================

# CloudWatch dashboard for data quality metrics
resource "aws_cloudwatch_dashboard" "data_quality" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "DeeQuDataQualityMonitoring-${random_id.suffix.hex}"

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
            ["DataQuality/Deequ", "Size", "DataSource", local.s3_bucket_name],
            [".", "Completeness_customer_id_", ".", "."],
            [".", "Completeness_email_", ".", "."],
            [".", "Completeness_income_", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Data Quality Metrics"
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
            ["DataQuality/Deequ", "Uniqueness_customer_id_", "DataSource", local.s3_bucket_name],
            [".", "Mean_age_", ".", "."],
            [".", "StandardDeviation_age_", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Data Distribution Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '/aws/emr/${aws_emr_cluster.deequ_cluster.id}'\n| fields @timestamp, @message\n| filter @message like /Quality/\n| sort @timestamp desc\n| limit 100"
          region  = data.aws_region.current.name
          title   = "EMR Quality Monitoring Logs"
        }
      }
    ]
  })
}

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

# CloudWatch log group for EMR cluster
resource "aws_cloudwatch_log_group" "emr_logs" {
  name              = "/aws/emr/${aws_emr_cluster.deequ_cluster.id}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "EMR Cluster Logs"
    Type = "LogGroup"
  })
}

# =============================================================================
# LAMBDA FUNCTION FOR AUTOMATED MONITORING (OPTIONAL)
# =============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "DeeQuLambdaRole_${random_id.suffix.hex}"

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

  tags = merge(local.common_tags, {
    Name = "DeeQu Lambda Role"
    Type = "LambdaRole"
  })
}

# Lambda policy for EMR and CloudWatch access
resource "aws_iam_role_policy" "lambda_policy" {
  name = "DeeQuLambdaPolicy_${random_id.suffix.hex}"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "emr:AddJobFlowSteps",
          "emr:DescribeCluster",
          "emr:ListSteps"
        ]
        Resource = aws_emr_cluster.deequ_cluster.arn
      }
    ]
  })
}

# Lambda function for automated monitoring
resource "aws_lambda_function" "automated_monitoring" {
  filename         = "${path.module}/lambda/automated-monitoring.zip"
  function_name    = "deequ-automated-monitoring-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      CLUSTER_ID     = aws_emr_cluster.deequ_cluster.id
      S3_BUCKET      = aws_s3_bucket.data_bucket.id
      SNS_TOPIC_ARN  = aws_sns_topic.data_quality_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "DeeQu Automated Monitoring Function"
    Type = "LambdaFunction"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/deequ-automated-monitoring-${random_id.suffix.hex}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "Lambda Function Logs"
    Type = "LogGroup"
  })
}