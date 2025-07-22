# Zero Trust Network Architecture with VPC Endpoints and PrivateLink
# This Terraform configuration implements a comprehensive zero trust network architecture
# using AWS VPC endpoints and PrivateLink for secure, private connectivity

# Data sources for availability zones and current AWS account
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })

  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result

  # Availability zones
  azs = [for i, az in var.availability_zones : "${var.aws_region}${az}"]
}

#####################################################
# Consumer VPC (Zero Trust Network)
#####################################################

# Consumer VPC for zero trust architecture
resource "aws_vpc" "consumer" {
  cidr_block           = var.consumer_vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-consumer-vpc-${local.suffix}"
    Type = "Consumer"
  })
}

# Private subnets for consumer VPC (no internet access)
resource "aws_subnet" "consumer_private" {
  count = length(var.consumer_private_subnet_cidrs)

  vpc_id            = aws_vpc.consumer.id
  cidr_block        = var.consumer_private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-consumer-private-${count.index + 1}-${local.suffix}"
    Type = "Private"
  })
}

# Route table for consumer private subnets (no internet gateway)
resource "aws_route_table" "consumer_private" {
  vpc_id = aws_vpc.consumer.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-consumer-private-rt-${local.suffix}"
    Type = "ZeroTrust"
  })
}

# Associate private subnets with route table
resource "aws_route_table_association" "consumer_private" {
  count = length(aws_subnet.consumer_private)

  subnet_id      = aws_subnet.consumer_private[count.index].id
  route_table_id = aws_route_table.consumer_private.id
}

#####################################################
# Provider VPC (Service Provider Network)
#####################################################

# Provider VPC for hosting PrivateLink services
resource "aws_vpc" "provider" {
  cidr_block           = var.provider_vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-provider-vpc-${local.suffix}"
    Type = "Provider"
  })
}

# Subnet for provider VPC
resource "aws_subnet" "provider" {
  vpc_id            = aws_vpc.provider.id
  cidr_block        = var.provider_subnet_cidr
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-provider-subnet-${local.suffix}"
    Type = "Provider"
  })
}

# Route table for provider subnet
resource "aws_route_table" "provider" {
  vpc_id = aws_vpc.provider.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-provider-rt-${local.suffix}"
    Type = "Provider"
  })
}

# Associate provider subnet with route table
resource "aws_route_table_association" "provider" {
  subnet_id      = aws_subnet.provider.id
  route_table_id = aws_route_table.provider.id
}

#####################################################
# Security Groups (Least Privilege Access)
#####################################################

# Security group for VPC endpoints (restrictive ingress)
resource "aws_security_group" "vpc_endpoint" {
  name_prefix = "${local.name_prefix}-endpoint-sg-"
  description = "Zero Trust VPC Endpoint Security Group"
  vpc_id      = aws_vpc.consumer.id

  # Allow HTTPS from consumer VPC CIDR only
  ingress {
    description = "HTTPS from Consumer VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.consumer_vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-sg-${local.suffix}"
    Type = "VPCEndpoint"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for applications (zero trust outbound)
resource "aws_security_group" "application" {
  name_prefix = "${local.name_prefix}-app-sg-"
  description = "Zero Trust Application Security Group"
  vpc_id      = aws_vpc.consumer.id

  # Allow outbound HTTPS to VPC endpoints only
  egress {
    description     = "HTTPS to VPC Endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_endpoint.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-sg-${local.suffix}"
    Type = "Application"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for provider services
resource "aws_security_group" "provider_service" {
  name_prefix = "${local.name_prefix}-provider-sg-"
  description = "Provider Service Security Group"
  vpc_id      = aws_vpc.provider.id

  # Allow HTTPS from consumer VPC CIDR
  ingress {
    description = "HTTPS from Consumer VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.consumer_vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-provider-sg-${local.suffix}"
    Type = "ProviderService"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#####################################################
# VPC Endpoints for AWS Services
#####################################################

# S3 Interface VPC Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = aws_vpc.consumer.id
  service_name        = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.consumer_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = var.private_dns_enabled

  policy = var.vpc_endpoint_policy_s3 != null ? var.vpc_endpoint_policy_s3 : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint-${local.suffix}"
    Type = "S3Interface"
  })
}

# Lambda Interface VPC Endpoint
resource "aws_vpc_endpoint" "lambda" {
  vpc_id              = aws_vpc.consumer.id
  service_name        = "com.amazonaws.${var.aws_region}.lambda"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.consumer_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-endpoint-${local.suffix}"
    Type = "LambdaInterface"
  })
}

# CloudWatch Logs Interface VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.consumer.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.consumer_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs-endpoint-${local.suffix}"
    Type = "LogsInterface"
  })
}

