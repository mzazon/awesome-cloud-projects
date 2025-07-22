# Multi-Region Aurora DSQL Application Infrastructure
# This configuration creates a globally distributed serverless application using Aurora DSQL
# across multiple AWS regions with Lambda functions and API Gateway

# =============================================================================
# DATA SOURCES AND LOCALS
# =============================================================================

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Get available AZs for each region
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Common naming convention
  name_prefix = "${var.cluster_name_prefix}-${random_id.suffix.hex}"
  
  # Aurora DSQL cluster names
  primary_cluster_name   = "${local.name_prefix}-primary"
  secondary_cluster_name = "${local.name_prefix}-secondary"
  
  # Lambda function names
  primary_lambda_name   = "${var.lambda_function_name_prefix}-${random_id.suffix.hex}-primary"
  secondary_lambda_name = "${var.lambda_function_name_prefix}-${random_id.suffix.hex}-secondary"
  
  # API Gateway names
  primary_api_name   = "${var.api_gateway_name_prefix}-${random_id.suffix.hex}-primary"
  secondary_api_name = "${var.api_gateway_name_prefix}-${random_id.suffix.hex}-secondary"
  
  # Common tags
  common_tags = merge(
    {
      Environment   = var.environment
      Application   = "multi-region-aurora-dsql"
      DeployedBy    = "terraform"
      Recipe        = "building-multi-region-applications-aurora-dsql"
      CostCenter    = var.cost_center
      ProjectName   = var.project_name
      Owner         = var.owner
      PrimaryRegion = var.primary_region
      SecondaryRegion = var.secondary_region
      WitnessRegion = var.witness_region
    },
    var.additional_tags
  )
}

# =============================================================================
# AURORA DSQL CLUSTERS
# =============================================================================

# Primary Aurora DSQL Cluster in us-east-1
resource "aws_dsql_cluster" "primary" {
  provider = aws.primary
  
  cluster_identifier  = local.primary_cluster_name
  deletion_protection = var.enable_deletion_protection
  
  # Multi-region configuration with witness region
  multi_region_properties {
    witness_region = var.witness_region
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.primary_cluster_name
      Region = var.primary_region
      Type   = "primary"
    }
  )
}

# Secondary Aurora DSQL Cluster in us-east-2
resource "aws_dsql_cluster" "secondary" {
  provider = aws.secondary
  
  cluster_identifier  = local.secondary_cluster_name
  deletion_protection = var.enable_deletion_protection
  
  # Multi-region configuration with witness region
  multi_region_properties {
    witness_region = var.witness_region
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.secondary_cluster_name
      Region = var.secondary_region
      Type   = "secondary"
    }
  )
}

# Note: Aurora DSQL cluster peering is handled automatically when clusters 
# are created with the same witness region. The clusters will peer themselves
# once they are both active and share the witness region configuration.

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM role for Lambda functions to access Aurora DSQL
resource "aws_iam_role" "lambda_execution_role" {
  name = "MultiRegionLambdaRole-${random_id.suffix.hex}"
  
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
  
  tags = merge(
    local.common_tags,
    {
      Name = "MultiRegionLambdaRole-${random_id.suffix.hex}"
      Type = "lambda-execution-role"
    }
  )
}

# Basic Lambda execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# VPC execution policy attachment (if Lambda is deployed in VPC)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count      = length(var.lambda_subnet_ids) > 0 ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# X-Ray tracing policy attachment
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_xray_tracing ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom IAM policy for Aurora DSQL access
resource "aws_iam_policy" "aurora_dsql_policy" {
  name        = "AuroraDSQLPolicy-${random_id.suffix.hex}"
  description = "Aurora DSQL access policy for Lambda functions"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect",
          "dsql:DbConnectAdmin",
          "dsql:DescribeCluster",
          "dsql:GetCluster"
        ]
        Resource = [
          aws_dsql_cluster.primary.arn,
          aws_dsql_cluster.secondary.arn,
          "${aws_dsql_cluster.primary.arn}/*",
          "${aws_dsql_cluster.secondary.arn}/*"
        ]
      }
    ]
  })
  
  tags = merge(
    local.common_tags,
    {
      Name = "AuroraDSQLPolicy-${random_id.suffix.hex}"
      Type = "aurora-dsql-policy"
    }
  )
}

# Attach Aurora DSQL policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "aurora_dsql_policy_attachment" {
  policy_arn = aws_iam_policy.aurora_dsql_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# =============================================================================
# LAMBDA FUNCTION CODE PACKAGING
# =============================================================================

# Create Lambda function source code
resource "local_file" "lambda_function_code" {
  filename = "${path.module}/lambda_function.py"
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    primary_endpoint   = aws_dsql_cluster.primary.endpoint
    secondary_endpoint = aws_dsql_cluster.secondary.endpoint
    database_name      = var.database_name
  })
}

