# =============================================================================
# Advanced Data Lake Governance with Lake Formation and DataZone
# =============================================================================
# This Terraform configuration creates an enterprise-grade data lake governance 
# platform using AWS Lake Formation for fine-grained access control and 
# Amazon DataZone for data discovery and cataloging.

# Random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# =============================================================================
# DATA LAKE STORAGE - S3 BUCKET CONFIGURATION
# =============================================================================

# S3 bucket for the data lake with versioning and encryption
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.data_lake_bucket_prefix}-${random_string.suffix.result}"

  tags = {
    Name        = "Enterprise Data Lake"
    Environment = var.environment
    Purpose     = "DataLakeGovernance"
    ManagedBy   = "Terraform"
  }
}

# Enable versioning for data protection
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for data at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for security
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create folder structure for data lake zones
resource "aws_s3_object" "raw_data_folder" {
  bucket  = aws_s3_bucket.data_lake.id
  key     = "${var.raw_data_prefix}/"
  content = ""
}

resource "aws_s3_object" "curated_data_folder" {
  bucket  = aws_s3_bucket.data_lake.id
  key     = "${var.curated_data_prefix}/"
  content = ""
}

resource "aws_s3_object" "analytics_data_folder" {
  bucket  = aws_s3_bucket.data_lake.id
  key     = "${var.analytics_data_prefix}/"
  content = ""
}

resource "aws_s3_object" "scripts_folder" {
  bucket  = aws_s3_bucket.data_lake.id
  key     = "scripts/"
  content = ""
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# Lake Formation Service Role for cross-service operations
resource "aws_iam_role" "lake_formation_service_role" {
  name = "${var.resource_prefix}-lake-formation-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lakeformation.amazonaws.com",
            "glue.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "Lake Formation Service Role"
    Purpose   = "DataLakeGovernance"
    ManagedBy = "Terraform"
  }
}

# Comprehensive policy for Lake Formation service operations
resource "aws_iam_role_policy" "lake_formation_service_policy" {
  name = "${var.resource_prefix}-lake-formation-service-policy"
  role = aws_iam_role.lake_formation_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition",
          "glue:BatchUpdatePartition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
          "lakeformation:GrantPermissions",
          "lakeformation:RevokePermissions",
          "lakeformation:BatchGrantPermissions",
          "lakeformation:BatchRevokePermissions",
          "lakeformation:ListPermissions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Data Analyst Role for restricted data access
resource "aws_iam_role" "data_analyst_role" {
  name = "${var.resource_prefix}-data-analyst-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "Data Analyst Role"
    Purpose   = "DataAccess"
    ManagedBy = "Terraform"
  }
}

# Attach Athena full access policy to data analyst role
resource "aws_iam_role_policy_attachment" "data_analyst_athena" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
  role       = aws_iam_role.data_analyst_role.name
}

# =============================================================================
# LAKE FORMATION CONFIGURATION
# =============================================================================

# Configure Lake Formation settings for governance
resource "aws_lakeformation_data_lake_settings" "main" {
  admins = [data.aws_caller_identity.current.arn]

  create_database_default_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }

  create_table_default_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }

  external_data_filtering_allow_list = [data.aws_caller_identity.current.account_id]
  trusted_resource_owners            = [data.aws_caller_identity.current.account_id]

  depends_on = [aws_iam_role.lake_formation_service_role]
}

# Register S3 bucket as Lake Formation resource
resource "aws_lakeformation_resource" "data_lake" {
  arn      = aws_s3_bucket.data_lake.arn
  use_service_linked_role = true

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# =============================================================================
# GLUE DATA CATALOG CONFIGURATION
# =============================================================================

# Create Glue database for enterprise data catalog
resource "aws_glue_catalog_database" "enterprise_data_catalog" {
  name         = var.glue_database_name
  description  = "Enterprise data catalog for governed data lake"

  parameters = {
    classification = "curated"
    environment    = var.environment
  }

  depends_on = [aws_lakeformation_resource.data_lake]
}

# Customer data table with comprehensive schema and PII classification
resource "aws_glue_catalog_table" "customer_data" {
  name          = "customer_data"
  database_name = aws_glue_catalog_database.enterprise_data_catalog.name
  description   = "Customer information with PII protection"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    classification      = "csv"
    delimiter          = ","
    has_encrypted_data = "false"
    data_classification = "confidential"
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.id}/${var.curated_data_prefix}/customer_data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim"             = ","
        "skip.header.line.count" = "1"
      }
    }

    columns {
      name    = "customer_id"
      type    = "bigint"
      comment = "Unique customer identifier"
    }

    columns {
      name    = "first_name"
      type    = "string"
      comment = "Customer first name - PII"
    }

    columns {
      name    = "last_name"
      type    = "string"
      comment = "Customer last name - PII"
    }

    columns {
      name    = "email"
      type    = "string"
      comment = "Customer email - PII"
    }

    columns {
      name    = "phone"
      type    = "string"
      comment = "Customer phone - PII"
    }

    columns {
      name    = "registration_date"
      type    = "date"
      comment = "Account registration date"
    }

    columns {
      name    = "customer_segment"
      type    = "string"
      comment = "Business customer segment"
    }

    columns {
      name    = "lifetime_value"
      type    = "double"
      comment = "Customer lifetime value"
    }

    columns {
      name    = "region"
      type    = "string"
      comment = "Customer geographic region"
    }
  }
}

