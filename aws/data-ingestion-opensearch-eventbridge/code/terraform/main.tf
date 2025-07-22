# Main Terraform configuration for AWS automated data ingestion pipelines
# This configuration creates a complete data ingestion solution using:
# - Amazon S3 for data storage
# - Amazon OpenSearch Service for analytics
# - OpenSearch Ingestion for data processing
# - EventBridge Scheduler for automation
# - IAM roles and policies for security

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources
  name_suffix         = lower(random_id.suffix.hex)
  opensearch_domain   = var.opensearch_domain_name != "" ? var.opensearch_domain_name : "${var.project_name}-domain-${local.name_suffix}"
  pipeline_name       = var.pipeline_name != "" ? var.pipeline_name : "${var.project_name}-pipeline-${local.name_suffix}"
  data_bucket_name    = var.data_bucket_name != "" ? var.data_bucket_name : "${var.project_name}-data-${local.name_suffix}"
  schedule_group_name = var.schedule_group_name != "" ? var.schedule_group_name : "${var.project_name}-schedules-${local.name_suffix}"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ========================================
# S3 Data Storage Configuration
# ========================================

# S3 bucket for storing raw data that will be processed by the ingestion pipeline
resource "aws_s3_bucket" "data_bucket" {
  bucket        = local.data_bucket_name
  force_destroy = !var.delete_protection

  tags = merge(local.common_tags, {
    Name        = local.data_bucket_name
    Purpose     = "DataIngestionSource"
    Description = "Storage bucket for raw data to be processed by OpenSearch Ingestion"
  })
}

# Enable versioning on the S3 bucket for data protection
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# Enable server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to the S3 bucket for security
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Optional lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "data_bucket_lifecycle" {
  count  = var.s3_lifecycle_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    id     = "data_expiration"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ========================================
# CloudWatch Logs for OpenSearch
# ========================================

# CloudWatch log groups for OpenSearch domain logging
resource "aws_cloudwatch_log_group" "opensearch_logs" {
  for_each = var.enable_cloudwatch_logs ? toset(var.log_types) : []
  
  name              = "/aws/opensearch/domains/${local.opensearch_domain}/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name    = "opensearch-${each.value}-logs"
    Purpose = "OpenSearchLogging"
  })
}

# CloudWatch log resource policy to allow OpenSearch to write logs
resource "aws_cloudwatch_log_resource_policy" "opensearch_log_policy" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  policy_name = "${local.opensearch_domain}-log-policy"
  
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:PutLogEventsBatch",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/opensearch/domains/${local.opensearch_domain}/*"
      }
    ]
  })
}

# ========================================
# OpenSearch Service Domain
# ========================================

# IAM service-linked role for OpenSearch Service
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "opensearchservice.amazonaws.com"
  description      = "Service-linked role for Amazon OpenSearch Service"

  # This resource might already exist, so we'll use lifecycle rules
  lifecycle {
    ignore_changes = [aws_service_name]
  }
}

# IAM policy document for OpenSearch domain access
data "aws_iam_policy_document" "opensearch_access_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    
    actions = [
      "es:*"
    ]
    
    resources = [
      "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain}/*"
    ]
    
    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_cidr_blocks
    }
  }
}

# Amazon OpenSearch Service domain for analytics and search capabilities
resource "aws_opensearch_domain" "analytics_domain" {
  domain_name    = local.opensearch_domain
  engine_version = var.opensearch_version
  
  # Cluster configuration for compute resources
  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = var.opensearch_instance_count
    dedicated_master_enabled = false
    zone_awareness_enabled = false
  }
  
  # EBS storage configuration
  ebs_options {
    ebs_enabled = true
    volume_type = var.opensearch_ebs_volume_type
    volume_size = var.opensearch_ebs_volume_size
  }
  
  # Security configuration
  encrypt_at_rest {
    enabled = true
  }
  
  node_to_node_encryption {
    enabled = true
  }
  
  domain_endpoint_options {
    enforce_https                   = true
    tls_security_policy            = "Policy-Min-TLS-1-2-2019-07"
    custom_endpoint_enabled        = false
  }
  
  # Fine-grained access control (optional)
  dynamic "advanced_security_options" {
    for_each = var.opensearch_master_user_name != "" ? [1] : []
    content {
      enabled                        = true
      anonymous_auth_enabled         = false
      internal_user_database_enabled = true
      
      master_user_options {
        master_user_name     = var.opensearch_master_user_name
        master_user_password = var.opensearch_master_user_password
      }
    }
  }
  
  # CloudWatch logging configuration
  dynamic "log_publishing_options" {
    for_each = var.enable_cloudwatch_logs ? toset(var.log_types) : []
    content {
      log_type                 = log_publishing_options.value
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_logs[log_publishing_options.value].arn
      enabled                  = true
    }
  }
  
  # Access policies for the domain
  access_policies = data.aws_iam_policy_document.opensearch_access_policy.json
  
  # Advanced options for OpenSearch
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "indices.fielddata.cache.size"           = "40%"
    "indices.query.bool.max_clause_count"    = "10000"
  }
  
  tags = merge(local.common_tags, {
    Name        = local.opensearch_domain
    Purpose     = "AnalyticsPlatform"
    Description = "OpenSearch domain for data analytics and search"
  })
  
  depends_on = [
    aws_iam_service_linked_role.opensearch,
    aws_cloudwatch_log_resource_policy.opensearch_log_policy
  ]
}

# ========================================
# IAM Roles and Policies for OpenSearch Ingestion
# ========================================

# IAM role for OpenSearch Ingestion pipeline to access S3 and OpenSearch
resource "aws_iam_role" "opensearch_ingestion_role" {
  name = "${local.pipeline_name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "osis-pipelines.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.pipeline_name}-role"
    Purpose     = "OpenSearchIngestionAccess"
    Description = "IAM role for OpenSearch Ingestion pipeline operations"
  })
}

