# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC for RDS subnet group
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#-----------------------------------------------------------
# S3 Bucket for QuickSight Data Sources
#-----------------------------------------------------------

# S3 bucket for storing analytics data
resource "aws_s3_bucket" "quicksight_data" {
  bucket        = "${var.s3_bucket_name}-${random_id.suffix.hex}"
  force_destroy = true

  tags = merge(var.additional_tags, {
    Name        = "${var.project_name}-data-bucket"
    Purpose     = "QuickSight data storage"
    Component   = "storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "quicksight_data" {
  bucket = aws_s3_bucket.quicksight_data.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "quicksight_data" {
  bucket = aws_s3_bucket.quicksight_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "quicksight_data" {
  bucket = aws_s3_bucket.quicksight_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "quicksight_data" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.quicksight_data.id

  rule {
    id     = "analytics_data_lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Upload sample sales data to S3
resource "aws_s3_object" "sample_sales_data" {
  bucket = aws_s3_bucket.quicksight_data.id
  key    = "sales/sales_data.csv"
  content = <<CSV
date,region,product,sales_amount,quantity,customer_segment
2024-01-15,North America,Product A,1200.50,25,Enterprise
2024-01-15,Europe,Product B,850.75,15,SMB
2024-01-16,Asia Pacific,Product A,2100.25,42,Enterprise
2024-01-16,North America,Product C,675.00,18,Consumer
2024-01-17,Europe,Product A,1450.80,29,Enterprise
2024-01-17,Asia Pacific,Product B,920.45,21,SMB
2024-01-18,North America,Product B,1100.30,22,SMB
2024-01-18,Europe,Product C,780.90,16,Consumer
2024-01-19,Asia Pacific,Product C,1350.60,35,Enterprise
2024-01-19,North America,Product A,1680.75,33,Enterprise
2024-01-20,Europe,Product B,1320.40,26,Enterprise
2024-01-20,Asia Pacific,Product A,1890.90,38,Enterprise
2024-01-21,North America,Product C,745.25,19,Consumer
2024-01-21,Europe,Product A,1575.60,31,Enterprise
2024-01-22,Asia Pacific,Product B,1025.80,23,SMB
CSV

  content_type = "text/csv"

  tags = {
    Name      = "Sample Sales Data"
    Purpose   = "QuickSight Analytics"
    DataType  = "CSV"
  }
}

# Upload historical sales data
resource "aws_s3_object" "historical_sales_data" {
  bucket = aws_s3_bucket.quicksight_data.id
  key    = "sales/historical/sales_data_historical.csv"
  content = <<CSV
date,region,product,sales_amount,quantity,customer_segment
2023-12-01,North America,Product A,1150.25,23,Enterprise
2023-12-02,Europe,Product B,820.50,14,SMB
2023-12-03,Asia Pacific,Product A,2050.75,41,Enterprise
2023-12-04,North America,Product C,650.00,17,Consumer
2023-12-05,Europe,Product A,1425.30,28,Enterprise
CSV

  content_type = "text/csv"

  tags = {
    Name      = "Historical Sales Data"
    Purpose   = "QuickSight Analytics"
    DataType  = "CSV"
  }
}

#-----------------------------------------------------------
# IAM Roles and Policies for QuickSight
#-----------------------------------------------------------

# IAM role for QuickSight S3 access
resource "aws_iam_role" "quicksight_s3_role" {
  name = "${var.project_name}-quicksight-s3-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-quicksight-s3-role"
    Purpose   = "QuickSight S3 access"
    Component = "security"
  })
}

# IAM policy for QuickSight S3 access
resource "aws_iam_role_policy" "quicksight_s3_policy" {
  name = "${var.project_name}-quicksight-s3-policy"
  role = aws_iam_role.quicksight_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.quicksight_data.arn,
          "${aws_s3_bucket.quicksight_data.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for QuickSight service
resource "aws_iam_role" "quicksight_service_role" {
  name = "${var.project_name}-quicksight-service-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-quicksight-service-role"
    Purpose   = "QuickSight service operations"
    Component = "security"
  })
}

# IAM policy for QuickSight service operations
resource "aws_iam_role_policy" "quicksight_service_policy" {
  name = "${var.project_name}-quicksight-service-policy"
  role = aws_iam_role.quicksight_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "quicksight:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:ListRoles"
        ]
        Resource = "*"
      }
    ]
  })
}

