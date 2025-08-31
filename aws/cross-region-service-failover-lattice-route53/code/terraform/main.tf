# Cross-Region Service Failover with VPC Lattice and Route53
# This Terraform configuration deploys a multi-region microservices architecture
# with automated failover using VPC Lattice service networks and Route53 health checks

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  suffix                = random_id.suffix.hex
  service_network_name  = var.service_network_name != "" ? var.service_network_name : "${var.project_name}-network-${local.suffix}"
  lambda_function_name  = var.lambda_function_name != "" ? var.lambda_function_name : "health-check-service-${local.suffix}"
  domain_name          = var.domain_name != "" ? var.domain_name : "api-${local.suffix}.example.com"
  
  # Common tags for all resources
  common_tags = merge(
    var.default_tags,
    var.additional_tags,
    {
      Environment = var.environment
      Project     = var.project_name
    }
  )

  # Get current AWS account ID and caller identity
  current_account_id = data.aws_caller_identity.current.account_id
}

# Data sources for current AWS account information
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

# ============================================================================
# VPC and Networking Resources (Primary Region)
# ============================================================================

resource "aws_vpc" "primary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.primary

  cidr_block           = var.primary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-primary-vpc"
    Region = var.primary_region
  })
}

resource "aws_internet_gateway" "primary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.primary

  vpc_id = aws_vpc.primary[0].id

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-primary-igw"
    Region = var.primary_region
  })
}

resource "aws_subnet" "primary" {
  count    = var.create_vpc_resources ? length(var.primary_subnet_cidrs) : 0
  provider = aws.primary

  vpc_id                  = aws_vpc.primary[0].id
  cidr_block              = var.primary_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.primary.names[count.index % length(data.aws_availability_zones.primary.names)]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-primary-subnet-${count.index + 1}"
    Region = var.primary_region
    AZ     = data.aws_availability_zones.primary.names[count.index % length(data.aws_availability_zones.primary.names)]
  })
}

resource "aws_route_table" "primary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.primary

  vpc_id = aws_vpc.primary[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary[0].id
  }

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-primary-rt"
    Region = var.primary_region
  })
}

resource "aws_route_table_association" "primary" {
  count    = var.create_vpc_resources ? length(aws_subnet.primary) : 0
  provider = aws.primary

  subnet_id      = aws_subnet.primary[count.index].id
  route_table_id = aws_route_table.primary[0].id
}

# ============================================================================
# VPC and Networking Resources (Secondary Region)
# ============================================================================

resource "aws_vpc" "secondary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.secondary

  cidr_block           = var.secondary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-secondary-vpc"
    Region = var.secondary_region
  })
}

resource "aws_internet_gateway" "secondary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.secondary

  vpc_id = aws_vpc.secondary[0].id

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-secondary-igw"
    Region = var.secondary_region
  })
}

resource "aws_subnet" "secondary" {
  count    = var.create_vpc_resources ? length(var.secondary_subnet_cidrs) : 0
  provider = aws.secondary

  vpc_id                  = aws_vpc.secondary[0].id
  cidr_block              = var.secondary_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.secondary.names[count.index % length(data.aws_availability_zones.secondary.names)]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-secondary-subnet-${count.index + 1}"
    Region = var.secondary_region
    AZ     = data.aws_availability_zones.secondary.names[count.index % length(data.aws_availability_zones.secondary.names)]
  })
}

resource "aws_route_table" "secondary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.secondary

  vpc_id = aws_vpc.secondary[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary[0].id
  }

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-secondary-rt"
    Region = var.secondary_region
  })
}

resource "aws_route_table_association" "secondary" {
  count    = var.create_vpc_resources ? length(aws_subnet.secondary) : 0
  provider = aws.secondary

  subnet_id      = aws_subnet.secondary[count.index].id
  route_table_id = aws_route_table.secondary[0].id
}

# ============================================================================
# IAM Role for Lambda Functions
# ============================================================================

