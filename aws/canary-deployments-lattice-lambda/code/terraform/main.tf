# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = random_id.suffix.hex
  
  # Common resource naming
  function_name           = "${var.project_name}-function-${local.resource_suffix}"
  service_name           = "${var.project_name}-service-${local.resource_suffix}"
  service_network_name   = "${var.project_name}-network-${local.resource_suffix}"
  prod_target_group_name = "${var.project_name}-prod-targets-${local.resource_suffix}"
  canary_target_group_name = "${var.project_name}-canary-targets-${local.resource_suffix}"
  rollback_function_name = "${var.project_name}-rollback-${local.resource_suffix}"
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###############################
# IAM Roles and Policies
###############################

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-canary-execution-role-${local.resource_suffix}"

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

  tags = merge(var.default_tags, {
    Name = "lambda-canary-execution-role-${local.resource_suffix}"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC Lattice service access policy
resource "aws_iam_role_policy_attachment" "vpc_lattice_service_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/VPCLatticeServiceAccess"
}

# Additional IAM policy for rollback function
resource "aws_iam_role_policy" "rollback_function_policy" {
  count = var.enable_rollback_function ? 1 : 0
  name  = "rollback-function-policy-${local.resource_suffix}"
  role  = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "vpc-lattice:UpdateListener",
          "vpc-lattice:GetListener",
          "vpc-lattice:GetService"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################
# Lambda Functions
###############################

# Create Lambda function code for version 1 (production)
data "archive_file" "lambda_v1_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-v1.zip"
  
  source {
    content = <<EOF
import json
import time

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'version': 'v1.0.0',
            'message': 'Hello from production version',
            'timestamp': int(time.time()),
            'environment': 'production'
        })
    }
EOF
    filename = "lambda-v1.py"
  }
}

# Create Lambda function code for version 2 (canary)
data "archive_file" "lambda_v2_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-v2.zip"
  
  source {
    content = <<EOF
import json
import time
import random

def lambda_handler(event, context):
    # Simulate enhanced features in canary version
    features = ['feature-a', 'feature-b', 'enhanced-logging']
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Version': 'v2.0.0'
        },
        'body': json.dumps({
            'version': 'v2.0.0',
            'message': 'Hello from canary version',
            'timestamp': int(time.time()),
            'environment': 'canary',
            'features': features,
            'response_time': random.randint(50, 200)
        })
    }
EOF
    filename = "lambda-v2.py"
  }
}

# Main Lambda function
resource "aws_lambda_function" "canary_demo_function" {
  filename         = data.archive_file.lambda_v1_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda-v1.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_v1_zip.output_base64sha256

  description = "Production version for canary deployment demo"

  tags = merge(var.default_tags, {
    Name = local.function_name
    Version = "1.0.0"
  })
}

# Publish version 1 (production)
resource "aws_lambda_version" "version_1" {
  function_name = aws_lambda_function.canary_demo_function.function_name
  description   = "Production version 1.0.0"
  
  depends_on = [aws_lambda_function.canary_demo_function]
}

# Update function code for version 2 and publish
resource "aws_lambda_function" "canary_demo_function_v2" {
  filename         = data.archive_file.lambda_v2_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda-v2.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_v2_zip.output_base64sha256

  description = "Canary version for canary deployment demo"

  tags = merge(var.default_tags, {
    Name = local.function_name
    Version = "2.0.0"
  })
  
  depends_on = [aws_lambda_version.version_1]
}

# Publish version 2 (canary)
resource "aws_lambda_version" "version_2" {
  function_name = aws_lambda_function.canary_demo_function_v2.function_name
  description   = "Canary version 2.0.0 with enhanced features"
  
  depends_on = [aws_lambda_function.canary_demo_function_v2]
}

###############################
# VPC Lattice Resources
###############################

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "canary_service_network" {
  name      = local.service_network_name
  auth_type = var.service_auth_type

  tags = merge(var.default_tags, {
    Name = local.service_network_name
  })
}

# Target Group for Production Version (v1)
resource "aws_vpclattice_target_group" "production_targets" {
  name = local.prod_target_group_name
  type = "LAMBDA"

  tags = merge(var.default_tags, {
    Name = local.prod_target_group_name
    Environment = "production"
  })
}

# Target Group for Canary Version (v2)
resource "aws_vpclattice_target_group" "canary_targets" {
  name = local.canary_target_group_name
  type = "LAMBDA"

  tags = merge(var.default_tags, {
    Name = local.canary_target_group_name
    Environment = "canary"
  })
}

# Register Lambda version 1 with production target group
resource "aws_vpclattice_target_group_attachment" "production_target" {
  target_group_identifier = aws_vpclattice_target_group.production_targets.id
  
  target {
    id = "${aws_lambda_function.canary_demo_function.function_name}:${aws_lambda_version.version_1.version}"
  }
}

# Register Lambda version 2 with canary target group
resource "aws_vpclattice_target_group_attachment" "canary_target" {
  target_group_identifier = aws_vpclattice_target_group.canary_targets.id
  
  target {
    id = "${aws_lambda_function.canary_demo_function_v2.function_name}:${aws_lambda_version.version_2.version}"
  }
}