# Transaction data table with optimized Parquet format
resource "aws_glue_catalog_table" "transaction_data" {
  name          = "transaction_data"
  database_name = aws_glue_catalog_database.enterprise_data_catalog.name
  description   = "Customer transaction records"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    classification      = "parquet"
    data_classification = "internal"
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.id}/${var.curated_data_prefix}/transaction_data/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name    = "transaction_id"
      type    = "string"
      comment = "Unique transaction identifier"
    }

    columns {
      name    = "customer_id"
      type    = "bigint"
      comment = "Associated customer ID"
    }

    columns {
      name    = "transaction_date"
      type    = "timestamp"
      comment = "Transaction timestamp"
    }

    columns {
      name    = "amount"
      type    = "double"
      comment = "Transaction amount"
    }

    columns {
      name    = "currency"
      type    = "string"
      comment = "Transaction currency"
    }

    columns {
      name    = "merchant_category"
      type    = "string"
      comment = "Merchant category code"
    }

    columns {
      name    = "payment_method"
      type    = "string"
      comment = "Payment method used"
    }

    columns {
      name    = "status"
      type    = "string"
      comment = "Transaction status"
    }
  }
}

# =============================================================================
# LAKE FORMATION PERMISSIONS AND DATA FILTERS
# =============================================================================

# Grant database permissions to current user (admin)
resource "aws_lakeformation_permissions" "database_admin" {
  principal   = data.aws_caller_identity.current.arn
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.enterprise_data_catalog.name
  }

  depends_on = [aws_glue_catalog_database.enterprise_data_catalog]
}

# Create data cell filter for PII protection
resource "aws_lakeformation_data_cells_filter" "customer_data_pii_filter" {
  table_data {
    database_name    = aws_glue_catalog_database.enterprise_data_catalog.name
    name             = "customer_data_pii_filter"
    table_catalog_id = data.aws_caller_identity.current.account_id
    table_name       = aws_glue_catalog_table.customer_data.name

    column_names = [
      "customer_id",
      "registration_date", 
      "customer_segment",
      "lifetime_value",
      "region"
    ]

    row_filter {
      filter_expression = "customer_segment IN ('premium', 'standard')"
    }
  }

  depends_on = [aws_glue_catalog_table.customer_data]
}

# Grant filtered permissions to data analyst role
resource "aws_lakeformation_permissions" "analyst_customer_data_filtered" {
  principal   = aws_iam_role.data_analyst_role.arn
  permissions = ["SELECT"]

  data_cells_filter {
    database_name    = aws_glue_catalog_database.enterprise_data_catalog.name
    name             = aws_lakeformation_data_cells_filter.customer_data_pii_filter.table_data[0].name
    table_catalog_id = data.aws_caller_identity.current.account_id
    table_name       = aws_glue_catalog_table.customer_data.name
  }

  depends_on = [aws_lakeformation_data_cells_filter.customer_data_pii_filter]
}

# Grant full access to transaction data for analysts
resource "aws_lakeformation_permissions" "analyst_transaction_data" {
  principal   = aws_iam_role.data_analyst_role.arn
  permissions = ["SELECT"]

  table {
    database_name = aws_glue_catalog_database.enterprise_data_catalog.name
    name          = aws_glue_catalog_table.transaction_data.name
  }

  depends_on = [aws_glue_catalog_table.transaction_data]
}

# =============================================================================
# GLUE ETL JOB WITH LINEAGE TRACKING
# =============================================================================

# ETL job script for customer data processing with lineage tracking
resource "aws_s3_object" "etl_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "scripts/customer_data_etl.py"
  content = templatefile("${path.module}/templates/customer_data_etl.py", {
    data_lake_bucket = aws_s3_bucket.data_lake.id
  })
}

