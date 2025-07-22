# S3 Cross-Region Replication Disaster Recovery Solution
# This Terraform configuration creates a complete disaster recovery solution using S3 cross-region replication

# Data sources for current AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "primary" {
  provider = aws.primary
}
data "aws_region" "secondary" {
  provider = aws.secondary
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and common configurations
locals {
  source_bucket_name         = "${var.bucket_name_prefix}-source-${random_string.suffix.result}"
  replica_bucket_name        = "${var.bucket_name_prefix}-replica-${random_string.suffix.result}"
  replication_role_name      = "s3-replication-role-${random_string.suffix.result}"
  cloudtrail_bucket_name     = "${var.bucket_name_prefix}-cloudtrail-${random_string.suffix.result}"
  account_id                 = data.aws_caller_identity.current.account_id
  
  common_tags = merge(
    {
      Environment   = var.environment
      Purpose       = "DisasterRecovery"
      CostCenter    = var.cost_center
      ManagedBy     = "Terraform"
      ProjectName   = var.project_name
    },
    var.additional_tags
  )
}

# KMS Key for S3 encryption in primary region
resource "aws_kms_key" "s3_primary" {
  count    = var.enable_server_side_encryption ? 1 : 0
  provider = aws.primary
  
  description             = "KMS key for S3 encryption in primary region"
  deletion_window_in_days = var.kms_key_deletion_window
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-primary-key"
  })
}

# KMS Key alias for primary region
resource "aws_kms_alias" "s3_primary" {
  count         = var.enable_server_side_encryption ? 1 : 0
  provider      = aws.primary
  name          = "alias/${var.project_name}-s3-primary-key"
  target_key_id = aws_kms_key.s3_primary[0].key_id
}

# KMS Key for S3 encryption in secondary region
resource "aws_kms_key" "s3_secondary" {
  count    = var.enable_server_side_encryption ? 1 : 0
  provider = aws.secondary
  
  description             = "KMS key for S3 encryption in secondary region"
  deletion_window_in_days = var.kms_key_deletion_window
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-secondary-key"
  })
}

# KMS Key alias for secondary region
resource "aws_kms_alias" "s3_secondary" {
  count         = var.enable_server_side_encryption ? 1 : 0
  provider      = aws.secondary
  name          = "alias/${var.project_name}-s3-secondary-key"
  target_key_id = aws_kms_key.s3_secondary[0].key_id
}

# S3 bucket for CloudTrail logs (in primary region)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count    = var.enable_cloudtrail ? 1 : 0
  provider = aws.primary
  bucket   = local.cloudtrail_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cloudtrail-logs"
  })
}

# CloudTrail bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count    = var.enable_cloudtrail ? 1 : 0
  provider = aws.primary
  bucket   = aws_s3_bucket.cloudtrail_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudTrail bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count    = var.enable_cloudtrail && var.enable_server_side_encryption ? 1 : 0
  provider = aws.primary
  bucket   = aws_s3_bucket.cloudtrail_logs[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_primary[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count    = var.enable_cloudtrail ? 1 : 0
  provider = aws.primary
  bucket   = aws_s3_bucket.cloudtrail_logs[0].id
  
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
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.primary.name}:${local.account_id}:trail/s3-dr-audit-trail"
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
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.primary.name}:${local.account_id}:trail/s3-dr-audit-trail"
          }
        }
      }
    ]
  })
}

