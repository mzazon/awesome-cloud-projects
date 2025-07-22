# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
  name_prefix   = "${var.project_name}-${var.environment}"
  bucket_prefix = "${var.data_lake_name}-${random_string.suffix.result}"
  
  # S3 bucket names
  raw_bucket_name       = "${local.bucket_prefix}-raw"
  processed_bucket_name = "${local.bucket_prefix}-processed"
  curated_bucket_name   = "${local.bucket_prefix}-curated"
  
  # Database name with suffix
  database_name = "${replace(var.database_name, "-", "_")}_${random_string.suffix.result}"
  
  # Common tags
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "data-lake-architectures-s3-lake-formation"
  }
}

# ============================================================================
# S3 BUCKETS FOR DATA LAKE ZONES
# ============================================================================

# Raw Data Zone S3 Bucket
resource "aws_s3_bucket" "raw_data" {
  bucket = local.raw_bucket_name
  
  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-raw-data"
    DataZone = "Raw"
  })
}

# Processed Data Zone S3 Bucket
resource "aws_s3_bucket" "processed_data" {
  bucket = local.processed_bucket_name
  
  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-processed-data"
    DataZone = "Processed"
  })
}

# Curated Data Zone S3 Bucket
resource "aws_s3_bucket" "curated_data" {
  bucket = local.curated_bucket_name
  
  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-curated-data"
    DataZone = "Curated"
  })
}

# S3 Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "raw_data" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "processed_data" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "curated_data" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.curated_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption Configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_encryption_algorithm
      kms_master_key_id = var.s3_encryption_algorithm == "aws:kms" ? var.s3_kms_key_id : null
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_encryption_algorithm
      kms_master_key_id = var.s3_encryption_algorithm == "aws:kms" ? var.s3_kms_key_id : null
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "curated_data" {
  bucket = aws_s3_bucket.curated_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_encryption_algorithm
      kms_master_key_id = var.s3_encryption_algorithm == "aws:kms" ? var.s3_kms_key_id : null
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "curated_data" {
  bucket = aws_s3_bucket.curated_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# SAMPLE DATA UPLOAD
# ============================================================================

# Upload sample data files to raw bucket
resource "aws_s3_object" "sample_data" {
  for_each = var.upload_sample_data ? var.sample_data_files : {}
  
  bucket  = aws_s3_bucket.raw_data.id
  key     = each.value.key
  content = each.value.content
  
  tags = merge(local.common_tags, {
    Name = "sample-data-${each.key}"
  })
}

# ============================================================================
# LAKE FORMATION SERVICE ROLE
# ============================================================================

# Lake Formation Service Role
resource "aws_iam_role" "lake_formation_service" {
  name = "${local.name_prefix}-lake-formation-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lakeformation.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lake-formation-service-role"
  })
}

# Attach Lake Formation service role policy
resource "aws_iam_role_policy_attachment" "lake_formation_service" {
  role       = aws_iam_role.lake_formation_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/LakeFormationServiceRole"
}

# ============================================================================
# IAM USERS AND ROLES
# ============================================================================

# Create IAM users for data lake access
resource "aws_iam_user" "data_lake_users" {
  for_each = var.create_iam_users ? var.iam_users : {}
  
  name = "${local.name_prefix}-${each.value.name}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.value.name}"
    Role = each.value.role_name
  })
}

# Create IAM roles for data lake access
resource "aws_iam_role" "data_lake_roles" {
  for_each = var.create_iam_users ? var.iam_users : {}
  
  name = "${local.name_prefix}-${each.value.role_name}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.data_lake_users[each.key].arn
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.value.role_name}"
  })
}

# Attach policies to IAM roles
resource "aws_iam_role_policy_attachment" "data_lake_role_policies" {
  for_each = {
    for combo in flatten([
      for user_key, user_config in var.iam_users : [
        for policy in user_config.policies : {
          user_key   = user_key
          policy_arn = policy
        }
      ]
    ]) : "${combo.user_key}-${combo.policy_arn}" => combo
    if var.create_iam_users
  }
  
  role       = aws_iam_role.data_lake_roles[each.value.user_key].name
  policy_arn = each.value.policy_arn
}

# ============================================================================
# GLUE CRAWLER ROLE AND POLICY
# ============================================================================

# Glue Crawler Service Role
resource "aws_iam_role" "glue_crawler" {
  name = "${local.name_prefix}-glue-crawler-role"
  
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
    Name = "${local.name_prefix}-glue-crawler-role"
  })
}

