# Data sources for account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate unique names for resources
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-data-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# KMS Key for encryption
resource "aws_kms_key" "voting_system_key" {
  description             = "KMS key for blockchain voting system encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = var.enable_kms_key_rotation
  
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
        Sid    = "Allow Lambda Functions"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-encryption-key"
  })
}

resource "aws_kms_alias" "voting_system_key_alias" {
  name          = "alias/${var.project_name}-encryption-key"
  target_key_id = aws_kms_key.voting_system_key.key_id
}

# S3 Bucket for voting system data
resource "aws_s3_bucket" "voting_system_data" {
  bucket = local.bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-data-bucket"
  })
}

resource "aws_s3_bucket_versioning" "voting_system_data" {
  bucket = aws_s3_bucket.voting_system_data.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_encryption" "voting_system_data" {
  bucket = aws_s3_bucket.voting_system_data.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.voting_system_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "voting_system_data" {
  bucket = aws_s3_bucket.voting_system_data.id

  rule {
    id     = "voting_data_lifecycle"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_public_access_block" "voting_system_data" {
  bucket = aws_s3_bucket.voting_system_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for Voter Registry
resource "aws_dynamodb_table" "voter_registry" {
  name           = "VoterRegistry"
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "VoterId"
  range_key      = "ElectionId"

  attribute {
    name = "VoterId"
    type = "S"
  }

  attribute {
    name = "ElectionId"
    type = "S"
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.voting_system_key.arn : null
  }

  point_in_time_recovery {
    enabled = var.enable_dynamodb_backup
  }

  tags = merge(local.common_tags, {
    Name = "VoterRegistry"
  })
}

# DynamoDB Table for Elections
resource "aws_dynamodb_table" "elections" {
  name           = "Elections"
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "ElectionId"

  attribute {
    name = "ElectionId"
    type = "S"
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.voting_system_key.arn : null
  }

  point_in_time_recovery {
    enabled = var.enable_dynamodb_backup
  }

  tags = merge(local.common_tags, {
    Name = "Elections"
  })
}

# Cognito User Pool for voter authentication
resource "aws_cognito_user_pool" "voter_pool" {
  name = "${var.project_name}-voter-pool"

  password_policy {
    minimum_length                   = var.cognito_password_policy.minimum_length
    require_lowercase                = var.cognito_password_policy.require_lowercase
    require_numbers                  = var.cognito_password_policy.require_numbers
    require_symbols                  = var.cognito_password_policy.require_symbols
    require_uppercase                = var.cognito_password_policy.require_uppercase
    temporary_password_validity_days = var.cognito_password_policy.temporary_password_validity_days
  }

  mfa_configuration = var.cognito_mfa_configuration

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-voter-pool"
  })
}

resource "aws_cognito_user_pool_client" "voter_pool_client" {
  name         = "${var.project_name}-voter-client"
  user_pool_id = aws_cognito_user_pool.voter_pool.id

  generate_secret = false
  
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Policy for Lambda Functions
resource "aws_iam_role_policy" "lambda_voting_policy" {
  name = "${var.project_name}-lambda-voting-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.voter_registry.arn,
          aws_dynamodb_table.elections.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.voting_system_data.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.voting_system_key.arn
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
          "sns:Publish"
        ]
        Resource = aws_sns_topic.voting_notifications.arn
      }
    ]
  })
}

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "voter_auth_logs" {
  name              = "/aws/lambda/${var.project_name}-voter-auth"
  retention_in_days = var.lambda_log_retention_days
  kms_key_id        = aws_kms_key.voting_system_key.arn
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "vote_monitor_logs" {
  name              = "/aws/lambda/${var.project_name}-vote-monitor"
  retention_in_days = var.lambda_log_retention_days
  kms_key_id        = aws_kms_key.voting_system_key.arn
  
  tags = local.common_tags
}

# Lambda Function for Voter Authentication
resource "aws_lambda_function" "voter_auth" {
  filename         = "voter-auth-lambda.zip"
  function_name    = "${var.project_name}-voter-auth"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "voter-auth-lambda.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      KMS_KEY_ID       = aws_kms_key.voting_system_key.key_id
      VOTER_TABLE_NAME = aws_dynamodb_table.voter_registry.name
      BUCKET_NAME      = aws_s3_bucket.voting_system_data.bucket
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.voter_auth_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_voting_policy
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-voter-auth"
  })
}

# Lambda Function for Vote Monitoring
resource "aws_lambda_function" "vote_monitor" {
  filename         = "vote-monitor-lambda.zip"
  function_name    = "${var.project_name}-vote-monitor"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "vote-monitor-lambda.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      BUCKET_NAME          = aws_s3_bucket.voting_system_data.bucket
      ELECTIONS_TABLE_NAME = aws_dynamodb_table.elections.name
      SNS_TOPIC_ARN        = aws_sns_topic.voting_notifications.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.vote_monitor_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_voting_policy
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vote-monitor"
  })
}

# SNS Topic for Voting Notifications
resource "aws_sns_topic" "voting_notifications" {
  name              = "${var.project_name}-notifications"
  kms_master_key_id = aws_kms_key.voting_system_key.key_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-notifications"
  })
}