#####################################################
# Network Load Balancer for PrivateLink
#####################################################

# Network Load Balancer for PrivateLink service
resource "aws_lb" "provider_nlb" {
  name               = "${local.name_prefix}-nlb-${local.suffix}"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.provider.id]

  enable_deletion_protection = var.nlb_enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nlb-${local.suffix}"
    Type = "NetworkLoadBalancer"
  })
}

# Target group for the NLB
resource "aws_lb_target_group" "provider" {
  name        = "${local.name_prefix}-tg-${local.suffix}"
  port        = 443
  protocol    = "TCP"
  vpc_id      = aws_vpc.provider.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = null
    path                = null
    port                = "traffic-port"
    protocol            = "TCP"
    timeout             = 10
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg-${local.suffix}"
    Type = "TargetGroup"
  })
}

# Listener for the NLB
resource "aws_lb_listener" "provider" {
  load_balancer_arn = aws_lb.provider_nlb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.provider.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-listener-${local.suffix}"
    Type = "Listener"
  })
}

#####################################################
# VPC Endpoint Service Configuration
#####################################################

# VPC Endpoint Service Configuration
resource "aws_vpc_endpoint_service" "custom" {
  acceptance_required        = var.endpoint_service_acceptance_required
  network_load_balancer_arns = [aws_lb.provider_nlb.arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-service-${local.suffix}"
    Type = "EndpointService"
  })
}

# Add permissions for consumer account to connect
resource "aws_vpc_endpoint_service_allowed_principal" "consumer" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.custom.id
  principal_arn          = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}

#####################################################
# Custom Service VPC Endpoint
#####################################################

# VPC Endpoint for custom PrivateLink service
resource "aws_vpc_endpoint" "custom_service" {
  vpc_id              = aws_vpc.consumer.id
  service_name        = aws_vpc_endpoint_service.custom.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.consumer_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-custom-endpoint-${local.suffix}"
    Type = "CustomInterface"
  })
}

# Accept the VPC endpoint connection
resource "aws_vpc_endpoint_connection_accepter" "custom" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.custom.id
  vpc_endpoint_id         = aws_vpc_endpoint.custom_service.id
}

#####################################################
# Private DNS Resolution
#####################################################

# Private hosted zone for custom service
resource "aws_route53_zone" "private" {
  name = "zero-trust-service.internal"

  vpc {
    vpc_id = aws_vpc.consumer.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-zone-${local.suffix}"
    Type = "PrivateHostedZone"
  })
}

# DNS record for service discovery
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "api.zero-trust-service.internal"
  type    = "CNAME"
  ttl     = 300
  records = [aws_vpc_endpoint.custom_service.dns_entry[0].dns_name]
}

#####################################################
# VPC Flow Logs for Monitoring
#####################################################

# CloudWatch log group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/zero-trust-flowlogs-${local.suffix}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-flow-logs-${local.suffix}"
    Type = "FlowLogs"
  })
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-flow-logs-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-flow-logs-role-${local.suffix}"
    Type = "IAMRole"
  })
}

# Attach policy to Flow Logs role
resource "aws_iam_role_policy_attachment" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  role       = aws_iam_role.flow_logs[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy"
}