# Attach Glue service role policy
resource "aws_iam_role_policy_attachment" "glue_crawler_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom S3 access policy for Glue crawler
resource "aws_iam_policy" "glue_s3_access" {
  name        = "${local.name_prefix}-glue-s3-access"
  description = "S3 access policy for Glue crawler"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.curated_data.arn,
          "${aws_s3_bucket.curated_data.arn}/*"
        ]
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-s3-access"
  })
}

# Attach S3 access policy to Glue crawler role
resource "aws_iam_role_policy_attachment" "glue_s3_access" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = aws_iam_policy.glue_s3_access.arn
}

# ============================================================================
# GLUE DATABASE
# ============================================================================

# Glue Database for Data Catalog
resource "aws_glue_catalog_database" "data_lake" {
  name        = local.database_name
  description = "Data lake database for ${var.project_name} analytics"
  
  catalog_id = local.account_id
}

# ============================================================================
# GLUE CRAWLERS
# ============================================================================

# Sales Data Crawler
resource "aws_glue_crawler" "sales_crawler" {
  count = var.enable_glue_crawlers ? 1 : 0
  
  database_name = aws_glue_catalog_database.data_lake.name
  name          = "${local.name_prefix}-sales-crawler"
  role          = aws_iam_role.glue_crawler.arn
  
  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.id}/sales/"
  }
  
  table_prefix = "sales_"
  
  schedule = var.crawler_schedule
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sales-crawler"
  })
}

# Customer Data Crawler
resource "aws_glue_crawler" "customer_crawler" {
  count = var.enable_glue_crawlers ? 1 : 0
  
  database_name = aws_glue_catalog_database.data_lake.name
  name          = "${local.name_prefix}-customer-crawler"
  role          = aws_iam_role.glue_crawler.arn
  
  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.id}/customers/"
  }
  
  table_prefix = "customer_"
  
  schedule = var.crawler_schedule
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-customer-crawler"
  })
}

# ============================================================================
# LAKE FORMATION CONFIGURATION
# ============================================================================

# Get current user/role for Lake Formation admin
data "aws_caller_identity" "current_user" {}

# Lake Formation Data Lake Settings
resource "aws_lakeformation_data_lake_settings" "main" {
  # Determine admins from variable or use current caller
  admins = length(var.lake_formation_admins) > 0 ? var.lake_formation_admins : [
    data.aws_caller_identity.current_user.arn
  ]
  
  # Remove default permissions for create database and table
  create_database_default_permissions = []
  create_table_default_permissions    = []
  
  # Set trusted resource owners (defaults to current account)
  trusted_resource_owners = length(var.trusted_resource_owners) > 0 ? var.trusted_resource_owners : [
    local.account_id
  ]
  
  # Enable external data filtering
  allow_external_data_filtering = var.enable_external_data_filtering
  
  external_data_filtering_allow_list = var.enable_external_data_filtering ? [
    local.account_id
  ] : []
}

# ============================================================================
# LAKE FORMATION RESOURCE REGISTRATION
# ============================================================================

