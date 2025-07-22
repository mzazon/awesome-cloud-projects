# Main Terraform configuration for Lake Formation cross-account data access

# Get current AWS account ID and region for resource configuration
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region = data.aws_region.current.name
  unique_suffix = random_id.suffix.hex
  bucket_name = "${var.data_lake_bucket_name}-${local.account_id}-${local.unique_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project = var.project_name
    ManagedBy = "terraform"
    Recipe = "cross-account-data-access-lake-formation"
  })
}

#######################
# S3 Data Lake Bucket
#######################

# S3 bucket for the data lake with unique naming
resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = "Data Lake Bucket"
    Purpose = "Primary data storage for Lake Formation"
  })
}

# S3 bucket versioning for data governance
resource "aws_s3_bucket_versioning" "data_lake" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.data_lake.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
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

# Upload sample data files for demonstration
resource "aws_s3_object" "financial_sample_data" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "financial-reports/2024-q1.csv"
  content = <<EOF
department,revenue,expenses,profit,quarter
finance,1000000,800000,200000,Q1
marketing,500000,450000,50000,Q1
engineering,750000,700000,50000,Q1
EOF

  tags = merge(local.common_tags, {
    DataType = "financial"
    Quarter = "Q1-2024"
  })
}

resource "aws_s3_object" "customer_sample_data" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "customer-data/customers.csv"
  content = <<EOF
customer_id,name,department,region
1001,Acme Corp,finance,us-east
1002,TechStart Inc,engineering,us-west
1003,Marketing Pro,marketing,eu-west
EOF

  tags = merge(local.common_tags, {
    DataType = "customer"
    Region = "global"
  })
}

#######################
# Lake Formation Setup
#######################

# Register S3 location with Lake Formation for governance
resource "aws_lakeformation_resource" "data_lake" {
  arn = aws_s3_bucket.data_lake.arn

  depends_on = [aws_s3_bucket.data_lake]
}

# Configure Lake Formation data lake settings
resource "aws_lakeformation_data_lake_settings" "main" {
  admins = [local.account_id]

  # Use Lake Formation permissions model instead of IAM-only
  create_database_default_permissions {
    permissions = ["ALL"]
    principal   = local.account_id
  }

  create_table_default_permissions {
    permissions = ["ALL"]
    principal   = local.account_id
  }

  depends_on = [aws_lakeformation_resource.data_lake]
}

# Create LF-Tags for tag-based access control
resource "aws_lakeformation_lf_tag" "department" {
  key    = "department"
  values = var.lf_tag_values.department

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_lf_tag" "classification" {
  key    = "classification"
  values = var.lf_tag_values.classification

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_lf_tag" "data_category" {
  key    = "data-category"
  values = var.lf_tag_values.data_category

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

#######################
# IAM Roles for Glue
#######################

# IAM role for Glue service operations
resource "aws_iam_role" "glue_service_role" {
  name = "${var.project_name}-glue-service-role-${local.unique_suffix}"

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
    Name = "Glue Service Role"
    Purpose = "Service role for AWS Glue operations"
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_policy" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3 data lake access
resource "aws_iam_role_policy" "glue_s3_access" {
  name = "${var.project_name}-glue-s3-access"
  role = aws_iam_role.glue_service_role.id

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
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      }
    ]
  })
}

#######################
# Glue Data Catalog
#######################

# Create Glue databases based on configuration
resource "aws_glue_catalog_database" "databases" {
  for_each = var.database_configurations

  name        = each.key
  description = each.value.description

  depends_on = [aws_lakeformation_data_lake_settings.main]

  tags = merge(local.common_tags, {
    Name = each.key
    Purpose = each.value.description
  })
}

# Assign LF-Tags to databases
resource "aws_lakeformation_resource_lf_tags" "database_tags" {
  for_each = var.database_configurations

  database {
    name = aws_glue_catalog_database.databases[each.key].name
  }

  dynamic "lf_tag" {
    for_each = each.value.lf_tags
    content {
      key    = lf_tag.key
      values = lf_tag.value
    }
  }

  depends_on = [
    aws_lakeformation_lf_tag.department,
    aws_lakeformation_lf_tag.classification,
    aws_lakeformation_lf_tag.data_category,
    aws_glue_catalog_database.databases
  ]
}

# Create Glue crawlers for schema discovery
resource "aws_glue_crawler" "crawlers" {
  for_each = var.glue_crawler_configurations

  database_name = each.value.database_name
  name          = each.key
  role          = aws_iam_role.glue_service_role.arn
  description   = each.value.description
  schedule      = each.value.schedule

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/${each.value.s3_path}"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  depends_on = [
    aws_glue_catalog_database.databases,
    aws_s3_object.financial_sample_data,
    aws_s3_object.customer_sample_data
  ]

  tags = merge(local.common_tags, {
    Name = each.key
    Database = each.value.database_name
  })
}