#-----------------------------------------------------------
# RDS Database (Optional)
#-----------------------------------------------------------

# RDS subnet group for QuickSight demo database
resource "aws_db_subnet_group" "quicksight_demo" {
  count      = var.create_rds_instance ? 1 : 0
  name       = "${var.project_name}-subnet-group-${random_id.suffix.hex}"
  subnet_ids = data.aws_subnets.default.ids

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-db-subnet-group"
    Purpose   = "QuickSight RDS database"
    Component = "database"
  })
}

# Security group for RDS instance
resource "aws_security_group" "rds_quicksight" {
  count       = var.create_rds_instance ? 1 : 0
  name        = "${var.project_name}-rds-sg-${random_id.suffix.hex}"
  description = "Security group for QuickSight RDS instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "MySQL access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-rds-sg"
    Purpose   = "QuickSight RDS security"
    Component = "security"
  })
}

# Generate random password for RDS
resource "random_password" "rds_password" {
  count   = var.create_rds_instance ? 1 : 0
  length  = 16
  special = true
}

# Store RDS password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "rds_password" {
  count                   = var.create_rds_instance ? 1 : 0
  name                    = "${var.project_name}-rds-password-${random_id.suffix.hex}"
  description             = "RDS password for QuickSight demo database"
  recovery_window_in_days = 7

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-rds-password"
    Purpose   = "RDS credentials"
    Component = "security"
  })
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  count     = var.create_rds_instance ? 1 : 0
  secret_id = aws_secretsmanager_secret.rds_password[0].id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.rds_password[0].result
  })
}

# RDS instance for additional data source
resource "aws_db_instance" "quicksight_demo" {
  count = var.create_rds_instance ? 1 : 0

  identifier             = "${var.project_name}-demo-db-${random_id.suffix.hex}"
  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  storage_encrypted      = true
  
  db_name  = "quicksightdemo"
  username = "admin"
  password = random_password.rds_password[0].result

  db_subnet_group_name   = aws_db_subnet_group.quicksight_demo[0].name
  vpc_security_group_ids = [aws_security_group.rds_quicksight[0].id]

  backup_retention_period = var.rds_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring[0].arn

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-demo-db"
    Purpose   = "QuickSight data source"
    Component = "database"
  })
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.create_rds_instance ? 1 : 0
  name  = "${var.project_name}-rds-monitoring-role-${random_id.suffix.hex}"

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

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-rds-monitoring-role"
    Purpose   = "RDS enhanced monitoring"
    Component = "monitoring"
  })
}

# Attach AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.create_rds_instance ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#-----------------------------------------------------------
# CloudWatch Monitoring and Alerts
#-----------------------------------------------------------

# CloudWatch log group for QuickSight monitoring
resource "aws_cloudwatch_log_group" "quicksight_monitoring" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  name              = "/aws/quicksight/${var.project_name}"
  retention_in_days = 30

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-quicksight-logs"
    Purpose   = "QuickSight monitoring"
    Component = "monitoring"
  })
}

# SNS topic for alerts
resource "aws_sns_topic" "quicksight_alerts" {
  count = var.enable_cost_monitoring && var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-quicksight-alerts-${random_id.suffix.hex}"

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-quicksight-alerts"
    Purpose   = "QuickSight alerting"
    Component = "monitoring"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cost_monitoring && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.quicksight_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch metric alarm for S3 bucket size
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-s3-bucket-size-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400"
  statistic           = "Average"
  threshold           = "1073741824" # 1GB in bytes
  alarm_description   = "This metric monitors S3 bucket size"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.quicksight_alerts[0].arn] : []

  dimensions = {
    BucketName  = aws_s3_bucket.quicksight_data.bucket
    StorageType = "StandardStorage"
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-s3-size-alarm"
    Purpose   = "S3 monitoring"
    Component = "monitoring"
  })
}

#-----------------------------------------------------------
# Cost Monitoring and Budgets
#-----------------------------------------------------------

