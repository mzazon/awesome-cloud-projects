# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  unique_suffix = random_id.suffix.hex
  
  # S3 bucket names (must be globally unique)
  data_lake_bucket_name = "${local.name_prefix}-data-lake-${local.unique_suffix}"
  athena_results_bucket_name = "${local.name_prefix}-athena-results-${local.unique_suffix}"
  glue_scripts_bucket_name = "${local.name_prefix}-glue-scripts-${local.unique_suffix}"
  
  # Glue database name
  glue_database_name = "${replace(local.name_prefix, "-", "_")}_db_${local.unique_suffix}"
  
  # IAM role names
  glue_service_role_name = "${local.name_prefix}-glue-service-role-${local.unique_suffix}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# ============================================================================
# S3 BUCKETS AND CONFIGURATION
# ============================================================================

# Main Data Lake S3 Bucket
resource "aws_s3_bucket" "data_lake" {
  bucket = local.data_lake_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-lake-bucket"
    Purpose = "Data Lake Storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  depends_on = [aws_s3_bucket_versioning.data_lake]
  bucket     = aws_s3_bucket.data_lake.id

  # Raw zone lifecycle rules
  rule {
    id     = "raw-zone-lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "raw-zone/"
    }

    dynamic "transition" {
      for_each = var.lifecycle_rules.raw_zone_transitions
      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }
  }

  # Processed zone lifecycle rules
  rule {
    id     = "processed-zone-lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "processed-zone/"
    }

    dynamic "transition" {
      for_each = var.lifecycle_rules.processed_zone_transitions
      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }
  }

  # Archive zone lifecycle rules
  rule {
    id     = "archive-zone-lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "archive-zone/"
    }

    transition {
      days          = 1
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# Create folder structure using S3 objects
resource "aws_s3_object" "data_lake_folders" {
  for_each = toset([
    "raw-zone/",
    "processed-zone/",
    "archive-zone/",
    "scripts/"
  ])
  
  bucket = aws_s3_bucket.data_lake.id
  key    = each.value
  
  tags = local.common_tags
}

# Athena Query Results S3 Bucket
resource "aws_s3_bucket" "athena_results" {
  bucket = local.athena_results_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-athena-results-bucket"
    Purpose = "Athena Query Results Storage"
  })
}

# Athena results bucket versioning
resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Athena results bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

# Athena results bucket public access block
resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athena results bucket lifecycle (cleanup old query results)
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  depends_on = [aws_s3_bucket_versioning.athena_results]
  bucket     = aws_s3_bucket.athena_results.id

  rule {
    id     = "athena-results-cleanup"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM trust policy for Glue service
data "aws_iam_policy_document" "glue_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

# IAM role for Glue service
resource "aws_iam_role" "glue_service_role" {
  name               = local.glue_service_role_name
  assume_role_policy = data.aws_iam_policy_document.glue_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-service-role"
    Purpose = "Glue Service Role"
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_policy" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom IAM policy for S3 access
data "aws_iam_policy_document" "glue_s3_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.data_lake.arn
    ]
  }
}

# Create custom S3 policy for Glue
resource "aws_iam_policy" "glue_s3_policy" {
  name        = "${local.glue_service_role_name}-s3-policy"
  description = "S3 access policy for Glue service role"
  policy      = data.aws_iam_policy_document.glue_s3_policy.json
  
  tags = local.common_tags
}

# Attach custom S3 policy to Glue role
resource "aws_iam_role_policy_attachment" "glue_s3_policy" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = aws_iam_policy.glue_s3_policy.arn
}

# ============================================================================
# GLUE DATA CATALOG
# ============================================================================

# Glue database
resource "aws_glue_catalog_database" "data_lake_db" {
  name        = local.glue_database_name
  description = "Data lake database for analytics"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-database"
    Purpose = "Data Catalog Database"
  })
}

# ============================================================================
# GLUE CRAWLERS
# ============================================================================

# Glue crawler for sales data
resource "aws_glue_crawler" "sales_data_crawler" {
  name          = "${local.name_prefix}-sales-data-crawler-${local.unique_suffix}"
  database_name = aws_glue_catalog_database.data_lake_db.name
  role          = aws_iam_role.glue_service_role.arn
  description   = "Crawler for sales data in CSV format"
  
  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/raw-zone/sales-data/"
  }
  
  # Optional: Set up schedule for automatic crawling
  dynamic "schedule" {
    for_each = var.crawler_schedule != null ? [var.crawler_schedule] : []
    content {
      schedule_expression = schedule.value
    }
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
    Name = "${local.name_prefix}-sales-data-crawler"
    Purpose = "Data Catalog Crawler"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.glue_service_policy,
    aws_iam_role_policy_attachment.glue_s3_policy
  ]
}

