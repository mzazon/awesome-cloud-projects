# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Create unique bucket name with random suffix
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "cost-estimation-pricing-calculator-s3"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
  
  # Create dynamic folder structure including project-specific folders
  all_folders = concat(
    var.estimate_folders,
    ["projects/${var.project_name}/"]
  )
}

# S3 bucket for storing cost estimates and related documents
resource "aws_s3_bucket" "cost_estimates" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = "Cost Estimates Storage"
    Description = "Centralized repository for AWS cost estimation documents and reports"
  })
}

# Configure S3 bucket versioning for estimate history tracking
resource "aws_s3_bucket_versioning" "cost_estimates_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.cost_estimates.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for security compliance
resource "aws_s3_bucket_server_side_encryption_configuration" "cost_estimates_encryption" {
  bucket = aws_s3_bucket.cost_estimates.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to ensure estimate data remains private
resource "aws_s3_bucket_public_access_block" "cost_estimates_pab" {
  bucket = aws_s3_bucket.cost_estimates.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create organized folder structure for cost estimates
resource "aws_s3_object" "estimate_folders" {
  count = length(local.all_folders)
  
  bucket       = aws_s3_bucket.cost_estimates.id
  key          = local.all_folders[count.index]
  content_type = "application/x-directory"
  
  tags = merge(local.common_tags, {
    FolderPath = local.all_folders[count.index]
    Purpose    = "Organization"
  })
}

# S3 lifecycle policy for automated cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "cost_estimates_lifecycle" {
  count  = var.enable_lifecycle_policy ? 1 : 0
  bucket = aws_s3_bucket.cost_estimates.id

  rule {
    id     = "CostEstimateLifecycle"
    status = "Enabled"

    filter {
      prefix = "estimates/"
    }

    # Transition to Standard-IA after specified days
    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after specified days
    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Transition to Deep Archive after specified days
    transition {
      days          = var.transition_to_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Clean up incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Separate rule for managing object versions
  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []
    
    content {
      id     = "VersionManagement"
      status = "Enabled"

      noncurrent_version_transition {
        noncurrent_days = 30
        storage_class   = "STANDARD_IA"
      }

      noncurrent_version_transition {
        noncurrent_days = 90
        storage_class   = "GLACIER"
      }

      # Delete old versions after 2 years to control costs
      noncurrent_version_expiration {
        noncurrent_days = 730
      }
    }
  }
}

# SNS topic for budget notifications
resource "aws_sns_topic" "budget_alerts" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-budget-alerts"

  tags = merge(local.common_tags, {
    Name        = "Budget Alert Notifications"
    Description = "SNS topic for AWS budget threshold notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "budget_email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.budget_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM role for AWS Budgets to publish to SNS
resource "aws_iam_role" "budget_role" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-budget-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for budget notifications
resource "aws_iam_role_policy" "budget_policy" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-budget-policy"
  role  = aws_iam_role.budget_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.budget_alerts[0].arn
      }
    ]
  })
}

# AWS Budget for cost monitoring and alerts
resource "aws_budgets_budget" "project_budget" {
  name         = "${var.project_name}-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filters {
    tag {
      key = "Project"
      values = [var.project_name]
    }
  }

  # Budget notification configuration
  dynamic "notification" {
    for_each = var.notification_email != "" ? [1] : []
    
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                 = var.budget_alert_threshold
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_email_addresses = [var.notification_email]
      subscriber_sns_topic_arns   = [aws_sns_topic.budget_alerts[0].arn]
    }
  }
}

# Sample cost estimate file for demonstration purposes
resource "aws_s3_object" "sample_estimate" {
  bucket       = aws_s3_bucket.cost_estimates.id
  key          = "projects/${var.project_name}/sample-estimate-${formatdate("YYYYMMDD", timestamp())}.csv"
  content_type = "text/csv"
  
  content = <<-EOT
Service,Configuration,Monthly Cost,Annual Cost
Amazon EC2,t3.medium Linux,30.37,364.44
Amazon S3,100GB Standard Storage,2.30,27.60
Amazon RDS,db.t3.micro PostgreSQL,13.32,159.84
Total,,46.99,563.88
EOT

  metadata = {
    "project"      = var.project_name
    "created-by"   = "terraform"
    "estimate-date" = formatdate("YYYY-MM-DD", timestamp())
  }

  tags = merge(local.common_tags, {
    EstimateType = "Monthly"
    Department   = "Finance"
    FileType     = "CSV"
  })
}

# Sample estimate summary document
resource "aws_s3_object" "sample_summary" {
  bucket       = aws_s3_bucket.cost_estimates.id
  key          = "projects/${var.project_name}/summary-${formatdate("YYYYMMDD", timestamp())}.txt"
  content_type = "text/plain"
  
  content = <<-EOT
Cost Estimate Summary - ${var.project_name}
Generated: ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}

Estimated Monthly Cost: $46.99
Estimated Annual Cost: $563.88

Services Included:
- EC2 t3.medium instance
- S3 storage (100GB)
- RDS PostgreSQL database

Notes: This estimate assumes standard usage patterns
Configuration deployed via Terraform infrastructure as code
EOT

  tags = merge(local.common_tags, {
    DocumentType = "Summary"
    Department   = "Finance"
    FileType     = "Text"
  })
}

# CloudWatch log group for cost estimation activities (optional)
resource "aws_cloudwatch_log_group" "cost_estimation_logs" {
  name              = "/aws/cost-estimation/${var.project_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name        = "Cost Estimation Logs"
    Description = "Log group for cost estimation and budget activities"
  })
}