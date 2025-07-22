# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_id.suffix.hex
  
  # Derived resource names
  glue_database_name        = var.glue_database_name != null ? var.glue_database_name : "${local.name_prefix}-database-${local.suffix}"
  raw_bucket_name          = "${local.name_prefix}-raw-data-${local.suffix}"
  processed_bucket_name    = "${local.name_prefix}-processed-data-${local.suffix}"
  glue_role_name          = "${local.name_prefix}-glue-role-${local.suffix}"
  crawler_name            = "${local.name_prefix}-data-discovery-crawler-${local.suffix}"
  processed_crawler_name  = "${local.name_prefix}-processed-data-crawler-${local.suffix}"
  etl_job_name           = "${local.name_prefix}-etl-job-${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# KMS Key for S3 encryption
resource "aws_kms_key" "s3_encryption" {
  description             = "KMS key for S3 bucket encryption in ETL pipeline"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Glue Service"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "s3_encryption" {
  name          = "alias/${local.name_prefix}-s3-${local.suffix}"
  target_key_id = aws_kms_key.s3_encryption.key_id
}

# S3 Bucket for raw data
resource "aws_s3_bucket" "raw_data" {
  bucket        = local.raw_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = local.raw_bucket_name
    Purpose     = "Raw data storage for ETL pipeline"
    DataType    = "Raw"
  })
}

resource "aws_s3_bucket_versioning" "raw_data" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.raw_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_data" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.raw_data.id

  rule {
    id     = "raw_data_lifecycle"
    status = "Enabled"

    transition {
      days          = var.raw_data_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.raw_data_transition_days * 2
      storage_class = "GLACIER"
    }

    transition {
      days          = var.raw_data_transition_days * 4
      storage_class = "DEEP_ARCHIVE"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# S3 Bucket for processed data
resource "aws_s3_bucket" "processed_data" {
  bucket        = local.processed_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = local.processed_bucket_name
    Purpose     = "Processed data storage for ETL pipeline"
    DataType    = "Processed"
  })
}