# CloudTrail for audit logging
resource "aws_cloudtrail" "s3_audit" {
  count          = var.enable_cloudtrail ? 1 : 0
  provider       = aws.primary
  name           = "s3-dr-audit-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].id
  
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_log_file_validation   = true
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${local.source_bucket_name}/*"]
    }
  }
  
  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-audit-trail"
  })
}

# S3 Source Bucket in Primary Region
resource "aws_s3_bucket" "source" {
  provider = aws.primary
  bucket   = local.source_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-source-bucket"
    Type = "Source"
  })
}

# Source bucket versioning (required for replication)
resource "aws_s3_bucket_versioning" "source" {
  provider = aws.primary
  bucket   = aws_s3_bucket.source.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Source bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count    = var.enable_server_side_encryption ? 1 : 0
  provider = aws.primary
  bucket   = aws_s3_bucket.source.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_primary[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Source bucket public access block
resource "aws_s3_bucket_public_access_block" "source" {
  provider = aws.primary
  bucket   = aws_s3_bucket.source.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Replica Bucket in Secondary Region
resource "aws_s3_bucket" "replica" {
  provider = aws.secondary
  bucket   = local.replica_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-replica-bucket"
    Type = "Replica"
  })
}

# Replica bucket versioning
resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Replica bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  count    = var.enable_server_side_encryption ? 1 : 0
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_secondary[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Replica bucket public access block
resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for S3 Replication
resource "aws_iam_role" "replication" {
  provider = aws.primary
  name     = local.replication_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-replication-role"
  })
}

# IAM Policy for S3 Replication
resource "aws_iam_policy" "replication" {
  provider = aws.primary
  name     = "${local.replication_role_name}-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.source.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.replica.arn}/*"
      }
    ]
  })
}

# Attach replication policy to role
resource "aws_iam_role_policy_attachment" "replication" {
  provider   = aws.primary
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# S3 Bucket Replication Configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.primary
  role     = aws_iam_role.replication.arn
  bucket   = aws_s3_bucket.source.id
  
  depends_on = [aws_s3_bucket_versioning.source]
  
  rule {
    id     = "ReplicateEverything"
    status = "Enabled"
    
    priority = var.replication_priority
    
    filter {
      prefix = ""
    }
    
    delete_marker_replication {
      status = "Enabled"
    }
    
    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = var.replica_storage_class
    }
  }
  
  rule {
    id     = "ReplicateCriticalData"
    status = "Enabled"
    
    priority = var.replication_priority + 1
    
    filter {
      and {
        prefix = var.critical_data_prefix
        tags = {
          Classification = "Critical"
        }
      }
    }
    
    delete_marker_replication {
      status = "Enabled"
    }
    
    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = var.critical_replica_storage_class
    }
  }
}

# Lifecycle Configuration for Source Bucket
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count      = var.enable_lifecycle_policies ? 1 : 0
  provider   = aws.primary
  bucket     = aws_s3_bucket.source.id
  depends_on = [aws_s3_bucket_versioning.source]
  
  rule {
    id     = "TransitionToIA"
    status = "Enabled"
    
    filter {
      prefix = var.standard_data_prefix
    }
    
    transition {
      days          = var.lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = var.lifecycle_glacier_days
      storage_class = "GLACIER"
    }
  }
  
  rule {
    id     = "ArchiveTransition"
    status = "Enabled"
    
    filter {
      prefix = var.archive_data_prefix
    }
    
    transition {
      days          = 1
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# SNS Topic for Replication Alerts
resource "aws_sns_topic" "replication_alerts" {
  count    = var.enable_sns_notifications ? 1 : 0
  provider = aws.primary
  name     = "${var.project_name}-replication-alerts"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-replication-alerts"
  })
}

# SNS Topic Subscription (Email)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_sns_notifications && var.sns_email_endpoint != "" ? 1 : 0
  provider  = aws.primary
  topic_arn = aws_sns_topic.replication_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# CloudWatch Alarm for Replication Latency
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  provider          = aws.primary
  alarm_name        = "S3-Replication-Latency-${local.source_bucket_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "2"
  metric_name       = "ReplicationLatency"
  namespace         = "AWS/S3"
  period            = "300"
  statistic         = "Average"
  threshold         = var.replication_latency_threshold
  alarm_description = "S3 replication latency is too high"
  alarm_actions     = var.enable_sns_notifications ? [aws_sns_topic.replication_alerts[0].arn] : []
  
  dimensions = {
    SourceBucket      = aws_s3_bucket.source.id
    DestinationBucket = aws_s3_bucket.replica.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-replication-latency-alarm"
  })
}

# CloudWatch Alarm for Replication Failures
resource "aws_cloudwatch_metric_alarm" "replication_failures" {
  count               = var.enable_cloudwatch_monitoring ? 1 : 0
  provider            = aws.primary
  alarm_name          = "S3-Replication-Failures-${local.source_bucket_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplicationFailureCount"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "S3 replication failures detected"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.replication_alerts[0].arn] : []
  
  dimensions = {
    SourceBucket      = aws_s3_bucket.source.id
    DestinationBucket = aws_s3_bucket.replica.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-replication-failures-alarm"
  })
}

# CloudWatch Dashboard for Replication Monitoring
resource "aws_cloudwatch_dashboard" "replication_dashboard" {
  count          = var.enable_cloudwatch_monitoring ? 1 : 0
  provider       = aws.primary
  dashboard_name = "S3-DR-Dashboard-${random_string.suffix.result}"
  
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
            ["AWS/S3", "ReplicationLatency", "SourceBucket", aws_s3_bucket.source.id],
            ["AWS/S3", "ReplicationFailureCount", "SourceBucket", aws_s3_bucket.source.id]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "S3 Replication Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.source.id, "StorageType", "StandardStorage"],
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.replica.id, "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
          region = var.primary_region
          title  = "Bucket Size Comparison"
        }
      }
    ]
  })
}