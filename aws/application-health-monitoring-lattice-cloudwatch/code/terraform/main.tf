# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Data source to get the default VPC if vpc_id is not provided
data "aws_vpc" "selected" {
  id      = var.vpc_id != null ? var.vpc_id : null
  default = var.vpc_id == null && var.use_default_vpc ? true : null
}

# Data source to get subnets from the selected VPC
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Local values for resource naming and configuration
locals {
  name_suffix               = random_id.suffix.hex
  service_network_name      = var.service_network_name != "" ? var.service_network_name : "${var.project_name}-network-${local.name_suffix}"
  service_name             = var.service_name != "" ? var.service_name : "${var.project_name}-service-${local.name_suffix}"
  target_group_name        = var.target_group_name != "" ? var.target_group_name : "${var.project_name}-targets-${local.name_suffix}"
  lambda_function_name     = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-remediation-${local.name_suffix}"
  sns_topic_name          = var.sns_topic_name != "" ? var.sns_topic_name : "${var.project_name}-alerts-${local.name_suffix}"
  dashboard_name          = var.dashboard_name != "" ? var.dashboard_name : "VPCLattice-Health-${local.name_suffix}"
  
  # Use provided subnet IDs or get them from the VPC
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : slice(data.aws_subnets.selected.ids, 0, min(2, length(data.aws_subnets.selected.ids)))
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ======================================================================================
# VPC LATTICE RESOURCES
# ======================================================================================

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = local.service_network_name
  auth_type = var.service_network_auth_type

  tags = merge(local.common_tags, {
    Name        = local.service_network_name
    Purpose     = "health-monitoring"
    ResourceType = "ServiceNetwork"
  })
}

# VPC Lattice Service Network VPC Association
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = data.aws_vpc.selected.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name         = "${local.service_network_name}-vpc-association"
    ResourceType = "ServiceNetworkVpcAssociation"
  })
}

# VPC Lattice Target Group
resource "aws_vpclattice_target_group" "main" {
  name     = local.target_group_name
  type     = "INSTANCE"
  protocol = "HTTP"
  port     = var.health_check_port
  vpc_identifier = data.aws_vpc.selected.id

  config {
    port              = var.health_check_port
    protocol          = var.health_check_protocol
    protocol_version  = "HTTP1"
  }

  health_check {
    enabled                       = var.health_check_enabled
    health_check_interval_seconds = var.health_check_interval_seconds
    health_check_timeout_seconds  = var.health_check_timeout_seconds
    healthy_threshold_count       = var.healthy_threshold_count
    path                         = var.health_check_path
    port                         = var.health_check_port
    protocol                     = var.health_check_protocol
    protocol_version             = "HTTP1"
    unhealthy_threshold_count    = var.unhealthy_threshold_count

    matcher {
      value = "200"
    }
  }

  tags = merge(local.common_tags, {
    Name         = local.target_group_name
    Purpose      = "health-monitoring"
    ResourceType = "TargetGroup"
  })
}

# VPC Lattice Service
resource "aws_vpclattice_service" "main" {
  name      = local.service_name
  auth_type = var.service_auth_type

  tags = merge(local.common_tags, {
    Name         = local.service_name
    Purpose      = "health-monitoring"
    ResourceType = "Service"
  })
}

# VPC Lattice Service Network Service Association
resource "aws_vpclattice_service_network_service_association" "main" {
  service_identifier         = aws_vpclattice_service.main.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name         = "${local.service_name}-network-association"
    ResourceType = "ServiceNetworkServiceAssociation"
  })
}

# VPC Lattice Listener
resource "aws_vpclattice_listener" "main" {
  name               = "http-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.main.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.main.id
        weight                  = 100
      }
    }
  }

  tags = merge(local.common_tags, {
    Name         = "${local.service_name}-http-listener"
    ResourceType = "Listener"
  })
}

# ======================================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ======================================================================================

# SNS Topic for health alerts
resource "aws_sns_topic" "health_alerts" {
  name         = local.sns_topic_name
  display_name = "Application Health Alerts"

  tags = merge(local.common_tags, {
    Name         = local.sns_topic_name
    Purpose      = "health-monitoring"
    ResourceType = "SNSTopic"
  })
}

# SNS Topic Policy to allow CloudWatch to publish
resource "aws_sns_topic_policy" "health_alerts" {
  arn = aws_sns_topic.health_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
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

# Optional email subscription
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.health_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ======================================================================================
# LAMBDA FUNCTION FOR AUTO-REMEDIATION
# ======================================================================================

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "HealthRemediationRole-${local.name_suffix}"

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
    Name         = "HealthRemediationRole-${local.name_suffix}"
    ResourceType = "IAMRole"
  })
}

# IAM Policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "HealthRemediationPolicy-${local.name_suffix}"
  description = "Policy for VPC Lattice health remediation Lambda function"

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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "vpc-lattice:*",
          "sns:Publish",
          "cloudwatch:GetMetricStatistics",
          "ec2:DescribeInstances",
          "ec2:RebootInstances"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name         = "HealthRemediationPolicy-${local.name_suffix}"
    ResourceType = "IAMPolicy"
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      sns_topic_arn = aws_sns_topic.health_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "health_remediation" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.health_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name         = local.lambda_function_name
    Purpose      = "health-monitoring"
    ResourceType = "LambdaFunction"
  })

  depends_on = [aws_iam_role_policy_attachment.lambda_policy_attachment]
}

# Lambda permission for SNS to invoke the function
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_remediation.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.health_alerts.arn
}

# SNS subscription for Lambda function
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.health_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.health_remediation.arn
}

# ======================================================================================
# CLOUDWATCH ALARMS
# ======================================================================================

