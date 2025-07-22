# main.tf - Main infrastructure configuration for AWS Glue Workflows
# This file contains the primary infrastructure resources for data pipeline orchestration

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_string.suffix.result
  
  # S3 bucket names (must be globally unique)
  raw_bucket_name = "${local.name_prefix}-raw-${local.random_suffix}"
  processed_bucket_name = "${local.name_prefix}-processed-${local.random_suffix}"
  
  # Glue resource names
  workflow_name = "${local.name_prefix}-workflow-${local.random_suffix}"
  database_name = "${local.name_prefix}-database-${local.random_suffix}"
  role_name = "${local.name_prefix}-glue-role-${local.random_suffix}"
  
  # Combined tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "aws-glue-workflows"
    },
    var.additional_tags
  )
}

# S3 bucket for raw data storage
resource "aws_s3_bucket" "raw_data" {
  bucket        = local.raw_bucket_name
  force_destroy = var.force_destroy_buckets
  
  tags = merge(local.common_tags, {
    Name        = "Raw Data Bucket"
    DataType    = "raw"
    Purpose     = "source-data-storage"
  })
}

# S3 bucket for processed data storage
resource "aws_s3_bucket" "processed_data" {
  bucket        = local.processed_bucket_name
  force_destroy = var.force_destroy_buckets
  
  tags = merge(local.common_tags, {
    Name        = "Processed Data Bucket"
    DataType    = "processed"
    Purpose     = "transformed-data-storage"
  })
}

# S3 bucket versioning configuration for raw data
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket versioning configuration for processed data
resource "aws_s3_bucket_versioning" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption for raw data
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.raw_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket server-side encryption for processed data
resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.processed_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for raw data bucket
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for processed data bucket
resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample data to raw bucket
resource "aws_s3_object" "sample_data" {
  bucket = aws_s3_bucket.raw_data.id
  key    = "input/sample-data.csv"
  content = <<EOF
customer_id,name,email,purchase_amount,purchase_date
1,John Doe,john@example.com,150.00,2024-01-15
2,Jane Smith,jane@example.com,200.00,2024-01-16
3,Bob Johnson,bob@example.com,75.00,2024-01-17
4,Alice Brown,alice@example.com,300.00,2024-01-18
5,Charlie Wilson,charlie@example.com,125.00,2024-01-19
EOF
  
  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name    = "Sample Data"
    Purpose = "testing-data-pipeline"
  })
}

# IAM trust policy document for Glue service
data "aws_iam_policy_document" "glue_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

# IAM policy document for S3 access
data "aws_iam_policy_document" "s3_access_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.raw_data.arn,
      "${aws_s3_bucket.raw_data.arn}/*",
      aws_s3_bucket.processed_data.arn,
      "${aws_s3_bucket.processed_data.arn}/*"
    ]
  }
}

# IAM role for Glue workflow operations
resource "aws_iam_role" "glue_role" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.glue_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name    = "Glue Workflow Role"
    Purpose = "glue-service-execution"
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3 access
resource "aws_iam_role_policy" "s3_access_policy" {
  name   = "S3AccessPolicy"
  role   = aws_iam_role.glue_role.id
  policy = data.aws_iam_policy_document.s3_access_policy.json
}

# CloudWatch log group for Glue jobs (optional)
resource "aws_cloudwatch_log_group" "glue_jobs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/glue/jobs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name    = "Glue Jobs Log Group"
    Purpose = "glue-job-logging"
  })
}

# Glue database for Data Catalog
resource "aws_glue_catalog_database" "workflow_database" {
  name        = local.database_name
  description = var.database_description
  
  tags = merge(local.common_tags, {
    Name    = "Workflow Database"
    Purpose = "data-catalog-metadata"
  })
}

# ETL script for data processing
resource "aws_s3_object" "etl_script" {
  bucket = aws_s3_bucket.processed_data.id
  key    = "scripts/etl-script.py"
  content = <<EOF
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

# Parse job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from the catalog
datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name="input"
)

# Apply data transformations
mapped_data = ApplyMapping.apply(
    frame=datasource0,
    mappings=[
        ("customer_id", "string", "customer_id", "int"),
        ("name", "string", "customer_name", "string"),
        ("email", "string", "email", "string"),
        ("purchase_amount", "string", "purchase_amount", "double"),
        ("purchase_date", "string", "purchase_date", "string")
    ]
)

# Filter out null values
filtered_data = Filter.apply(
    frame=mapped_data,
    f=lambda x: x["customer_id"] is not None and x["purchase_amount"] is not None
)

# Write processed data to S3 in Parquet format
glueContext.write_dynamic_frame.from_options(
    frame=filtered_data,
    connection_type="s3",
    connection_options={"path": f"s3://{args['OUTPUT_BUCKET']}/output/"},
    format="parquet",
    transformation_ctx="write_to_s3"
)

# Commit the job
job.commit()
EOF
  
  content_type = "text/plain"
  
  tags = merge(local.common_tags, {
    Name    = "ETL Script"
    Purpose = "data-transformation-logic"
  })
}

# Glue crawler for source data discovery
resource "aws_glue_crawler" "source_crawler" {
  database_name = aws_glue_catalog_database.workflow_database.name
  name          = "${local.name_prefix}-source-crawler-${local.random_suffix}"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler to discover source data schema"
  
  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.id}/input/"
  }
  
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name    = "Source Data Crawler"
    Purpose = "schema-discovery"
    DataType = "source"
  })
}

