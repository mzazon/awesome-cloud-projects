# Multi-Region Active-Active Application with AWS Global Accelerator
# This Terraform configuration deploys a globally distributed application across
# three regions with automatic failover and data replication

# Generate unique suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Current caller identity for account ID
data "aws_caller_identity" "current" {}

# ============================================================================
# DynamoDB Global Tables Setup
# ============================================================================

# DynamoDB table in primary region (US East 1)
resource "aws_dynamodb_table" "global_table_us" {
  provider = aws.us_east
  
  name           = "${var.dynamodb_table_name}-${random_string.suffix.result}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "userId"
  range_key      = "timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-us"
    Region      = var.primary_region
    TableType   = "GlobalTable"
  }
}

# DynamoDB table in EU region
resource "aws_dynamodb_table" "global_table_eu" {
  provider = aws.eu_west
  
  name           = "${var.dynamodb_table_name}-${random_string.suffix.result}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "userId"
  range_key      = "timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-eu"
    Region      = var.secondary_region_eu
    TableType   = "GlobalTable"
  }
}

# DynamoDB table in Asia region
resource "aws_dynamodb_table" "global_table_asia" {
  provider = aws.asia_southeast
  
  name           = "${var.dynamodb_table_name}-${random_string.suffix.result}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "userId"
  range_key      = "timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-asia"
    Region      = var.secondary_region_asia
    TableType   = "GlobalTable"
  }
}

# Configure Global Table replication
resource "aws_dynamodb_global_table" "global_user_data" {
  provider = aws.us_east
  
  name = "${var.dynamodb_table_name}-${random_string.suffix.result}"

  replica {
    region_name = var.primary_region
  }

  replica {
    region_name = var.secondary_region_eu
  }

  replica {
    region_name = var.secondary_region_asia
  }

  depends_on = [
    aws_dynamodb_table.global_table_us,
    aws_dynamodb_table.global_table_eu,
    aws_dynamodb_table.global_table_asia
  ]
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${random_string.suffix.result}"

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

  tags = {
    Name = "${var.project_name}-lambda-execution-role"
  }
}

# IAM policy for DynamoDB Global Table access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "DynamoDBGlobalAccess"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}-${random_string.suffix.result}",
          "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}-${random_string.suffix.result}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ============================================================================
# Lambda Function Code
# ============================================================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      table_name = "${var.dynamodb_table_name}-${random_string.suffix.result}"
    })
    filename = "lambda_function.py"
  }
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

# CloudWatch log group for US Lambda
resource "aws_cloudwatch_log_group" "lambda_logs_us" {
  provider = aws.us_east
  
  name              = "/aws/lambda/${var.project_name}-us-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name   = "${var.project_name}-lambda-logs-us"
    Region = var.primary_region
  }
}

# CloudWatch log group for EU Lambda
resource "aws_cloudwatch_log_group" "lambda_logs_eu" {
  provider = aws.eu_west
  
  name              = "/aws/lambda/${var.project_name}-eu-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name   = "${var.project_name}-lambda-logs-eu"
    Region = var.secondary_region_eu
  }
}

# CloudWatch log group for Asia Lambda
resource "aws_cloudwatch_log_group" "lambda_logs_asia" {
  provider = aws.asia_southeast
  
  name              = "/aws/lambda/${var.project_name}-asia-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name   = "${var.project_name}-lambda-logs-asia"
    Region = var.secondary_region_asia
  }
}

# ============================================================================
# Lambda Functions
# ============================================================================

# Lambda function in US region
resource "aws_lambda_function" "app_function_us" {
  provider = aws.us_east
  
  function_name = "${var.project_name}-us-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = "${var.dynamodb_table_name}-${random_string.suffix.result}"
      REGION     = var.primary_region
    }
  }

  reserved_concurrency = var.lambda_reserved_concurrency

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs_us,
    aws_iam_role_policy.lambda_dynamodb_policy
  ]

  tags = {
    Name   = "${var.project_name}-lambda-us"
    Region = var.primary_region
  }
}