# Register S3 buckets with Lake Formation
resource "aws_lakeformation_resource" "raw_data" {
  arn                   = aws_s3_bucket.raw_data.arn
  use_service_linked_role = true
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_resource" "processed_data" {
  arn                   = aws_s3_bucket.processed_data.arn
  use_service_linked_role = true
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_resource" "curated_data" {
  arn                   = aws_s3_bucket.curated_data.arn
  use_service_linked_role = true
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# ============================================================================
# LAKE FORMATION TAGS (LF-TAGS)
# ============================================================================

# Create LF-Tags for governance
resource "aws_lakeformation_lf_tag" "governance_tags" {
  for_each = var.lf_tags
  
  key    = each.value.tag_key
  values = each.value.tag_values
}

# Apply LF-Tags to the database
resource "aws_lakeformation_resource_lf_tags" "database_tags" {
  database {
    name = aws_glue_catalog_database.data_lake.name
  }
  
  lf_tag {
    key   = aws_lakeformation_lf_tag.governance_tags["department"].key
    value = "Sales"
  }
  
  lf_tag {
    key   = aws_lakeformation_lf_tag.governance_tags["classification"].key
    value = "Internal"
  }
  
  lf_tag {
    key   = aws_lakeformation_lf_tag.governance_tags["data_zone"].key
    value = "Raw"
  }
  
  depends_on = [aws_lakeformation_lf_tag.governance_tags]
}

# ============================================================================
# LAKE FORMATION PERMISSIONS
# ============================================================================

# Grant database permissions to data analyst role
resource "aws_lakeformation_permissions" "data_analyst_database" {
  count = var.create_iam_users ? 1 : 0
  
  principal   = aws_iam_role.data_lake_roles["data_analyst"].arn
  permissions = ["DESCRIBE"]
  
  database {
    name = aws_glue_catalog_database.data_lake.name
  }
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# Grant table permissions to data analyst role
resource "aws_lakeformation_permissions" "data_analyst_table" {
  count = var.create_iam_users ? 1 : 0
  
  principal   = aws_iam_role.data_lake_roles["data_analyst"].arn
  permissions = ["SELECT", "DESCRIBE"]
  
  table {
    database_name = aws_glue_catalog_database.data_lake.name
    wildcard      = true
  }
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# Grant broader permissions to data engineer role
resource "aws_lakeformation_permissions" "data_engineer_database" {
  count = var.create_iam_users ? 1 : 0
  
  principal   = aws_iam_role.data_lake_roles["data_engineer"].arn
  permissions = ["CREATE_TABLE", "ALTER", "DROP", "DESCRIBE"]
  
  database {
    name = aws_glue_catalog_database.data_lake.name
  }
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# Tag-based permissions for data analyst
resource "aws_lakeformation_permissions" "data_analyst_tag_department" {
  count = var.create_iam_users ? 1 : 0
  
  principal   = aws_iam_role.data_lake_roles["data_analyst"].arn
  permissions = ["DESCRIBE"]
  
  lf_tag {
    key    = aws_lakeformation_lf_tag.governance_tags["department"].key
    values = ["Sales"]
  }
  
  depends_on = [aws_lakeformation_lf_tag.governance_tags]
}

resource "aws_lakeformation_permissions" "data_analyst_tag_classification" {
  count = var.create_iam_users ? 1 : 0
  
  principal   = aws_iam_role.data_lake_roles["data_analyst"].arn
  permissions = ["SELECT", "DESCRIBE"]
  
  lf_tag {
    key    = aws_lakeformation_lf_tag.governance_tags["classification"].key
    values = ["Internal"]
  }
  
  depends_on = [aws_lakeformation_lf_tag.governance_tags]
}

# ============================================================================
# LAKE FORMATION DATA CELL FILTERS
# ============================================================================

# Create data cell filters for fine-grained access control
resource "aws_lakeformation_data_cells_filter" "filters" {
  for_each = var.enable_data_cell_filters ? var.data_cell_filters : {}
  
  table_data {
    database_name = aws_glue_catalog_database.data_lake.name
    name          = each.value.name
    table_name    = each.value.table_name
    
    # Use column_names or column_wildcard based on configuration
    dynamic "column_names" {
      for_each = length(each.value.column_names) > 0 ? [each.value.column_names] : []
      content {
        column_names = column_names.value
      }
    }
    
    dynamic "column_wildcard" {
      for_each = length(each.value.excluded_columns) > 0 ? [each.value.excluded_columns] : []
      content {
        excluded_column_names = column_wildcard.value
      }
    }
    
    # Row filter configuration
    dynamic "row_filter" {
      for_each = each.value.row_filter != "" ? [each.value.row_filter] : []
      content {
        filter_expression = row_filter.value
      }
    }
    
    dynamic "row_filter" {
      for_each = each.value.row_filter == "" ? ["all"] : []
      content {
        all_rows_wildcard {}
      }
    }
  }
  
  depends_on = [
    aws_glue_crawler.sales_crawler,
    aws_glue_crawler.customer_crawler
  ]
}

# ============================================================================
# CLOUDTRAIL AND CLOUDWATCH LOGGING
# ============================================================================

# CloudWatch Log Group for Lake Formation audit logs
resource "aws_cloudwatch_log_group" "lake_formation_audit" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name              = var.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lake-formation-audit-logs"
  })
}

# CloudTrail for Lake Formation auditing
resource "aws_cloudtrail" "lake_formation_audit" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name           = "${local.name_prefix}-${var.cloudtrail_name}"
  s3_bucket_name = aws_s3_bucket.raw_data.id
  s3_key_prefix  = "audit-logs/"
  
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    data_resource {
      type   = "AWS::LakeFormation::Table"
      values = ["arn:aws:lakeformation:*:${local.account_id}:table/*"]
    }
    
    data_resource {
      type   = "AWS::S3::Object"
      values = [
        "${aws_s3_bucket.raw_data.arn}/*",
        "${aws_s3_bucket.processed_data.arn}/*",
        "${aws_s3_bucket.curated_data.arn}/*"
      ]
    }
  }
  
  depends_on = [aws_s3_bucket_policy.cloudtrail_logging]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.cloudtrail_name}"
  })
}

# S3 bucket policy for CloudTrail logging
resource "aws_s3_bucket_policy" "cloudtrail_logging" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.raw_data.id
  
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
        Resource = aws_s3_bucket.raw_data.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.raw_data.arn}/audit-logs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}