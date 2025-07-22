# Main Terraform configuration for S3 Tables Analytics Infrastructure
# This file creates a complete analytics platform using S3 Tables with integrated
# AWS services including Athena, Glue, and QuickSight for business intelligence

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  unique_table_bucket_name = "${var.table_bucket_name}-${random_string.suffix.result}"
  athena_results_bucket    = "aws-athena-query-results-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  sample_data_bucket       = "glue-etl-data-${random_string.suffix.result}"
  
  common_tags = merge(var.tags, {
    Component = "S3TablesAnalytics"
    ManagedBy = "Terraform"
  })
}

# KMS key for S3 Tables encryption
resource "aws_kms_key" "s3_tables" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for S3 Tables encryption - ${var.project_name}"
  deletion_window_in_days = var.kms_key_deletion_window
  
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
        Sid    = "Allow S3 Tables service access"
        Effect = "Allow"
        Principal = {
          Service = "s3tables.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3tables-key"
  })
}

# KMS key alias for easier identification
resource "aws_kms_alias" "s3_tables" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${var.project_name}-s3tables"
  target_key_id = aws_kms_key.s3_tables[0].key_id
}

# S3 Table Bucket - Purpose-built storage for analytics workloads
resource "aws_s3tables_table_bucket" "analytics" {
  name   = local.unique_table_bucket_name
  region = var.aws_region
  
  # Encryption configuration for data security
  dynamic "encryption_configuration" {
    for_each = var.enable_encryption ? [1] : []
    
    content {
      sse_algorithm = "aws:kms"
      kms_key_arn   = aws_kms_key.s3_tables[0].arn
    }
  }
  
  # Maintenance configuration for automatic optimization
  dynamic "maintenance_configuration" {
    for_each = var.maintenance_enabled ? [1] : []
    
    content {
      iceberg_unreferenced_file_removal {
        status = "enabled"
        settings {
          unreferenced_days = var.unreferenced_file_removal_days
          non_current_days  = var.non_current_days
        }
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.unique_table_bucket_name
    Type = "AnalyticsStorage"
  })
}

# Table bucket policy for AWS analytics services integration
resource "aws_s3tables_table_bucket_policy" "analytics_integration" {
  table_bucket_arn = aws_s3tables_table_bucket.analytics.arn
  
  resource_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "glue.amazonaws.com",
            "athena.amazonaws.com"
          ]
        }
        Action = [
          "s3tables:GetTable",
          "s3tables:GetTableMetadataLocation",
          "s3tables:ListTables"
        ]
        Resource = [
          aws_s3tables_table_bucket.analytics.arn,
          "${aws_s3tables_table_bucket.analytics.arn}/*"
        ]
      }
    ]
  })
}

# Namespace for logical organization of related tables
resource "aws_s3tables_namespace" "sales_analytics" {
  namespace        = var.namespace_name
  table_bucket_arn = aws_s3tables_table_bucket.analytics.arn
  
  depends_on = [aws_s3tables_table_bucket.analytics]
}

# Apache Iceberg table with optimized schema for analytics
resource "aws_s3tables_table" "transaction_data" {
  name             = var.table_name
  namespace        = aws_s3tables_namespace.sales_analytics.namespace
  table_bucket_arn = aws_s3tables_table_bucket.analytics.arn
  format           = "ICEBERG"
  
  # Table schema definition for transaction analytics
  metadata {
    iceberg {
      schema {
        field {
          name     = "transaction_id"
          type     = "long"
          required = true
        }
        field {
          name     = "customer_id"
          type     = "long"
          required = true
        }
        field {
          name     = "product_id"
          type     = "long"
          required = true
        }
        field {
          name     = "quantity"
          type     = "int"
          required = true
        }
        field {
          name     = "price"
          type     = "decimal(10,2)"
          required = true
        }
        field {
          name     = "transaction_date"
          type     = "date"
          required = true
        }
        field {
          name     = "region"
          type     = "string"
          required = true
        }
        field {
          name     = "created_at"
          type     = "timestamp"
          required = false
        }
      }
    }
  }
  
  # Encryption configuration
  dynamic "encryption_configuration" {
    for_each = var.enable_encryption ? [1] : []
    
    content {
      sse_algorithm = "aws:kms"
      kms_key_arn   = aws_kms_key.s3_tables[0].arn
    }
  }
  
  # Maintenance configuration for table optimization
  dynamic "maintenance_configuration" {
    for_each = var.maintenance_enabled ? [1] : []
    
    content {
      iceberg_compaction {
        status = "enabled"
        settings {
          target_file_size_mb = var.compaction_target_file_size_mb
        }
      }
      
      iceberg_snapshot_management {
        status = "enabled"
        settings {
          max_snapshot_age_hours = var.max_snapshot_age_hours
          min_snapshots_to_keep  = var.min_snapshots_to_keep
        }
      }
    }
  }
  
  depends_on = [aws_s3tables_namespace.sales_analytics]
}