resource "aws_s3_bucket_versioning" "processed_data" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.processed_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "processed_data" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.processed_data.id

  rule {
    id     = "processed_data_lifecycle"
    status = "Enabled"

    transition {
      days          = var.processed_data_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.processed_data_transition_days * 2
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# IAM Role for AWS Glue
data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "glue_service_role" {
  name               = local.glue_role_name
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
  
  tags = merge(local.common_tags, {
    Name = local.glue_role_name
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom IAM policy for S3 access
data "aws_iam_policy_document" "glue_s3_access" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    
    resources = [
      "${aws_s3_bucket.raw_data.arn}/*",
      "${aws_s3_bucket.processed_data.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.raw_data.arn,
      aws_s3_bucket.processed_data.arn
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    
    resources = [aws_kms_key.s3_encryption.arn]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name   = "GlueS3Access"
  role   = aws_iam_role.glue_service_role.id
  policy = data.aws_iam_policy_document.glue_s3_access.json
}

# CloudWatch Log Group for Glue jobs
resource "aws_cloudwatch_log_group" "glue_job_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws-glue/jobs/logs-v2"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "glue-job-logs"
  })
}

# Glue Database
resource "aws_glue_catalog_database" "analytics_database" {
  name        = local.glue_database_name
  description = "Analytics database for ETL pipeline"
  
  create_table_default_permission {
    permissions = ["ALL"]
    
    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }

  tags = merge(local.common_tags, {
    Name = local.glue_database_name
  })
}

# Sample data objects for demonstration
resource "aws_s3_object" "sample_sales_csv" {
  bucket       = aws_s3_bucket.raw_data.id
  key          = "sales/sample-sales.csv"
  content_type = "text/csv"
  kms_key_id   = aws_kms_key.s3_encryption.arn
  
  content = <<EOF
order_id,customer_id,product_name,quantity,price,order_date
1001,C001,Laptop,1,999.99,2024-01-15
1002,C002,Mouse,2,25.50,2024-01-15
1003,C001,Keyboard,1,75.00,2024-01-16
1004,C003,Monitor,1,299.99,2024-01-16
1005,C002,Headphones,1,149.99,2024-01-17
EOF

  tags = merge(local.common_tags, {
    Name        = "sample-sales-data"
    DataType    = "Sales"
    Format      = "CSV"
  })
}

resource "aws_s3_object" "sample_customers_json" {
  bucket       = aws_s3_bucket.raw_data.id
  key          = "customers/sample-customers.json"
  content_type = "application/json"
  kms_key_id   = aws_kms_key.s3_encryption.arn
  
  content = <<EOF
{"customer_id": "C001", "name": "John Smith", "email": "john@email.com", "region": "North"}
{"customer_id": "C002", "name": "Jane Doe", "email": "jane@email.com", "region": "South"}
{"customer_id": "C003", "name": "Bob Johnson", "email": "bob@email.com", "region": "East"}
EOF

  tags = merge(local.common_tags, {
    Name        = "sample-customer-data"
    DataType    = "Customer"
    Format      = "JSON"
  })
}

# ETL Script for Glue Job
resource "aws_s3_object" "etl_script" {
  bucket       = aws_s3_bucket.processed_data.id
  key          = "scripts/etl-script.py"
  content_type = "text/x-python"
  kms_key_id   = aws_kms_key.s3_encryption.arn
  
  content = <<EOF
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read sales data from catalog
try:
    sales_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database = args['DATABASE_NAME'],
        table_name = "sales"
    )
    print(f"Sales data loaded with {sales_dynamic_frame.count()} records")
except Exception as e:
    print(f"Error loading sales data: {e}")
    sys.exit(1)

# Read customer data from catalog
try:
    customers_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database = args['DATABASE_NAME'],
        table_name = "customers"
    )
    print(f"Customer data loaded with {customers_dynamic_frame.count()} records")
except Exception as e:
    print(f"Error loading customer data: {e}")
    sys.exit(1)

# Convert to DataFrames for joins
sales_df = sales_dynamic_frame.toDF()
customers_df = customers_dynamic_frame.toDF()

# Join sales with customer data
enriched_sales = sales_df.join(customers_df, "customer_id", "left")
print(f"Enriched sales data created with {enriched_sales.count()} records")

# Calculate total amount per order
from pyspark.sql.functions import col, round as spark_round
enriched_sales = enriched_sales.withColumn("total_amount", 
                                         spark_round(col("quantity") * col("price"), 2))

# Add data quality checks
from pyspark.sql.functions import when, isnan, isnull
enriched_sales = enriched_sales.withColumn("data_quality_flag",
                                         when((col("quantity").isNull()) | 
                                              (col("price").isNull()) |
                                              (col("customer_id").isNull()), "POOR")
                                         .otherwise("GOOD"))

# Convert back to DynamicFrame
enriched_dynamic_frame = DynamicFrame.fromDF(enriched_sales, glueContext, "enriched_sales")

# Write to S3 in Parquet format with partitioning
try:
    glueContext.write_dynamic_frame.from_options(
        frame = enriched_dynamic_frame,
        connection_type = "s3",
        connection_options = {
            "path": f"s3://{args['OUTPUT_BUCKET']}/enriched-sales/",
            "partitionKeys": ["region"]
        },
        format = "parquet",
        format_options = {
            "compression": "snappy"
        }
    )
    print("ETL job completed successfully")
except Exception as e:
    print(f"Error writing output: {e}")
    sys.exit(1)

job.commit()
EOF

  tags = merge(local.common_tags, {
    Name = "etl-transformation-script"
  })
}

# Glue Crawler for raw data discovery
resource "aws_glue_crawler" "data_discovery" {
  database_name = aws_glue_catalog_database.analytics_database.name
  name          = local.crawler_name
  role          = aws_iam_role.glue_service_role.arn
  description   = "Crawler to discover raw data schemas"

  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.bucket}/"
  }

  # Schedule crawler to run daily
  schedule = var.crawler_schedule

  # Schema change policy
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "DEPRECATE_IN_DATABASE"
  }

  # Configuration for better data discovery
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = merge(local.common_tags, {
    Name        = local.crawler_name
    Purpose     = "Raw data discovery"
    DataType    = "Raw"
  })
}

