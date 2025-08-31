# Main Terraform configuration for Microservice Authorization with VPC Lattice and IAM
# This creates a complete zero-trust networking solution for microservices

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  suffix                = random_string.suffix.result
  service_network_name  = "${var.project_name}-network-${local.suffix}"
  vpc_lattice_service_name = "order-service-${local.suffix}"
  product_function_name = "product-service-${local.suffix}"
  order_function_name   = "order-service-${local.suffix}"
  log_group_name        = "/aws/vpclattice/${local.service_network_name}"
  target_group_name     = "order-targets-${local.suffix}"
  
  common_tags = {
    Recipe      = "microservice-authorization-lattice-iam"
    Suffix      = local.suffix
    CreatedBy   = "Terraform"
  }
}

#####################################################################
# IAM Roles and Policies for Microservice Identity Management
#####################################################################

# IAM trust policy for Lambda execution
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM Role for Product Service (Client)
resource "aws_iam_role" "product_service_role" {
  name               = "ProductServiceRole-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name        = "ProductServiceRole-${local.suffix}"
    ServiceType = "ProductService"
    Role        = "Client"
  })
}

# IAM Role for Order Service (Provider)
resource "aws_iam_role" "order_service_role" {
  name               = "OrderServiceRole-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name        = "OrderServiceRole-${local.suffix}"
    ServiceType = "OrderService"
    Role        = "Provider"
  })
}

# Attach basic Lambda execution policy to both roles
resource "aws_iam_role_policy_attachment" "product_service_basic_execution" {
  role       = aws_iam_role.product_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "order_service_basic_execution" {
  role       = aws_iam_role.order_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC Lattice invoke policy for product service
data "aws_iam_policy_document" "vpc_lattice_invoke_policy" {
  statement {
    effect = "Allow"
    actions = [
      "vpc-lattice-svcs:Invoke"
    ]
    resources = [
      "arn:aws:vpc-lattice:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_vpclattice_service.order_service.id}/*"
    ]
  }
}

# Attach VPC Lattice invoke policy to product service role
resource "aws_iam_role_policy" "product_service_vpc_lattice_policy" {
  name   = "VPCLatticeInvokePolicy"
  role   = aws_iam_role.product_service_role.id
  policy = data.aws_iam_policy_document.vpc_lattice_invoke_policy.json
}

#####################################################################
# Lambda Functions for Microservices
#####################################################################

# Archive for Product Service Lambda function
data "archive_file" "product_service_zip" {
  type        = "zip"
  output_path = "${path.module}/product-service.zip"
  
  source {
    content = <<EOF
import json
import boto3
import urllib3

def lambda_handler(event, context):
    # Simulate product service calling order service
    try:
        # In a real scenario, this would make HTTP requests to VPC Lattice service
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Product service authenticated and ready',
                'service': 'product-service',
                'role': context.invoked_function_arn.split(':')[4]
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "product-service.py"
  }
}

# Archive for Order Service Lambda function
data "archive_file" "order_service_zip" {
  type        = "zip"
  output_path = "${path.module}/order-service.zip"
  
  source {
    content = <<EOF
import json

def lambda_handler(event, context):
    # Simulate order service processing requests
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Order service processing request',
            'service': 'order-service',
            'requestId': context.aws_request_id,
            'orders': [
                {'id': 1, 'product': 'Widget A', 'quantity': 5},
                {'id': 2, 'product': 'Widget B', 'quantity': 3}
            ]
        })
    }
EOF
    filename = "order-service.py"
  }
}

# Product Service Lambda Function
resource "aws_lambda_function" "product_service" {
  filename         = data.archive_file.product_service_zip.output_path
  function_name    = local.product_function_name
  role            = aws_iam_role.product_service_role.arn
  handler         = "product-service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.product_service_zip.output_base64sha256
  
  tags = merge(local.common_tags, {
    Name        = local.product_function_name
    ServiceType = "ProductService"
    Role        = "Client"
  })
}

# Order Service Lambda Function
resource "aws_lambda_function" "order_service" {
  filename         = data.archive_file.order_service_zip.output_path
  function_name    = local.order_function_name
  role            = aws_iam_role.order_service_role.arn
  handler         = "order-service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.order_service_zip.output_base64sha256
  
  tags = merge(local.common_tags, {
    Name        = local.order_function_name
    ServiceType = "OrderService"
    Role        = "Provider"
  })
}

#####################################################################
# VPC Lattice Service Network and Services
#####################################################################

# VPC Lattice Service Network with IAM Authentication
resource "aws_vpclattice_service_network" "microservices_network" {
  name      = local.service_network_name
  auth_type = "AWS_IAM"
  
  tags = merge(local.common_tags, {
    Name        = local.service_network_name
    NetworkType = "ServiceMesh"
  })
}