# Lambda function in EU region
resource "aws_lambda_function" "app_function_eu" {
  provider = aws.eu_west
  
  function_name = "${var.project_name}-eu-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = "${var.dynamodb_table_name}-${random_string.suffix.result}"
      REGION     = var.secondary_region_eu
    }
  }

  reserved_concurrency = var.lambda_reserved_concurrency

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs_eu,
    aws_iam_role_policy.lambda_dynamodb_policy
  ]

  tags = {
    Name   = "${var.project_name}-lambda-eu"
    Region = var.secondary_region_eu
  }
}

# Lambda function in Asia region
resource "aws_lambda_function" "app_function_asia" {
  provider = aws.asia_southeast
  
  function_name = "${var.project_name}-asia-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = "${var.dynamodb_table_name}-${random_string.suffix.result}"
      REGION     = var.secondary_region_asia
    }
  }

  reserved_concurrency = var.lambda_reserved_concurrency

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs_asia,
    aws_iam_role_policy.lambda_dynamodb_policy
  ]

  tags = {
    Name   = "${var.project_name}-lambda-asia"
    Region = var.secondary_region_asia
  }
}

# ============================================================================
# VPC and Networking Setup
# ============================================================================

# Get default VPC for US region
data "aws_vpc" "default_us" {
  provider = aws.us_east
  default  = true
}

# Get default subnets for US region
data "aws_subnets" "default_us" {
  provider = aws.us_east
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_us.id]
  }
}

# Get default VPC for EU region
data "aws_vpc" "default_eu" {
  provider = aws.eu_west
  default  = true
}

# Get default subnets for EU region
data "aws_subnets" "default_eu" {
  provider = aws.eu_west
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_eu.id]
  }
}

# Get default VPC for Asia region
data "aws_vpc" "default_asia" {
  provider = aws.asia_southeast
  default  = true
}

# Get default subnets for Asia region
data "aws_subnets" "default_asia" {
  provider = aws.asia_southeast
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_asia.id]
  }
}

# ============================================================================
# Application Load Balancers
# ============================================================================

