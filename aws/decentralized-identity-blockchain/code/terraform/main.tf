# Main Terraform configuration for decentralized identity management blockchain infrastructure

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  suffix = random_string.suffix.result
  
  # Resource names with proper fallbacks
  network_name       = var.network_name != "" ? var.network_name : "${var.project_name}-network-${local.suffix}"
  member_name        = var.member_name != "" ? var.member_name : "${var.project_name}-org-${local.suffix}"
  qldb_ledger_name   = var.qldb_ledger_name != "" ? var.qldb_ledger_name : "${var.project_name}-ledger-${local.suffix}"
  dynamodb_table_name = var.dynamodb_table_name != "" ? var.dynamodb_table_name : "${var.project_name}-credentials-${local.suffix}"
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-identity-${local.suffix}"
  api_name           = var.api_name != "" ? var.api_name : "${var.project_name}-api-${local.suffix}"
  s3_bucket_name     = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-assets-${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Name        = var.project_name
      Environment = var.environment
      Project     = "DecentralizedIdentity"
      ManagedBy   = "Terraform"
      Recipe      = "decentralized-identity-management-blockchain"
    },
    var.additional_tags
  )
}

# Data source for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 bucket for chaincode and schema storage
resource "aws_s3_bucket" "blockchain_assets" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name        = local.s3_bucket_name
    Description = "Storage for blockchain chaincode and identity schemas"
    Purpose     = "ChaincodStorage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "blockchain_assets" {
  count  = var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.blockchain_assets.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "blockchain_assets" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.blockchain_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "blockchain_assets" {
  bucket = aws_s3_bucket.blockchain_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for credential indexing
resource "aws_dynamodb_table" "identity_credentials" {
  name           = local.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "did"
  range_key      = "credential_id"

  attribute {
    name = "did"
    type = "S"
  }

  attribute {
    name = "credential_id"
    type = "S"
  }

  # Global secondary index for querying by credential type
  global_secondary_index {
    name            = "CredentialTypeIndex"
    hash_key        = "credential_type"
    range_key       = "issued_at"
    write_capacity  = var.dynamodb_write_capacity
    read_capacity   = var.dynamodb_read_capacity
    projection_type = "ALL"
  }

  attribute {
    name = "credential_type"
    type = "S"
  }

  attribute {
    name = "issued_at"
    type = "S"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_backups
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.dynamodb_table_name
    Description = "Index for identity credentials and metadata"
    Purpose     = "CredentialIndex"
  })
}

# Auto scaling for DynamoDB table (read capacity)
resource "aws_appautoscaling_target" "dynamodb_read" {
  count              = var.auto_scaling_enabled ? 1 : 0
  max_capacity       = 100
  min_capacity       = var.dynamodb_read_capacity
  resource_id        = "table/${aws_dynamodb_table.identity_credentials.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

# Auto scaling policy for DynamoDB read capacity
resource "aws_appautoscaling_policy" "dynamodb_read" {
  count              = var.auto_scaling_enabled ? 1 : 0
  name               = "${local.dynamodb_table_name}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70.0
  }
}

# QLDB ledger for identity state management
resource "aws_qldb_ledger" "identity_ledger" {
  name                = local.qldb_ledger_name
  permissions_mode    = var.qldb_permissions_mode
  deletion_protection = var.qldb_deletion_protection
  kms_key             = aws_kms_key.qldb_key.arn

  tags = merge(local.common_tags, {
    Name        = local.qldb_ledger_name
    Description = "Cryptographically verifiable ledger for identity state"
    Purpose     = "IdentityState"
  })
}

# KMS key for QLDB encryption
resource "aws_kms_key" "qldb_key" {
  description             = "KMS key for QLDB ledger encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableQLDBAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowQLDBService"
        Effect = "Allow"
        Principal = {
          Service = "qldb.amazonaws.com"
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
    Name        = "${local.qldb_ledger_name}-key"
    Description = "KMS key for QLDB ledger encryption"
    Purpose     = "Encryption"
  })
}

# KMS key alias
resource "aws_kms_alias" "qldb_key" {
  name          = "alias/${local.qldb_ledger_name}-key"
  target_key_id = aws_kms_key.qldb_key.key_id
}

# Managed Blockchain network
resource "aws_managedblockchain_network" "identity_network" {
  name        = local.network_name
  framework   = var.blockchain_framework
  framework_version = var.framework_version

  # Voting policy for network governance
  voting_policy {
    approval_threshold_policy {
      threshold_percentage         = 50
      proposal_duration_in_hours   = 24
      threshold_comparator        = "GREATER_THAN"
    }
  }

  # Initial member configuration
  member_configuration {
    name        = local.member_name
    description = "Identity management organization member"

    member_framework_configuration {
      member_fabric_configuration {
        admin_username = var.admin_username
        admin_password = var.admin_password
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.network_name
    Description = "Hyperledger Fabric network for decentralized identity management"
    Purpose     = "BlockchainNetwork"
  })
}

# Get the member ID from the network
data "aws_managedblockchain_network" "identity_network" {
  id = aws_managedblockchain_network.identity_network.id
}

# Blockchain peer node
resource "aws_managedblockchain_node" "identity_peer" {
  network_id = aws_managedblockchain_network.identity_network.id
  member_id  = data.aws_managedblockchain_network.identity_network.member_blocks[0].id

  node_configuration {
    instance_type    = var.peer_instance_type
    availability_zone = "${var.aws_region}${var.peer_availability_zone}"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.member_name}-peer"
    Description = "Hyperledger Fabric peer node for identity transactions"
    Purpose     = "BlockchainPeer"
  })
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.lambda_function_name}-logs"
    Description = "CloudWatch logs for identity management Lambda function"
    Purpose     = "Logging"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.lambda_function_name}-role"

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

  tags = merge(local.common_tags, {
    Name        = "${local.lambda_function_name}-role"
    Description = "IAM role for identity management Lambda function"
    Purpose     = "LambdaExecution"
  })
}