# Trust policy for Lambda execution role
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

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda-health-check-role-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "lambda-health-check-role-${local.suffix}"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Additional policy for Lambda to write CloudWatch metrics
data "aws_iam_policy_document" "lambda_cloudwatch_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "cloudwatch:PutMetricData",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name   = "lambda-cloudwatch-policy-${local.suffix}"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_cloudwatch_policy.json
}

# ============================================================================
# Lambda Function Code Package
# ============================================================================

# Lambda function source code
data "archive_file" "lambda_function_zip" {
  type        = "zip"
  output_path = "${path.module}/health-check-function.zip"
  
  source {
    content = <<EOF
import json
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    """
    Health check endpoint that validates service availability
    Returns HTTP 200 for healthy, 503 for unhealthy
    """
    region = os.environ.get('AWS_REGION', 'unknown')
    simulate_failure = os.environ.get('SIMULATE_FAILURE', 'false').lower()
    
    try:
        current_time = datetime.utcnow().isoformat()
        
        # Check for simulated failure from environment variable
        if simulate_failure == 'true':
            health_status = False
        else:
            # Add actual health validation logic here
            # Example: Check database connectivity, external APIs, etc.
            health_status = check_service_health()
        
        if health_status:
            response = {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'pass'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'region': region,
                    'timestamp': current_time,
                    'version': '1.0'
                })
            }
        else:
            response = {
                'statusCode': 503,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'fail'
                },
                'body': json.dumps({
                    'status': 'unhealthy',
                    'region': region,
                    'timestamp': current_time
                })
            }
            
        return response
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'status': 'error',
                'message': str(e),
                'region': region
            })
        }

def check_service_health():
    """
    Implement actual health check logic
    Returns True if healthy, False otherwise
    """
    # Example health checks:
    # - Database connectivity
    # - External API availability  
    # - Cache service status
    # - Disk space checks
    return True
EOF
    filename = "health-check-function.py"
  }
}

# ============================================================================
# Lambda Functions (Primary and Secondary Regions)
# ============================================================================

# Lambda function in primary region
resource "aws_lambda_function" "health_check_primary" {
  provider = aws.primary

  filename         = data.archive_file.lambda_function_zip.output_path
  function_name    = "${local.lambda_function_name}-primary"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "health-check-function.lambda_handler"
  source_code_hash = data.archive_file.lambda_function_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SIMULATE_FAILURE = var.simulate_failure_on_deploy ? "true" : "false"
      REGION          = var.primary_region
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-primary"
    Region = var.primary_region
  })
}

# Lambda function in secondary region
resource "aws_lambda_function" "health_check_secondary" {
  provider = aws.secondary

  filename         = data.archive_file.lambda_function_zip.output_path
  function_name    = "${local.lambda_function_name}-secondary"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "health-check-function.lambda_handler"
  source_code_hash = data.archive_file.lambda_function_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SIMULATE_FAILURE = "false"
      REGION          = var.secondary_region
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-secondary"
    Region = var.secondary_region
  })
}

# ============================================================================
# VPC Lattice Service Networks
# ============================================================================

# VPC Lattice service network in primary region
resource "aws_vpclattice_service_network" "primary" {
  provider = aws.primary

  name      = local.service_network_name
  auth_type = var.service_auth_type

  tags = merge(local.common_tags, {
    Name   = "${local.service_network_name}-primary"
    Region = var.primary_region
  })
}

# VPC Lattice service network in secondary region
resource "aws_vpclattice_service_network" "secondary" {
  provider = aws.secondary

  name      = local.service_network_name
  auth_type = var.service_auth_type

  tags = merge(local.common_tags, {
    Name   = "${local.service_network_name}-secondary"
    Region = var.secondary_region
  })
}

# Associate VPCs with service networks
resource "aws_vpclattice_service_network_vpc_association" "primary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.primary

  vpc_identifier             = aws_vpc.primary[0].id
  service_network_identifier = aws_vpclattice_service_network.primary.id

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-primary-vpc-association"
    Region = var.primary_region
  })
}