# Security group for ALB in US region
resource "aws_security_group" "alb_sg_us" {
  provider = aws.us_east
  
  name_prefix = "${var.project_name}-alb-us-"
  vpc_id      = data.aws_vpc.default_us.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP traffic from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name   = "${var.project_name}-alb-sg-us"
    Region = var.primary_region
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer in US region
resource "aws_lb" "app_lb_us" {
  provider = aws.us_east
  
  name               = "${var.project_name}-us-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_us.id]
  subnets            = data.aws_subnets.default_us.ids

  enable_deletion_protection       = var.alb_enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  idle_timeout                     = var.alb_idle_timeout

  tags = {
    Name   = "${var.project_name}-alb-us"
    Region = var.primary_region
  }
}

# Security group for ALB in EU region
resource "aws_security_group" "alb_sg_eu" {
  provider = aws.eu_west
  
  name_prefix = "${var.project_name}-alb-eu-"
  vpc_id      = data.aws_vpc.default_eu.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP traffic from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name   = "${var.project_name}-alb-sg-eu"
    Region = var.secondary_region_eu
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer in EU region
resource "aws_lb" "app_lb_eu" {
  provider = aws.eu_west
  
  name               = "${var.project_name}-eu-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_eu.id]
  subnets            = data.aws_subnets.default_eu.ids

  enable_deletion_protection       = var.alb_enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  idle_timeout                     = var.alb_idle_timeout

  tags = {
    Name   = "${var.project_name}-alb-eu"
    Region = var.secondary_region_eu
  }
}

# Security group for ALB in Asia region
resource "aws_security_group" "alb_sg_asia" {
  provider = aws.asia_southeast
  
  name_prefix = "${var.project_name}-alb-asia-"
  vpc_id      = data.aws_vpc.default_asia.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP traffic from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name   = "${var.project_name}-alb-sg-asia"
    Region = var.secondary_region_asia
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer in Asia region
resource "aws_lb" "app_lb_asia" {
  provider = aws.asia_southeast
  
  name               = "${var.project_name}-asia-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_asia.id]
  subnets            = data.aws_subnets.default_asia.ids

  enable_deletion_protection       = var.alb_enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  idle_timeout                     = var.alb_idle_timeout

  tags = {
    Name   = "${var.project_name}-alb-asia"
    Region = var.secondary_region_asia
  }
}

# ============================================================================
# Target Groups
# ============================================================================

# Target group for US Lambda
resource "aws_lb_target_group" "lambda_tg_us" {
  provider = aws.us_east
  
  name        = "${var.project_name}-us-tg-${random_string.suffix.result}"
  target_type = "lambda"

  tags = {
    Name   = "${var.project_name}-lambda-tg-us"
    Region = var.primary_region
  }
}

# Target group for EU Lambda
resource "aws_lb_target_group" "lambda_tg_eu" {
  provider = aws.eu_west
  
  name        = "${var.project_name}-eu-tg-${random_string.suffix.result}"
  target_type = "lambda"

  tags = {
    Name   = "${var.project_name}-lambda-tg-eu"
    Region = var.secondary_region_eu
  }
}

# Target group for Asia Lambda
resource "aws_lb_target_group" "lambda_tg_asia" {
  provider = aws.asia_southeast
  
  name        = "${var.project_name}-asia-tg-${random_string.suffix.result}"
  target_type = "lambda"

  tags = {
    Name   = "${var.project_name}-lambda-tg-asia"
    Region = var.secondary_region_asia
  }
}

# Register Lambda functions as targets
resource "aws_lb_target_group_attachment" "lambda_attachment_us" {
  provider = aws.us_east
  
  target_group_arn = aws_lb_target_group.lambda_tg_us.arn
  target_id        = aws_lambda_function.app_function_us.arn
}

resource "aws_lb_target_group_attachment" "lambda_attachment_eu" {
  provider = aws.eu_west
  
  target_group_arn = aws_lb_target_group.lambda_tg_eu.arn
  target_id        = aws_lambda_function.app_function_eu.arn
}

resource "aws_lb_target_group_attachment" "lambda_attachment_asia" {
  provider = aws.asia_southeast
  
  target_group_arn = aws_lb_target_group.lambda_tg_asia.arn
  target_id        = aws_lambda_function.app_function_asia.arn
}

# ============================================================================
# Lambda Permissions for ALB
# ============================================================================

# Allow ALB to invoke Lambda in US
resource "aws_lambda_permission" "alb_invoke_us" {
  provider = aws.us_east
  
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_function_us.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg_us.arn
}

# Allow ALB to invoke Lambda in EU
resource "aws_lambda_permission" "alb_invoke_eu" {
  provider = aws.eu_west
  
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_function_eu.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg_eu.arn
}

# Allow ALB to invoke Lambda in Asia
resource "aws_lambda_permission" "alb_invoke_asia" {
  provider = aws.asia_southeast
  
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_function_asia.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg_asia.arn
}

# ============================================================================
# ALB Listeners
# ============================================================================

# HTTP listener for US ALB
resource "aws_lb_listener" "app_listener_us" {
  provider = aws.us_east
  
  load_balancer_arn = aws_lb.app_lb_us.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg_us.arn
  }

  tags = {
    Name   = "${var.project_name}-listener-us"
    Region = var.primary_region
  }
}

# HTTP listener for EU ALB
resource "aws_lb_listener" "app_listener_eu" {
  provider = aws.eu_west
  
  load_balancer_arn = aws_lb.app_lb_eu.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg_eu.arn
  }

  tags = {
    Name   = "${var.project_name}-listener-eu"
    Region = var.secondary_region_eu
  }
}

# HTTP listener for Asia ALB
resource "aws_lb_listener" "app_listener_asia" {
  provider = aws.asia_southeast
  
  load_balancer_arn = aws_lb.app_lb_asia.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg_asia.arn
  }

  tags = {
    Name   = "${var.project_name}-listener-asia"
    Region = var.secondary_region_asia
  }
}

# ============================================================================
# AWS Global Accelerator
# ============================================================================