# Glue ETL job with enhanced lineage tracking capabilities
resource "aws_glue_job" "customer_data_etl" {
  name         = "${var.resource_prefix}-customer-data-etl-lineage"
  role_arn     = aws_iam_role.lake_formation_service_role.arn
  glue_version = "4.0"
  max_capacity = 2.0
  timeout      = 60
  max_retries  = 1

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.data_lake.id}/scripts/customer_data_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${aws_s3_bucket.data_lake.id}/spark-logs/"
    "--enable-glue-datacatalog"          = "true"
    "--DATA_LAKE_BUCKET"                 = aws_s3_bucket.data_lake.id
  }

  tags = {
    Name      = "Customer Data ETL with Lineage"
    Purpose   = "DataProcessing"
    ManagedBy = "Terraform"
  }

  depends_on = [
    aws_s3_object.etl_script,
    aws_iam_role.lake_formation_service_role
  ]
}

# =============================================================================
# AMAZON DATAZONE DOMAIN AND GOVERNANCE
# =============================================================================

# DataZone domain for enterprise data governance
resource "aws_datazone_domain" "enterprise_governance" {
  name                   = var.datazone_domain_name
  description            = "Enterprise data governance domain with Lake Formation integration"
  domain_execution_role  = aws_iam_role.lake_formation_service_role.arn

  tags = {
    Name        = "Enterprise Data Governance Domain"
    Environment = var.environment
    Purpose     = "DataGovernance"
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_iam_role.lake_formation_service_role]
}

# Business glossary for standardized terminology
resource "aws_datazone_glossary" "enterprise_glossary" {
  domain_identifier = aws_datazone_domain.enterprise_governance.id
  name              = "Enterprise Business Glossary"
  description       = "Standardized business terms and definitions"
  status            = "ENABLED"

  depends_on = [aws_datazone_domain.enterprise_governance]
}

# Sample glossary terms for customer analytics
resource "aws_datazone_glossary_term" "customer_lifetime_value" {
  domain_identifier   = aws_datazone_domain.enterprise_governance.id
  glossary_identifier = aws_datazone_glossary.enterprise_glossary.id
  name                = "Customer Lifetime Value"
  short_description   = "The predicted revenue that a customer will generate during their relationship with the company"
  long_description    = "Customer Lifetime Value (CLV) is calculated using historical transaction data, customer behavior patterns, and predictive analytics to estimate the total economic value a customer represents over their entire relationship with the organization."

  depends_on = [aws_datazone_glossary.enterprise_glossary]
}

resource "aws_datazone_glossary_term" "customer_segment" {
  domain_identifier   = aws_datazone_domain.enterprise_governance.id
  glossary_identifier = aws_datazone_glossary.enterprise_glossary.id
  name                = "Customer Segment"
  short_description   = "Business classification of customers based on value, behavior, and characteristics"
  long_description    = "Customer segments include Premium (high-value customers), Standard (regular customers), and Basic (low-engagement customers). Segmentation drives personalized marketing and service strategies."

  depends_on = [aws_datazone_glossary.enterprise_glossary]
}

# DataZone project for analytics team collaboration
resource "aws_datazone_project" "customer_analytics" {
  domain_identifier = aws_datazone_domain.enterprise_governance.id
  name              = "Customer Analytics Project"
  description       = "Analytics project for customer behavior and transaction analysis"

  depends_on = [aws_datazone_domain.enterprise_governance]
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# CloudWatch log group for data quality monitoring
resource "aws_cloudwatch_log_group" "data_quality" {
  name              = "/aws/datazone/data-quality"
  retention_in_days = 30

  tags = {
    Name      = "Data Quality Monitoring"
    Purpose   = "Monitoring"
    ManagedBy = "Terraform"
  }
}

# SNS topic for data quality alerts
resource "aws_sns_topic" "data_quality_alerts" {
  name = "${var.resource_prefix}-data-quality-alerts"

  tags = {
    Name      = "Data Quality Alerts"
    Purpose   = "Alerting"
    ManagedBy = "Terraform"
  }
}

# CloudWatch alarm for ETL job failures
resource "aws_cloudwatch_metric_alarm" "etl_failures" {
  alarm_name          = "${var.resource_prefix}-etl-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.ALL.job.failure"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when ETL jobs fail"
  alarm_actions       = [aws_sns_topic.data_quality_alerts.arn]

  tags = {
    Name      = "ETL Failure Alarm"
    Purpose   = "Monitoring"
    ManagedBy = "Terraform"
  }
}

# =============================================================================
# DATA SOURCES FOR CURRENT AWS CONTEXT
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}