# AWS Budget for cost monitoring
resource "aws_budgets_budget" "quicksight_monthly" {
  count = var.enable_cost_monitoring ? 1 : 0

  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.cost_alert_threshold)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filters {
    tag {
      key = "Project"
      values = ["QuickSight-BI-Solutions"]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type             = "PERCENTAGE"
    notification_type           = "FORECASTED"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-monthly-budget"
    Purpose   = "Cost monitoring"
    Component = "monitoring"
  })
}

#-----------------------------------------------------------
# Outputs for Integration
#-----------------------------------------------------------

# Local values for resource references
locals {
  quicksight_account_id = data.aws_caller_identity.current.account_id
  aws_region           = data.aws_region.current.name
  
  # QuickSight resource ARNs
  data_source_arn = "arn:aws:quicksight:${local.aws_region}:${local.quicksight_account_id}:datasource/sales-data-s3"
  dataset_arn     = "arn:aws:quicksight:${local.aws_region}:${local.quicksight_account_id}:dataset/sales-dataset"
  analysis_arn    = "arn:aws:quicksight:${local.aws_region}:${local.quicksight_account_id}:analysis/sales-analysis"
  dashboard_arn   = "arn:aws:quicksight:${local.aws_region}:${local.quicksight_account_id}:dashboard/sales-dashboard"
}

# Create output file with configuration for QuickSight setup
resource "local_file" "quicksight_config" {
  filename = "${path.module}/quicksight_setup_config.json"
  content = jsonencode({
    aws_account_id = local.quicksight_account_id
    aws_region     = local.aws_region
    s3_bucket_name = aws_s3_bucket.quicksight_data.bucket
    s3_data_path   = "s3://${aws_s3_bucket.quicksight_data.bucket}/sales/sales_data.csv"
    
    # QuickSight configuration
    quicksight_edition              = var.quicksight_edition
    quicksight_authentication      = var.quicksight_authentication_method
    enable_spice                   = var.enable_quicksight_spice
    session_timeout_minutes        = var.quicksight_session_timeout
    
    # Data source configuration
    data_source_id   = "sales-data-s3"
    data_source_name = "Sales-Data-S3"
    data_source_type = "S3"
    
    # Dataset configuration
    dataset_id   = "sales-dataset"
    dataset_name = "Sales Analytics Dataset"
    
    # Analysis configuration
    analysis_id   = "sales-analysis"
    analysis_name = "Sales Performance Analysis"
    
    # Dashboard configuration
    dashboard_id   = "sales-dashboard"
    dashboard_name = "Sales Performance Dashboard"
    
    # Security configuration
    quicksight_s3_role_arn     = aws_iam_role.quicksight_s3_role.arn
    quicksight_service_role_arn = aws_iam_role.quicksight_service_role.arn
    
    # Optional RDS configuration
    rds_enabled  = var.create_rds_instance
    rds_endpoint = var.create_rds_instance ? aws_db_instance.quicksight_demo[0].endpoint : null
    rds_database = var.create_rds_instance ? aws_db_instance.quicksight_demo[0].db_name : null
    rds_username = var.create_rds_instance ? aws_db_instance.quicksight_demo[0].username : null
    rds_secret_arn = var.create_rds_instance ? aws_secretsmanager_secret.rds_password[0].arn : null
    
    # Feature flags
    enable_scheduled_refresh   = var.enable_scheduled_refresh
    enable_dashboard_sharing   = var.enable_dashboard_sharing
    enable_embedded_analytics  = var.enable_embedded_analytics
    enable_row_level_security  = var.enable_row_level_security
    
    # Refresh schedule configuration
    refresh_frequency = var.refresh_schedule_frequency
    refresh_time     = var.refresh_time_of_day
    
    # Monitoring configuration
    cloudwatch_log_group = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.quicksight_monitoring[0].name : null
    sns_topic_arn       = var.enable_cost_monitoring && var.notification_email != "" ? aws_sns_topic.quicksight_alerts[0].arn : null
    
    # Tags
    common_tags = merge(var.additional_tags, {
      Project     = "QuickSight-BI-Solutions"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "business-intelligence-solutions-quicksight"
    })
  })

  depends_on = [
    aws_s3_bucket.quicksight_data,
    aws_s3_object.sample_sales_data,
    aws_iam_role.quicksight_s3_role,
    aws_iam_role.quicksight_service_role
  ]
}