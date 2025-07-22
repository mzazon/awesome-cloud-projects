# Amazon Connect Contact Center Infrastructure
# This Terraform configuration deploys a complete contact center solution using Amazon Connect

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  instance_alias = var.connect_instance_alias != "" ? var.connect_instance_alias : "contact-center-${random_string.suffix.result}"
  bucket_name    = "${var.s3_bucket_prefix}-${data.aws_caller_identity.current.account_id}-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "CustomContactCenter"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# S3 Bucket for call recordings and chat transcripts
resource "aws_s3_bucket" "connect_recordings" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = "Connect Recordings Bucket"
    Purpose     = "CallRecordings"
    Compliance  = "Enabled"
  })
}

# S3 bucket versioning for data protection
resource "aws_s3_bucket_versioning" "connect_recordings_versioning" {
  bucket = aws_s3_bucket.connect_recordings.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for security compliance
resource "aws_s3_bucket_server_side_encryption_configuration" "connect_recordings_encryption" {
  bucket = aws_s3_bucket.connect_recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "connect_recordings_pab" {
  bucket = aws_s3_bucket.connect_recordings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "connect_recordings_lifecycle" {
  count  = var.s3_lifecycle_config.enabled ? 1 : 0
  bucket = aws_s3_bucket.connect_recordings.id

  rule {
    id     = "recordings_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access storage class
    transition {
      days          = var.s3_lifecycle_config.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier for long-term archival
    transition {
      days          = var.s3_lifecycle_config.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Expiration for compliance (7 years default)
    expiration {
      days = var.s3_lifecycle_config.expiration_days
    }
  }
}

# IAM role for Amazon Connect service
resource "aws_iam_role" "connect_service_role" {
  name = "AmazonConnect-ServiceRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "connect.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Connect Service Role"
  })
}

# IAM policy for S3 access (call recordings)
resource "aws_iam_role_policy" "connect_s3_policy" {
  name = "ConnectS3AccessPolicy"
  role = aws_iam_role.connect_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.connect_recordings.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.connect_recordings.arn
      }
    ]
  })
}

