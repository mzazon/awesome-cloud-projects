# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names
  database_name       = var.database_name != null ? var.database_name : "governance_catalog_${random_id.suffix.hex}"
  crawler_name        = var.crawler_name != null ? var.crawler_name : "governance-crawler-${random_id.suffix.hex}"
  classifier_name     = var.classifier_name != null ? var.classifier_name : "pii-classifier-${random_id.suffix.hex}"
  cloudtrail_name     = var.cloudtrail_name != null ? var.cloudtrail_name : "DataCatalogGovernanceTrail-${random_id.suffix.hex}"
  dashboard_name      = var.dashboard_name != null ? var.dashboard_name : "DataGovernanceDashboard-${random_id.suffix.hex}"
  data_analyst_role_name = var.data_analyst_role_name != null ? var.data_analyst_role_name : "DataAnalystGovernanceRole-${random_id.suffix.hex}"
  
  # S3 bucket names
  governance_bucket_name = "${var.project_name}-${random_id.suffix.hex}"
  audit_bucket_name      = "${var.project_name}-audit-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = "DataCatalogGovernance"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 BUCKETS FOR DATA AND AUDIT LOGS
# ============================================================================

# S3 bucket for data storage
resource "aws_s3_bucket" "governance_bucket" {
  bucket = local.governance_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning for data bucket
resource "aws_s3_bucket_versioning" "governance_bucket_versioning" {
  bucket = aws_s3_bucket.governance_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for data bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "governance_bucket_encryption" {
  bucket = aws_s3_bucket.governance_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for data bucket
resource "aws_s3_bucket_public_access_block" "governance_bucket_pab" {
  bucket = aws_s3_bucket.governance_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for audit logs
resource "aws_s3_bucket" "audit_bucket" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = local.audit_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning for audit bucket
resource "aws_s3_bucket_versioning" "audit_bucket_versioning" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for audit bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "audit_bucket_encryption" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for audit bucket
resource "aws_s3_bucket_public_access_block" "audit_bucket_pab" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "audit_bucket_policy" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_bucket[0].id

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
        Resource = aws_s3_bucket.audit_bucket[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
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
        Resource = "${aws_s3_bucket.audit_bucket[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
          }
        }
      }
    ]
  })
}

# Sample data object for testing (if enabled)
resource "aws_s3_object" "sample_data" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.governance_bucket.id
  key    = "data/sample_customer_data.csv"
  
  content = <<EOF
customer_id,first_name,last_name,email,ssn,phone,address,city,state,zip
1,John,Doe,john.doe@email.com,123-45-6789,555-123-4567,123 Main St,Anytown,NY,12345
2,Jane,Smith,jane.smith@email.com,987-65-4321,555-987-6543,456 Oak Ave,Somewhere,CA,67890
3,Bob,Johnson,bob.johnson@email.com,456-78-9012,555-456-7890,789 Pine Rd,Nowhere,TX,54321
EOF
  
  content_type = "text/csv"
  tags         = local.common_tags
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for Glue crawler
resource "aws_iam_role" "glue_crawler_role" {
  name = "GlueGovernanceCrawlerRole-${random_id.suffix.hex}"
  
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
  
  tags = local.common_tags
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3 access
resource "aws_iam_role_policy" "glue_s3_access" {
  name = "GlueS3AccessPolicy"
  role = aws_iam_role.glue_crawler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.governance_bucket.arn,
          "${aws_s3_bucket.governance_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.governance_bucket.arn}/scripts/*"
      }
    ]
  })
}

# Attach additional IAM policies if specified
resource "aws_iam_role_policy_attachment" "additional_policies" {
  count      = length(var.additional_iam_policies)
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = var.additional_iam_policies[count.index]
}