# Global Accelerator (must be created in us-west-2)
resource "aws_globalaccelerator_accelerator" "main" {
  provider = aws.us_west_2
  
  name            = "${var.accelerator_name}-${random_string.suffix.result}"
  ip_address_type = var.accelerator_ip_address_type
  enabled         = var.accelerator_enabled

  attributes {
    flow_logs_enabled   = var.enable_detailed_monitoring
    flow_logs_s3_bucket = var.enable_detailed_monitoring ? aws_s3_bucket.flow_logs[0].bucket : ""
    flow_logs_s3_prefix = var.enable_detailed_monitoring ? "global-accelerator-logs/" : ""
  }

  tags = {
    Name = "${var.project_name}-global-accelerator"
  }
}

# Global Accelerator Listener
resource "aws_globalaccelerator_listener" "main" {
  provider = aws.us_west_2
  
  accelerator_arn = aws_globalaccelerator_accelerator.main.id
  client_affinity = "NONE"
  protocol        = "TCP"

  port_range {
    from_port = 80
    to_port   = 80
  }
}

# Endpoint group for US region
resource "aws_globalaccelerator_endpoint_group" "us" {
  provider = aws.us_west_2
  
  listener_arn = aws_globalaccelerator_listener.main.id

  endpoint_group_region         = var.primary_region
  traffic_dial_percentage       = var.traffic_dial_percentage
  health_check_interval_seconds = var.health_check_interval_seconds
  healthy_threshold_count       = var.healthy_threshold_count
  unhealthy_threshold_count     = var.unhealthy_threshold_count

  endpoint_configuration {
    endpoint_id                    = aws_lb.app_lb_us.arn
    weight                         = var.endpoint_weight
    client_ip_preservation_enabled = false
  }
}

# Endpoint group for EU region
resource "aws_globalaccelerator_endpoint_group" "eu" {
  provider = aws.us_west_2
  
  listener_arn = aws_globalaccelerator_listener.main.id

  endpoint_group_region         = var.secondary_region_eu
  traffic_dial_percentage       = var.traffic_dial_percentage
  health_check_interval_seconds = var.health_check_interval_seconds
  healthy_threshold_count       = var.healthy_threshold_count
  unhealthy_threshold_count     = var.unhealthy_threshold_count

  endpoint_configuration {
    endpoint_id                    = aws_lb.app_lb_eu.arn
    weight                         = var.endpoint_weight
    client_ip_preservation_enabled = false
  }
}

# Endpoint group for Asia region
resource "aws_globalaccelerator_endpoint_group" "asia" {
  provider = aws.us_west_2
  
  listener_arn = aws_globalaccelerator_listener.main.id

  endpoint_group_region         = var.secondary_region_asia
  traffic_dial_percentage       = var.traffic_dial_percentage
  health_check_interval_seconds = var.health_check_interval_seconds
  healthy_threshold_count       = var.healthy_threshold_count
  unhealthy_threshold_count     = var.unhealthy_threshold_count

  endpoint_configuration {
    endpoint_id                    = aws_lb.app_lb_asia.arn
    weight                         = var.endpoint_weight
    client_ip_preservation_enabled = false
  }
}

# ============================================================================
# S3 Bucket for Global Accelerator Flow Logs (optional)
# ============================================================================

resource "aws_s3_bucket" "flow_logs" {
  provider = aws.us_west_2
  count    = var.enable_detailed_monitoring ? 1 : 0
  
  bucket        = "${var.project_name}-ga-flow-logs-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-global-accelerator-logs"
    Purpose = "GlobalAcceleratorFlowLogs"
  }
}

resource "aws_s3_bucket_versioning" "flow_logs_versioning" {
  provider = aws.us_west_2
  count    = var.enable_detailed_monitoring ? 1 : 0
  
  bucket = aws_s3_bucket.flow_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs_encryption" {
  provider = aws.us_west_2
  count    = var.enable_detailed_monitoring ? 1 : 0
  
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs_pab" {
  provider = aws.us_west_2
  count    = var.enable_detailed_monitoring ? 1 : 0
  
  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}