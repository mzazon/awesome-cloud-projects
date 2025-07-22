# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  resource_suffix = random_id.suffix.hex
  source_bucket_name = "${var.project_name}-source-${local.resource_suffix}"
  dest_bucket_1_name = "${var.project_name}-dest1-${local.resource_suffix}"
  dest_bucket_2_name = "${var.project_name}-dest2-${local.resource_suffix}"
  replication_role_name = "MultiRegionReplicationRole-${local.resource_suffix}"
  sns_topic_name = "s3-replication-alerts-${local.resource_suffix}"
  cloudtrail_name = "s3-multi-region-audit-trail-${local.resource_suffix}"
  
  # Common tags to merge with provider default tags
  common_tags = merge(var.additional_tags, {
    Name = "${var.project_name}-${var.environment}"
  })
}

# =============================================================================
# KMS KEYS FOR ENCRYPTION
# =============================================================================

# KMS key for source bucket (primary region)
resource "aws_kms_key" "source" {
  description             = "KMS key for S3 multi-region replication source bucket"
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
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "source-s3-kms-key"
    Region      = var.primary_region
    KeyPurpose  = "S3SourceEncryption"
  })
}

# KMS key alias for source bucket
resource "aws_kms_alias" "source" {
  name          = "alias/s3-multi-region-source-${local.resource_suffix}"
  target_key_id = aws_kms_key.source.key_id
}

# KMS key for destination bucket 1 (secondary region)
resource "aws_kms_key" "dest1" {
  provider = aws.secondary
  
  description             = "KMS key for S3 multi-region replication destination 1"
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
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "dest1-s3-kms-key"
    Region      = var.secondary_region
    KeyPurpose  = "S3DestinationEncryption"
  })
}

# KMS key alias for destination bucket 1
resource "aws_kms_alias" "dest1" {
  provider = aws.secondary
  
  name          = "alias/s3-multi-region-dest1-${local.resource_suffix}"
  target_key_id = aws_kms_key.dest1.key_id
}

# KMS key for destination bucket 2 (tertiary region)
resource "aws_kms_key" "dest2" {
  provider = aws.tertiary
  
  description             = "KMS key for S3 multi-region replication destination 2"
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
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "dest2-s3-kms-key"
    Region      = var.tertiary_region
    KeyPurpose  = "S3DestinationEncryption"
  })
}

# KMS key alias for destination bucket 2
resource "aws_kms_alias" "dest2" {
  provider = aws.tertiary
  
  name          = "alias/s3-multi-region-dest2-${local.resource_suffix}"
  target_key_id = aws_kms_key.dest2.key_id
}

# =============================================================================
# S3 BUCKETS WITH ENCRYPTION AND VERSIONING
# =============================================================================

# Source S3 bucket (primary region)
resource "aws_s3_bucket" "source" {
  bucket        = local.source_bucket_name
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name         = "source-bucket"
    Region       = var.primary_region
    BucketType   = "Source"
    DataClass    = "Production"
  })
}

# Source bucket versioning
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Source bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.source.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = var.enable_bucket_key
  }
}

# Source bucket public access block
resource "aws_s3_bucket_public_access_block" "source" {
  count  = var.enable_bucket_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.source.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Destination bucket 1 (secondary region)
resource "aws_s3_bucket" "dest1" {
  provider      = aws.secondary
  bucket        = local.dest_bucket_1_name
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name         = "dest1-bucket"
    Region       = var.secondary_region
    BucketType   = "Destination"
    ReplicaOf    = local.source_bucket_name
  })
}

# Destination bucket 1 versioning
resource "aws_s3_bucket_versioning" "dest1" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.dest1.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Destination bucket 1 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "dest1" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.dest1.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.dest1.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = var.enable_bucket_key
  }
}

# Destination bucket 1 public access block
resource "aws_s3_bucket_public_access_block" "dest1" {
  provider = aws.secondary
  count    = var.enable_bucket_public_access_block ? 1 : 0
  bucket   = aws_s3_bucket.dest1.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Destination bucket 2 (tertiary region)
resource "aws_s3_bucket" "dest2" {
  provider      = aws.tertiary
  bucket        = local.dest_bucket_2_name
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name         = "dest2-bucket"
    Region       = var.tertiary_region
    BucketType   = "Destination"
    ReplicaOf    = local.source_bucket_name
  })
}

