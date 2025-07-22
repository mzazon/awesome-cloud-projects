# main.tf - Main Terraform configuration for Enterprise Migration Assessment
# This file creates the core infrastructure for AWS Application Discovery Service
# and supporting resources for enterprise migration assessment

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  resource_prefix = "${var.migration_project_name}-${random_id.suffix.hex}"
  
  # Common tags merged with default tags
  common_tags = merge(var.default_tags, {
    Project     = var.migration_project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    Region      = data.aws_region.current.name
  })
  
  # S3 bucket name with random suffix for uniqueness
  s3_bucket_name = "${local.resource_prefix}-discovery-data"
}

# KMS Key for encryption of discovery data
resource "aws_kms_key" "discovery_encryption" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for encrypting Application Discovery Service data"
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
        Sid    = "Allow Application Discovery Service"
        Effect = "Allow"
        Principal = {
          Service = "discovery.amazonaws.com"
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
    Name = "${local.resource_prefix}-discovery-kms-key"
  })
}

# KMS Key Alias for easier reference
resource "aws_kms_alias" "discovery_encryption" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.resource_prefix}-discovery-encryption"
  target_key_id = aws_kms_key.discovery_encryption[0].key_id
}

# S3 Bucket for storing discovery data exports
resource "aws_s3_bucket" "discovery_data" {
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.s3_bucket_name
    Purpose     = "DiscoveryDataStorage"
    DataType    = "MigrationAssessment"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "discovery_data" {
  bucket = aws_s3_bucket.discovery_data.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "discovery_data" {
  count = var.enable_encryption ? 1 : 0
  
  bucket = aws_s3_bucket.discovery_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.discovery_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "discovery_data" {
  bucket = aws_s3_bucket.discovery_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy for Application Discovery Service
resource "aws_s3_bucket_policy" "discovery_data" {
  bucket = aws_s3_bucket.discovery_data.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowApplicationDiscoveryService"
        Effect = "Allow"
        Principal = {
          Service = "discovery.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.discovery_data.arn,
          "${aws_s3_bucket.discovery_data.arn}/*"
        ]
      },
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.discovery_data.arn,
          "${aws_s3_bucket.discovery_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# S3 Bucket Lifecycle Configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "discovery_data" {
  bucket = aws_s3_bucket.discovery_data.id
  
  rule {
    id     = "discovery_data_lifecycle"
    status = "Enabled"
    
    # Move to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    # Move to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    # Delete objects after retention period
    expiration {
      days = var.data_retention_days
    }
    
    # Handle incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  
  # Manage versioned objects
  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      id     = "versioned_objects_lifecycle"
      status = "Enabled"
      
      noncurrent_version_expiration {
        noncurrent_days = 30
      }
    }
  }
}

# CloudWatch Log Group for Application Discovery Service
resource "aws_cloudwatch_log_group" "discovery_service" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  name              = "/aws/discovery/${local.resource_prefix}"
  retention_in_days = 30
  
  kms_key_id = var.enable_encryption ? aws_kms_key.discovery_encryption[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-discovery-logs"
  })
}

# IAM Role for Lambda functions (if needed for automation)
resource "aws_iam_role" "discovery_automation" {
  count = var.enable_eventbridge_automation ? 1 : 0
  
  name = "${local.resource_prefix}-discovery-automation-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Policy for Discovery Automation
resource "aws_iam_role_policy" "discovery_automation" {
  count = var.enable_eventbridge_automation ? 1 : 0
  
  name = "${local.resource_prefix}-discovery-automation-policy"
  role = aws_iam_role.discovery_automation[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "discovery:*",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.discovery_encryption[0].arn] : []
      }
    ]
  })
}

# EventBridge Rule for automated discovery export
resource "aws_cloudwatch_event_rule" "discovery_export" {
  count = var.enable_eventbridge_automation ? 1 : 0
  
  name                = "${local.resource_prefix}-discovery-export"
  description         = "Trigger automated discovery data export"
  schedule_expression = "cron(${var.export_schedule})"
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-discovery-export-rule"
  })
}