# Create requirements.txt for Lambda dependencies
resource "local_file" "lambda_requirements" {
  filename = "${path.module}/requirements.txt"
  content  = <<-EOT
    boto3==1.34.131
    botocore==1.34.131
    psycopg2-binary==2.9.7
  EOT
}

# Package Lambda function code
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      database_name = var.database_name
    })
    filename = "lambda_function.py"
  }
  
  source {
    content  = local_file.lambda_requirements.content
    filename = "requirements.txt"
  }
  
  depends_on = [
    local_file.lambda_function_code,
    local_file.lambda_requirements
  ]
}

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

# CloudWatch log group for primary Lambda function
resource "aws_cloudwatch_log_group" "primary_lambda_logs" {
  provider = aws.primary
  
  name              = "/aws/lambda/${local.primary_lambda_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(
    local.common_tags,
    {
      Name   = "/aws/lambda/${local.primary_lambda_name}"
      Region = var.primary_region
      Type   = "lambda-logs"
    }
  )
}

# CloudWatch log group for secondary Lambda function
resource "aws_cloudwatch_log_group" "secondary_lambda_logs" {
  provider = aws.secondary
  
  name              = "/aws/lambda/${local.secondary_lambda_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(
    local.common_tags,
    {
      Name   = "/aws/lambda/${local.secondary_lambda_name}"
      Region = var.secondary_region
      Type   = "lambda-logs"
    }
  )
}

# =============================================================================
# LAMBDA FUNCTIONS
# =============================================================================

# Lambda function in primary region
resource "aws_lambda_function" "primary" {
  provider = aws.primary
  
  function_name = local.primary_lambda_name
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  # Environment variables
  environment {
    variables = merge(
      {
        DSQL_ENDPOINT = aws_dsql_cluster.primary.endpoint
        AWS_REGION    = var.primary_region
        DATABASE_NAME = var.database_name
        REGION_TYPE   = "primary"
      },
      var.lambda_environment_variables
    )
  }
  
  # VPC configuration (if specified)
  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  # Reserved concurrency
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  
  # Lambda layers
  layers = var.lambda_layer_arns
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.primary_lambda_name
      Region = var.primary_region
      Type   = "primary-lambda"
    }
  )
  
  depends_on = [
    aws_cloudwatch_log_group.primary_lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.aurora_dsql_policy_attachment
  ]
}

# Lambda function in secondary region
resource "aws_lambda_function" "secondary" {
  provider = aws.secondary
  
  function_name = local.secondary_lambda_name
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  # Environment variables
  environment {
    variables = merge(
      {
        DSQL_ENDPOINT = aws_dsql_cluster.secondary.endpoint
        AWS_REGION    = var.secondary_region
        DATABASE_NAME = var.database_name
        REGION_TYPE   = "secondary"
      },
      var.lambda_environment_variables
    )
  }
  
  # VPC configuration (if specified)
  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  # Reserved concurrency
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  
  # Lambda layers
  layers = var.lambda_layer_arns
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.secondary_lambda_name
      Region = var.secondary_region
      Type   = "secondary-lambda"
    }
  )
  
  depends_on = [
    aws_cloudwatch_log_group.secondary_lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.aurora_dsql_policy_attachment
  ]
}

# =============================================================================
# API GATEWAY REST APIS
# =============================================================================

# API Gateway REST API in primary region
resource "aws_api_gateway_rest_api" "primary" {
  provider = aws.primary
  
  name        = local.primary_api_name
  description = "Multi-region API - Primary"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.primary_api_name
      Region = var.primary_region
      Type   = "primary-api"
    }
  )
}

# API Gateway REST API in secondary region
resource "aws_api_gateway_rest_api" "secondary" {
  provider = aws.secondary
  
  name        = local.secondary_api_name
  description = "Multi-region API - Secondary"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.secondary_api_name
      Region = var.secondary_region
      Type   = "secondary-api"
    }
  )
}

# =============================================================================
# API GATEWAY RESOURCES AND METHODS
# =============================================================================

# Primary API Gateway resources and methods
module "primary_api_gateway" {
  source = "./modules/api_gateway"
  
  providers = {
    aws = aws.primary
  }
  
  api_id                = aws_api_gateway_rest_api.primary.id
  lambda_arn            = aws_lambda_function.primary.arn
  lambda_name           = aws_lambda_function.primary.function_name
  region                = var.primary_region
  account_id            = data.aws_caller_identity.current.account_id
  stage_name            = var.api_gateway_stage_name
  enable_logging        = var.enable_api_gateway_logging
  cors_origins          = var.cors_allow_origins
  cors_headers          = var.cors_allow_headers
  cors_methods          = var.cors_allow_methods
  throttle_rate_limit   = var.api_gateway_throttle_rate_limit
  throttle_burst_limit  = var.api_gateway_throttle_burst_limit
  api_key_required      = var.enable_api_key_required
  
  tags = local.common_tags
}

# Secondary API Gateway resources and methods
module "secondary_api_gateway" {
  source = "./modules/api_gateway"
  
  providers = {
    aws = aws.secondary
  }
  