# Glue crawler for web logs
resource "aws_glue_crawler" "web_logs_crawler" {
  name          = "${local.name_prefix}-web-logs-crawler-${local.unique_suffix}"
  database_name = aws_glue_catalog_database.data_lake_db.name
  role          = aws_iam_role.glue_service_role.arn
  description   = "Crawler for web logs in JSON format"
  
  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/raw-zone/web-logs/"
  }
  
  # Optional: Set up schedule for automatic crawling
  dynamic "schedule" {
    for_each = var.crawler_schedule != null ? [var.crawler_schedule] : []
    content {
      schedule_expression = schedule.value
    }
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
    Name = "${local.name_prefix}-web-logs-crawler"
    Purpose = "Data Catalog Crawler"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.glue_service_policy,
    aws_iam_role_policy_attachment.glue_s3_policy
  ]
}

# ============================================================================
# GLUE ETL JOBS
# ============================================================================

# Upload Glue ETL script to S3
resource "aws_s3_object" "glue_etl_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "scripts/glue-etl-script.py"
  
  content = <<EOF
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F

# Parse job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'TABLE_NAME', 'OUTPUT_PATH'])

# Initialize Spark and Glue contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Glue catalog
datasource = glueContext.create_dynamic_frame.from_catalog(
    database = args['DATABASE_NAME'],
    table_name = args['TABLE_NAME']
)

# Convert to Spark DataFrame for transformations
df = datasource.toDF()

# Add processing timestamp
df_processed = df.withColumn("processed_timestamp", F.current_timestamp())

# Data quality checks and transformations
if args['TABLE_NAME'] == 'sales_data':
    # Sales data specific transformations
    df_processed = df_processed.filter(df_processed.quantity > 0)
    df_processed = df_processed.filter(df_processed.price > 0)
    df_processed = df_processed.withColumn("total_amount", F.col("quantity") * F.col("price"))

# Convert back to DynamicFrame
processed_dynamic_frame = DynamicFrame.fromDF(df_processed, glueContext, "processed_data")

# Write to S3 in Parquet format with partitioning
glueContext.write_dynamic_frame.from_options(
    frame = processed_dynamic_frame,
    connection_type = "s3",
    connection_options = {
        "path": args['OUTPUT_PATH'],
        "partitionKeys": ["year", "month"]
    },
    format = "parquet",
    transformation_ctx = "datasink"
)

# Job completion
job.commit()
EOF
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-etl-script"
    Purpose = "Glue ETL Script"
  })
}

# Glue ETL job for sales data processing
resource "aws_glue_job" "sales_data_etl" {
  name         = "${local.name_prefix}-sales-data-etl-${local.unique_suffix}"
  role_arn     = aws_iam_role.glue_service_role.arn
  description  = "ETL job for processing sales data"
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.data_lake.bucket}/${aws_s3_object.glue_etl_script.key}"
    python_version  = var.glue_job_configuration.python_version
  }
  
  default_arguments = {
    "--DATABASE_NAME"                          = aws_glue_catalog_database.data_lake_db.name
    "--TABLE_NAME"                            = "sales_data"
    "--OUTPUT_PATH"                           = "s3://${aws_s3_bucket.data_lake.bucket}/processed-zone/sales-data-processed/"
    "--enable-metrics"                        = var.glue_job_configuration.enable_metrics ? "true" : "false"
    "--enable-continuous-cloudwatch-log"     = var.glue_job_configuration.enable_logs ? "true" : "false"
    "--job-language"                          = "python"
    "--job-bookmark-option"                   = "job-bookmark-enable"
    "--TempDir"                               = "s3://${aws_s3_bucket.data_lake.bucket}/temp/"
  }
  
  max_capacity = var.glue_job_configuration.max_capacity
  timeout      = var.glue_job_configuration.timeout
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sales-data-etl-job"
    Purpose = "Data Processing ETL Job"
  })
  
  depends_on = [
    aws_s3_object.glue_etl_script,
    aws_iam_role_policy_attachment.glue_service_policy,
    aws_iam_role_policy_attachment.glue_s3_policy
  ]
}

