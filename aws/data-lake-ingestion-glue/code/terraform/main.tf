# AWS Glue Data Lake Ingestion Pipeline Infrastructure
# This Terraform configuration creates a complete data lake pipeline using AWS Glue

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # S3 bucket name with auto-generation if not provided
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-${local.random_suffix}"
  
  # Glue database name with auto-generation if not provided
  glue_database_name = var.glue_database_name != "" ? var.glue_database_name : replace("${local.name_prefix}_catalog_${local.random_suffix}", "-", "_")
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# =====================================================
# S3 Data Lake Storage Infrastructure
# =====================================================

# S3 bucket for data lake storage with proper versioning and encryption
resource "aws_s3_bucket" "data_lake" {
  bucket        = local.s3_bucket_name
  force_destroy = var.environment != "prod" ? true : false

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-data-lake"
    Purpose     = "Data Lake Storage"
    Layer       = "Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "data_lake_lifecycle"
    status = "Enabled"

    # Transition raw data to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Create the folder structure for data lake layers
resource "aws_s3_object" "folder_structure" {
  for_each = toset([
    "raw-data/",
    "raw-data/events/",
    "raw-data/customers/",
    "processed-data/",
    "processed-data/bronze/",
    "processed-data/silver/",
    "processed-data/gold/",
    "scripts/",
    "temp/",
    "athena-results/"
  ])

  bucket       = aws_s3_bucket.data_lake.bucket
  key          = each.value
  content_type = "application/x-directory"
  
  tags = local.common_tags
}

# =====================================================
# IAM Roles and Policies for AWS Glue
# =====================================================

# IAM trust policy for AWS Glue service
data "aws_iam_policy_document" "glue_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy for Glue to access S3 data lake bucket
data "aws_iam_policy_document" "glue_s3_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetBucketAcl",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion"
    ]
    
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["arn:aws:logs:*:*:*"]
  }
}

# IAM role for AWS Glue with comprehensive permissions
resource "aws_iam_role" "glue_role" {
  name               = "${local.name_prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_trust_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-glue-role"
    Purpose = "AWS Glue Service Role"
  })
}

# Attach AWS managed Glue service role policy
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Attach custom S3 access policy
resource "aws_iam_role_policy" "glue_s3_access" {
  name   = "${local.name_prefix}-glue-s3-access"
  role   = aws_iam_role.glue_role.id
  policy = data.aws_iam_policy_document.glue_s3_policy.json
}

# =====================================================
# AWS Glue Data Catalog Database
# =====================================================

# AWS Glue database for the data catalog
resource "aws_glue_catalog_database" "data_lake" {
  name        = local.glue_database_name
  description = "Data lake catalog for analytics pipeline - ${var.environment} environment"

  create_table_default_permission {
    permissions = ["SELECT"]
    
    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }

  tags = merge(local.common_tags, {
    Name    = local.glue_database_name
    Purpose = "Data Catalog Database"
  })
}

# =====================================================
# Sample Data Creation for Testing
# =====================================================

# Sample JSON events data
resource "aws_s3_object" "sample_events" {
  bucket       = aws_s3_bucket.data_lake.bucket
  key          = "raw-data/events/year=2024/month=01/day=15/sample-events.json"
  content_type = "application/json"
  
  content = jsonencode([
    {
      event_id   = "evt001"
      user_id    = "user123"
      event_type = "purchase"
      product_id = "prod456"
      amount     = 89.99
      timestamp  = "2024-01-15T10:30:00Z"
      category   = "electronics"
    },
    {
      event_id   = "evt002"
      user_id    = "user456"
      event_type = "view"
      product_id = "prod789"
      amount     = 0.0
      timestamp  = "2024-01-15T10:31:00Z"
      category   = "books"
    },
    {
      event_id   = "evt003"
      user_id    = "user789"
      event_type = "cart_add"
      product_id = "prod123"
      amount     = 45.50
      timestamp  = "2024-01-15T10:32:00Z"
      category   = "clothing"
    },
    {
      event_id   = "evt004"
      user_id    = "user123"
      event_type = "purchase"
      product_id = "prod321"
      amount     = 129.00
      timestamp  = "2024-01-15T10:33:00Z"
      category   = "home"
    },
    {
      event_id   = "evt005"
      user_id    = "user654"
      event_type = "view"
      product_id = "prod555"
      amount     = 0.0
      timestamp  = "2024-01-15T10:34:00Z"
      category   = "electronics"
    }
  ])

  tags = merge(local.common_tags, {
    Name    = "sample-events-data"
    Purpose = "Sample Data"
  })
}