  api_id                = aws_api_gateway_rest_api.secondary.id
  lambda_arn            = aws_lambda_function.secondary.arn
  lambda_name           = aws_lambda_function.secondary.function_name
  region                = var.secondary_region
  account_id            = data.aws_caller_identity.current.account_id
  stage_name            = var.api_gateway_stage_name
  enable_logging        = var.enable_api_gateway_logging
  cors_origins          = var.cors_allow_origins
  cors_headers          = var.cors_allow_headers
  cors_methods          = var.cors_allow_methods
  throttle_rate_limit   = var.api_gateway_throttle_rate_limit
  throttle_burst_limit  = var.api_gateway_throttle_burst_limit
  api_key_required      = var.enable_api_key_required
  
  tags = local.common_tags
}

# =============================================================================
# LAMBDA PERMISSIONS FOR API GATEWAY
# =============================================================================

# Lambda permission for primary API Gateway
resource "aws_lambda_permission" "primary_api_gateway" {
  provider = aws.primary
  
  statement_id  = "apigateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.primary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.primary.execution_arn}/*/*/*"
}

# Lambda permission for secondary API Gateway
resource "aws_lambda_permission" "secondary_api_gateway" {
  provider = aws.secondary
  
  statement_id  = "apigateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secondary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secondary.execution_arn}/*/*/*"
}

# =============================================================================
# DATABASE INITIALIZATION
# =============================================================================

# Database initialization Lambda function
resource "aws_lambda_function" "db_init" {
  provider = aws.primary
  
  function_name = "${local.name_prefix}-db-init"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "init_db.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = 60
  memory_size  = 256
  
  filename = data.archive_file.db_init_package.output_path
  source_code_hash = data.archive_file.db_init_package.output_base64sha256
  
  environment {
    variables = {
      DSQL_ENDPOINT    = aws_dsql_cluster.primary.endpoint
      DATABASE_NAME    = var.database_name
      CREATE_SAMPLE_DATA = var.create_sample_data ? "true" : "false"
    }
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-db-init"
      Type = "db-initialization"
    }
  )
  
  depends_on = [
    aws_dsql_cluster.primary,
    aws_dsql_cluster.secondary
  ]
}

# Database initialization Lambda package
data "archive_file" "db_init_package" {
  type        = "zip"
  output_path = "${path.module}/db-init-function.zip"
  
  source {
    content = templatefile("${path.module}/init_db.py.tpl", {
      database_name      = var.database_name
      create_sample_data = var.create_sample_data
    })
    filename = "init_db.py"
  }
}

# Execute database initialization
resource "aws_lambda_invocation" "db_init" {
  provider = aws.primary
  
  function_name = aws_lambda_function.db_init.function_name
  input         = jsonencode({})
  
  depends_on = [
    aws_lambda_function.db_init,
    aws_dsql_cluster.primary,
    aws_dsql_cluster.secondary
  ]
}

# =============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# =============================================================================

# CloudWatch alarms for primary Lambda function
module "primary_lambda_monitoring" {
  count  = var.create_cloudwatch_alarms ? 1 : 0
  source = "./modules/lambda_monitoring"
  
  providers = {
    aws = aws.primary
  }
  
  function_name = aws_lambda_function.primary.function_name
  region       = var.primary_region
  tags         = local.common_tags
}

# CloudWatch alarms for secondary Lambda function
module "secondary_lambda_monitoring" {
  count  = var.create_cloudwatch_alarms ? 1 : 0
  source = "./modules/lambda_monitoring"
  
  providers = {
    aws = aws.secondary
  }
  
  function_name = aws_lambda_function.secondary.function_name
  region       = var.secondary_region
  tags         = local.common_tags
}

# =============================================================================
# ROUTE 53 HEALTH CHECKS (OPTIONAL)
# =============================================================================

# Route 53 health check for primary API Gateway
resource "aws_route53_health_check" "primary" {
  count = var.create_route53_health_checks ? 1 : 0
  
  fqdn                            = "${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com"
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/${var.api_gateway_stage_name}/health"
  failure_threshold               = 3
  request_interval                = 30
  cloudwatch_alarm_region         = var.primary_region
  cloudwatch_alarm_name           = "primary-api-health"
  insufficient_data_health_status = "Failure"
  
  tags = merge(
    local.common_tags,
    {
      Name = "primary-api-health-check"
      Type = "health-check"
    }
  )
}

# Route 53 health check for secondary API Gateway
resource "aws_route53_health_check" "secondary" {
  count = var.create_route53_health_checks ? 1 : 0
  
  fqdn                            = "${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com"
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/${var.api_gateway_stage_name}/health"
  failure_threshold               = 3
  request_interval                = 30
  cloudwatch_alarm_region         = var.secondary_region
  cloudwatch_alarm_name           = "secondary-api-health"
  insufficient_data_health_status = "Failure"
  
  tags = merge(
    local.common_tags,
    {
      Name = "secondary-api-health-check"
      Type = "health-check"
    }
  )
}