# ============================================================================
# ATHENA CONFIGURATION
# ============================================================================

# Athena workgroup for data lake analytics
resource "aws_athena_workgroup" "data_lake_workgroup" {
  name        = "${local.name_prefix}-workgroup-${local.unique_suffix}"
  description = "Workgroup for data lake analytics"
  
  configuration {
    enforce_workgroup_configuration    = var.athena_workgroup_configuration.enforce_workgroup_configuration
    publish_cloudwatch_metrics_enabled = var.athena_workgroup_configuration.publish_cloudwatch_metrics
    bytes_scanned_cutoff_per_query     = var.athena_workgroup_configuration.bytes_scanned_cutoff_per_query
    
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
      
      dynamic "encryption_configuration" {
        for_each = var.athena_workgroup_configuration.result_configuration_encryption && var.enable_encryption ? [1] : []
        content {
          encryption_option = var.kms_key_id != null ? "SSE_KMS" : "SSE_S3"
          kms_key = var.kms_key_id
        }
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-athena-workgroup"
    Purpose = "Athena Analytics Workgroup"
  })
}

# ============================================================================
# SAMPLE DATA SETUP
# ============================================================================

# Sample sales data CSV file
resource "aws_s3_object" "sample_sales_data" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "raw-zone/sales-data/year=2024/month=01/sample-sales-data.csv"
  
  content = <<EOF
order_id,customer_id,product_name,category,quantity,price,order_date,region
1001,C001,Laptop,Electronics,1,999.99,2024-01-15,North
1002,C002,Coffee Maker,Appliances,2,79.99,2024-01-15,South
1003,C003,Book Set,Books,3,45.50,2024-01-16,East
1004,C001,Wireless Mouse,Electronics,1,29.99,2024-01-16,North
1005,C004,Desk Chair,Furniture,1,199.99,2024-01-17,West
1006,C005,Smartphone,Electronics,1,699.99,2024-01-17,South
1007,C002,Blender,Appliances,1,89.99,2024-01-18,South
1008,C006,Novel,Books,5,12.99,2024-01-18,East
1009,C003,Monitor,Electronics,2,299.99,2024-01-19,East
1010,C007,Coffee Table,Furniture,1,149.99,2024-01-19,West
EOF
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sample-sales-data"
    Purpose = "Sample Data for Testing"
  })
}

# Sample web logs JSON file
resource "aws_s3_object" "sample_web_logs" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "raw-zone/web-logs/year=2024/month=01/sample-web-logs.json"
  
  content = <<EOF
{"timestamp":"2024-01-15T10:30:00Z","user_id":"U001","page":"/home","action":"view","duration":45,"ip":"192.168.1.100"}
{"timestamp":"2024-01-15T10:31:00Z","user_id":"U002","page":"/products","action":"view","duration":120,"ip":"192.168.1.101"}
{"timestamp":"2024-01-15T10:32:00Z","user_id":"U001","page":"/cart","action":"add_item","duration":30,"ip":"192.168.1.100"}
{"timestamp":"2024-01-15T10:33:00Z","user_id":"U003","page":"/checkout","action":"purchase","duration":180,"ip":"192.168.1.102"}
{"timestamp":"2024-01-15T10:34:00Z","user_id":"U002","page":"/profile","action":"update","duration":90,"ip":"192.168.1.101"}
EOF
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sample-web-logs"
    Purpose = "Sample Data for Testing"
  })
}

# ============================================================================
# CLOUDWATCH ALARMS AND MONITORING
# ============================================================================

# CloudWatch alarm for Glue job failures
resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  alarm_name          = "${local.name_prefix}-glue-job-failure-${local.unique_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Glue job failures"
  
  dimensions = {
    JobName = aws_glue_job.sales_data_etl.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-job-failure-alarm"
    Purpose = "Monitoring and Alerting"
  })
}

# CloudWatch alarm for high Athena query costs
resource "aws_cloudwatch_metric_alarm" "athena_high_cost" {
  alarm_name          = "${local.name_prefix}-athena-high-cost-${local.unique_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DataScannedInBytes"
  namespace           = "AWS/Athena"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1073741824" # 1GB in bytes
  alarm_description   = "This metric monitors high Athena query costs"
  
  dimensions = {
    WorkGroup = aws_athena_workgroup.data_lake_workgroup.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-athena-high-cost-alarm"
    Purpose = "Cost Monitoring"
  })
}