# VPC Lattice Service for Order Service
resource "aws_vpclattice_service" "order_service" {
  name      = local.vpc_lattice_service_name
  auth_type = "AWS_IAM"
  
  tags = merge(local.common_tags, {
    Name        = local.vpc_lattice_service_name
    ServiceType = "OrderService"
  })
}

# VPC Lattice Target Group for Lambda
resource "aws_vpclattice_target_group" "order_targets" {
  name = local.target_group_name
  type = "LAMBDA"
  
  tags = merge(local.common_tags, {
    Name        = local.target_group_name
    ServiceType = "OrderService"
  })
}

# Register Lambda function as target
resource "aws_vpclattice_target_group_attachment" "order_target" {
  target_group_identifier = aws_vpclattice_target_group.order_targets.id
  
  target {
    id = aws_lambda_function.order_service.arn
  }
}

# VPC Lattice Service Listener
resource "aws_vpclattice_listener" "order_listener" {
  name               = "order-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.order_service.id
  
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order_targets.id
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "order-listener"
    ServiceType = "OrderService"
  })
}

# Associate Service with Service Network
resource "aws_vpclattice_service_network_service_association" "order_service_association" {
  service_identifier         = aws_vpclattice_service.order_service.id
  service_network_identifier = aws_vpclattice_service_network.microservices_network.id
  
  tags = merge(local.common_tags, {
    AssociationType = "ServiceNetworkService"
  })
}

# Grant VPC Lattice permission to invoke Lambda function
resource "aws_lambda_permission" "vpc_lattice_invoke" {
  statement_id  = "vpc-lattice-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_service.function_name
  principal     = "vpc-lattice.amazonaws.com"
}

#####################################################################
# Fine-Grained Authorization Policy
#####################################################################

# Authorization policy for fine-grained access control
data "aws_iam_policy_document" "vpc_lattice_auth_policy" {
  # Allow Product Service Access
  statement {
    sid    = "AllowProductServiceAccess"
    effect = "Allow"
    
    principals {
      type = "AWS"
      identifiers = [aws_iam_role.product_service_role.arn]
    }
    
    actions = ["vpc-lattice-svcs:Invoke"]
    
    resources = [
      "arn:aws:vpc-lattice:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_vpclattice_service.order_service.id}/*"
    ]
    
    condition {
      test     = "StringEquals"
      variable = "vpc-lattice-svcs:RequestMethod"
      values   = var.auth_policy_methods
    }
    
    condition {
      test     = "StringLike"
      variable = "vpc-lattice-svcs:RequestPath"
      values   = var.auth_policy_paths
    }
  }
  
  # Deny Unauthorized Access
  statement {
    sid    = "DenyUnauthorizedAccess"
    effect = "Deny"
    
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    
    actions = ["vpc-lattice-svcs:Invoke"]
    
    resources = [
      "arn:aws:vpc-lattice:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_vpclattice_service.order_service.id}/*"
    ]
    
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.product_service_role.arn]
    }
  }
}

# Apply authorization policy to VPC Lattice service
resource "aws_vpclattice_auth_policy" "order_service_auth" {
  resource_identifier = aws_vpclattice_service.order_service.id
  policy             = data.aws_iam_policy_document.vpc_lattice_auth_policy.json
}

#####################################################################
# CloudWatch Monitoring and Logging
#####################################################################

# CloudWatch Log Group for VPC Lattice Access Logs
resource "aws_cloudwatch_log_group" "vpc_lattice_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = local.log_group_name
    LogType     = "VPCLatticeAccess"
  })
}

# VPC Lattice Access Log Subscription
resource "aws_vpclattice_access_log_subscription" "service_network_logs" {
  count                = var.enable_cloudwatch_logs ? 1 : 0
  resource_identifier  = aws_vpclattice_service_network.microservices_network.id
  destination_arn      = aws_cloudwatch_log_group.vpc_lattice_logs[0].arn
  
  tags = merge(local.common_tags, {
    LogType = "AccessLogs"
  })
}

# CloudWatch Alarm for Authorization Failures
resource "aws_cloudwatch_metric_alarm" "auth_failures" {
  alarm_name          = "VPC-Lattice-Auth-Failures-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "4XXError"
  namespace           = "AWS/VpcLattice"
  period              = 300
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "Monitor VPC Lattice authorization failures"
  
  dimensions = {
    ServiceNetwork = aws_vpclattice_service_network.microservices_network.id
  }
  
  tags = merge(local.common_tags, {
    Name      = "VPC-Lattice-Auth-Failures-${local.suffix}"
    AlarmType = "AuthorizationFailures"
  })
}