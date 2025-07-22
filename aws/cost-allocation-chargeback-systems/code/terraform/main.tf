# Cost Allocation and Chargeback Systems Infrastructure

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_id.suffix.hex

  # Resource naming
  cost_bucket_name        = "${var.project_name}-cost-reports-${local.suffix}"
  sns_topic_name         = "${var.project_name}-alerts-${local.suffix}"
  lambda_function_name   = "${var.project_name}-processor-${local.suffix}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ============================================================================
# S3 Bucket for Cost and Usage Reports
# ============================================================================

resource "aws_s3_bucket" "cost_reports" {
  bucket        = local.cost_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name        = "Cost Reports Bucket"
    Description = "Storage for AWS Cost and Usage Reports"
  })
}

resource "aws_s3_bucket_versioning" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id

  rule {
    id     = "cost_report_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_rules.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_rules.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_rules.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 bucket policy for Cost and Usage Reports
resource "aws_s3_bucket_policy" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCURServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy"
        ]
        Resource = aws_s3_bucket.cost_reports.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "AllowCURServiceDelivery"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cost_reports.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# ============================================================================
# Cost and Usage Report Definition
# ============================================================================

resource "aws_cur_report_definition" "cost_allocation_report" {
  report_name                = "cost-allocation-detailed-report"
  time_unit                  = "DAILY"
  format                     = "textORcsv"
  compression                = "GZIP"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cost_reports.bucket
  s3_prefix                  = "cost-reports/"
  s3_region                  = local.region
  additional_artifacts       = ["REDSHIFT", "ATHENA"]
  refresh_closed_reports     = true
  report_versioning          = var.cur_report_versioning

  depends_on = [aws_s3_bucket_policy.cost_reports]

  tags = merge(local.common_tags, {
    Name        = "Cost Allocation Report"
    Description = "Detailed cost and usage report for chargeback analysis"
  })
}

# ============================================================================
# SNS Topic and Subscriptions for Cost Notifications
# ============================================================================

resource "aws_sns_topic" "cost_allocation_alerts" {
  name         = local.sns_topic_name
  display_name = "Cost Allocation Alerts"

  tags = merge(local.common_tags, {
    Name        = "Cost Allocation Alerts"
    Description = "SNS topic for cost allocation and budget notifications"
  })
}