# IAM role for data analysts (if enabled)
resource "aws_iam_role" "data_analyst_role" {
  count = var.create_data_analyst_role ? 1 : 0
  name  = local.data_analyst_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for data analysts
resource "aws_iam_policy" "data_analyst_policy" {
  count       = var.create_data_analyst_role ? 1 : 0
  name        = "DataAnalystGovernancePolicy-${random_id.suffix.hex}"
  description = "Policy for data analysts to access governed data"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "lakeformation:GetDataAccess"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.governance_bucket.arn,
          "${aws_s3_bucket.governance_bucket.arn}/*"
        ]
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach data analyst policy to role
resource "aws_iam_role_policy_attachment" "data_analyst_policy_attachment" {
  count      = var.create_data_analyst_role ? 1 : 0
  role       = aws_iam_role.data_analyst_role[0].name
  policy_arn = aws_iam_policy.data_analyst_policy[0].arn
}

# ============================================================================
# AWS GLUE DATA CATALOG
# ============================================================================

# Glue Data Catalog database
resource "aws_glue_catalog_database" "governance_database" {
  name        = local.database_name
  description = var.database_description
  
  tags = local.common_tags
}

# Custom CSV classifier for PII detection
resource "aws_glue_classifier" "pii_classifier" {
  name = local.classifier_name
  
  csv_classifier {
    allow_single_column    = false
    contains_header        = "PRESENT"
    delimiter             = ","
    disable_value_trimming = false
    header                = ["customer_id", "first_name", "last_name", "email", "ssn", "phone", "address", "city", "state", "zip"]
    quote_symbol          = "\""
  }
  
  tags = local.common_tags
}

# Glue crawler for data discovery and classification
resource "aws_glue_crawler" "governance_crawler" {
  name          = local.crawler_name
  database_name = aws_glue_catalog_database.governance_database.name
  role          = aws_iam_role.glue_crawler_role.arn
  description   = "Governance crawler with PII classification"
  
  # Configure crawler targets
  s3_target {
    path = var.existing_data_bucket != null ? "s3://${var.existing_data_bucket}/${var.existing_data_prefix}" : "s3://${aws_s3_bucket.governance_bucket.bucket}/data/"
  }
  
  # Use custom classifier for PII detection
  classifiers = [aws_glue_classifier.pii_classifier.name]
  
  # Optional: Configure crawler schedule
  dynamic "schedule" {
    for_each = var.crawler_schedule != null ? [var.crawler_schedule] : []
    content {
      schedule_expression = schedule.value
    }
  }
  
  # Configure schema change policy
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
  
  tags = local.common_tags
}

# Upload PII detection script to S3
resource "aws_s3_object" "pii_detection_script" {
  bucket = aws_s3_bucket.governance_bucket.id
  key    = "scripts/pii-detection-script.py"
  
  content = <<EOF
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'TABLE_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Data Catalog
datasource = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name=args['TABLE_NAME'],
    transformation_ctx="datasource"
)

# Apply PII detection transform
pii_transform = DetectPII.apply(
    frame=datasource,
    detection_threshold=${var.pii_detection_threshold},
    sample_fraction=${var.pii_sample_fraction},
    actions_map={
        "ssn": "DETECT",
        "email": "DETECT",
        "phone": "DETECT",
        "address": "DETECT"
    },
    transformation_ctx="pii_transform"
)

# Log PII detection results
print("PII Detection completed for table: " + args['TABLE_NAME'])

job.commit()
EOF
  
  content_type = "text/plain"
  tags         = local.common_tags
}

# ============================================================================
# LAKE FORMATION CONFIGURATION
# ============================================================================

# Lake Formation data lake settings (if enabled)
resource "aws_lakeformation_data_lake_settings" "governance_settings" {
  count = var.enable_lake_formation ? 1 : 0
  
  # Set data lake administrators
  admins = length(var.lake_formation_admins) > 0 ? var.lake_formation_admins : [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
  
  # Disable default database and table permissions
  default_database_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
  
  default_table_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
  
  # Enable trusted resource owners
  trusted_resource_owners = [data.aws_caller_identity.current.account_id]
}

# Register S3 location with Lake Formation
resource "aws_lakeformation_resource" "governance_resource" {
  count = var.enable_lake_formation ? 1 : 0
  
  arn = var.existing_data_bucket != null ? "arn:aws:s3:::${var.existing_data_bucket}/${var.existing_data_prefix}" : "${aws_s3_bucket.governance_bucket.arn}/data/"
  
  depends_on = [aws_lakeformation_data_lake_settings.governance_settings]
}

# ============================================================================
# CLOUDTRAIL FOR AUDIT LOGGING
# ============================================================================

# CloudTrail for audit logging (if enabled)
resource "aws_cloudtrail" "governance_trail" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.audit_bucket[0].id
  include_global_service_events = var.include_global_service_events
  is_multi_region_trail         = var.is_multi_region_trail
  enable_log_file_validation    = var.enable_log_file_validation
  
  # Configure data events for Glue tables
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    data_resource {
      type   = "AWS::Glue::Table"
      values = ["arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${local.database_name}/*"]
    }
  }
  
  tags = local.common_tags
  
  depends_on = [aws_s3_bucket_policy.audit_bucket_policy]
}

# ============================================================================
# CLOUDWATCH MONITORING
# ============================================================================

# CloudWatch dashboard for governance metrics (if enabled)
resource "aws_cloudwatch_dashboard" "governance_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = local.dashboard_name
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", local.crawler_name],
            ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", local.crawler_name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Data Catalog Crawler Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          query = "SOURCE '/aws/glue/crawlers' | fields @timestamp, @message\n| filter @message like /PII/\n| sort @timestamp desc\n| limit 100"
          region = data.aws_region.current.name
          title  = "PII Detection Events"
        }
      }
    ]
  })
  
  depends_on = [aws_glue_crawler.governance_crawler]
}

# CloudWatch log group for Glue crawler
resource "aws_cloudwatch_log_group" "glue_crawler_logs" {
  name              = "/aws/glue/crawlers/${local.crawler_name}"
  retention_in_days = 30
  
  tags = local.common_tags
}

# ============================================================================
# OUTPUTS
# ============================================================================

# Wait for crawler to be ready before allowing dependent resources
resource "null_resource" "wait_for_crawler" {
  depends_on = [aws_glue_crawler.governance_crawler]
  
  provisioner "local-exec" {
    command = "sleep 30"  # Allow time for crawler to be fully configured
  }
}