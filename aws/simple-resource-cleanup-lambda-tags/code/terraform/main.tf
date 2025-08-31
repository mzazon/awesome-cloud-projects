# Resource Cleanup Automation Infrastructure
# This Terraform configuration creates an automated resource cleanup system
# using AWS Lambda, SNS, and CloudWatch Events for cost optimization

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming pattern for resources
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
      Purpose     = "resource-cleanup-automation"
    },
    var.additional_tags
  )
}

# ====================================================================
# SNS Topic for Cleanup Notifications
# ====================================================================

# SNS topic for sending cleanup notifications to administrators
resource "aws_sns_topic" "cleanup_alerts" {
  name         = "${local.name_prefix}-cleanup-alerts-${local.name_suffix}"
  display_name = "Resource Cleanup Alerts"

  # Enable encryption at rest using AWS managed keys
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cleanup-alerts-${local.name_suffix}"
    Type = "notification"
  })
}

# SNS topic policy to allow Lambda function to publish messages
resource "aws_sns_topic_policy" "cleanup_alerts_policy" {
  arn = aws_sns_topic.cleanup_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution_role.arn
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.cleanup_alerts.arn
      }
    ]
  })
}

# Email subscription to SNS topic (conditional based on variable)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cleanup_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ====================================================================
# IAM Role and Policies for Lambda Function
# ====================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"

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
    Name = "${local.name_prefix}-lambda-role-${local.name_suffix}"
    Type = "iam-role"
  })
}

# Custom IAM policy for resource cleanup permissions
resource "aws_iam_role_policy" "lambda_cleanup_policy" {
  name = "${local.name_prefix}-lambda-cleanup-policy"
  role = aws_iam_role.lambda_execution_role.id

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
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances"
        ]
        Resource = "*"
        Condition = var.dry_run_mode ? {
          "Bool" = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        } : {}
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cleanup_alerts.arn
      }
    ]
  })
}

# ====================================================================
# Lambda Function for Resource Cleanup
# ====================================================================

# Archive the Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/cleanup_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      sns_topic_arn     = aws_sns_topic.cleanup_alerts.arn
      cleanup_tag_key   = var.cleanup_tag_key
      cleanup_tag_values = jsonencode(var.cleanup_tag_values)
      dry_run_mode      = var.dry_run_mode
      aws_region        = data.aws_region.current.name
    })
    filename = "lambda_function.py"
  }
}