# AWS Glue Database for metadata catalog integration
resource "aws_glue_catalog_database" "s3_tables_analytics" {
  name        = var.glue_database_name
  description = "Database for S3 Tables analytics workloads"
  
  parameters = {
    "classification" = "iceberg"
    "table_type"     = "EXTERNAL_TABLE"
  }
  
  tags = merge(local.common_tags, {
    Name = var.glue_database_name
    Type = "MetadataCatalog"
  })
}

# IAM role for Glue ETL jobs
resource "aws_iam_role" "glue_etl" {
  name = "${var.project_name}-glue-etl-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-glue-etl-role"
    Type = "ServiceRole"
  })
}

# IAM policy for Glue ETL to access S3 Tables
resource "aws_iam_role_policy" "glue_s3_tables_access" {
  name = "${var.project_name}-glue-s3tables-policy"
  role = aws_iam_role.glue_etl.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3tables:GetTable",
          "s3tables:GetTableMetadataLocation",
          "s3tables:ListTables",
          "s3tables:PutTableData",
          "s3tables:GetTableData"
        ]
        Resource = [
          aws_s3tables_table_bucket.analytics.arn,
          "${aws_s3tables_table_bucket.analytics.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:CreateTable",
          "glue:UpdateTable"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*"
        ]
      }
    ]
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_etl.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# S3 bucket for sample data and ETL processing
resource "aws_s3_bucket" "sample_data" {
  count = var.create_sample_data_bucket ? 1 : 0
  
  bucket        = local.sample_data_bucket
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name = local.sample_data_bucket
    Type = "SampleData"
  })
}

# S3 bucket versioning for sample data
resource "aws_s3_bucket_versioning" "sample_data" {
  count = var.create_sample_data_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.sample_data[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for sample data
resource "aws_s3_bucket_server_side_encryption_configuration" "sample_data" {
  count = var.create_sample_data_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.sample_data[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Athena workgroup for S3 Tables querying
resource "aws_athena_workgroup" "s3_tables" {
  name          = "${var.project_name}-s3tables-workgroup"
  description   = "Athena workgroup for S3 Tables analytics"
  force_destroy = true
  
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3tables-workgroup"
    Type = "Analytics"
  })
}

# S3 bucket for Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket        = local.athena_results_bucket
  force_destroy = var.athena_query_result_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name = local.athena_results_bucket
    Type = "QueryResults"
  })
}

# S3 bucket encryption for Athena results
resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket lifecycle configuration for Athena results
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  
  rule {
    id     = "athena_results_cleanup"
    status = "Enabled"
    
    expiration {
      days = 30
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# CloudWatch Log Group for monitoring
resource "aws_cloudwatch_log_group" "s3_tables_analytics" {
  name              = "/aws/s3tables/${var.project_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3tables-logs"
    Type = "Monitoring"
  })
}

# IAM role for Athena to access S3 Tables
resource "aws_iam_role" "athena_s3_tables" {
  name = "${var.project_name}-athena-s3tables-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "athena.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-athena-s3tables-role"
    Type = "ServiceRole"
  })
}

# IAM policy for Athena S3 Tables access
resource "aws_iam_role_policy" "athena_s3_tables_access" {
  name = "${var.project_name}-athena-s3tables-policy"
  role = aws_iam_role.athena_s3_tables.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3tables:GetTable",
          "s3tables:GetTableMetadataLocation",
          "s3tables:ListTables",
          "s3tables:GetTableData"
        ]
        Resource = [
          aws_s3tables_table_bucket.analytics.arn,
          "${aws_s3tables_table_bucket.analytics.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*"
        ]
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
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*"
        ]
      }
    ]
  })
}

# Sample data file creation for testing
resource "aws_s3_object" "sample_transactions" {
  count = var.create_sample_data_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.sample_data[0].id
  key    = "input/sample_transactions.csv"
  
  content = <<-EOF
transaction_id,customer_id,product_id,quantity,price,transaction_date,region
1,101,501,2,29.99,2024-01-15,us-east-1
2,102,502,1,149.99,2024-01-15,us-west-2
3,103,503,3,19.99,2024-01-16,eu-west-1
4,104,501,1,29.99,2024-01-16,us-east-1
5,105,504,2,79.99,2024-01-17,ap-southeast-1
6,106,505,1,199.99,2024-01-18,us-east-1
7,107,506,4,12.50,2024-01-18,eu-central-1
8,108,507,2,89.99,2024-01-19,ap-northeast-1
9,109,508,1,299.99,2024-01-19,us-west-1
10,110,509,3,45.00,2024-01-20,eu-west-2
EOF
  
  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name = "sample-transactions-data"
    Type = "SampleData"
  })
}