# IAM policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.lambda_function_name}-policy"
  description = "IAM policy for identity management Lambda function"

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
          "qldb:ExecuteStatement",
          "qldb:StartSession",
          "qldb:SendCommand"
        ]
        Resource = [
          aws_qldb_ledger.identity_ledger.arn,
          "${aws_qldb_ledger.identity_ledger.arn}/*"
        ]
      },
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
          aws_dynamodb_table.identity_credentials.arn,
          "${aws_dynamodb_table.identity_credentials.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "managedblockchain:GetNetwork",
          "managedblockchain:GetMember",
          "managedblockchain:GetNode",
          "managedblockchain:ListMembers",
          "managedblockchain:ListNodes"
        ]
        Resource = [
          aws_managedblockchain_network.identity_network.arn,
          "${aws_managedblockchain_network.identity_network.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.blockchain_assets.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.qldb_key.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.lambda_function_name}-policy"
    Description = "IAM policy for identity management operations"
    Purpose     = "LambdaPermissions"
  })
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_custom" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_role.name
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.js", {
      dynamodb_table_name = aws_dynamodb_table.identity_credentials.name
      qldb_ledger_name   = aws_qldb_ledger.identity_ledger.name
      s3_bucket_name     = aws_s3_bucket.blockchain_assets.bucket
      network_id         = aws_managedblockchain_network.identity_network.id
    })
    filename = "index.js"
  }
}

# Lambda function
resource "aws_lambda_function" "identity_management" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.identity_credentials.name
      QLDB_LEDGER_NAME   = aws_qldb_ledger.identity_ledger.name
      S3_BUCKET_NAME     = aws_s3_bucket.blockchain_assets.bucket
      NETWORK_ID         = aws_managedblockchain_network.identity_network.id
      MEMBER_ID          = data.aws_managedblockchain_network.identity_network.member_blocks[0].id
      NODE_ID            = aws_managedblockchain_node.identity_peer.id
      AWS_REGION         = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_custom,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Lambda function for decentralized identity management operations"
    Purpose     = "IdentityProcessing"
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "identity_api" {
  name        = local.api_name
  description = var.api_description

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name        = local.api_name
    Description = "REST API for decentralized identity management"
    Purpose     = "APIGateway"
  })
}

# API Gateway resource for /identity
resource "aws_api_gateway_resource" "identity_resource" {
  rest_api_id = aws_api_gateway_rest_api.identity_api.id
  parent_id   = aws_api_gateway_rest_api.identity_api.root_resource_id
  path_part   = "identity"
}

# API Gateway method (POST)
resource "aws_api_gateway_method" "identity_post" {
  rest_api_id   = aws_api_gateway_rest_api.identity_api.id
  resource_id   = aws_api_gateway_resource.identity_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "identity_lambda" {
  rest_api_id = aws_api_gateway_rest_api.identity_api.id
  resource_id = aws_api_gateway_resource.identity_resource.id
  http_method = aws_api_gateway_method.identity_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.identity_management.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.identity_management.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.identity_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "identity_api" {
  depends_on = [
    aws_api_gateway_method.identity_post,
    aws_api_gateway_integration.identity_lambda
  ]

  rest_api_id = aws_api_gateway_rest_api.identity_api.id
  stage_name  = var.api_stage_name

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_detailed_monitoring ? 1 : 0
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.api_name}-logs"
    Description = "CloudWatch logs for identity management API Gateway"
    Purpose     = "APILogging"
  })
}

# API Gateway stage with logging
resource "aws_api_gateway_stage" "identity_api" {
  count         = var.enable_detailed_monitoring ? 1 : 0
  deployment_id = aws_api_gateway_deployment.identity_api.id
  rest_api_id   = aws_api_gateway_rest_api.identity_api.id
  stage_name    = var.api_stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
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

  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]

  tags = merge(local.common_tags, {
    Name        = "${local.api_name}-${var.api_stage_name}"
    Description = "API Gateway stage with detailed logging"
    Purpose     = "APIStage"
  })
}

# Cognito User Pool for authentication (optional)
resource "aws_cognito_user_pool" "identity_users" {
  name = "${var.project_name}-users-${local.suffix}"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  username_configuration {
    case_sensitive = false
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-users-${local.suffix}"
    Description = "Cognito User Pool for identity management system users"
    Purpose     = "Authentication"
  })
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "identity_client" {
  name         = "${var.project_name}-client-${local.suffix}"
  user_pool_id = aws_cognito_user_pool.identity_users.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = ["https://localhost:3000/callback"]
  logout_urls                          = ["https://localhost:3000/logout"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_detailed_monitoring ? 1 : 0
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "120"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [] # Add SNS topic ARN for notifications

  dimensions = {
    FunctionName = aws_lambda_function.identity_management.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.lambda_function_name}-errors-alarm"
    Description = "CloudWatch alarm for Lambda function errors"
    Purpose     = "Monitoring"
  })
}

# CloudWatch alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttle" {
  count               = var.enable_detailed_monitoring ? 1 : 0
  alarm_name          = "${local.dynamodb_table_name}-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling events"

  dimensions = {
    TableName = aws_dynamodb_table.identity_credentials.name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.dynamodb_table_name}-throttle-alarm"
    Description = "CloudWatch alarm for DynamoDB throttling"
    Purpose     = "Monitoring"
  })
}