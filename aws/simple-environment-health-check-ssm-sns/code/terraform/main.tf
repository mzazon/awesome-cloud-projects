# main.tf
# Main Terraform configuration for simple-environment-health-check-ssm-sns

# Data sources for AWS account information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for resource naming and common configurations
locals {
  resource_suffix = random_string.suffix.result
  common_tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    Purpose      = "HealthMonitoring"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  }
}

# ========================================
# SNS Topic and Subscription
# ========================================

# SNS topic for health notifications
resource "aws_sns_topic" "health_alerts" {
  name         = "${var.project_name}-alerts-${local.resource_suffix}"
  display_name = "Environment Health Alerts"

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alerts-${local.resource_suffix}"
    Type = "NotificationTopic"
  })
}

# Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.health_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  # Automatically confirm subscription (requires manual confirmation via email)
  depends_on = [aws_sns_topic.health_alerts]
}

# SNS topic policy for EventBridge access
resource "aws_sns_topic_policy" "health_alerts_policy" {
  arn = aws_sns_topic.health_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.health_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ========================================
# Lambda Function for Health Checks
# ========================================

# IAM role for Lambda function
resource "aws_iam_role" "health_check_lambda_role" {
  name = "HealthCheckLambdaRole-${local.resource_suffix}"

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
    Name = "HealthCheckLambdaRole-${local.resource_suffix}"
    Type = "IAMRole"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.health_check_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for Systems Manager and SNS access
resource "aws_iam_policy" "health_check_policy" {
  name        = "HealthCheckPolicy-${local.resource_suffix}"
  description = "Policy for health check Lambda to access SSM and SNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:PutComplianceItems",
          "ssm:ListComplianceItems",
          "ssm:GetComplianceSummary"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.health_alerts.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "HealthCheckPolicy-${local.resource_suffix}"
    Type = "IAMPolicy"
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "health_check_policy_attachment" {
  role       = aws_iam_role.health_check_lambda_role.name
  policy_arn = aws_iam_policy.health_check_policy.arn
}

# Archive Lambda function code
data "archive_file" "health_check_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/health_check_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      sns_topic_arn    = aws_sns_topic.health_alerts.arn
      compliance_type  = var.compliance_type
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for health checks
resource "aws_lambda_function" "health_check" {
  function_name    = "${var.project_name}-${local.resource_suffix}"
  role            = aws_iam_role.health_check_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.health_check_lambda_zip.output_base64sha256
  filename        = data.archive_file.health_check_lambda_zip.output_path

  runtime     = "python3.12"
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.health_alerts.arn
      COMPLIANCE_TYPE = var.compliance_type
      LOG_LEVEL      = "INFO"
    }
  }

  # Enable CloudWatch Logs retention
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.health_check_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.resource_suffix}"
    Type = "LambdaFunction"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${local.resource_suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${var.project_name}-${local.resource_suffix}"
    Type = "LogGroup"
  })
}

# Create Lambda function source code template
resource "local_file" "lambda_function_template" {
  content = <<-EOT
import json
import boto3
import logging
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logger.setLevel(getattr(logging, log_level, logging.INFO))

def lambda_handler(event, context):
    """
    Health check function that monitors SSM agent status
    and updates Systems Manager compliance accordingly.
    """
    ssm = boto3.client('ssm')
    sns = boto3.client('sns')
    
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    compliance_type = os.environ.get('COMPLIANCE_TYPE', '${compliance_type}')
    
    try:
        # Get all managed instances
        response = ssm.describe_instance_information()
        
        compliance_items = []
        non_compliant_instances = []
        
        for instance in response['InstanceInformationList']:
            instance_id = instance['InstanceId']
            ping_status = instance['PingStatus']
            last_ping_time = instance.get('LastPingDateTime', 'Unknown')
            
            # Determine compliance status based on ping status
            status = 'COMPLIANT' if ping_status == 'Online' else 'NON_COMPLIANT'
            severity = 'HIGH' if status == 'NON_COMPLIANT' else 'INFORMATIONAL'
            
            if status == 'NON_COMPLIANT':
                non_compliant_instances.append({
                    'InstanceId': instance_id,
                    'PingStatus': ping_status,
                    'LastPingTime': str(last_ping_time)
                })
            
            # Update compliance with enhanced details
            compliance_item = {
                'Id': f'HealthCheck-{instance_id}',
                'Title': 'InstanceConnectivityCheck',
                'Severity': severity,
                'Status': status,
                'Details': {
                    'PingStatus': ping_status,
                    'LastPingTime': str(last_ping_time),
                    'CheckTime': datetime.utcnow().isoformat() + 'Z'
                }
            }
            
            ssm.put_compliance_items(
                ResourceId=instance_id,
                ResourceType='ManagedInstance',
                ComplianceType=compliance_type,
                ExecutionSummary={
                    'ExecutionTime': datetime.utcnow().isoformat() + 'Z'
                },
                Items=[compliance_item]
            )
            
            compliance_items.append(compliance_item)
        
        # Log health check results
        logger.info(f"Health check completed for {len(compliance_items)} instances")
        
        # Send notification if there are non-compliant instances
        if non_compliant_instances and sns_topic_arn:
            message = f"Environment Health Alert: {len(non_compliant_instances)} instances are non-compliant\\n\\n"
            for instance in non_compliant_instances:
                message += f"Instance: {instance['InstanceId']}, Status: {instance['PingStatus']}, Last Ping: {instance['LastPingTime']}\\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Environment Health Alert",
                Message=message
            )
            
            logger.warning(f"Sent alert for {len(non_compliant_instances)} non-compliant instances")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Health check completed successfully',
                'total_instances': len(compliance_items),
                'non_compliant_instances': len(non_compliant_instances)
            })
        }
        
    except ClientError as e:
        error_message = f"AWS API error: {str(e)}"
        logger.error(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {error_message}')
        }
    except Exception as e:
        error_message = f"Unexpected error: {str(e)}"
        logger.error(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {error_message}')
        }