# Sample CSV customers data
resource "aws_s3_object" "sample_customers" {
  bucket       = aws_s3_bucket.data_lake.bucket
  key          = "raw-data/customers/sample-customers.csv"
  content_type = "text/csv"
  
  content = <<EOF
customer_id,name,email,registration_date,country,age_group
user123,John Doe,john.doe@example.com,2023-05-15,US,25-34
user456,Jane Smith,jane.smith@example.com,2023-06-20,CA,35-44
user789,Bob Johnson,bob.johnson@example.com,2023-07-10,UK,45-54
user654,Alice Brown,alice.brown@example.com,2023-08-05,US,18-24
user321,Charlie Wilson,charlie.wilson@example.com,2023-09-12,AU,25-34
EOF

  tags = merge(local.common_tags, {
    Name    = "sample-customers-data"
    Purpose = "Sample Data"
  })
}

# =====================================================
# AWS Glue Crawler for Schema Discovery
# =====================================================

# AWS Glue crawler for automatic schema discovery
resource "aws_glue_crawler" "data_lake_crawler" {
  database_name = aws_glue_catalog_database.data_lake.name
  name          = "${local.name_prefix}-crawler"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler for data lake raw data sources"
  table_prefix  = "raw_"

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/raw-data/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  lineage_configuration {
    crawler_lineage_settings = "ENABLE"
  }

  # Schedule the crawler if scheduling is enabled
  dynamic "schedule" {
    for_each = var.enable_workflow_scheduling && var.crawler_schedule != "" ? [1] : []
    content {
      schedule_expression = var.crawler_schedule
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-crawler"
    Purpose = "Schema Discovery"
  })

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy.glue_s3_access,
    aws_s3_object.sample_events,
    aws_s3_object.sample_customers
  ]
}

# =====================================================
# AWS Glue ETL Job Script
# =====================================================

# ETL script for data transformation
resource "aws_s3_object" "etl_script" {
  bucket       = aws_s3_bucket.data_lake.bucket
  key          = "scripts/etl-script.py"
  content_type = "text/x-python"
  
  content = templatefile("${path.module}/etl-script.py.tpl", {
    database_name  = aws_glue_catalog_database.data_lake.name
    s3_bucket_name = aws_s3_bucket.data_lake.bucket
  })

  tags = merge(local.common_tags, {
    Name    = "etl-script"
    Purpose = "ETL Processing"
  })
}

# =====================================================
# AWS Glue ETL Job
# =====================================================

# AWS Glue ETL job for data processing
resource "aws_glue_job" "data_lake_etl" {
  name         = "${local.name_prefix}-etl-job"
  description  = "Data lake ETL pipeline for multi-layer architecture"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.data_lake.bucket}/scripts/etl-script.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-bookmark-option"                     = "job-bookmark-enable"
    "--enable-metrics"                         = "true"
    "--enable-continuous-cloudwatch-log"      = "true"
    "--enable-spark-ui"                        = "true"
    "--spark-event-logs-path"                  = "s3://${aws_s3_bucket.data_lake.bucket}/temp/spark-logs/"
    "--DATABASE_NAME"                          = aws_glue_catalog_database.data_lake.name
    "--S3_BUCKET_NAME"                         = aws_s3_bucket.data_lake.bucket
    "--additional-python-modules"              = "pandas==1.5.3,pyarrow==12.0.0"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  max_retries = 1
  timeout     = var.etl_job_timeout
  
  # Use new worker type for better performance
  worker_type       = "G.1X"
  number_of_workers = 5

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-etl-job"
    Purpose = "Data Processing"
  })

  depends_on = [
    aws_s3_object.etl_script,
    aws_glue_crawler.data_lake_crawler
  ]
}