#######################
# AWS RAM Resource Share
#######################

# Create resource share for cross-account sharing
resource "aws_ram_resource_share" "lake_formation_share" {
  name                      = "${var.project_name}-cross-account-share"
  description              = "Lake Formation cross-account data sharing"
  allow_external_principals = true

  tags = merge(local.common_tags, {
    Name = "Lake Formation Cross-Account Share"
    Purpose = "Cross-account data sharing via RAM"
  })
}

# Associate databases with the resource share
resource "aws_ram_resource_association" "database_associations" {
  for_each = toset(var.shared_databases)

  resource_arn       = "arn:aws:glue:${local.region}:${local.account_id}:database/${each.value}"
  resource_share_arn = aws_ram_resource_share.lake_formation_share.arn

  depends_on = [aws_glue_catalog_database.databases]
}

# Invite consumer account to the resource share
resource "aws_ram_principal_association" "consumer_invitation" {
  principal          = var.consumer_account_id
  resource_share_arn = aws_ram_resource_share.lake_formation_share.arn
}

#######################
# Lake Formation Permissions
#######################

# Grant cross-account permissions based on LF-Tags
resource "aws_lakeformation_permissions" "cross_account_permissions" {
  for_each = var.cross_account_permissions

  principal   = var.consumer_account_id
  permissions = each.value.permissions
  permissions_with_grant_option = each.value.permissions_with_grant_option

  lf_tag_policy {
    resource_type = "DATABASE"
    expression {
      key    = each.value.tag_key
      values = each.value.tag_values
    }
  }

  depends_on = [
    aws_lakeformation_lf_tag.department,
    aws_lakeformation_lf_tag.classification,
    aws_lakeformation_lf_tag.data_category,
    aws_ram_principal_association.consumer_invitation
  ]
}

#######################
# CloudTrail for Audit (Optional)
#######################

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = "${var.project_name}-cloudtrail-logs-${local.account_id}-${local.unique_suffix}"

  tags = merge(local.common_tags, {
    Name = "CloudTrail Logs Bucket"
    Purpose = "Audit logging for Lake Formation operations"
  })
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
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
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${var.project_name}-audit-trail"
          }
        }
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
            "AWS:SourceArn" = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${var.project_name}-audit-trail"
          }
        }
      }
    ]
  })
}

# CloudTrail for Lake Formation API auditing
resource "aws_cloudtrail" "lake_formation_audit" {
  count                         = var.enable_cloudtrail_logging ? 1 : 0
  name                          = "${var.project_name}-audit-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail_logs[0].bucket
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::LakeFormation::Table"
      values = ["arn:aws:glue:*:*:table/*/*"]
    }

    data_resource {
      type   = "AWS::Glue::Database"
      values = ["arn:aws:glue:*:*:database/*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs_policy]

  tags = merge(local.common_tags, {
    Name = "Lake Formation Audit Trail"
    Purpose = "Audit logging for data access and permissions"
  })
}

#######################
# Consumer Account Setup (Optional)
#######################

# Consumer account Lake Formation settings (if enabled and assume role provided)
resource "aws_lakeformation_data_lake_settings" "consumer" {
  count    = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? 1 : 0
  provider = aws.consumer

  admins = [var.consumer_account_id]

  create_database_default_permissions {
    permissions = ["ALL"]
    principal   = var.consumer_account_id
  }

  create_table_default_permissions {
    permissions = ["ALL"]
    principal   = var.consumer_account_id
  }
}

# Data analyst role in consumer account
resource "aws_iam_role" "data_analyst_consumer" {
  count    = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? 1 : 0
  provider = aws.consumer
  
  name = var.data_analyst_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.consumer_account_id}:root"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Data Analyst Role"
    Purpose = "Cross-account data analysis access"
  })
}

# Attach policies to data analyst role
resource "aws_iam_role_policy_attachment" "data_analyst_athena" {
  count      = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? 1 : 0
  provider   = aws.consumer
  role       = aws_iam_role.data_analyst_consumer[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

resource "aws_iam_role_policy_attachment" "data_analyst_glue" {
  count      = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? 1 : 0
  provider   = aws.consumer
  role       = aws_iam_role.data_analyst_consumer[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}

# Create resource links in consumer account for shared databases
resource "aws_glue_catalog_database" "shared_database_links" {
  for_each = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? toset(var.shared_databases) : toset([])
  provider = aws.consumer

  name        = "shared_${each.value}"
  description = "Resource link to shared ${each.value} database"

  target_database {
    catalog_id    = local.account_id
    database_name = each.value
  }

  depends_on = [aws_ram_principal_association.consumer_invitation]

  tags = merge(local.common_tags, {
    Name = "shared_${each.value}"
    Purpose = "Resource link to producer account database"
    SourceDatabase = each.value
  })
}