resource "aws_vpclattice_service_network_vpc_association" "secondary" {
  count    = var.create_vpc_resources ? 1 : 0
  provider = aws.secondary

  vpc_identifier             = aws_vpc.secondary[0].id
  service_network_identifier = aws_vpclattice_service_network.secondary.id

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-secondary-vpc-association"
    Region = var.secondary_region
  })
}

# ============================================================================
# VPC Lattice Target Groups
# ============================================================================

# Target group for primary region Lambda
resource "aws_vpclattice_target_group" "primary" {
  provider = aws.primary

  name = "health-check-targets-primary-${local.suffix}"
  type = "LAMBDA"

  config {
    lambda_event_structure_version = "V2"
  }

  tags = merge(local.common_tags, {
    Name   = "health-check-targets-primary-${local.suffix}"
    Region = var.primary_region
  })
}

# Target group for secondary region Lambda
resource "aws_vpclattice_target_group" "secondary" {
  provider = aws.secondary

  name = "health-check-targets-secondary-${local.suffix}"
  type = "LAMBDA"

  config {
    lambda_event_structure_version = "V2"
  }

  tags = merge(local.common_tags, {
    Name   = "health-check-targets-secondary-${local.suffix}"
    Region = var.secondary_region
  })
}

# Register Lambda functions as targets
resource "aws_vpclattice_target_group_attachment" "primary" {
  provider = aws.primary

  target_group_identifier = aws_vpclattice_target_group.primary.id
  
  target {
    id = aws_lambda_function.health_check_primary.arn
  }
}

resource "aws_vpclattice_target_group_attachment" "secondary" {
  provider = aws.secondary

  target_group_identifier = aws_vpclattice_target_group.secondary.id
  
  target {
    id = aws_lambda_function.health_check_secondary.arn
  }
}

# ============================================================================
# VPC Lattice Services
# ============================================================================

# VPC Lattice service in primary region
resource "aws_vpclattice_service" "primary" {
  provider = aws.primary

  name      = "${var.project_name}-service-primary"
  auth_type = var.service_auth_type

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-service-primary"
    Region = var.primary_region
  })
}

# VPC Lattice service in secondary region
resource "aws_vpclattice_service" "secondary" {
  provider = aws.secondary

  name      = "${var.project_name}-service-secondary"
  auth_type = var.service_auth_type

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-service-secondary"
    Region = var.secondary_region
  })
}

# Listeners for VPC Lattice services
resource "aws_vpclattice_listener" "primary" {
  provider = aws.primary

  name               = "health-check-listener"
  protocol           = "HTTPS"
  port               = 443
  service_identifier = aws_vpclattice_service.primary.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.primary.id
      }
    }
  }

  tags = merge(local.common_tags, {
    Name   = "health-check-listener-primary"
    Region = var.primary_region
  })
}

resource "aws_vpclattice_listener" "secondary" {
  provider = aws.secondary

  name               = "health-check-listener"
  protocol           = "HTTPS"
  port               = 443
  service_identifier = aws_vpclattice_service.secondary.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.secondary.id
      }
    }
  }

  tags = merge(local.common_tags, {
    Name   = "health-check-listener-secondary"
    Region = var.secondary_region
  })
}

# Associate services with service networks
resource "aws_vpclattice_service_network_service_association" "primary" {
  provider = aws.primary

  service_identifier         = aws_vpclattice_service.primary.id
  service_network_identifier = aws_vpclattice_service_network.primary.id

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-primary-service-association"
    Region = var.primary_region
  })
}

resource "aws_vpclattice_service_network_service_association" "secondary" {
  provider = aws.secondary

  service_identifier         = aws_vpclattice_service.secondary.id
  service_network_identifier = aws_vpclattice_service_network.secondary.id

  tags = merge(local.common_tags, {
    Name   = "${var.project_name}-secondary-service-association"
    Region = var.secondary_region
  })
}