# IAM policy for CloudWatch logs access
resource "aws_iam_role_policy" "connect_cloudwatch_policy" {
  name = "ConnectCloudWatchLogsPolicy"
  role = aws_iam_role.connect_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/connect/*"
      }
    ]
  })
}

# Amazon Connect Instance - the core contact center infrastructure
resource "aws_connect_instance" "contact_center" {
  identity_management_type = "CONNECT_MANAGED"
  instance_alias          = local.instance_alias
  inbound_calls_enabled   = var.enable_inbound_calls
  outbound_calls_enabled  = var.enable_outbound_calls

  tags = merge(local.common_tags, {
    Name = "Contact Center Instance"
  })
}

# Enable contact flow logging for troubleshooting and analytics
resource "aws_connect_instance_attribute" "contact_flow_logs" {
  count        = var.enable_contact_flow_logs ? 1 : 0
  instance_id  = aws_connect_instance.contact_center.id
  attribute_type = "CONTACTFLOW_LOGS"
  value        = "true"
}

# Enable Contact Lens for AI-powered conversation analytics
resource "aws_connect_instance_attribute" "contact_lens" {
  count        = var.enable_contact_lens ? 1 : 0
  instance_id  = aws_connect_instance.contact_center.id
  attribute_type = "CONTACT_LENS"
  value        = "true"
}

# Storage configuration for call recordings
resource "aws_connect_instance_storage_config" "call_recordings" {
  instance_id   = aws_connect_instance.contact_center.id
  resource_type = "CALL_RECORDINGS"

  storage_config {
    s3_config {
      bucket_name   = aws_s3_bucket.connect_recordings.bucket
      bucket_prefix = "call-recordings/"
    }
    storage_type = "S3"
  }
}

# Storage configuration for chat transcripts
resource "aws_connect_instance_storage_config" "chat_transcripts" {
  instance_id   = aws_connect_instance.contact_center.id
  resource_type = "CHAT_TRANSCRIPTS"

  storage_config {
    s3_config {
      bucket_name   = aws_s3_bucket.connect_recordings.bucket
      bucket_prefix = "chat-transcripts/"
    }
    storage_type = "S3"
  }
}

# Data source to get default hours of operation
data "aws_connect_hours_of_operation" "basic" {
  instance_id = aws_connect_instance.contact_center.id
  name        = "Basic Hours"
}

# Customer service queue for routing incoming contacts
resource "aws_connect_queue" "customer_service" {
  instance_id           = aws_connect_instance.contact_center.id
  name                  = var.queue_config.name
  description           = var.queue_config.description
  hours_of_operation_id = data.aws_connect_hours_of_operation.basic.hours_of_operation_id
  max_contacts          = var.queue_config.max_contacts

  tags = merge(local.common_tags, {
    Name    = "Customer Service Queue"
    Purpose = "CustomerService"
  })
}

# Data sources for default security profiles
data "aws_connect_security_profile" "admin" {
  instance_id = aws_connect_instance.contact_center.id
  name        = "Admin"
}

data "aws_connect_security_profile" "agent" {
  instance_id = aws_connect_instance.contact_center.id
  name        = "Agent"
}

# Data source for default routing profile
data "aws_connect_routing_profile" "basic" {
  instance_id = aws_connect_instance.contact_center.id
  name        = "Basic Routing Profile"
}

# Administrative user with full management capabilities
resource "aws_connect_user" "admin" {
  instance_id = aws_connect_instance.contact_center.id
  name        = var.admin_user_config.username
  password    = var.admin_user_config.password

  identity_info {
    first_name = var.admin_user_config.first_name
    last_name  = var.admin_user_config.last_name
  }

  phone_config {
    phone_type                    = "SOFT_PHONE"
    auto_accept                   = false
    after_contact_work_time_limit = 120
  }

  security_profile_ids = [data.aws_connect_security_profile.admin.security_profile_id]
  routing_profile_id   = data.aws_connect_routing_profile.basic.routing_profile_id

  tags = merge(local.common_tags, {
    Name = "Admin User"
    Role = "Administrator"
  })
}

# Routing profile for customer service agents
resource "aws_connect_routing_profile" "customer_service_agents" {
  instance_id               = aws_connect_instance.contact_center.id
  name                      = var.routing_profile_config.name
  description               = var.routing_profile_config.description
  default_outbound_queue_id = aws_connect_queue.customer_service.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = var.routing_profile_config.voice_concurrency
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.customer_service.queue_id
  }

  tags = merge(local.common_tags, {
    Name = "Customer Service Routing Profile"
  })
}

# Customer service agent user
resource "aws_connect_user" "agent" {
  instance_id = aws_connect_instance.contact_center.id
  name        = var.agent_user_config.username
  password    = var.agent_user_config.password

  identity_info {
    first_name = var.agent_user_config.first_name
    last_name  = var.agent_user_config.last_name
  }

  phone_config {
    phone_type                    = "SOFT_PHONE"
    auto_accept                   = var.routing_profile_config.auto_accept
    after_contact_work_time_limit = var.routing_profile_config.after_contact_work_timeout
  }

  security_profile_ids = [data.aws_connect_security_profile.agent.security_profile_id]
  routing_profile_id   = aws_connect_routing_profile.customer_service_agents.routing_profile_id

  tags = merge(local.common_tags, {
    Name = "Service Agent"
    Role = "Agent"
  })
}

# Contact flow for handling incoming customer calls
resource "aws_connect_contact_flow" "customer_service_flow" {
  instance_id = aws_connect_instance.contact_center.id
  name        = var.contact_flow_config.name
  description = var.contact_flow_config.description
  type        = var.contact_flow_config.type

  content = jsonencode({
    Version = "2019-10-30"
    StartAction = "12345678-1234-1234-1234-123456789012"
    Metadata = {
      entryPointPosition = { x = 20, y = 20 }
      snapToGrid = false
      ActionMetadata = {
        "12345678-1234-1234-1234-123456789012" = {
          position = { x = 178, y = 52 }
        }
        "87654321-4321-4321-4321-210987654321" = {
          position = { x = 392, y = 154 }
        }
        "11111111-2222-3333-4444-555555555555" = {
          position = { x = 626, y = 154 }
        }
      }
    }
    Actions = [
      {
        Identifier = "12345678-1234-1234-1234-123456789012"
        Type = "MessageParticipant"
        Parameters = {
          Text = "Thank you for calling our customer service. Please wait while we connect you to an available agent."
        }
        Transitions = {
          NextAction = "87654321-4321-4321-4321-210987654321"
        }
      },
      {
        Identifier = "87654321-4321-4321-4321-210987654321"
        Type = "SetRecordingBehavior"
        Parameters = {
          RecordingBehaviorOption = "Enable"
          RecordingParticipantOption = "Both"
        }
        Transitions = {
          NextAction = "11111111-2222-3333-4444-555555555555"
        }
      },
      {
        Identifier = "11111111-2222-3333-4444-555555555555"
        Type = "TransferToQueue"
        Parameters = {
          QueueId = aws_connect_queue.customer_service.queue_id
        }
        Transitions = {}
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Customer Service Contact Flow"
  })
}

# CloudWatch dashboard for monitoring contact center metrics
resource "aws_cloudwatch_dashboard" "connect_dashboard" {
  count          = var.cloudwatch_dashboard_config.enabled ? 1 : 0
  dashboard_name = "${var.cloudwatch_dashboard_config.name}-${random_string.suffix.result}"

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
            ["AWS/Connect", "ContactsReceived", "InstanceId", aws_connect_instance.contact_center.id],
            [".", "ContactsHandled", ".", "."],
            [".", "ContactsAbandoned", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Contact Center Metrics"
          view   = "timeSeries"
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
            ["AWS/Connect", "ContactsQueued", "InstanceId", aws_connect_instance.contact_center.id, "QueueName", aws_connect_queue.customer_service.name],
            [".", "LongestQueueWaitTime", ".", ".", ".", "."],
            [".", "QueueCapacityExceededError", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Queue Performance Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# CloudWatch log group for Connect instance logs
resource "aws_cloudwatch_log_group" "connect_logs" {
  name              = "/aws/connect/${aws_connect_instance.contact_center.id}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "Connect Instance Logs"
  })
}