resource "aws_sns_topic_policy" "cost_allocation_alerts" {
  arn = aws_sns_topic.cost_allocation_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBudgetService"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cost_allocation_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "AllowCostAnomalyService"
        Effect = "Allow"
        Principal = {
          Service = "ce.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cost_allocation_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Email subscription (only if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_allocation_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# Cost Categories for Standardized Allocation
# ============================================================================

resource "aws_ce_cost_category" "cost_center" {
  name         = "CostCenter"
  rule_version = "CostCategoryExpression.v1"

  dynamic "rule" {
    for_each = var.department_budgets
    content {
      value = title(rule.key)
      rule {
        tags {
          key    = "Department"
          values = rule.value.department_values
        }
      }
    }
  }

  # Default rule for untagged resources
  rule {
    value = "Unallocated"
    rule {
      not {
        tags {
          key    = "Department"
          values = flatten([for dept in var.department_budgets : dept.department_values])
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = "Cost Center Categories"
    Description = "Standardized cost allocation categories by department"
  })
}

# ============================================================================
# AWS Budgets for Department Cost Monitoring
# ============================================================================

resource "aws_budgets_budget" "department_budgets" {
  for_each = var.department_budgets

  name         = "${title(each.key)}-Monthly-Budget"
  budget_type  = "COST"
  limit_amount = tostring(each.value.amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filters {
    tag {
      key    = "Department"
      values = each.value.department_values
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = each.value.threshold_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
    subscriber_sns_topic_arns   = [aws_sns_topic.cost_allocation_alerts.arn]
  }

  # Forecast notification at 100% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
    subscriber_sns_topic_arns   = [aws_sns_topic.cost_allocation_alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.cost_allocation_alerts]

  tags = merge(local.common_tags, {
    Name       = "${title(each.key)} Department Budget"
    Department = title(each.key)
  })
}

# ============================================================================
# Cost Anomaly Detection
# ============================================================================

resource "aws_ce_anomaly_detector" "department_anomaly_detector" {
  count        = var.enable_cost_anomaly_detection ? 1 : 0
  name         = "DepartmentCostAnomalyDetector"
  monitor_type = "DIMENSIONAL"

  specification = jsonencode({
    Dimension     = "TAG"
    Key          = "Department"
    MatchOptions = ["EQUALS"]
  })

  tags = merge(local.common_tags, {
    Name        = "Department Cost Anomaly Detector"
    Description = "Detects unusual spending patterns by department"
  })
}

resource "aws_ce_anomaly_subscription" "cost_anomaly_alerts" {
  count     = var.enable_cost_anomaly_detection ? 1 : 0
  name      = "CostAnomalyAlerts"
  frequency = "DAILY"
  
  monitor_arn_list = [aws_ce_anomaly_detector.department_anomaly_detector[0].arn]
  
  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_allocation_alerts.arn
  }

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = [tostring(var.cost_anomaly_threshold)]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  depends_on = [aws_sns_topic_policy.cost_allocation_alerts]

  tags = merge(local.common_tags, {
    Name        = "Cost Anomaly Subscription"
    Description = "Subscription for cost anomaly notifications"
  })
}

# ============================================================================
# Lambda Function for Cost Processing
# ============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_cost_processor" {
  name = "${local.lambda_function_name}-role"

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
    Name        = "Lambda Cost Processor Role"
    Description = "IAM role for cost allocation processing Lambda function"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_cost_processor" {
  name = "CostAllocationProcessorPolicy"
  role = aws_iam_role.lambda_cost_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:ListCostCategoryDefinitions",
          "ce:GetCostCategories"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cost_reports.arn,
          "${aws_s3_bucket.cost_reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_allocation_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      }
    ]
  })
}

# Lambda function code
resource "local_file" "lambda_function_code" {
  filename = "${path.module}/cost_processor.py"
  content  = <<EOF
import json
import boto3
import csv
from datetime import datetime, timedelta
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process cost allocation data and generate chargeback reports
    """
    ce_client = boto3.client('ce')
    sns_client = boto3.client('sns')
    s3_client = boto3.client('s3')
    
    # Get environment variables
    sns_topic_arn = '${aws_sns_topic.cost_allocation_alerts.arn}'
    s3_bucket = '${aws_s3_bucket.cost_reports.bucket}'
    
    try:
        # Calculate date range (last 30 days)
        end_date = datetime.now().strftime('%Y-%m-%d')
        start_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        
        logger.info(f"Processing costs from {start_date} to {end_date}")
        
        # Query costs by department
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost', 'UnblendedCost', 'UsageQuantity'],
            GroupBy=[
                {
                    'Type': 'TAG',
                    'Key': 'Department'
                }
            ]
        )
        
        # Process cost data
        department_costs = {}
        total_cost = 0
        
        for result in response['ResultsByTime']:
            for group in result['Groups']:
                dept_name = group['Keys'][0] if group['Keys'][0] != 'No Department' else 'Untagged'
                blended_cost = float(group['Metrics']['BlendedCost']['Amount'])
                unblended_cost = float(group['Metrics']['UnblendedCost']['Amount'])
                
                if dept_name not in department_costs:
                    department_costs[dept_name] = {
                        'blended_cost': 0,
                        'unblended_cost': 0
                    }
                
                department_costs[dept_name]['blended_cost'] += blended_cost
                department_costs[dept_name]['unblended_cost'] += unblended_cost
                total_cost += blended_cost
        
        # Create detailed report
        report = {
            'report_date': end_date,
            'period': f"{start_date} to {end_date}",
            'department_costs': department_costs,
            'total_cost': total_cost,
            'report_type': 'cost_allocation_chargeback'
        }
        
        # Save detailed report to S3
        report_key = f"processed-reports/{end_date}/cost_allocation_report.json"
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=report_key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        
        # Create summary message
        message = f"""
Cost Allocation Report - {end_date}
Report Period: {start_date} to {end_date}

Department Breakdown (Blended Costs):
"""
        
        # Sort departments by cost (highest first)
        sorted_depts = sorted(department_costs.items(), 
                            key=lambda x: x[1]['blended_cost'], 
                            reverse=True)
        
        for dept, costs in sorted_depts:
            percentage = (costs['blended_cost'] / total_cost * 100) if total_cost > 0 else 0
            message += f"• {dept}: ${costs['blended_cost']:.2f} ({percentage:.1f}%)\n"
        
        message += f"\nTotal Cost: ${total_cost:.2f}"
        message += f"\nDetailed report saved to: s3://{s3_bucket}/{report_key}"
        
        # Send notification
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=f'Cost Allocation Report - {end_date}',
            Message=message
        )
        
        logger.info(f"Successfully processed cost allocation report. Total cost: ${total_cost:.2f}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost allocation report processed successfully',
                'total_cost': total_cost,
                'departments': len(department_costs),
                'report_location': f"s3://{s3_bucket}/{report_key}"
            }, default=str)
        }
        
    except Exception as e:
        error_message = f"Error processing cost allocation: {str(e)}"
        logger.error(error_message)
        
        # Send error notification
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject='Cost Allocation Processing Error',
                Message=f"Failed to process cost allocation report: {error_message}"
            )
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }
EOF
}

# Create deployment package
data "archive_file" "lambda_cost_processor" {
  type        = "zip"
  output_path = "${path.module}/cost_processor.zip"
  
  source {
    content  = local_file.lambda_function_code.content
    filename = "cost_processor.py"
  }
}

# Lambda function
resource "aws_lambda_function" "cost_processor" {
  filename         = data.archive_file.lambda_cost_processor.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_cost_processor.arn
  handler         = "cost_processor.lambda_handler"
  source_code_hash = data.archive_file.lambda_cost_processor.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_allocation_alerts.arn
      S3_BUCKET     = aws_s3_bucket.cost_reports.bucket
      PROJECT_NAME  = var.project_name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_cost_processor,
    aws_cloudwatch_log_group.lambda_cost_processor
  ]

  tags = merge(local.common_tags, {
    Name        = "Cost Allocation Processor"
    Description = "Lambda function for processing cost allocation data"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_cost_processor" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "Lambda Cost Processor Logs"
    Description = "CloudWatch logs for cost allocation Lambda function"
  })
}

# ============================================================================
# EventBridge Scheduled Rule for Automated Processing
# ============================================================================

resource "aws_cloudwatch_event_rule" "cost_allocation_schedule" {
  name                = "${var.project_name}-cost-allocation-schedule"
  description         = "Trigger cost allocation processing monthly"
  schedule_expression = var.schedule_expression

  tags = merge(local.common_tags, {
    Name        = "Cost Allocation Schedule"
    Description = "EventBridge rule for automated cost processing"
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cost_allocation_schedule.name
  target_id = "CostAllocationLambdaTarget"
  arn       = aws_lambda_function.cost_processor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_allocation_schedule.arn
}