# SNS Topic Subscription (if email is provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.voting_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge Rule for Voting Events
resource "aws_cloudwatch_event_rule" "voting_events" {
  name        = "${var.project_name}-voting-events"
  description = "Rule for blockchain voting system events"

  event_pattern = jsonencode({
    source      = ["voting.blockchain"]
    detail-type = [
      "VoteCast",
      "ElectionCreated",
      "ElectionEnded",
      "CandidateRegistered"
    ]
  })

  tags = local.common_tags
}

# EventBridge Target for SNS
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.voting_events.name
  target_id = "VotingEventsSNSTarget"
  arn       = aws_sns_topic.voting_notifications.arn
}

# EventBridge Target for Vote Monitor Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.voting_events.name
  target_id = "VotingEventsLambdaTarget"
  arn       = aws_lambda_function.vote_monitor.arn
}

# EventBridge Archive
resource "aws_cloudwatch_event_archive" "voting_events_archive" {
  count            = var.enable_eventbridge_archive ? 1 : 0
  name             = "${var.project_name}-events-archive"
  event_source_arn = aws_cloudwatch_event_rule.voting_events.arn
  retention_days   = var.eventbridge_archive_retention_days
  description      = "Archive for blockchain voting system events"
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vote_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.voting_events.arn
}

# SNS Topic Policy for EventBridge
resource "aws_sns_topic_policy" "voting_notifications_policy" {
  arn = aws_sns_topic.voting_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.voting_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "voting_api" {
  name        = "${var.project_name}-api"
  description = "API for blockchain voting system"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway Resource
resource "aws_api_gateway_resource" "auth_resource" {
  rest_api_id = aws_api_gateway_rest_api.voting_api.id
  parent_id   = aws_api_gateway_rest_api.voting_api.root_resource_id
  path_part   = "auth"
}

# API Gateway Method
resource "aws_api_gateway_method" "auth_post" {
  rest_api_id   = aws_api_gateway_rest_api.voting_api.id
  resource_id   = aws_api_gateway_resource.auth_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "auth_integration" {
  rest_api_id = aws_api_gateway_rest_api.voting_api.id
  resource_id = aws_api_gateway_resource.auth_resource.id
  http_method = aws_api_gateway_method.auth_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.voter_auth.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.voter_auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.voting_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "voting_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.voting_api.id
  stage_name  = var.api_gateway_stage_name

  depends_on = [
    aws_api_gateway_method.auth_post,
    aws_api_gateway_integration.auth_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "voting_api_stage" {
  deployment_id = aws_api_gateway_deployment.voting_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.voting_api.id
  stage_name    = var.api_gateway_stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.common_tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.project_name}-api"
  retention_in_days = var.cloudwatch_log_group_retention_days
  kms_key_id        = aws_kms_key.voting_system_key.arn

  tags = local.common_tags
}

# API Gateway Method Settings
resource "aws_api_gateway_method_settings" "voting_api_settings" {
  rest_api_id = aws_api_gateway_rest_api.voting_api.id
  stage_name  = aws_api_gateway_stage.voting_api_stage.stage_name
  method_path = "*/*"

  settings {
    logging_level          = var.enable_api_gateway_logging ? "INFO" : "OFF"
    data_trace_enabled     = var.enable_detailed_monitoring
    metrics_enabled        = var.enable_detailed_monitoring
    throttling_rate_limit  = var.api_gateway_throttle_rate_limit
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "voting_system_dashboard" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.voter_auth.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.voter_auth.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.voter_auth.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Voter Authentication Metrics"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.vote_monitor.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.vote_monitor.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.vote_monitor.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Vote Monitoring Metrics"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.voting_events.name],
            ["AWS/Events", "InvocationsCount", "RuleName", aws_cloudwatch_event_rule.voting_events.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Voting Event Processing"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.voter_registry.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.voter_registry.name],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.elections.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.elections.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Database Activity"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "voter_auth_errors" {
  alarm_name          = "${var.project_name}-auth-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors voter authentication errors"
  alarm_actions       = [aws_sns_topic.voting_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.voter_auth.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "vote_monitor_errors" {
  alarm_name          = "${var.project_name}-monitor-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors vote monitoring errors"
  alarm_actions       = [aws_sns_topic.voting_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.vote_monitor.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${var.project_name}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = [aws_sns_topic.voting_notifications.arn]

  dimensions = {
    TableName = aws_dynamodb_table.voter_registry.name
  }

  tags = local.common_tags
}

# NOTE: Amazon Managed Blockchain resources cannot be created via Terraform
# as there is no official provider support. These would need to be created
# manually via AWS CLI or Console. The following output provides the
# necessary information for manual creation.

# Placeholder for blockchain node creation instructions
locals {
  blockchain_creation_instructions = <<-EOT
    # Create Ethereum blockchain node manually using AWS CLI:
    
    aws managedblockchain create-node \
        --node-configuration '{
            "NodeConfiguration": {
                "InstanceType": "${var.blockchain_node_instance_type}",
                "AvailabilityZone": "${data.aws_region.current.name}a"
            }
        }' \
        --network-type ${var.blockchain_network_type} \
        --network-configuration '{
            "Ethereum": {
                "Network": "${var.ethereum_network}",
                "NodeConfiguration": {
                    "InstanceType": "${var.blockchain_node_instance_type}"
                }
            }
        }'
  EOT
}