# Create the Lambda function source code template
resource "local_file" "lambda_function_template" {
  content = <<-EOT
import json
import boto3
import os
from datetime import datetime, timezone
from typing import List, Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda function to automatically clean up EC2 instances based on tags.
    
    This function identifies EC2 instances with specific cleanup tags and terminates them
    to optimize costs. It sends notifications via SNS about cleanup actions performed.
    
    Args:
        event: Lambda event data (not used in this implementation)
        context: Lambda context object containing runtime information
        
    Returns:
        Dictionary containing status code and response body
    """
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2', region_name=os.environ.get('AWS_REGION'))
    sns = boto3.client('sns', region_name=os.environ.get('AWS_REGION'))
    
    # Configuration from environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    cleanup_tag_key = os.environ['CLEANUP_TAG_KEY']
    cleanup_tag_values = json.loads(os.environ['CLEANUP_TAG_VALUES'])
    dry_run_mode = os.environ.get('DRY_RUN_MODE', 'false').lower() == 'true'
    
    try:
        # Query instances with cleanup tag
        print(f"Searching for instances with tag {cleanup_tag_key} in values: {cleanup_tag_values}")
        
        response = ec2.describe_instances(
            Filters=[
                {
                    'Name': f'tag:{cleanup_tag_key}',
                    'Values': cleanup_tag_values
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running', 'stopped', 'stopping']
                }
            ]
        )
        
        instances_to_cleanup = []
        
        # Extract instance information
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_name = 'Unnamed'
                instance_type = instance.get('InstanceType', 'Unknown')
                instance_state = instance['State']['Name']
                launch_time = instance.get('LaunchTime', datetime.now(timezone.utc))
                
                # Get instance name from tags
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_name = tag['Value']
                        break
                
                # Calculate instance age
                age_days = (datetime.now(timezone.utc) - launch_time.replace(tzinfo=timezone.utc)).days
                
                instances_to_cleanup.append({
                    'InstanceId': instance_id,
                    'Name': instance_name,
                    'State': instance_state,
                    'Type': instance_type,
                    'LaunchTime': launch_time.isoformat(),
                    'AgeDays': age_days
                })
        
        if not instances_to_cleanup:
            message = f"No instances found with {cleanup_tag_key} tag for cleanup"
            print(message)
            
            # Send notification about no instances found
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='AWS Resource Cleanup - No Action Needed',
                Message=f"""
AWS Resource Cleanup Report
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {os.environ.get('AWS_REGION', 'Unknown')}

No EC2 instances found with {cleanup_tag_key} tag requiring cleanup.

Search criteria:
- Tag key: {cleanup_tag_key}
- Tag values: {', '.join(cleanup_tag_values)}
- Instance states: running, stopped, stopping

This indicates all resources are properly managed or no resources are tagged for cleanup.
"""
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps(message)
            }
        
        # Prepare notification message
        action_word = "identified" if dry_run_mode else "terminated"
        mode_notice = " (DRY RUN MODE - No instances were actually terminated)" if dry_run_mode else ""
        
        message = f"""
AWS Resource Cleanup Report{mode_notice}
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {os.environ.get('AWS_REGION', 'Unknown')}
Mode: {'Dry Run' if dry_run_mode else 'Live'}

The following EC2 instances were {action_word}:

"""
        
        total_estimated_monthly_savings = 0
        instance_ids = []
        
        for instance in instances_to_cleanup:
            instance_ids.append(instance['InstanceId'])
            
            # Basic cost estimation (simplified)
            estimated_monthly_cost = get_estimated_monthly_cost(instance['Type'])
            total_estimated_monthly_savings += estimated_monthly_cost
            
            message += f"- {instance['Name']} ({instance['InstanceId']})\n"
            message += f"  Type: {instance['Type']}, State: {instance['State']}\n"
            message += f"  Age: {instance['AgeDays']} days\n"
            message += f"  Estimated monthly cost: ${estimated_monthly_cost:.2f}\n\n"
        
        message += f"Total instances {action_word}: {len(instances_to_cleanup)}\n"
        message += f"Estimated monthly savings: ${total_estimated_monthly_savings:.2f}\n"
        
        if not dry_run_mode:
            message += f"\nTag criteria used:\n"
            message += f"- Tag key: {cleanup_tag_key}\n"
            message += f"- Tag values: {', '.join(cleanup_tag_values)}\n"
        
        # Terminate instances (only if not in dry run mode)
        if not dry_run_mode and instance_ids:
            print(f"Terminating {len(instance_ids)} instances: {instance_ids}")
            terminate_response = ec2.terminate_instances(InstanceIds=instance_ids)
            
            # Log termination details
            for instance_change in terminate_response.get('TerminatingInstances', []):
                print(f"Instance {instance_change['InstanceId']} state changed from "
                      f"{instance_change['PreviousState']['Name']} to "
                      f"{instance_change['CurrentState']['Name']}")
        
        # Send SNS notification
        subject = f"AWS Resource Cleanup {'Dry Run ' if dry_run_mode else ''}Completed"
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=message
        )
        
        success_message = f"Successfully {action_word} {len(instances_to_cleanup)} instances"
        print(success_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': success_message,
                'instances_processed': len(instances_to_cleanup),
                'estimated_monthly_savings': total_estimated_monthly_savings,
                'dry_run_mode': dry_run_mode
            })
        }
        
    except Exception as e:
        error_message = f"Error during cleanup: {str(e)}"
        print(error_message)
        
        # Send error notification
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='AWS Resource Cleanup Error',
                Message=f"""
Error occurred during resource cleanup:

Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {os.environ.get('AWS_REGION', 'Unknown')}
Function: {context.function_name if context else 'Unknown'}

Error Details:
{error_message}

Please check CloudWatch logs for more details and investigate the issue.
Log Group: /aws/lambda/{context.function_name if context else 'resource-cleanup'}
"""
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'dry_run_mode': dry_run_mode
            })
        }

def get_estimated_monthly_cost(instance_type: str) -> float:
    """
    Get estimated monthly cost for an EC2 instance type.
    
    This is a simplified cost estimation based on common pricing.
    For accurate costs, integrate with AWS Pricing API or Cost Explorer.
    
    Args:
        instance_type: EC2 instance type (e.g., 't2.micro', 'm5.large')
        
    Returns:
        Estimated monthly cost in USD
    """
    
    # Simplified cost mapping (US East 1 on-demand pricing, approximate)
    # These are example costs and should be updated based on current AWS pricing
    cost_map = {
        't2.nano': 4.5,      # $0.0058/hour * 24 * 30
        't2.micro': 8.5,     # $0.0116/hour * 24 * 30  
        't2.small': 17.0,    # $0.023/hour * 24 * 30
        't2.medium': 34.0,   # $0.0464/hour * 24 * 30
        't2.large': 68.0,    # $0.0928/hour * 24 * 30
        't3.micro': 7.7,     # $0.0104/hour * 24 * 30
        't3.small': 15.4,    # $0.0208/hour * 24 * 30
        't3.medium': 30.8,   # $0.0416/hour * 24 * 30
        't3.large': 61.6,    # $0.0832/hour * 24 * 30
        'm5.large': 70.0,    # $0.096/hour * 24 * 30
        'm5.xlarge': 140.0,  # $0.192/hour * 24 * 30
        'c5.large': 62.5,    # $0.085/hour * 24 * 30
        'r5.large': 91.3,    # $0.126/hour * 24 * 30
    }
    
    # Return specific cost if found, otherwise estimate based on instance family
    if instance_type in cost_map:
        return cost_map[instance_type]
    
    # Generic estimation based on instance family
    if instance_type.startswith('t2.') or instance_type.startswith('t3.'):
        return 25.0  # Average for burstable instances
    elif instance_type.startswith('m5.') or instance_type.startswith('m4.'):
        return 80.0  # Average for general purpose
    elif instance_type.startswith('c5.') or instance_type.startswith('c4.'):
        return 75.0  # Average for compute optimized
    elif instance_type.startswith('r5.') or instance_type.startswith('r4.'):
        return 100.0  # Average for memory optimized
    else:
        return 50.0   # Generic fallback estimate
EOT
  filename = "${path.module}/lambda_function.py.tpl"
}

# Lambda function for resource cleanup
resource "aws_lambda_function" "resource_cleanup" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "${local.name_prefix}-cleanup-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  description = "Automated cleanup of EC2 instances based on tags for cost optimization"

  environment {
    variables = {
      SNS_TOPIC_ARN      = aws_sns_topic.cleanup_alerts.arn
      CLEANUP_TAG_KEY    = var.cleanup_tag_key
      CLEANUP_TAG_VALUES = jsonencode(var.cleanup_tag_values)
      DRY_RUN_MODE       = tostring(var.dry_run_mode)
      AWS_REGION         = data.aws_region.current.name
    }
  }

  # Enable tracing for better observability
  tracing_config {
    mode = "Active"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cleanup-${local.name_suffix}"
    Type = "lambda-function"
  })

  depends_on = [
    aws_iam_role_policy.lambda_cleanup_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-cleanup-${local.name_suffix}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cleanup-logs-${local.name_suffix}"
    Type = "log-group"
  })
}

# ====================================================================
# CloudWatch Events (EventBridge) for Scheduled Execution
# ====================================================================

# CloudWatch Events rule for scheduled cleanup (optional)
resource "aws_cloudwatch_event_rule" "cleanup_schedule" {
  count               = var.enable_scheduled_cleanup ? 1 : 0
  name                = "${local.name_prefix}-cleanup-schedule-${local.name_suffix}"
  description         = "Trigger resource cleanup Lambda function on schedule"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cleanup-schedule-${local.name_suffix}"
    Type = "cloudwatch-event-rule"
  })
}

# CloudWatch Events target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.enable_scheduled_cleanup ? 1 : 0
  rule      = aws_cloudwatch_event_rule.cleanup_schedule[0].name
  target_id = "ResourceCleanupLambdaTarget"
  arn       = aws_lambda_function.resource_cleanup.arn
}

# Permission for CloudWatch Events to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_scheduled_cleanup ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resource_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup_schedule[0].arn
}

# ====================================================================
# CloudWatch Alarms for Monitoring
# ====================================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name_prefix}-cleanup-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lambda function errors detected"
  alarm_actions       = [aws_sns_topic.cleanup_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.resource_cleanup.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cleanup-errors-${local.name_suffix}"
    Type = "cloudwatch-alarm" 
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.name_prefix}-cleanup-duration-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8) # 80% of timeout in milliseconds
  alarm_description   = "Lambda function duration approaching timeout"
  alarm_actions       = [aws_sns_topic.cleanup_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.resource_cleanup.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cleanup-duration-${local.name_suffix}"
    Type = "cloudwatch-alarm"
  })
}