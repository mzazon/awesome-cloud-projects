# Data sources for AWS account information and current region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # Resource names with unique suffix
  service_name = "${local.name_prefix}-${local.random_suffix}"
  blue_function_name = "${local.name_prefix}-blue-${local.random_suffix}"
  green_function_name = "${local.name_prefix}-green-${local.random_suffix}"
  blue_tg_name = "blue-tg-${local.random_suffix}"
  green_tg_name = "green-tg-${local.random_suffix}"
  lattice_service_name = "lattice-service-${local.random_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Purpose = "blue-green-deployment"
    Recipe  = "blue-green-deployments-lattice-lambda"
  })
}

# ==============================================================================
# IAM Role for Lambda Functions
# ==============================================================================

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "LambdaVPCLatticeRole-${local.random_suffix}"

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
    Name = "LambdaVPCLatticeRole-${local.random_suffix}"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# ==============================================================================
# CloudWatch Log Groups for Lambda Functions
# ==============================================================================

# CloudWatch log group for blue Lambda function
resource "aws_cloudwatch_log_group" "blue_lambda_logs" {
  name              = "/aws/lambda/${local.blue_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "Blue Lambda Logs"
    Environment = "blue"
  })
}

# CloudWatch log group for green Lambda function
resource "aws_cloudwatch_log_group" "green_lambda_logs" {
  name              = "/aws/lambda/${local.green_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "Green Lambda Logs"
    Environment = "green"
  })
}

# ==============================================================================
# Lambda Function Code Archives
# ==============================================================================

# Archive for blue Lambda function
data "archive_file" "blue_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/blue_function.zip"
  
  source {
    content = <<EOF
import json
import time

def lambda_handler(event, context):
    # Blue environment - stable production version
    response_data = {
        'environment': 'blue',
        'version': '1.0.0',
        'message': 'Hello from Blue Environment!',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Environment': 'blue'
        },
        'body': json.dumps(response_data)
    }
EOF
    filename = "blue_function.py"
  }
}

# Archive for green Lambda function
data "archive_file" "green_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/green_function.zip"
  
  source {
    content = <<EOF
import json
import time

def lambda_handler(event, context):
    # Green environment - new version being deployed
    response_data = {
        'environment': 'green',
        'version': '2.0.0',
        'message': 'Hello from Green Environment!',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id,
        'new_feature': 'Enhanced response with additional metadata'
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Environment': 'green'
        },
        'body': json.dumps(response_data)
    }
EOF
    filename = "green_function.py"
  }
}

# ==============================================================================
# Lambda Functions
# ==============================================================================

# Blue environment Lambda function (current production version)
resource "aws_lambda_function" "blue_function" {
  function_name = local.blue_function_name
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "blue_function.lambda_handler"
  runtime      = var.lambda_runtime
  
  filename         = data.archive_file.blue_lambda_zip.output_path
  source_code_hash = data.archive_file.blue_lambda_zip.output_base64sha256
  
  timeout     = var.lambda_timeout
  memory_size = var.blue_lambda_memory_size
  
  environment {
    variables = {
      ENVIRONMENT = "blue"
      VERSION     = "1.0.0"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.blue_lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.blue_function_name
    Environment = "blue"
    Deployment  = "blue-green"
  })
}

# Green environment Lambda function (new version for deployment)
resource "aws_lambda_function" "green_function" {
  function_name = local.green_function_name
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "green_function.lambda_handler"
  runtime      = var.lambda_runtime
  
  filename         = data.archive_file.green_lambda_zip.output_path
  source_code_hash = data.archive_file.green_lambda_zip.output_base64sha256
  
  timeout     = var.lambda_timeout
  memory_size = var.green_lambda_memory_size
  
  environment {
    variables = {
      ENVIRONMENT = "green"
      VERSION     = "2.0.0"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.green_lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.green_function_name
    Environment = "green"
    Deployment  = "blue-green"
  })
}

# ==============================================================================
# VPC Lattice Service Network
# ==============================================================================

# VPC Lattice service network for application-layer networking
resource "aws_vpclattice_service_network" "ecommerce_network" {
  name      = "ecommerce-network-${local.random_suffix}"
  auth_type = "AWS_IAM"

  tags = merge(local.common_tags, {
    Name    = "ecommerce-network-${local.random_suffix}"
    Purpose = "blue-green-deployment"
  })
}

# ==============================================================================
# VPC Lattice Target Groups
# ==============================================================================

# Target group for blue environment Lambda function
resource "aws_vpclattice_target_group" "blue_target_group" {
  name = local.blue_tg_name
  type = "LAMBDA"

  tags = merge(local.common_tags, {
    Name        = local.blue_tg_name
    Environment = "blue"
    Purpose     = "target-group"
  })
}