# IAM policy for OpenSearch Ingestion to read from S3
resource "aws_iam_role_policy" "opensearch_ingestion_s3_policy" {
  name = "${local.pipeline_name}-s3-policy"
  role = aws_iam_role.opensearch_ingestion_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_bucket.arn,
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM policy for OpenSearch Ingestion to write to OpenSearch domain
resource "aws_iam_role_policy" "opensearch_ingestion_domain_policy" {
  name = "${local.pipeline_name}-domain-policy"
  role = aws_iam_role.opensearch_ingestion_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet",
          "es:ESHttpHead"
        ]
        Resource = "${aws_opensearch_domain.analytics_domain.arn}/*"
      }
    ]
  })
}

# ========================================
# OpenSearch Ingestion Pipeline
# ========================================

# OpenSearch Ingestion pipeline for automated data processing
resource "aws_osis_pipeline" "data_ingestion_pipeline" {
  pipeline_name = local.pipeline_name
  min_units     = var.pipeline_min_units
  max_units     = var.pipeline_max_units
  
  # Data Prepper pipeline configuration in YAML format
  pipeline_configuration_body = templatefile("${path.module}/pipeline-config.yaml", {
    bucket_name            = aws_s3_bucket.data_bucket.bucket
    opensearch_endpoint    = aws_opensearch_domain.analytics_domain.endpoint
    aws_region            = data.aws_region.current.name
    pipeline_role_arn     = aws_iam_role.opensearch_ingestion_role.arn
    data_source_prefixes  = var.data_source_prefixes
    index_template        = var.opensearch_index_template
  })
  
  # CloudWatch logging for the pipeline
  log_publishing_options {
    is_logging_enabled = true
    cloudwatch_log_destination {
      log_group = "/aws/osis/pipelines/${local.pipeline_name}"
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.pipeline_name
    Purpose     = "DataIngestionProcessing"
    Description = "OpenSearch Ingestion pipeline for automated data processing"
  })
  
  depends_on = [
    aws_opensearch_domain.analytics_domain,
    aws_iam_role_policy.opensearch_ingestion_s3_policy,
    aws_iam_role_policy.opensearch_ingestion_domain_policy
  ]
}

# CloudWatch log group for OpenSearch Ingestion pipeline
resource "aws_cloudwatch_log_group" "pipeline_logs" {
  name              = "/aws/osis/pipelines/${local.pipeline_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name    = "pipeline-logs"
    Purpose = "PipelineLogging"
  })
}

# ========================================
# EventBridge Scheduler Configuration
# ========================================

# IAM role for EventBridge Scheduler to control OpenSearch Ingestion pipeline
resource "aws_iam_role" "scheduler_role" {
  count = var.enable_pipeline_scheduling ? 1 : 0
  name  = "${local.schedule_group_name}-scheduler-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.schedule_group_name}-scheduler-role"
    Purpose     = "SchedulerPipelineControl"
    Description = "IAM role for EventBridge Scheduler to control pipeline operations"
  })
}

# IAM policy for EventBridge Scheduler to manage pipeline operations
resource "aws_iam_role_policy" "scheduler_pipeline_policy" {
  count = var.enable_pipeline_scheduling ? 1 : 0
  name  = "${local.schedule_group_name}-pipeline-policy"
  role  = aws_iam_role.scheduler_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "osis:StartPipeline",
          "osis:StopPipeline",
          "osis:GetPipeline"
        ]
        Resource = aws_osis_pipeline.data_ingestion_pipeline.pipeline_arn
      }
    ]
  })
}

# EventBridge Scheduler schedule group for organizing pipeline schedules
resource "aws_scheduler_schedule_group" "pipeline_schedules" {
  count = var.enable_pipeline_scheduling ? 1 : 0
  name  = local.schedule_group_name
  
  tags = merge(local.common_tags, {
    Name        = local.schedule_group_name
    Purpose     = "PipelineScheduling"
    Description = "Schedule group for automated pipeline operations"
  })
}

# Schedule to automatically start the ingestion pipeline
resource "aws_scheduler_schedule" "pipeline_start" {
  count      = var.enable_pipeline_scheduling ? 1 : 0
  name       = "start-${local.pipeline_name}"
  group_name = aws_scheduler_schedule_group.pipeline_schedules[0].name
  
  description                 = "Daily start of data ingestion pipeline"
  schedule_expression         = var.pipeline_start_schedule
  schedule_expression_timezone = var.schedule_timezone
  state                       = "ENABLED"
  
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 15
  }
  
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:osis:startPipeline"
    role_arn = aws_iam_role.scheduler_role[0].arn
    
    input = jsonencode({
      PipelineName = aws_osis_pipeline.data_ingestion_pipeline.pipeline_name
    })
    
    retry_policy {
      maximum_retry_attempts   = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Schedule to automatically stop the ingestion pipeline
resource "aws_scheduler_schedule" "pipeline_stop" {
  count      = var.enable_pipeline_scheduling ? 1 : 0
  name       = "stop-${local.pipeline_name}"
  group_name = aws_scheduler_schedule_group.pipeline_schedules[0].name
  
  description                 = "Daily stop of data ingestion pipeline"
  schedule_expression         = var.pipeline_stop_schedule
  schedule_expression_timezone = var.schedule_timezone
  state                       = "ENABLED"
  
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 15
  }
  
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:osis:stopPipeline"
    role_arn = aws_iam_role.scheduler_role[0].arn
    
    input = jsonencode({
      PipelineName = aws_osis_pipeline.data_ingestion_pipeline.pipeline_name
    })
    
    retry_policy {
      maximum_retry_attempts   = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}