EOT
  filename = "${path.module}/lambda_function.py.tpl"
}

# ========================================
# EventBridge Rules and Targets
# ========================================

# EventBridge rule for scheduled health checks
resource "aws_cloudwatch_event_rule" "health_check_schedule" {
  name                = "health-check-schedule-${local.resource_suffix}"
  description         = "Schedule health checks at regular intervals"
  schedule_expression = var.health_check_schedule
  state              = "ENABLED"

  tags = merge(local.common_tags, {
    Name = "health-check-schedule-${local.resource_suffix}"
    Type = "EventBridgeRule"
  })
}

# EventBridge target for scheduled health checks
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.health_check_schedule.name
  target_id = "HealthCheckLambdaTarget"
  arn       = aws_lambda_function.health_check.arn

  input = jsonencode({
    source = "eventbridge-schedule"
  })
}

# Lambda permission for EventBridge to invoke function
resource "aws_lambda_permission" "allow_eventbridge_schedule" {
  statement_id  = "AllowExecutionFromEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check_schedule.arn
}

# EventBridge rule for compliance state changes
resource "aws_cloudwatch_event_rule" "compliance_alerts" {
  name        = "compliance-health-alerts-${local.resource_suffix}"
  description = "Respond to compliance state changes for health monitoring"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Configuration Compliance State Change"]
    detail = {
      compliance-type   = [var.compliance_type]
      compliance-status = ["NON_COMPLIANT"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "compliance-health-alerts-${local.resource_suffix}"
    Type = "EventBridgeRule"
  })
}

# EventBridge target for compliance alerts
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.compliance_alerts.name
  target_id = "ComplianceAlertSNSTarget"
  arn       = aws_sns_topic.health_alerts.arn

  input_transformer {
    input_paths = {
      instance = "$.detail.resource-id"
      status   = "$.detail.compliance-status"
      time     = "$.time"
    }
    input_template = "Environment Health Alert: Instance <instance> is <status> at <time>. Please investigate immediately."
  }
}

# ========================================
# CloudWatch Dashboards (Optional)
# ========================================

# CloudWatch dashboard for health monitoring
resource "aws_cloudwatch_dashboard" "health_monitoring" {
  dashboard_name = "${var.project_name}-dashboard-${local.resource_suffix}"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.health_check.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Health Check Lambda Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.health_check.function_name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Health Check Lambda Logs"
          view    = "table"
        }
      }
    ]
  })
}

# ========================================
# Systems Manager Initial Compliance Setup
# ========================================

# Data source to get available EC2 instances
data "aws_instances" "managed_instances" {
  instance_state_names = ["running"]
  
  filter {
    name   = "tag:SSMManaged"
    values = ["true"]
  }
}

# Initial compliance baseline (only if instances exist)
resource "aws_ssm_compliance_item" "initial_baseline" {
  count = length(data.aws_instances.managed_instances.ids) > 0 ? 1 : 0
  
  resource_id   = data.aws_instances.managed_instances.ids[0]
  resource_type = "ManagedInstance"
  compliance_type = var.compliance_type
  
  execution_summary = {
    execution_id   = "initial-setup-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
    execution_time = timestamp()
    execution_type = "Command"
  }

  item_details = {
    "InitialHealthCheck" = {
      title    = "EnvironmentHealthStatus"
      severity = "INFORMATIONAL"
      status   = "COMPLIANT"
    }
  }
}