# CloudWatch Alarm for high 5XX error rate
resource "aws_cloudwatch_metric_alarm" "high_5xx_rate" {
  alarm_name          = "VPCLattice-${local.service_name}-High5XXRate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HTTPCode_5XX_Count"
  namespace           = "AWS/VpcLattice"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.high_5xx_threshold
  alarm_description   = "High 5XX error rate detected for VPC Lattice service ${local.service_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Service = aws_vpclattice_service.main.id
  }

  alarm_actions = [aws_sns_topic.health_alerts.arn]
  ok_actions    = [aws_sns_topic.health_alerts.arn]

  tags = merge(local.common_tags, {
    Name         = "VPCLattice-${local.service_name}-High5XXRate"
    Purpose      = "health-monitoring"
    ResourceType = "CloudWatchAlarm"
  })
}

# CloudWatch Alarm for request timeouts
resource "aws_cloudwatch_metric_alarm" "request_timeouts" {
  alarm_name          = "VPCLattice-${local.service_name}-RequestTimeouts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "RequestTimeoutCount"
  namespace           = "AWS/VpcLattice"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.request_timeout_threshold
  alarm_description   = "High request timeout rate detected for VPC Lattice service ${local.service_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Service = aws_vpclattice_service.main.id
  }

  alarm_actions = [aws_sns_topic.health_alerts.arn]
  ok_actions    = [aws_sns_topic.health_alerts.arn]

  tags = merge(local.common_tags, {
    Name         = "VPCLattice-${local.service_name}-RequestTimeouts"
    Purpose      = "health-monitoring"
    ResourceType = "CloudWatchAlarm"
  })
}

# CloudWatch Alarm for high response times
resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "VPCLattice-${local.service_name}-HighResponseTime"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RequestTime"
  namespace           = "AWS/VpcLattice"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.high_response_time_threshold
  alarm_description   = "High response time detected for VPC Lattice service ${local.service_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Service = aws_vpclattice_service.main.id
  }

  alarm_actions = [aws_sns_topic.health_alerts.arn]

  tags = merge(local.common_tags, {
    Name         = "VPCLattice-${local.service_name}-HighResponseTime"
    Purpose      = "health-monitoring"
    ResourceType = "CloudWatchAlarm"
  })
}

# ======================================================================================
# CLOUDWATCH DASHBOARD
# ======================================================================================

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "health_monitoring" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = local.dashboard_name

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
            ["AWS/VpcLattice", "HTTPCode_2XX_Count", "Service", aws_vpclattice_service.main.id],
            ["AWS/VpcLattice", "HTTPCode_4XX_Count", "Service", aws_vpclattice_service.main.id],
            ["AWS/VpcLattice", "HTTPCode_5XX_Count", "Service", aws_vpclattice_service.main.id]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "HTTP Response Codes"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/VpcLattice", "RequestTime", "Service", aws_vpclattice_service.main.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Request Response Time"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/VpcLattice", "TotalRequestCount", "Service", aws_vpclattice_service.main.id],
            ["AWS/VpcLattice", "RequestTimeoutCount", "Service", aws_vpclattice_service.main.id]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Request Volume and Timeouts"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/VpcLattice", "HealthyTargetCount", "TargetGroup", aws_vpclattice_target_group.main.id],
            ["AWS/VpcLattice", "UnhealthyTargetCount", "TargetGroup", aws_vpclattice_target_group.main.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Target Health Status"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}

# ======================================================================================
# LAMBDA FUNCTION TEMPLATE
# ======================================================================================

# Create the Lambda function template file
resource "local_file" "lambda_function_template" {
  content = <<EOF
import json
import boto3
import os
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Auto-remediation function for VPC Lattice health issues
    """
    try:
        # Parse CloudWatch alarm data
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_state = message['NewStateValue']
        
        logger.info(f"Processing alarm: {alarm_name}, State: {alarm_state}")
        
        if alarm_state == 'ALARM':
            # Determine remediation action based on alarm type
            if '5XX' in alarm_name:
                remediate_error_rate(message)
            elif 'Timeout' in alarm_name:
                remediate_timeouts(message)
            elif 'ResponseTime' in alarm_name:
                remediate_performance(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed alarm: {alarm_name}')
        }
        
    except Exception as e:
        logger.error(f"Error processing alarm: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def remediate_error_rate(alarm_data):
    """Handle high error rate alarms"""
    logger.info("Implementing error rate remediation")
    
    # In a real implementation, you would:
    # 1. Identify unhealthy targets
    # 2. Remove them from the target group
    # 3. Trigger instance replacement
    # 4. Notify operations team
    
    send_notification(
        "🚨 High Error Rate Detected",
        f"Alarm: {alarm_data['AlarmName']}\n"
        f"Action: Investigating unhealthy targets\n"
        f"Time: {alarm_data['StateChangeTime']}"
    )

def remediate_timeouts(alarm_data):
    """Handle timeout alarms"""
    logger.info("Implementing timeout remediation")
    
    send_notification(
        "⏰ Request Timeouts Detected", 
        f"Alarm: {alarm_data['AlarmName']}\n"
        f"Action: Checking target capacity\n"
        f"Time: {alarm_data['StateChangeTime']}"
    )

def remediate_performance(alarm_data):
    """Handle performance degradation"""
    logger.info("Implementing performance remediation")
    
    send_notification(
        "📉 Performance Degradation Detected",
        f"Alarm: {alarm_data['AlarmName']}\n"
        f"Action: Analyzing response times\n"
        f"Time: {alarm_data['StateChangeTime']}"
    )

def send_notification(subject, message):
    """Send SNS notification"""
    try:
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=subject,
            Message=message
        )
        logger.info("Notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
EOF

  filename = "${path.module}/lambda_function.py.tpl"
}