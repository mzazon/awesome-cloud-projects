# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming
locals {
  prefix = var.resource_prefix != "" ? var.resource_prefix : "clean-rooms-analytics"
  suffix = random_id.suffix.hex
  
  # Resource names
  collaboration_name     = var.collaboration_name != "" ? var.collaboration_name : "${local.prefix}-${local.suffix}"
  org_a_bucket_name     = var.org_a_data_bucket_name != "" ? var.org_a_data_bucket_name : "clean-rooms-data-a-${local.suffix}"
  org_b_bucket_name     = var.org_b_data_bucket_name != "" ? var.org_b_data_bucket_name : "clean-rooms-data-b-${local.suffix}"
  results_bucket_name   = var.results_bucket_name != "" ? var.results_bucket_name : "clean-rooms-results-${local.suffix}"
  glue_database_name    = var.glue_database_name != "" ? var.glue_database_name : replace("clean_rooms_analytics_${local.suffix}", "-", "_")
  clean_rooms_role_name = var.clean_rooms_role_name != "" ? var.clean_rooms_role_name : "CleanRoomsAnalyticsRole-${local.suffix}"
  glue_role_name       = var.glue_role_name != "" ? var.glue_role_name : "GlueCleanRoomsRole-${local.suffix}"
  
  common_tags = merge(
    {
      Name        = local.collaboration_name
      Project     = "Privacy-Preserving Analytics"
      Environment = var.environment
    },
    var.additional_tags
  )
}

# ==========================================
# S3 Buckets for Data Storage
# ==========================================

# S3 bucket for Organization A data
resource "aws_s3_bucket" "org_a_data" {
  bucket = local.org_a_bucket_name

  tags = merge(local.common_tags, {
    Purpose      = "Organization A Data Storage"
    Organization = "Org-A"
  })
}

# S3 bucket for Organization B data
resource "aws_s3_bucket" "org_b_data" {
  bucket = local.org_b_bucket_name

  tags = merge(local.common_tags, {
    Purpose      = "Organization B Data Storage"
    Organization = "Org-B"
  })
}