# Glue job for data processing
resource "aws_glue_job" "data_processing" {
  name              = "${local.name_prefix}-data-processing-${local.random_suffix}"
  role_arn          = aws_iam_role.glue_role.arn
  description       = "ETL job for data processing in workflow"
  glue_version      = var.glue_version
  max_retries       = var.glue_job_max_retries
  timeout           = var.glue_job_timeout
  worker_type       = "G.1X"
  number_of_workers = 2
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.processed_data.id}/scripts/etl-script.py"
    python_version  = "3"
  }
  
  default_arguments = {
    "--DATABASE_NAME"                     = aws_glue_catalog_database.workflow_database.name
    "--OUTPUT_BUCKET"                    = aws_s3_bucket.processed_data.id
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = var.enable_cloudwatch_logs ? "true" : "false"
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--TempDir"                          = "s3://${aws_s3_bucket.processed_data.id}/temp/"
  }
  
  tags = merge(local.common_tags, {
    Name    = "Data Processing Job"
    Purpose = "etl-data-transformation"
  })
}

# Glue crawler for processed data discovery
resource "aws_glue_crawler" "target_crawler" {
  database_name = aws_glue_catalog_database.workflow_database.name
  name          = "${local.name_prefix}-target-crawler-${local.random_suffix}"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler to discover processed data schema"
  
  s3_target {
    path = "s3://${aws_s3_bucket.processed_data.id}/output/"
  }
  
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name    = "Target Data Crawler"
    Purpose = "schema-discovery"
    DataType = "processed"
  })
}

# Glue workflow for orchestration
resource "aws_glue_workflow" "data_pipeline" {
  name                  = local.workflow_name
  description           = "Data pipeline workflow orchestrating crawlers and ETL jobs"
  max_concurrent_runs   = var.max_concurrent_runs
  
  default_run_properties = {
    environment      = var.environment
    pipeline_version = "1.0"
    managed_by       = "terraform"
  }
  
  tags = merge(local.common_tags, {
    Name    = "Data Pipeline Workflow"
    Purpose = "pipeline-orchestration"
  })
}

# Schedule trigger to start workflow
resource "aws_glue_trigger" "schedule_trigger" {
  name          = "${local.name_prefix}-schedule-trigger-${local.random_suffix}"
  workflow_name = aws_glue_workflow.data_pipeline.name
  type          = "SCHEDULED"
  schedule      = var.workflow_schedule
  description   = "Scheduled trigger for daily workflow execution"
  start_on_creation = true
  
  actions {
    crawler_name = aws_glue_crawler.source_crawler.name
  }
  
  tags = merge(local.common_tags, {
    Name    = "Schedule Trigger"
    Purpose = "workflow-scheduling"
  })
}

# Event trigger for ETL job after successful crawler completion
resource "aws_glue_trigger" "crawler_success_trigger" {
  name          = "${local.name_prefix}-crawler-success-trigger-${local.random_suffix}"
  workflow_name = aws_glue_workflow.data_pipeline.name
  type          = "CONDITIONAL"
  description   = "Trigger ETL job after successful source crawler completion"
  start_on_creation = true
  
  predicate {
    logical = "AND"
    
    conditions {
      logical_operator = "EQUALS"
      crawler_name     = aws_glue_crawler.source_crawler.name
      crawl_state      = "SUCCEEDED"
    }
  }
  
  actions {
    job_name = aws_glue_job.data_processing.name
  }
  
  tags = merge(local.common_tags, {
    Name    = "Crawler Success Trigger"
    Purpose = "job-dependency-management"
  })
}

# Event trigger for target crawler after successful job completion
resource "aws_glue_trigger" "job_success_trigger" {
  name          = "${local.name_prefix}-job-success-trigger-${local.random_suffix}"
  workflow_name = aws_glue_workflow.data_pipeline.name
  type          = "CONDITIONAL"
  description   = "Trigger target crawler after successful ETL job completion"
  start_on_creation = true
  
  predicate {
    logical = "AND"
    
    conditions {
      logical_operator = "EQUALS"
      job_name         = aws_glue_job.data_processing.name
      state            = "SUCCEEDED"
    }
  }
  
  actions {
    crawler_name = aws_glue_crawler.target_crawler.name
  }
  
  tags = merge(local.common_tags, {
    Name    = "Job Success Trigger"
    Purpose = "catalog-update-management"
  })
}

# Optional: SNS topic for workflow notifications
resource "aws_sns_topic" "workflow_notifications" {
  count = var.enable_workflow_notifications ? 1 : 0
  name  = "${local.name_prefix}-workflow-notifications-${local.random_suffix}"
  
  tags = merge(local.common_tags, {
    Name    = "Workflow Notifications"
    Purpose = "workflow-monitoring"
  })
}

# Optional: SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_workflow_notifications ? 1 : 0
  topic_arn = aws_sns_topic.workflow_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Optional: CloudWatch alarm for workflow failures
resource "aws_cloudwatch_metric_alarm" "workflow_failure" {
  count               = var.enable_workflow_notifications ? 1 : 0
  alarm_name          = "${local.name_prefix}-workflow-failure-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Glue workflow failures"
  alarm_actions       = [aws_sns_topic.workflow_notifications[0].arn]
  
  dimensions = {
    JobName = aws_glue_job.data_processing.name
  }
  
  tags = merge(local.common_tags, {
    Name    = "Workflow Failure Alarm"
    Purpose = "workflow-monitoring"
  })
}