# Lambda permissions for VPC Lattice to invoke functions
resource "aws_lambda_permission" "primary_vpclattice" {
  provider = aws.primary

  statement_id  = "AllowVPCLatticeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check_primary.function_name
  principal     = "vpc-lattice.amazonaws.com"
}

resource "aws_lambda_permission" "secondary_vpclattice" {
  provider = aws.secondary

  statement_id  = "AllowVPCLatticeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check_secondary.function_name
  principal     = "vpc-lattice.amazonaws.com"
}

# ============================================================================
# Route53 Health Checks
# ============================================================================

# Health check for primary region service
resource "aws_route53_health_check" "primary" {
  fqdn                            = aws_vpclattice_service.primary.dns_entry[0].domain_name
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/"
  failure_threshold               = var.health_check_failure_threshold
  request_interval                = var.health_check_interval
  cloudwatch_alarm_region         = var.primary_region
  cloudwatch_alarm_name           = "Primary-Service-Health-${local.suffix}"
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name   = "primary-service-health-${local.suffix}"
    Region = var.primary_region
  })
}

# Health check for secondary region service
resource "aws_route53_health_check" "secondary" {
  fqdn                            = aws_vpclattice_service.secondary.dns_entry[0].domain_name
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/"
  failure_threshold               = var.health_check_failure_threshold
  request_interval                = var.health_check_interval
  cloudwatch_alarm_region         = var.secondary_region
  cloudwatch_alarm_name           = "Secondary-Service-Health-${local.suffix}"
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name   = "secondary-service-health-${local.suffix}"
    Region = var.secondary_region
  })
}

# ============================================================================
# Route53 Hosted Zone and DNS Records
# ============================================================================

# Route53 hosted zone (conditional creation)
resource "aws_route53_zone" "main" {
  count = var.create_hosted_zone ? 1 : 0

  name = local.domain_name

  tags = merge(local.common_tags, {
    Name = "failover-zone-${local.suffix}"
  })
}

# Get hosted zone ID (either created or existing)
locals {
  hosted_zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.existing_hosted_zone_id
}

# Primary DNS record with failover routing
resource "aws_route53_record" "primary" {
  zone_id = local.hosted_zone_id
  name    = local.domain_name
  type    = "CNAME"
  ttl     = var.dns_record_ttl

  set_identifier = "primary"
  
  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id
  records         = [aws_vpclattice_service.primary.dns_entry[0].domain_name]
}

# Secondary DNS record with failover routing
resource "aws_route53_record" "secondary" {
  zone_id = local.hosted_zone_id
  name    = local.domain_name
  type    = "CNAME"
  ttl     = var.dns_record_ttl

  set_identifier = "secondary"
  
  failover_routing_policy {
    type = "SECONDARY"
  }

  records = [aws_vpclattice_service.secondary.dns_entry[0].domain_name]
}

# ============================================================================
# CloudWatch Alarms for Health Check Monitoring
# ============================================================================

# CloudWatch alarm for primary health check
resource "aws_cloudwatch_metric_alarm" "primary_health_check" {
  count    = var.enable_cloudwatch_alarms ? 1 : 0
  provider = aws.primary

  alarm_name          = "Primary-Service-Health-${local.suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Monitor primary region service health"
  alarm_actions       = []

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  tags = merge(local.common_tags, {
    Name   = "Primary-Service-Health-${local.suffix}"
    Region = var.primary_region
  })
}

# CloudWatch alarm for secondary health check
resource "aws_cloudwatch_metric_alarm" "secondary_health_check" {
  count    = var.enable_cloudwatch_alarms ? 1 : 0
  provider = aws.secondary

  alarm_name          = "Secondary-Service-Health-${local.suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Monitor secondary region service health"
  alarm_actions       = []

  dimensions = {
    HealthCheckId = aws_route53_health_check.secondary.id
  }

  tags = merge(local.common_tags, {
    Name   = "Secondary-Service-Health-${local.suffix}"
    Region = var.secondary_region
  })
}