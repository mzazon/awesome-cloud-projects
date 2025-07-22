# Main Terraform configuration for Lake Formation Fine-Grained Access Control

# Get current caller identity for data lake administrator
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed configurations
locals {
  # Use provided data lake admin ARN or current caller identity
  data_lake_admin_arn = var.data_lake_admin_arn != "" ? var.data_lake_admin_arn : data.aws_caller_identity.current.arn
  
  # Bucket name with random suffix for uniqueness
  bucket_name = "${var.bucket_prefix}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = {
    Environment = var.environment
    Project     = "DataLakeFormationFGAC"
    ManagedBy   = "Terraform"
  }
}

# S3 bucket for data lake storage
resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name

  # Prevent accidental deletion of bucket with data
  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.common_tags, {
    Name        = "Data Lake Storage"
    Purpose     = "Lake Formation data storage with fine-grained access control"
    DataClass   = "Sensitive"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample data if enabled
resource "aws_s3_object" "sample_data" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.data_lake.bucket
  key    = "customer_data/sample_data.csv"
  
  content = <<-EOT
    customer_id,name,email,department,salary,ssn
    1,John Doe,john@example.com,Engineering,75000,123-45-6789
    2,Jane Smith,jane@example.com,Marketing,65000,987-65-4321
    3,Bob Johnson,bob@example.com,Finance,80000,456-78-9012
    4,Alice Brown,alice@example.com,Engineering,70000,321-54-9876
    5,Charlie Wilson,charlie@example.com,HR,60000,654-32-1098
  EOT
  
  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name        = "Sample Customer Data"
    DataType    = "CSV"
    Sensitivity = "High"
  })
}

# Register S3 location with Lake Formation
resource "aws_lakeformation_resource" "data_lake_bucket" {
  arn                   = aws_s3_bucket.data_lake.arn
  use_service_linked_role = true

  depends_on = [aws_lakeformation_data_lake_settings.settings]
}

# Configure Lake Formation data lake settings
resource "aws_lakeformation_data_lake_settings" "settings" {
  admins = [local.data_lake_admin_arn]
  
  # Disable default permissions to enable fine-grained access control
  create_database_default_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
  
  create_table_default_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
  
  # Enable cross-account data sharing (optional)
  external_data_filtering_allow_list = []
  
  # Configure default settings for database and table creation
  trusted_resource_owners = [data.aws_caller_identity.current.account_id]
}

# Glue database for data catalog
resource "aws_glue_catalog_database" "sample_database" {
  name        = var.database_name
  description = "Sample database for Lake Formation fine-grained access control demonstration"
  
  # Register database with Lake Formation
  create_table_default_permission {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }

  tags = merge(local.common_tags, {
    Name    = "Sample Database"
    Purpose = "Lake Formation FGAC demonstration"
  })
}

# Glue table for customer data
resource "aws_glue_catalog_table" "customer_data" {
  name          = var.table_name
  database_name = aws_glue_catalog_database.sample_database.name
  description   = "Customer data table with sensitive information for FGAC testing"
  
  table_type = "EXTERNAL_TABLE"
  
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.bucket}/customer_data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim"             = ","
        "skip.header.line.count" = "1"
      }
    }
    
    # Define table schema with different sensitivity levels
    columns {
      name = "customer_id"
      type = "bigint"
    }
    
    columns {
      name = "name"
      type = "string"
    }
    
    columns {
      name = "email"
      type = "string"
    }
    
    columns {
      name = "department"
      type = "string"
    }
    
    columns {
      name = "salary"
      type = "bigint"
    }
    
    columns {
      name = "ssn"
      type = "string"
    }
  }

  tags = merge(local.common_tags, {
    Name         = "Customer Data Table"
    DataType     = "CSV"
    Sensitivity  = "High"
    HasPII       = "true"
  })
}

# IAM trust policy for cross-service access
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Data Analyst Role - Full table access
resource "aws_iam_role" "data_analyst" {
  name               = var.data_analyst_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  description        = "Role for data analysts with full table access"

  tags = merge(local.common_tags, {
    Name        = "Data Analyst Role"
    AccessLevel = "Full"
    Department  = "Analytics"
  })
}

# Finance Team Role - Limited column access
resource "aws_iam_role" "finance_team" {
  name               = var.finance_team_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  description        = "Role for finance team with limited column access (no SSN)"

  tags = merge(local.common_tags, {
    Name        = "Finance Team Role"
    AccessLevel = "Restricted"
    Department  = "Finance"
  })
}

# HR Role - Very limited access
resource "aws_iam_role" "hr" {
  name               = var.hr_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  description        = "Role for HR with very limited access (name and department only)"

  tags = merge(local.common_tags, {
    Name        = "HR Role"
    AccessLevel = "Minimal"
    Department  = "HR"
  })
}