# S3 bucket for Clean Rooms query results
resource "aws_s3_bucket" "results" {
  bucket = local.results_bucket_name

  tags = merge(local.common_tags, {
    Purpose = "Clean Rooms Query Results"
  })
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "org_a_encryption" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.org_a_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "org_b_encryption" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.org_b_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results_encryption" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "org_a_versioning" {
  count  = var.enable_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.org_a_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "org_b_versioning" {
  count  = var.enable_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.org_b_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "results_versioning" {
  count  = var.enable_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.results.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "org_a_pab" {
  count  = var.enable_bucket_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.org_a_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "org_b_pab" {
  count  = var.enable_bucket_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.org_b_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "results_pab" {
  count  = var.enable_bucket_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# Sample Data Upload (Optional)
# ==========================================

# Convert sample data to CSV format for Organization A
locals {
  org_a_csv_header = "customer_id,age_group,region,purchase_amount,product_category,registration_date"
  org_a_csv_rows = [
    for item in var.sample_data_org_a :
    "${item.customer_id},${item.age_group},${item.region},${item.purchase_amount},${item.product_category},${item.registration_date}"
  ]
  org_a_csv_content = "${local.org_a_csv_header}\n${join("\n", local.org_a_csv_rows)}"
}

# Convert sample data to CSV format for Organization B
locals {
  org_b_csv_header = "customer_id,age_group,region,engagement_score,channel_preference,last_interaction"
  org_b_csv_rows = [
    for item in var.sample_data_org_b :
    "${item.customer_id},${item.age_group},${item.region},${item.engagement_score},${item.channel_preference},${item.last_interaction}"
  ]
  org_b_csv_content = "${local.org_b_csv_header}\n${join("\n", local.org_b_csv_rows)}"
}

# Upload sample data for Organization A
resource "aws_s3_object" "org_a_sample_data" {
  count = var.create_sample_data ? 1 : 0
  
  bucket = aws_s3_bucket.org_a_data.id
  key    = "data/customer_data_org_a.csv"
  content = local.org_a_csv_content
  content_type = "text/csv"

  tags = merge(local.common_tags, {
    DataType = "Sample Customer Data"
    Organization = "Org-A"
  })
}

# Upload sample data for Organization B
resource "aws_s3_object" "org_b_sample_data" {
  count = var.create_sample_data ? 1 : 0
  
  bucket = aws_s3_bucket.org_b_data.id
  key    = "data/customer_data_org_b.csv"
  content = local.org_b_csv_content
  content_type = "text/csv"

  tags = merge(local.common_tags, {
    DataType = "Sample Customer Data"
    Organization = "Org-B"
  })
}

# ==========================================
# IAM Roles and Policies
# ==========================================

# Clean Rooms service role trust policy
data "aws_iam_policy_document" "clean_rooms_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cleanrooms.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Clean Rooms IAM role
resource "aws_iam_role" "clean_rooms_role" {
  name               = local.clean_rooms_role_name
  assume_role_policy = data.aws_iam_policy_document.clean_rooms_trust_policy.json

  tags = merge(local.common_tags, {
    Purpose = "Clean Rooms Service Role"
  })
}

# Clean Rooms S3 access policy
data "aws_iam_policy_document" "clean_rooms_s3_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"
    ]
    
    resources = [
      aws_s3_bucket.org_a_data.arn,
      "${aws_s3_bucket.org_a_data.arn}/*",
      aws_s3_bucket.org_b_data.arn,
      "${aws_s3_bucket.org_b_data.arn}/*",
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetDatabase",
      "glue:GetDatabases"
    ]
    
    resources = ["*"]
  }
}

# Create custom policy for Clean Rooms S3 access
resource "aws_iam_policy" "clean_rooms_s3_access" {
  name        = "CleanRoomsS3Access-${local.suffix}"
  description = "Policy for Clean Rooms to access S3 buckets and Glue catalog"
  policy      = data.aws_iam_policy_document.clean_rooms_s3_policy.json

  tags = local.common_tags
}

# Attach AWS managed policy to Clean Rooms role
resource "aws_iam_role_policy_attachment" "clean_rooms_service_policy" {
  role       = aws_iam_role.clean_rooms_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCleanRoomsService"
}

# Attach custom S3 policy to Clean Rooms role
resource "aws_iam_role_policy_attachment" "clean_rooms_s3_policy" {
  role       = aws_iam_role.clean_rooms_role.name
  policy_arn = aws_iam_policy.clean_rooms_s3_access.arn
}

# Glue service role trust policy
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

# Glue IAM role
resource "aws_iam_role" "glue_role" {
  name               = local.glue_role_name
  assume_role_policy = data.aws_iam_policy_document.glue_trust_policy.json

  tags = merge(local.common_tags, {
    Purpose = "Glue Service Role"
  })
}

# Attach AWS managed policy to Glue role
resource "aws_iam_role_policy_attachment" "glue_service_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Attach custom S3 policy to Glue role
resource "aws_iam_role_policy_attachment" "glue_s3_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.clean_rooms_s3_access.arn
}

# ==========================================
# AWS Glue Data Catalog
# ==========================================

# Glue database for Clean Rooms analytics
resource "aws_glue_catalog_database" "clean_rooms_database" {
  name        = local.glue_database_name
  description = "Clean Rooms analytics database for privacy-preserving collaboration"

  tags = merge(local.common_tags, {
    Purpose = "Data Catalog for Clean Rooms"
  })
}

# Glue crawler for Organization A data
resource "aws_glue_crawler" "org_a_crawler" {
  database_name = aws_glue_catalog_database.clean_rooms_database.name
  name          = "crawler-org-a-${local.suffix}"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler for Organization A customer data"

  s3_target {
    path = "s3://${aws_s3_bucket.org_a_data.id}/data/"
  }

  tags = merge(local.common_tags, {
    Purpose      = "Data Discovery"
    Organization = "Org-A"
  })

  depends_on = [
    aws_s3_object.org_a_sample_data
  ]
}

# Glue crawler for Organization B data
resource "aws_glue_crawler" "org_b_crawler" {
  database_name = aws_glue_catalog_database.clean_rooms_database.name
  name          = "crawler-org-b-${local.suffix}"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler for Organization B customer data"

  s3_target {
    path = "s3://${aws_s3_bucket.org_b_data.id}/data/"
  }

  tags = merge(local.common_tags, {
    Purpose      = "Data Discovery"
    Organization = "Org-B"
  })

  depends_on = [
    aws_s3_object.org_b_sample_data
  ]
}

# ==========================================
# QuickSight Configuration (Optional)
# ==========================================

# QuickSight account subscription (if enabled)
resource "aws_quicksight_account_subscription" "subscription" {
  count = var.enable_quicksight ? 1 : 0
  
  account_name                 = var.quicksight_account_name
  authentication_method        = "IAM_IDENTITY_CENTER"
  edition                     = var.quicksight_edition
  notification_email          = var.quicksight_notification_email
  
  tags = merge(local.common_tags, {
    Purpose = "QuickSight Analytics Platform"
  })
}

# QuickSight user registration
resource "aws_quicksight_user" "admin_user" {
  count = var.enable_quicksight ? 1 : 0
  
  aws_account_id = data.aws_caller_identity.current.account_id
  namespace      = "default"
  identity_type  = "IAM"
  user_role      = "ADMIN"
  iam_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"

  depends_on = [aws_quicksight_account_subscription.subscription]
}

# QuickSight data source for Clean Rooms results
resource "aws_quicksight_data_source" "clean_rooms_results" {
  count = var.enable_quicksight ? 1 : 0
  
  aws_account_id = data.aws_caller_identity.current.account_id
  data_source_id = "clean-rooms-results-${local.suffix}"
  name           = "Clean Rooms Analytics Results"
  type           = "S3"

  parameters {
    s3 {
      manifest_file_location {
        bucket = aws_s3_bucket.results.id
        key    = "query-results/"
      }
    }
  }

  permission {
    principal = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions"
    ]
  }

  tags = merge(local.common_tags, {
    Purpose = "QuickSight Data Source"
  })

  depends_on = [aws_quicksight_user.admin_user]
}

# ==========================================
# CloudWatch Log Group for Clean Rooms
# ==========================================

# CloudWatch log group for Clean Rooms query logs
resource "aws_cloudwatch_log_group" "clean_rooms_logs" {
  name              = "/aws/cleanrooms/${local.collaboration_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Purpose = "Clean Rooms Query Logging"
  })
}

# ==========================================
# Outputs for Resource References
# ==========================================

# Output key resource identifiers for use in scripts or other configurations
output "collaboration_setup_info" {
  description = "Information needed to complete Clean Rooms collaboration setup"
  value = {
    glue_database_name    = aws_glue_catalog_database.clean_rooms_database.name
    clean_rooms_role_arn  = aws_iam_role.clean_rooms_role.arn
    org_a_crawler_name    = aws_glue_crawler.org_a_crawler.name
    org_b_crawler_name    = aws_glue_crawler.org_b_crawler.name
    collaboration_name    = local.collaboration_name
    results_bucket_name   = aws_s3_bucket.results.id
    account_id           = data.aws_caller_identity.current.account_id
    region              = data.aws_region.current.name
  }
  sensitive = false
}