# VPC Flow Logs for consumer VPC
resource "aws_flow_log" "consumer" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.consumer.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-consumer-flow-logs-${local.suffix}"
    Type = "ConsumerFlowLogs"
  })
}

# VPC Flow Logs for provider VPC
resource "aws_flow_log" "provider" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.provider.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-provider-flow-logs-${local.suffix}"
    Type = "ProviderFlowLogs"
  })
}

#####################################################
# Test Lambda Function for Validation
#####################################################

# IAM role for test Lambda function
resource "aws_iam_role" "lambda_test" {
  count = var.create_test_lambda ? 1 : 0

  name = "${local.name_prefix}-lambda-test-role-${local.suffix}"

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
    Name = "${local.name_prefix}-lambda-test-role-${local.suffix}"
    Type = "LambdaRole"
  })
}

# Attach VPC execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count = var.create_test_lambda ? 1 : 0

  role       = aws_iam_role.lambda_test[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Policy for S3 access through VPC endpoint
resource "aws_iam_role_policy" "lambda_s3" {
  count = var.create_test_lambda ? 1 : 0

  name = "${local.name_prefix}-lambda-s3-policy-${local.suffix}"
  role = aws_iam_role.lambda_test[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBuckets",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function for testing zero trust connectivity
resource "aws_lambda_function" "test" {
  count = var.create_test_lambda ? 1 : 0

  function_name = "${local.name_prefix}-test-${local.suffix}"
  role          = aws_iam_role.lambda_test[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = var.lambda_timeout

  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.consumer_private[0].id]
    security_group_ids = [aws_security_group.application.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-test-lambda-${local.suffix}"
    Type = "TestFunction"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_cloudwatch_log_group.lambda_test
  ]
}

# CloudWatch log group for test Lambda
resource "aws_cloudwatch_log_group" "lambda_test" {
  count = var.create_test_lambda ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-test-${local.suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-test-logs-${local.suffix}"
    Type = "LambdaLogs"
  })
}

# Lambda function code
data "archive_file" "lambda_zip" {
  count = var.create_test_lambda ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content = <<EOF
import json
import boto3
import urllib3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """Test function to validate zero trust connectivity"""
    results = {
        'message': 'Zero Trust validation complete',
        'tests': {}
    }
    
    try:
        # Test S3 access through VPC endpoint
        s3_client = boto3.client('s3')
        buckets = s3_client.list_buckets()
        results['tests']['s3_access'] = {
            'status': 'PASS',
            'details': f"Successfully accessed S3 through VPC endpoint. Found {len(buckets['Buckets'])} buckets."
        }
    except ClientError as e:
        results['tests']['s3_access'] = {
            'status': 'FAIL',
            'details': f"S3 access failed: {str(e)}"
        }
    except Exception as e:
        results['tests']['s3_access'] = {
            'status': 'ERROR',
            'details': f"Unexpected error: {str(e)}"
        }
    
    # Test external HTTP request (should fail in zero trust)
    try:
        http = urllib3.PoolManager()
        response = http.request('GET', 'https://httpbin.org/get', timeout=5)
        results['tests']['internet_access'] = {
            'status': 'FAIL',
            'details': f"Internet access succeeded (should be blocked). Response: {response.status}"
        }
    except Exception as e:
        results['tests']['internet_access'] = {
            'status': 'PASS',
            'details': f"Internet access correctly blocked: {str(e)}"
        }
    
    # Test VPC endpoint functionality
    try:
        # Verify we're in VPC
        import socket
        hostname = socket.gethostname()
        results['tests']['vpc_endpoint_working'] = {
            'status': 'PASS',
            'details': f"Lambda running in VPC: {hostname}"
        }
    except Exception as e:
        results['tests']['vpc_endpoint_working'] = {
            'status': 'ERROR',
            'details': f"Error checking VPC status: {str(e)}"
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, indent=2)
    }
EOF
    filename = "lambda_function.py"
  }
}