# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  budget_name = var.budget_name != "" ? var.budget_name : "${local.name_prefix}-${local.random_suffix}"
  sns_topic_name = "${local.name_prefix}-alerts-${local.random_suffix}"
  lambda_function_name = "${local.name_prefix}-action-${local.random_suffix}"
  
  common_tags = merge(var.additional_tags, {
    Name        = local.name_prefix
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# SNS Topic for Budget Notifications
resource "aws_sns_topic" "budget_alerts" {
  name         = local.sns_topic_name
  display_name = "Budget Alerts Topic"
  
  tags = merge(local.common_tags, {
    Description = "SNS topic for AWS Budget alerts and notifications"
  })
}

# SNS Topic Policy to allow AWS Budgets service to publish
resource "aws_sns_topic_policy" "budget_alerts" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBudgetsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.budget_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.random_suffix}"

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
    Description = "IAM role for budget action Lambda function"
  })
}

# IAM Policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.name_prefix}-lambda-policy-${local.random_suffix}"
  description = "IAM policy for budget action Lambda function"

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
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.budget_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "budgets:ViewBudget",
          "budgets:ModifyBudget"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/budget_action_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        # Parse the budget alert event
        message = json.loads(event['Records'][0]['Sns']['Message'])
        budget_name = message.get('BudgetName', 'Unknown')
        account_id = message.get('AccountId', 'Unknown')
        
        logger.info(f"Budget alert triggered for {budget_name} in account {account_id}")
        
        # Initialize AWS clients
        ec2 = boto3.client('ec2')
        sns = boto3.client('sns')
        
        # Get development instances (tagged as Environment=Development)
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Environment', 'Values': ['Development', 'Dev']},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        instances_to_stop = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instances_to_stop.append(instance['InstanceId'])
        
        # Stop development instances
        if instances_to_stop:
            ec2.stop_instances(InstanceIds=instances_to_stop)
            logger.info(f"Stopped {len(instances_to_stop)} development instances")
            
            # Send notification
            sns.publish(
                TopicArn='${aws_sns_topic.budget_alerts.arn}',
                Subject=f'Budget Action Executed - {budget_name}',
                Message=f'Automatically stopped {len(instances_to_stop)} development instances due to budget alert.\n\nInstances: {", ".join(instances_to_stop)}'
            )
        else:
            logger.info("No development instances found to stop")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Budget action completed for {budget_name}',
                'instances_stopped': len(instances_to_stop)
            })
        }
        
    except Exception as e:
        logger.error(f"Error executing budget action: {str(e)}")
        raise e
EOF
    filename = "budget_action_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "budget_action" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "budget_action_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Automated budget action function"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.budget_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Description = "Lambda function for automated budget actions"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Description = "Log group for budget action Lambda function"
  })
}

# Lambda permission for SNS to invoke the function
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.budget_action.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.budget_alerts.arn
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "lambda_notification" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.budget_action.arn
}

# IAM Role for Budget Actions
resource "aws_iam_role" "budget_action_role" {
  name = "${local.name_prefix}-budget-action-role-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Description = "IAM role for AWS Budgets automated actions"
  })
}

# Attach AWS managed policy for budget actions
resource "aws_iam_role_policy_attachment" "budget_action_policy" {
  role       = aws_iam_role.budget_action_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/BudgetsActionsWithAWSResourceControlAccess"
}

# Budget restriction policy for automated actions
resource "aws_iam_policy" "budget_restriction_policy" {
  name        = "${local.name_prefix}-budget-restriction-policy-${local.random_suffix}"
  description = "Policy to restrict expensive resources when budget is exceeded"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:StartInstances",
          "rds:CreateDBInstance",
          "rds:StartDBInstance"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "ec2:InstanceType" = [
              "t3.nano",
              "t3.micro",
              "t3.small"
            ]
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# AWS Budget with multiple notification thresholds
resource "aws_budgets_budget" "cost_budget" {
  name       = local.budget_name
  budget_type = "COST"
  limit_amount = var.budget_amount
  limit_unit   = "USD"
  time_unit    = var.budget_time_unit
  time_period_start = "2024-01-01_00:00"

  cost_filters = {
    Service = ["Amazon Elastic Compute Cloud - Compute"]
  }

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }

  # Budget cost types configuration
  cost_types {
    include_credit             = var.budget_cost_types.include_credit
    include_discount           = var.budget_cost_types.include_discount
    include_other_subscription = var.budget_cost_types.include_other_subscription
    include_recurring          = var.budget_cost_types.include_recurring
    include_refund            = var.budget_cost_types.include_refund
    include_subscription      = var.budget_cost_types.include_subscription
    include_support           = var.budget_cost_types.include_support
    include_tax               = var.budget_cost_types.include_tax
    include_upfront           = var.budget_cost_types.include_upfront
    use_blended               = var.budget_cost_types.use_blended
    use_amortized             = var.budget_cost_types.use_amortized
  }

  # Create notifications for each threshold
  dynamic "notification" {
    for_each = var.notification_thresholds
    content {
      comparison_operator        = notification.value.comparison_operator
      threshold                 = notification.value.threshold
      threshold_type            = notification.value.threshold_type
      notification_type         = notification.value.notification_type
      
      subscriber_email_addresses = [var.notification_email]
      subscriber_sns_topic_arns   = [aws_sns_topic.budget_alerts.arn]
    }
  }

  tags = merge(local.common_tags, {
    Description = "AWS Budget for cost monitoring and alerts"
  })

  depends_on = [aws_sns_topic_policy.budget_alerts]
}