# VPC Lattice Service
resource "aws_vpclattice_service" "canary_service" {
  name      = local.service_name
  auth_type = var.service_auth_type

  tags = merge(var.default_tags, {
    Name = local.service_name
  })
}

# VPC Lattice Listener with weighted routing for canary deployment
resource "aws_vpclattice_listener" "canary_listener" {
  name               = "canary-listener"
  protocol           = var.listener_protocol
  port               = var.listener_port
  service_identifier = aws_vpclattice_service.canary_service.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.production_targets.id
        weight                  = var.production_weight
      }
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.canary_targets.id
        weight                  = var.initial_canary_weight
      }
    }
  }

  tags = merge(var.default_tags, {
    Name = "canary-listener"
  })
}

# Associate service with service network
resource "aws_vpclattice_service_network_service_association" "canary_service_association" {
  service_identifier         = aws_vpclattice_service.canary_service.id
  service_network_identifier = aws_vpclattice_service_network.canary_service_network.id

  tags = var.default_tags
}

###############################
# CloudWatch Monitoring
###############################

# CloudWatch alarm for Lambda errors in canary version
resource "aws_cloudwatch_metric_alarm" "canary_lambda_errors" {
  alarm_name          = "canary-lambda-errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "Monitor errors in canary Lambda version"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.canary_demo_function_v2.function_name
    Resource     = "${aws_lambda_function.canary_demo_function_v2.function_name}:${aws_lambda_version.version_2.version}"
  }

  alarm_actions = var.enable_sns_notifications ? [aws_sns_topic.rollback_topic[0].arn] : []

  tags = merge(var.default_tags, {
    Name = "canary-lambda-errors-${local.resource_suffix}"
  })
}

# CloudWatch alarm for Lambda duration in canary version
resource "aws_cloudwatch_metric_alarm" "canary_lambda_duration" {
  alarm_name          = "canary-lambda-duration-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.duration_threshold
  alarm_description   = "Monitor duration in canary Lambda version"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.canary_demo_function_v2.function_name
    Resource     = "${aws_lambda_function.canary_demo_function_v2.function_name}:${aws_lambda_version.version_2.version}"
  }

  alarm_actions = var.enable_sns_notifications ? [aws_sns_topic.rollback_topic[0].arn] : []

  tags = merge(var.default_tags, {
    Name = "canary-lambda-duration-${local.resource_suffix}"
  })
}

###############################
# SNS and Rollback Function
###############################

# SNS topic for rollback notifications
resource "aws_sns_topic" "rollback_topic" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "canary-rollback-${local.resource_suffix}"

  tags = merge(var.default_tags, {
    Name = "canary-rollback-${local.resource_suffix}"
  })
}

# Lambda function for automatic rollback
data "archive_file" "rollback_function_zip" {
  count       = var.enable_rollback_function ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/rollback-function.zip"
  
  source {
    content = <<EOF
import boto3
import json
import os

def lambda_handler(event, context):
    lattice = boto3.client('vpc-lattice')
    
    # Parse CloudWatch alarm
    message = json.loads(event['Records'][0]['Sns']['Message'])
    alarm_name = message['AlarmName']
    
    if 'canary' in alarm_name and message['NewStateValue'] == 'ALARM':
        # Rollback to 100% production traffic
        try:
            lattice.update_listener(
                serviceIdentifier=os.environ['SERVICE_ID'],
                listenerIdentifier=os.environ['LISTENER_ID'],
                defaultAction={
                    'forward': {
                        'targetGroups': [
                            {
                                'targetGroupIdentifier': os.environ['PROD_TARGET_GROUP_ID'],
                                'weight': 100
                            }
                        ]
                    }
                }
            )
            print(f"Automatic rollback triggered by alarm: {alarm_name}")
            return {'statusCode': 200, 'body': 'Rollback successful'}
        except Exception as e:
            print(f"Rollback failed: {str(e)}")
            return {'statusCode': 500, 'body': f'Rollback failed: {str(e)}'}
    
    return {'statusCode': 200, 'body': 'No action required'}
EOF
    filename = "rollback-function.py"
  }
}

resource "aws_lambda_function" "rollback_function" {
  count            = var.enable_rollback_function ? 1 : 0
  filename         = data.archive_file.rollback_function_zip[0].output_path
  function_name    = local.rollback_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "rollback-function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.rollback_function_zip[0].output_base64sha256

  environment {
    variables = {
      SERVICE_ID            = aws_vpclattice_service.canary_service.id
      LISTENER_ID           = aws_vpclattice_listener.canary_listener.id
      PROD_TARGET_GROUP_ID  = aws_vpclattice_target_group.production_targets.id
    }
  }

  tags = merge(var.default_tags, {
    Name = local.rollback_function_name
    Purpose = "automatic-rollback"
  })
}

# SNS topic subscription for rollback function
resource "aws_sns_topic_subscription" "rollback_subscription" {
  count     = var.enable_rollback_function && var.enable_sns_notifications ? 1 : 0
  topic_arn = aws_sns_topic.rollback_topic[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.rollback_function[0].arn
}

# Lambda permission for SNS to invoke rollback function
resource "aws_lambda_permission" "allow_sns_invoke" {
  count         = var.enable_rollback_function && var.enable_sns_notifications ? 1 : 0
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rollback_function[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.rollback_topic[0].arn
}