# Target group for green environment Lambda function
resource "aws_vpclattice_target_group" "green_target_group" {
  name = local.green_tg_name
  type = "LAMBDA"

  tags = merge(local.common_tags, {
    Name        = local.green_tg_name
    Environment = "green"
    Purpose     = "target-group"
  })
}

# ==============================================================================
# Lambda Permissions for VPC Lattice
# ==============================================================================

# Permission for VPC Lattice to invoke blue Lambda function
resource "aws_lambda_permission" "blue_vpc_lattice_permission" {
  statement_id  = "vpc-lattice-blue"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.blue_function.function_name
  principal     = "vpc-lattice.amazonaws.com"
  source_arn    = aws_vpclattice_target_group.blue_target_group.arn
}

# Permission for VPC Lattice to invoke green Lambda function
resource "aws_lambda_permission" "green_vpc_lattice_permission" {
  statement_id  = "vpc-lattice-green"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.green_function.function_name
  principal     = "vpc-lattice.amazonaws.com"
  source_arn    = aws_vpclattice_target_group.green_target_group.arn
}

# ==============================================================================
# VPC Lattice Target Group Attachments
# ==============================================================================

# Attach blue Lambda function to blue target group
resource "aws_vpclattice_target_group_attachment" "blue_attachment" {
  target_group_identifier = aws_vpclattice_target_group.blue_target_group.id
  
  target {
    id = aws_lambda_function.blue_function.arn
  }

  depends_on = [aws_lambda_permission.blue_vpc_lattice_permission]
}

# Attach green Lambda function to green target group
resource "aws_vpclattice_target_group_attachment" "green_attachment" {
  target_group_identifier = aws_vpclattice_target_group.green_target_group.id
  
  target {
    id = aws_lambda_function.green_function.arn
  }

  depends_on = [aws_lambda_permission.green_vpc_lattice_permission]
}

# ==============================================================================
# VPC Lattice Service and Listener
# ==============================================================================

# VPC Lattice service for blue-green deployment
resource "aws_vpclattice_service" "blue_green_service" {
  name      = local.lattice_service_name
  auth_type = "AWS_IAM"

  tags = merge(local.common_tags, {
    Name        = local.lattice_service_name
    Purpose     = "blue-green-service"
  })
}

# Associate service with service network
resource "aws_vpclattice_service_network_service_association" "service_association" {
  service_identifier         = aws_vpclattice_service.blue_green_service.id
  service_network_identifier = aws_vpclattice_service_network.ecommerce_network.id

  tags = merge(local.common_tags, {
    Name = "service-network-association"
  })
}

# HTTP listener with weighted routing for blue-green deployment
resource "aws_vpclattice_listener" "http_listener" {
  name               = "http-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.blue_green_service.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.blue_target_group.id
        weight                  = var.initial_blue_weight
      }
      
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.green_target_group.id
        weight                  = var.initial_green_weight
      }
    }
  }

  depends_on = [
    aws_vpclattice_target_group_attachment.blue_attachment,
    aws_vpclattice_target_group_attachment.green_attachment,
    aws_vpclattice_service_network_service_association.service_association
  ]

  tags = merge(local.common_tags, {
    Name = "http-listener"
  })
}

# ==============================================================================
# CloudWatch Monitoring and Alarms
# ==============================================================================

# CloudWatch alarm for green environment error rate
resource "aws_cloudwatch_metric_alarm" "green_error_rate" {
  alarm_name          = "${local.green_function_name}-ErrorRate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_error_threshold
  alarm_description   = "Monitor error rate for green environment Lambda function"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.green_function.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.green_function_name}-ErrorRate"
    Environment = "green"
    Type        = "error-monitoring"
  })
}

# CloudWatch alarm for green environment duration
resource "aws_cloudwatch_metric_alarm" "green_duration" {
  alarm_name          = "${local.green_function_name}-Duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_duration_threshold
  alarm_description   = "Monitor duration for green environment Lambda function"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.green_function.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.green_function_name}-Duration"
    Environment = "green"
    Type        = "performance-monitoring"
  })
}

# CloudWatch alarm for blue environment error rate (for comparison)
resource "aws_cloudwatch_metric_alarm" "blue_error_rate" {
  alarm_name          = "${local.blue_function_name}-ErrorRate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_error_threshold
  alarm_description   = "Monitor error rate for blue environment Lambda function"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.blue_function.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.blue_function_name}-ErrorRate"
    Environment = "blue"
    Type        = "error-monitoring"
  })
}