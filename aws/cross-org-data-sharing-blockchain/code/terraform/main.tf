# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  common_tags = merge(
    {
      Project     = "CrossOrgDataSharing"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
  
  unique_suffix = random_id.suffix.hex
  network_name  = "${var.network_name}-${local.unique_suffix}"
  org_a_name    = "${var.organization_a_name}-${local.unique_suffix}"
  org_b_name    = "${var.organization_b_name}-${local.unique_suffix}"
  bucket_name   = "${var.bucket_name_prefix}-${local.unique_suffix}"
}

# S3 Bucket for shared data and chaincode storage
resource "aws_s3_bucket" "cross_org_data" {
  bucket = local.bucket_name

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "cross_org_data" {
  bucket = aws_s3_bucket.cross_org_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cross_org_data" {
  bucket = aws_s3_bucket.cross_org_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cross_org_data" {
  bucket = aws_s3_bucket.cross_org_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for audit trail
resource "aws_dynamodb_table" "audit_trail" {
  name           = var.audit_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.audit_table_read_capacity
  write_capacity = var.audit_table_write_capacity
  hash_key       = "TransactionId"
  range_key      = "Timestamp"

  attribute {
    name = "TransactionId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "N"
  }

  tags = local.common_tags
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "CrossOrgDataSharingLambdaRole-${local.unique_suffix}"

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

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "CrossOrgLambdaPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.audit_trail.arn
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.cross_org_data.arn}/*"
      }
    ]
  })
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content = templatefile("${path.module}/lambda_function.js", {
      bucket_name = local.bucket_name
    })
    filename = "index.js"
  }
}

# Lambda function for data validation and event processing
resource "aws_lambda_function" "data_validator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${local.unique_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.cross_org_data.bucket
      TABLE_NAME  = aws_dynamodb_table.audit_trail.name
    }
  }

  tags = local.common_tags
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.data_validator.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# SNS topic for cross-organization notifications
resource "aws_sns_topic" "notifications" {
  name = "${var.sns_topic_name}-${local.unique_suffix}"

  tags = local.common_tags
}

# EventBridge rule for data sharing events
resource "aws_cloudwatch_event_rule" "data_sharing_events" {
  name        = "${var.eventbridge_rule_name}-${local.unique_suffix}"
  description = "Rule for cross-organization data sharing events"

  event_pattern = jsonencode({
    source      = ["cross-org.blockchain"]
    detail-type = [
      "DataSharingAgreementCreated",
      "OrganizationJoinedAgreement",
      "DataShared",
      "DataAccessed"
    ]
  })

  tags = local.common_tags
}

# EventBridge target for SNS
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.data_sharing_events.name
  target_id = "SNSTarget"
  arn       = aws_sns_topic.notifications.arn
}

# SNS topic policy to allow EventBridge to publish
resource "aws_sns_topic_policy" "notifications_policy" {
  arn = aws_sns_topic.notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# Managed Blockchain Network
resource "aws_managedblockchain_network" "cross_org_network" {
  name        = local.network_name
  description = var.network_description
  framework   = var.blockchain_framework
  framework_version = var.framework_version

  framework_configuration {
    network_fabric_configuration {
      edition = var.network_edition
    }
  }

  voting_policy {
    approval_threshold_policy {
      threshold_percentage      = var.voting_threshold_percentage
      proposal_duration_in_hours = var.proposal_duration_hours
      threshold_comparator      = "GREATER_THAN"
    }
  }

  member_configuration {
    name        = local.org_a_name
    description = var.organization_a_description

    member_fabric_configuration {
      admin_username = var.admin_username
      admin_password = var.admin_password
    }
  }

  tags = local.common_tags
}

# Get the first member ID (Organization A)
data "aws_managedblockchain_member" "org_a" {
  network_id = aws_managedblockchain_network.cross_org_network.id
  name       = local.org_a_name
  
  depends_on = [aws_managedblockchain_network.cross_org_network]
}

# Peer node for Organization A
resource "aws_managedblockchain_node" "org_a_node" {
  network_id = aws_managedblockchain_network.cross_org_network.id
  member_id  = data.aws_managedblockchain_member.org_a.id

  node_configuration {
    instance_type    = var.node_instance_type
    availability_zone = "${data.aws_region.current.name}a"
  }

  tags = local.common_tags
}

# IAM policy for cross-organization access control
resource "aws_iam_policy" "cross_org_access" {
  name        = "CrossOrgDataSharingAccessPolicy-${local.unique_suffix}"
  description = "Policy for cross-organization data sharing access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "managedblockchain:GetNetwork",
          "managedblockchain:GetMember",
          "managedblockchain:GetNode",
          "managedblockchain:ListMembers",
          "managedblockchain:ListNodes"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "managedblockchain:NetworkId" = aws_managedblockchain_network.cross_org_network.id
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.cross_org_data.arn}/agreements/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.audit_trail.arn
      }
    ]
  })

  tags = local.common_tags
}

# CloudWatch Dashboard (optional)
resource "aws_cloudwatch_dashboard" "cross_org_monitoring" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "CrossOrgDataSharing-${local.unique_suffix}"

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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.data_validator.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.data_validator.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.data_validator.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Cross-Organization Data Processing Metrics"
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
            ["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.data_sharing_events.name],
            ["AWS/Events", "InvocationsCount", "RuleName", aws_cloudwatch_event_rule.data_sharing_events.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Cross-Organization Event Processing"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.audit_trail.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.audit_trail.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Audit Trail Storage Metrics"
        }
      }
    ]
  })
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "CrossOrg-Lambda-Errors-${local.unique_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.data_validator.function_name
  }

  tags = local.common_tags
}

# Lambda function code template
resource "local_file" "lambda_function_code" {
  content = templatefile("${path.module}/lambda_function.js.tpl", {
    bucket_name = local.bucket_name
  })
  filename = "${path.module}/lambda_function.js"
}