# Basic IAM policy for Lake Formation access
data "aws_iam_policy_document" "lake_formation_basic" {
  statement {
    effect = "Allow"
    actions = [
      "lakeformation:GetDataAccess",
      "lakeformation:GetWorkUnits",
      "lakeformation:StartQueryPlanning",
      "lakeformation:GetWorkUnitResults",
      "lakeformation:GetQueryState",
      "lakeformation:GetQueryStatistics"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]
  }
}

# Attach basic Lake Formation policy to all roles
resource "aws_iam_role_policy" "data_analyst_basic" {
  name   = "LakeFormationBasicAccess"
  role   = aws_iam_role.data_analyst.id
  policy = data.aws_iam_policy_document.lake_formation_basic.json
}

resource "aws_iam_role_policy" "finance_team_basic" {
  name   = "LakeFormationBasicAccess"
  role   = aws_iam_role.finance_team.id
  policy = data.aws_iam_policy_document.lake_formation_basic.json
}

resource "aws_iam_role_policy" "hr_basic" {
  name   = "LakeFormationBasicAccess"
  role   = aws_iam_role.hr.id
  policy = data.aws_iam_policy_document.lake_formation_basic.json
}

# Lake Formation Permissions - Data Analyst (Full table access)
resource "aws_lakeformation_permissions" "data_analyst_table" {
  principal   = aws_iam_role.data_analyst.arn
  permissions = ["SELECT"]
  
  table {
    database_name = aws_glue_catalog_database.sample_database.name
    name          = aws_glue_catalog_table.customer_data.name
  }
  
  depends_on = [aws_lakeformation_data_lake_settings.settings]
}

# Lake Formation Permissions - Finance Team (Column-level access, no SSN)
resource "aws_lakeformation_permissions" "finance_team_columns" {
  principal   = aws_iam_role.finance_team.arn
  permissions = ["SELECT"]
  
  table_with_columns {
    database_name = aws_glue_catalog_database.sample_database.name
    name          = aws_glue_catalog_table.customer_data.name
    column_names  = ["customer_id", "name", "department", "salary"]
  }
  
  depends_on = [aws_lakeformation_data_lake_settings.settings]
}

# Lake Formation Permissions - HR (Very limited column access)
resource "aws_lakeformation_permissions" "hr_columns" {
  principal   = aws_iam_role.hr.arn
  permissions = ["SELECT"]
  
  table_with_columns {
    database_name = aws_glue_catalog_database.sample_database.name
    name          = aws_glue_catalog_table.customer_data.name
    column_names  = ["customer_id", "name", "department"]
  }
  
  depends_on = [aws_lakeformation_data_lake_settings.settings]
}

# Data Cells Filter for row-level security (Finance team - Engineering only)
resource "aws_lakeformation_data_cells_filter" "engineering_only" {
  table_data {
    table_catalog_id = data.aws_caller_identity.current.account_id
    database_name    = aws_glue_catalog_database.sample_database.name
    table_name       = aws_glue_catalog_table.customer_data.name
    name             = "engineering-only-filter"
    
    row_filter {
      filter_expression = var.row_level_filter_expression
    }
    
    column_names = ["customer_id", "name", "department", "salary"]
  }
  
  depends_on = [
    aws_lakeformation_permissions.finance_team_columns,
    aws_glue_catalog_table.customer_data
  ]
}

# Athena workgroup for query testing
resource "aws_athena_workgroup" "query_workgroup" {
  name        = "lake-formation-fgac-workgroup"
  description = "Workgroup for testing Lake Formation fine-grained access controls"
  
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics         = true
    bytes_scanned_cutoff_per_query     = 1024 * 1024 * 1024 # 1GB
    
    result_configuration {
      output_location                = "s3://${aws_s3_bucket.data_lake.bucket}/query-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name    = "Lake Formation FGAC Workgroup"
    Purpose = "Query testing for fine-grained access controls"
  })
}

# CloudTrail for Lake Formation audit logging (optional)
resource "aws_cloudtrail" "lake_formation_audit" {
  count                        = var.enable_cloudtrail_logging ? 1 : 0
  name                        = "lake-formation-fgac-audit"
  s3_bucket_name              = aws_s3_bucket.cloudtrail_logs[0].bucket
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    data_resource {
      type   = "AWS::LakeFormation::Table"
      values = ["arn:aws:lakeformation:*:${data.aws_caller_identity.current.account_id}:table/*"]
    }
  }

  tags = merge(local.common_tags, {
    Name    = "Lake Formation Audit Trail"
    Purpose = "Audit logging for Lake Formation activities"
  })
}

# S3 bucket for CloudTrail logs (if enabled)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = "${local.bucket_name}-cloudtrail-logs"

  tags = merge(local.common_tags, {
    Name    = "CloudTrail Logs"
    Purpose = "Store CloudTrail audit logs"
  })
}

# CloudTrail S3 bucket policy (if enabled)
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}