# Glue Crawler for processed data discovery
resource "aws_glue_crawler" "processed_data_discovery" {
  database_name = aws_glue_catalog_database.analytics_database.name
  name          = local.processed_crawler_name
  role          = aws_iam_role.glue_service_role.arn
  description   = "Crawler for processed/transformed data"

  s3_target {
    path = "s3://${aws_s3_bucket.processed_data.bucket}/enriched-sales/"
  }

  # Schema change policy
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "DEPRECATE_IN_DATABASE"
  }

  # Configuration for processed data
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = merge(local.common_tags, {
    Name        = local.processed_crawler_name
    Purpose     = "Processed data discovery"
    DataType    = "Processed"
  })

  # Don't run this crawler until ETL job has run
  depends_on = [aws_glue_job.etl_transformation]
}

# Glue ETL Job
resource "aws_glue_job" "etl_transformation" {
  name              = local.etl_job_name
  role_arn          = aws_iam_role.glue_service_role.arn
  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.etl_job_timeout
  max_retries       = var.etl_job_max_retries
  description       = "ETL job for data transformation and enrichment"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.processed_data.bucket}/${aws_s3_object.etl_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"           = "s3://${aws_s3_bucket.processed_data.bucket}/spark-logs/"
    "--enable-continuous-cloudwatch-log" = var.enable_cloudwatch_logs ? "true" : "false"
    "--DATABASE_NAME"                    = aws_glue_catalog_database.analytics_database.name
    "--OUTPUT_BUCKET"                    = aws_s3_bucket.processed_data.bucket
    "--TempDir"                          = "s3://${aws_s3_bucket.processed_data.bucket}/temp/"
    "--enable-glue-datacatalog"          = "true"
  }

  # Enable Data Quality rules if requested
  dynamic "execution_property" {
    for_each = var.enable_data_quality ? [1] : []
    content {
      max_concurrent_runs = 1
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.etl_job_name
    Purpose     = "Data transformation and enrichment"
    JobType     = "ETL"
  })

  # Ensure script is uploaded before creating job
  depends_on = [aws_s3_object.etl_script]
}

# Data Quality Ruleset (if enabled)
resource "aws_glue_data_quality_ruleset" "sales_data_quality" {
  count       = var.enable_data_quality ? 1 : 0
  name        = "${local.name_prefix}-sales-dq-rules-${local.suffix}"
  description = "Data quality rules for sales data"
  
  ruleset = <<EOF
Rules = [
    ColumnCount > 5,
    IsComplete "customer_id",
    IsComplete "order_id",
    IsComplete "product_name",
    IsUnique "order_id",
    ColumnValues "quantity" > 0,
    ColumnValues "price" > 0
]
EOF

  target_table {
    database_name = aws_glue_catalog_database.analytics_database.name
    table_name    = "sales"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sales-dq-rules"
  })

  depends_on = [aws_glue_crawler.data_discovery]
}

# Glue Workflow for orchestrating ETL pipeline
resource "aws_glue_workflow" "etl_workflow" {
  name        = "${local.name_prefix}-etl-workflow-${local.suffix}"
  description = "ETL workflow for data pipeline orchestration"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-etl-workflow"
  })
}

# Workflow triggers
resource "aws_glue_trigger" "start_crawlers" {
  name         = "${local.name_prefix}-start-crawlers-${local.suffix}"
  description  = "Trigger to start raw data crawlers"
  type         = "ON_DEMAND"
  workflow_name = aws_glue_workflow.etl_workflow.name

  actions {
    crawler_name = aws_glue_crawler.data_discovery.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-start-crawlers-trigger"
  })
}

resource "aws_glue_trigger" "start_etl_job" {
  name         = "${local.name_prefix}-start-etl-${local.suffix}"
  description  = "Trigger to start ETL job after crawlers complete"
  type         = "CONDITIONAL"
  workflow_name = aws_glue_workflow.etl_workflow.name

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.data_discovery.name
      crawl_state  = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.etl_transformation.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-start-etl-trigger"
  })
}

resource "aws_glue_trigger" "crawl_processed_data" {
  name         = "${local.name_prefix}-crawl-processed-${local.suffix}"
  description  = "Trigger to crawl processed data after ETL job completes"
  type         = "CONDITIONAL"
  workflow_name = aws_glue_workflow.etl_workflow.name

  predicate {
    conditions {
      job_name = aws_glue_job.etl_transformation.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.processed_data_discovery.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-crawl-processed-trigger"
  })
}