# =====================================================
# AWS Glue Workflow for Pipeline Orchestration
# =====================================================

# AWS Glue workflow for orchestrating crawler and ETL job
resource "aws_glue_workflow" "data_lake_pipeline" {
  name        = "${local.name_prefix}-workflow"
  description = "Data lake ingestion workflow with crawler and ETL"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-workflow"
    Purpose = "Pipeline Orchestration"
  })
}

# Trigger for starting the crawler (scheduled or on-demand)
resource "aws_glue_trigger" "crawler_trigger" {
  count = var.enable_workflow_scheduling ? 1 : 0
  
  name          = "${local.name_prefix}-crawler-trigger"
  type          = var.crawler_schedule != "" ? "SCHEDULED" : "ON_DEMAND"
  workflow_name = aws_glue_workflow.data_lake_pipeline.name
  
  dynamic "schedule" {
    for_each = var.crawler_schedule != "" ? [1] : []
    content {
      schedule_expression = var.crawler_schedule
    }
  }

  actions {
    crawler_name = aws_glue_crawler.data_lake_crawler.name
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-crawler-trigger"
    Purpose = "Crawler Scheduling"
  })
}

# Trigger for ETL job (conditional on crawler success)
resource "aws_glue_trigger" "etl_trigger" {
  name          = "${local.name_prefix}-etl-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.data_lake_pipeline.name

  predicate {
    conditions {
      logical_operator = "EQUALS"
      crawler_name     = aws_glue_crawler.data_lake_crawler.name
      crawl_state      = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.data_lake_etl.name
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-etl-trigger"
    Purpose = "ETL Job Orchestration"
  })
}

# =====================================================
# Data Quality Rules (Optional)
# =====================================================

# AWS Glue Data Quality ruleset
resource "aws_glue_data_quality_ruleset" "data_lake_quality" {
  count = var.enable_data_quality_rules ? 1 : 0
  
  name        = "${local.name_prefix}-quality-rules"
  description = "Data quality rules for data lake pipeline"
  
  ruleset = "Rules = [ColumnCount > 5, IsComplete \"user_id\", IsComplete \"event_type\", IsComplete \"timestamp\", ColumnValues \"amount\" >= 0]"
  
  target_table {
    database_name = aws_glue_catalog_database.data_lake.name
    table_name    = "silver_events"
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-quality-rules"
    Purpose = "Data Quality"
  })

  depends_on = [aws_glue_job.data_lake_etl]
}

# =====================================================
# CloudWatch Monitoring and Alerting (Optional)
# =====================================================

# SNS topic for pipeline alerts
resource "aws_sns_topic" "pipeline_alerts" {
  count = var.enable_cloudwatch_monitoring && var.notification_email != "" ? 1 : 0
  
  name         = "${local.name_prefix}-pipeline-alerts"
  display_name = "Data Lake Pipeline Alerts"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-pipeline-alerts"
    Purpose = "Monitoring"
  })
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.enable_cloudwatch_monitoring && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.pipeline_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for Glue job failures
resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-glue-job-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when Glue job fails"
  
  dimensions = {
    JobName    = aws_glue_job.data_lake_etl.name
    JobRunId   = "ALL"
  }

  alarm_actions = var.notification_email != "" ? [aws_sns_topic.pipeline_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-glue-job-failure"
    Purpose = "Monitoring"
  })
}

# CloudWatch alarm for crawler failures
resource "aws_cloudwatch_metric_alarm" "crawler_failure" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-crawler-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when Glue crawler fails"
  
  dimensions = {
    CrawlerName = aws_glue_crawler.data_lake_crawler.name
  }

  alarm_actions = var.notification_email != "" ? [aws_sns_topic.pipeline_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-crawler-failure"
    Purpose = "Monitoring"
  })
}

# =====================================================
# Amazon Athena Workgroup for Analytics
# =====================================================

# Athena workgroup for data lake analytics
resource "aws_athena_workgroup" "data_lake" {
  name        = "${local.name_prefix}-workgroup"
  description = "Workgroup for data lake analytics"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-workgroup"
    Purpose = "Analytics"
  })
}