# Destination bucket 2 versioning
resource "aws_s3_bucket_versioning" "dest2" {
  provider = aws.tertiary
  bucket   = aws_s3_bucket.dest2.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Destination bucket 2 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "dest2" {
  provider = aws.tertiary
  bucket   = aws_s3_bucket.dest2.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.dest2.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = var.enable_bucket_key
  }
}

# Destination bucket 2 public access block
resource "aws_s3_bucket_public_access_block" "dest2" {
  provider = aws.tertiary
  count    = var.enable_bucket_public_access_block ? 1 : 0
  bucket   = aws_s3_bucket.dest2.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# IAM ROLE FOR REPLICATION
# =============================================================================

# IAM role for S3 replication
resource "aws_iam_role" "replication" {
  name = local.replication_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "s3-replication-role"
    Purpose     = "S3CrossRegionReplication"
    ServiceRole = "true"
  })
}

# IAM policy for replication permissions
resource "aws_iam_role_policy" "replication" {
  name = "MultiRegionS3ReplicationPolicy"
  role = aws_iam_role.replication.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
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
        Resource = [
          "${aws_s3_bucket.dest1.arn}/*",
          "${aws_s3_bucket.dest2.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.source.arn,
          aws_kms_key.dest1.arn,
          aws_kms_key.dest2.arn
        ]
      }
    ]
  })
}

# =============================================================================
# S3 BUCKET POLICIES FOR SECURITY
# =============================================================================

# Source bucket policy
resource "aws_s3_bucket_policy" "source" {
  count  = var.enable_ssl_requests_only ? 1 : 0
  bucket = aws_s3_bucket.source.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowReplicationRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.replication.arn
        }
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# S3 REPLICATION CONFIGURATION
# =============================================================================

# S3 bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "source" {
  depends_on = [aws_s3_bucket_versioning.source]
  
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.source.id
  
  # Replication rule for secondary region
  rule {
    id     = "ReplicateAllToSecondary"
    status = "Enabled"
    priority = 1
    
    filter {
      prefix = ""
    }
    
    delete_marker_replication {
      status = var.enable_delete_marker_replication ? "Enabled" : "Disabled"
    }
    
    destination {
      bucket        = aws_s3_bucket.dest1.arn
      storage_class = var.destination_storage_class
      
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dest1.arn
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = var.replication_time_control_minutes
        }
      }
      
      replication_time {
        status = "Enabled"
        time {
          minutes = var.replication_time_control_minutes
        }
      }
    }
  }
  
  # Replication rule for tertiary region
  rule {
    id     = "ReplicateAllToTertiary"
    status = "Enabled"
    priority = 2
    
    filter {
      prefix = ""
    }
    
    delete_marker_replication {
      status = var.enable_delete_marker_replication ? "Enabled" : "Disabled"
    }
    
    destination {
      bucket        = aws_s3_bucket.dest2.arn
      storage_class = var.destination_storage_class
      
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dest2.arn
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = var.replication_time_control_minutes
        }
      }
      
      replication_time {
        status = "Enabled"
        time {
          minutes = var.replication_time_control_minutes
        }
      }
    }
  }
  
  # High priority replication rule for critical data
  rule {
    id     = "ReplicateCriticalDataFast"
    status = "Enabled"
    priority = 3
    
    filter {
      and {
        prefix = "critical/"
        tags = {
          Priority = "High"
        }
      }
    }
    
    delete_marker_replication {
      status = var.enable_delete_marker_replication ? "Enabled" : "Disabled"
    }
    
    destination {
      bucket        = aws_s3_bucket.dest1.arn
      storage_class = "STANDARD"
      
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dest1.arn
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = var.replication_time_control_minutes
        }
      }
      
      replication_time {
        status = "Enabled"
        time {
          minutes = var.replication_time_control_minutes
        }
      }
    }
  }
}

# =============================================================================
# S3 INTELLIGENT TIERING CONFIGURATION
# =============================================================================