# SNS Topic for notifications (if email provided)
resource "aws_sns_topic" "migration_notifications" {
  count = var.notification_email != "" ? 1 : 0
  
  name = "${local.resource_prefix}-migration-notifications"
  
  kms_master_key_id = var.enable_encryption ? aws_kms_key.discovery_encryption[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-migration-notifications"
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.migration_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Store migration wave configuration in S3
resource "aws_s3_object" "migration_waves_config" {
  bucket = aws_s3_bucket.discovery_data.id
  key    = "planning/migration-waves.json"
  
  content = jsonencode({
    waves = var.migration_waves
    created_at = timestamp()
    project_name = var.migration_project_name
  })
  
  content_type = "application/json"
  
  server_side_encryption = var.enable_encryption ? "aws:kms" : null
  kms_key_id            = var.enable_encryption ? aws_kms_key.discovery_encryption[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-migration-waves-config"
  })
}

# Store agent configuration in S3
resource "aws_s3_object" "agent_config" {
  bucket = aws_s3_bucket.discovery_data.id
  key    = "config/agent-config.json"
  
  content = jsonencode({
    region = data.aws_region.current.name
    enableSSL = true
    collectionConfiguration = {
      collectProcesses = var.discovery_agent_config.collect_processes
      collectNetworkConnections = var.discovery_agent_config.collect_network_connections
      collectPerformanceData = var.discovery_agent_config.collect_performance_data
      collectionIntervalHours = var.discovery_agent_config.collection_interval_hours
    }
    accountId = data.aws_caller_identity.current.account_id
    projectName = var.migration_project_name
  })
  
  content_type = "application/json"
  
  server_side_encryption = var.enable_encryption ? "aws:kms" : null
  kms_key_id            = var.enable_encryption ? aws_kms_key.discovery_encryption[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-agent-config"
  })
}

# Store VMware connector configuration (if provided)
resource "aws_s3_object" "connector_config" {
  count = var.vmware_vcenter_config.hostname != "" ? 1 : 0
  
  bucket = aws_s3_bucket.discovery_data.id
  key    = "config/connector-config.json"
  
  content = jsonencode({
    connectorName = "${local.resource_prefix}-vmware-connector"
    awsRegion = data.aws_region.current.name
    vCenterDetails = {
      hostname = var.vmware_vcenter_config.hostname
      username = var.vmware_vcenter_config.username
      enableSSL = var.vmware_vcenter_config.enable_ssl
      port = var.vmware_vcenter_config.port
    }
    dataCollectionPreferences = {
      collectVMMetrics = true
      collectNetworkInfo = true
      collectPerformanceData = true
    }
  })
  
  content_type = "application/json"
  
  server_side_encryption = var.enable_encryption ? "aws:kms" : null
  kms_key_id            = var.enable_encryption ? aws_kms_key.discovery_encryption[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-connector-config"
  })
}

# CloudWatch Dashboard for monitoring discovery progress
resource "aws_cloudwatch_dashboard" "discovery_monitoring" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  dashboard_name = "${local.resource_prefix}-discovery-dashboard"
  
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
            ["AWS/ApplicationDiscovery", "AgentHealth", "AgentStatus", "HEALTHY"],
            ["AWS/ApplicationDiscovery", "AgentHealth", "AgentStatus", "UNHEALTHY"],
            ["AWS/ApplicationDiscovery", "DataCollectionStatus", "CollectionType", "AGENT"],
            ["AWS/ApplicationDiscovery", "DataCollectionStatus", "CollectionType", "CONNECTOR"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Discovery Agent Status"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          query = "SOURCE '${aws_cloudwatch_log_group.discovery_service[0].name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = data.aws_region.current.name
          title  = "Discovery Service Logs"
        }
      }
    ]
  })
}

# Time-based resource to track deployment time
resource "time_static" "deployment_time" {
  triggers = {
    project_name = var.migration_project_name
  }
}

# Local file with deployment information
resource "local_file" "deployment_info" {
  filename = "${path.module}/deployment-info.json"
  
  content = jsonencode({
    deployment_time = time_static.deployment_time.rfc3339
    project_name = var.migration_project_name
    aws_region = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id
    s3_bucket_name = aws_s3_bucket.discovery_data.id
    resource_prefix = local.resource_prefix
    migration_waves = var.migration_waves
    agent_download_urls = {
      windows = "https://aws-discovery-agent.s3.amazonaws.com/windows/latest/AWSApplicationDiscoveryAgentInstaller.exe"
      linux = "https://aws-discovery-agent.s3.amazonaws.com/linux/latest/aws-discovery-agent.tar.gz"
      connector_ova = "https://aws-discovery-connector.s3.amazonaws.com/VMware/latest/AWS-Discovery-Connector.ova"
    }
    next_steps = [
      "Download and install Discovery Agents on target servers",
      "Configure VMware Discovery Connector if using VMware",
      "Monitor agent health in CloudWatch Dashboard",
      "Review collected data in Migration Hub",
      "Plan migration waves based on discovered dependencies"
    ]
  })
}