# Intelligent tiering configuration for source bucket
resource "aws_s3_bucket_intelligent_tiering_configuration" "source" {
  count  = var.enable_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.source.id
  name   = "EntireBucket"
  
  status = "Enabled"
  
  filter {
    prefix = ""
  }
  
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
  
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
  
  optional_fields = ["BucketKeyStatus"]
}

# =============================================================================
# S3 LIFECYCLE CONFIGURATION
# =============================================================================

# Lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.enable_lifecycle_policy ? 1 : 0
  bucket = aws_s3_bucket.source.id
  
  rule {
    id     = "MultiRegionLifecycleRule"
    status = "Enabled"
    
    filter {
      prefix = "archive/"
    }
    
    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }
    
    transition {
      days          = var.transition_to_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }
    
    noncurrent_version_transition {
      noncurrent_days = var.noncurrent_version_transition_ia_days
      storage_class   = "STANDARD_IA"
    }
    
    noncurrent_version_transition {
      noncurrent_days = var.noncurrent_version_transition_glacier_days
      storage_class   = "GLACIER"
    }
    
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# =============================================================================
# SNS TOPIC FOR ALERTS
# =============================================================================

# SNS topic for replication alerts
resource "aws_sns_topic" "alerts" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  name  = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name    = "s3-replication-alerts"
    Purpose = "ReplicationMonitoring"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "alerts" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  arn   = aws_sns_topic.alerts[0].arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.alerts[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS email subscriptions
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cloudwatch_monitoring && length(var.sns_email_endpoints) > 0 ? length(var.sns_email_endpoints) : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoints[count.index]
}

# =============================================================================
# CLOUDWATCH MONITORING AND ALERTING
# =============================================================================

# CloudWatch alarm for replication failures
resource "aws_cloudwatch_metric_alarm" "replication_failure" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "S3-Replication-Failure-Rate-${local.source_bucket_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedReplication"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.replication_failure_threshold
  alarm_description   = "High replication failure rate detected"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  
  dimensions = {
    SourceBucket = aws_s3_bucket.source.id
  }
  
  tags = merge(local.common_tags, {
    Name      = "replication-failure-alarm"
    AlarmType = "ReplicationFailure"
  })
}

# CloudWatch alarm for replication latency
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "S3-Replication-Latency-${local.source_bucket_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replication_latency_threshold
  alarm_description   = "Replication latency too high"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  
  dimensions = {
    SourceBucket      = aws_s3_bucket.source.id
    DestinationBucket = aws_s3_bucket.dest1.id
  }
  
  tags = merge(local.common_tags, {
    Name      = "replication-latency-alarm"
    AlarmType = "ReplicationLatency"
  })
}

# CloudWatch dashboard for replication monitoring
resource "aws_cloudwatch_dashboard" "replication" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "S3-Multi-Region-Replication-Dashboard"
  
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
            ["AWS/S3", "ReplicationLatency", "SourceBucket", aws_s3_bucket.source.id, "DestinationBucket", aws_s3_bucket.dest1.id],
            ["AWS/S3", "ReplicationLatency", "SourceBucket", aws_s3_bucket.source.id, "DestinationBucket", aws_s3_bucket.dest2.id],
            ["AWS/S3", "FailedReplication", "SourceBucket", aws_s3_bucket.source.id]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "S3 Multi-Region Replication Metrics"
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
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.dest1.id, "StorageType", "StandardStorage"],
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.dest2.id, "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
          region = var.primary_region
          title  = "Bucket Size Comparison"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}

# =============================================================================
# CLOUDTRAIL FOR AUDIT LOGGING
# =============================================================================

# CloudTrail for comprehensive audit logging
resource "aws_cloudtrail" "audit" {
  count = var.enable_cloudtrail ? 1 : 0
  name  = local.cloudtrail_name
  
  s3_bucket_name                = aws_s3_bucket.source.id
  include_global_service_events = var.cloudtrail_include_global_events
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  
  tags = merge(local.common_tags, {
    Name    = "s3-multi-region-audit-trail"
    Purpose = "AuditLogging"
  })
}