# Main Terraform configuration for AWS Lambda Cost Optimization with Compute Optimizer
# This infrastructure supports the complete Lambda cost optimization workflow using AWS Compute Optimizer

# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention for all resources
  common_name = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = {
    Project             = var.project_name
    Environment         = var.environment
    ManagedBy          = "terraform"
    CostCenter         = var.cost_center
    Purpose            = "compute-optimizer-demo"
    Recipe             = "lambda-cost-compute-optimizer"
    OptimizationTarget = "cost-performance"
    CreatedDate        = timestamp()
  }
}

# ================================================================================================
# IAM ROLES AND POLICIES
# ================================================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.common_name}-lambda-execution-role"

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
    Description = "IAM role for Lambda function execution with optimization permissions"
    Component   = "iam"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda functions to access CloudWatch and Cost Explorer
resource "aws_iam_role_policy" "lambda_optimization_policy" {
  name = "${local.common_name}-lambda-optimization-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:ListCostCategoryDefinitions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListFunctions",
          "lambda:UpdateFunctionConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# IAM role for Compute Optimizer service
resource "aws_iam_role" "compute_optimizer_role" {
  name = "${local.common_name}-compute-optimizer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "compute-optimizer.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Description = "IAM role for AWS Compute Optimizer service"
    Component   = "iam"
  })
}

# Attach Compute Optimizer service role policy
resource "aws_iam_role_policy_attachment" "compute_optimizer_service_role" {
  role       = aws_iam_role.compute_optimizer_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ComputeOptimizerServiceRolePolicy"
}

# ================================================================================================
# KMS KEY FOR ENCRYPTION (OPTIONAL)
# ================================================================================================

resource "aws_kms_key" "lambda_key" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for Lambda function encryption in ${var.project_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Service"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Description = "KMS key for Lambda function encryption"
    Component   = "security"
  })
}

resource "aws_kms_alias" "lambda_key_alias" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.common_name}-lambda-key"
  target_key_id = aws_kms_key.lambda_key[0].key_id
}

# ================================================================================================
# LAMBDA FUNCTION CODE ARCHIVES
# ================================================================================================

# Sample Lambda function code for testing optimization
resource "local_file" "sample_function_code" {
  count = var.create_sample_functions ? 1 : 0

  filename = "${path.module}/sample_function.py"
  content  = <<EOF
import json
import time
import os
import random

def lambda_handler(event, context):
    """
    Sample Lambda function for testing AWS Compute Optimizer recommendations.
    This function simulates various workload patterns to generate metrics.
    """
    
    # Get function configuration
    memory_size = int(context.memory_limit_in_mb)
    function_name = context.function_name
    
    print(f"Function: {function_name}, Memory: {memory_size}MB")
    
    # Simulate different workload types based on memory allocation
    if memory_size <= 256:
        # Light workload - minimal processing
        workload_type = "light"
        processing_time = random.uniform(0.1, 0.3)
        
    elif memory_size <= 512:
        # Medium workload - moderate processing
        workload_type = "medium"
        processing_time = random.uniform(0.3, 0.8)
        
    else:
        # Heavy workload - intensive processing
        workload_type = "heavy"
        processing_time = random.uniform(0.8, 2.0)
    
    print(f"Workload type: {workload_type}, Processing time: {processing_time:.2f}s")
    
    # Simulate processing work
    time.sleep(processing_time)
    
    # Generate some computational work
    result = sum(i * i for i in range(1000))
    
    # Return response with metrics
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Function {function_name} executed successfully',
            'workload_type': workload_type,
            'memory_size_mb': memory_size,
            'processing_time_seconds': round(processing_time, 2),
            'computation_result': result,
            'timestamp': context.aws_request_id
        }),
        'headers': {
            'Content-Type': 'application/json'
        }
    }
EOF
}

# Test function with intentionally high memory for optimization demonstration
resource "local_file" "test_function_code" {
  count = var.create_sample_functions ? 1 : 0

  filename = "${path.module}/test_function.py"
  content  = <<EOF
import json
import time
import os

def lambda_handler(event, context):
    """
    Test Lambda function with intentionally high memory allocation.
    This demonstrates how Compute Optimizer identifies over-provisioned functions.
    """
    
    print(f"Test function executing with {context.memory_limit_in_mb}MB memory")
    
    # Simple function that doesn't need much memory
    time.sleep(0.1)  # Simulate minimal work
    
    # Basic computation that doesn't require high memory
    simple_calculation = sum(range(100))
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Test function executed - should be flagged for optimization',
            'memory_allocated_mb': int(context.memory_limit_in_mb),
            'actual_memory_needed': 'Much less than allocated',
            'optimization_candidate': True,
            'calculation_result': simple_calculation,
            'request_id': context.aws_request_id
        })
    }
EOF
}

# Cost analysis function code
resource "local_file" "cost_analysis_function_code" {
  count = var.enable_cost_analysis ? 1 : 0

  filename = "${path.module}/cost_analysis_function.py"
  content  = <<EOF
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Analyzes Lambda costs and provides optimization insights.
    """
    
    # Initialize AWS clients
    ce_client = boto3.client('ce')
    lambda_client = boto3.client('lambda')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Get current month's Lambda costs
        current_month = datetime.now().replace(day=1)
        next_month = (current_month + timedelta(days=32)).replace(day=1)
        
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': current_month.strftime('%Y-%m-%d'),
                'End': next_month.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ],
            Filter={
                'Dimensions': {
                    'Key': 'SERVICE',
                    'Values': ['AWS Lambda']
                }
            }
        )
        
        # Extract Lambda costs
        lambda_cost = 0
        if cost_response['ResultsByTime']:
            for group in cost_response['ResultsByTime'][0]['Groups']:
                if 'AWS Lambda' in group['Keys']:
                    lambda_cost = float(group['Metrics']['BlendedCost']['Amount'])
        
        # Get Lambda function count and configurations
        functions_response = lambda_client.list_functions()
        function_count = len(functions_response['Functions'])
        
        memory_distribution = {}
        for func in functions_response['Functions']:
            memory = func['MemorySize']
            memory_distribution[memory] = memory_distribution.get(memory, 0) + 1
        
        # Create cost analysis report
        report = {
            'analysis_date': datetime.now().isoformat(),
            'lambda_cost_this_month': lambda_cost,
            'total_functions': function_count,
            'memory_distribution': memory_distribution,
            'average_cost_per_function': lambda_cost / max(function_count, 1),
            'recommendations': []
        }
        
        # Add basic recommendations
        if lambda_cost > 10:
            report['recommendations'].append('Consider reviewing high-cost functions for optimization opportunities')
        
        if len([m for m in memory_distribution.keys() if m >= 1024]) > function_count * 0.3:
            report['recommendations'].append('30%+ of functions use 1GB+ memory - review for over-provisioning')
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='LambdaCostOptimization',
            MetricData=[
                {
                    'MetricName': 'MonthlyCost',
                    'Value': lambda_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'Account',
                            'Value': context.invoked_function_arn.split(':')[4]
                        }
                    ]
                },
                {
                    'MetricName': 'FunctionCount',
                    'Value': function_count,
                    'Unit': 'Count'
                }
            ]
        )
        
        print("Cost Analysis Report:")
        print(json.dumps(report, indent=2, default=str))
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, default=str)
        }
        
    except Exception as e:
        error_message = f"Error in cost analysis: {str(e)}"
        print(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'function_name': context.function_name
            })
        }
EOF
}

# Create ZIP archives for Lambda functions
data "archive_file" "sample_function_zip" {
  count = var.create_sample_functions ? 1 : 0

  type        = "zip"
  source_file = local_file.sample_function_code[0].filename
  output_path = "${path.module}/sample_function.zip"
  depends_on  = [local_file.sample_function_code]
}

data "archive_file" "test_function_zip" {
  count = var.create_sample_functions ? 1 : 0

  type        = "zip"
  source_file = local_file.test_function_code[0].filename
  output_path = "${path.module}/test_function.zip"
  depends_on  = [local_file.test_function_code]
}

data "archive_file" "cost_analysis_function_zip" {
  count = var.enable_cost_analysis ? 1 : 0

  type        = "zip"
  source_file = local_file.cost_analysis_function_code[0].filename
  output_path = "${path.module}/cost_analysis_function.zip"
  depends_on  = [local_file.cost_analysis_function_code]
}

# ================================================================================================
# CLOUDWATCH LOG GROUPS
# ================================================================================================

# Log groups for sample Lambda functions
resource "aws_cloudwatch_log_group" "lambda_log_groups" {
  count = var.create_sample_functions ? var.sample_function_count : 0

  name              = "/aws/lambda/${local.common_name}-sample-function-${count.index + 1}"
  retention_in_days = var.retention_in_days

  kms_key_id = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  tags = merge(local.common_tags, {
    Description = "CloudWatch log group for sample Lambda function ${count.index + 1}"
    Component   = "monitoring"
    FunctionType = "sample"
  })
}

# Log group for test optimization function
resource "aws_cloudwatch_log_group" "test_function_log_group" {
  count = var.create_sample_functions ? 1 : 0

  name              = "/aws/lambda/${local.common_name}-test-optimization-function"
  retention_in_days = var.retention_in_days

  kms_key_id = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  tags = merge(local.common_tags, {
    Description = "CloudWatch log group for test optimization Lambda function"
    Component   = "monitoring"
    FunctionType = "test"
  })
}

# Log group for cost analysis function
resource "aws_cloudwatch_log_group" "cost_analysis_log_group" {
  count = var.enable_cost_analysis ? 1 : 0

  name              = "/aws/lambda/${local.common_name}-cost-analysis-function"
  retention_in_days = var.retention_in_days

  kms_key_id = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  tags = merge(local.common_tags, {
    Description = "CloudWatch log group for cost analysis Lambda function"
    Component   = "monitoring"
    FunctionType = "cost-analysis"
  })
}

# ================================================================================================
# LAMBDA FUNCTIONS
# ================================================================================================

# Sample Lambda functions with different memory allocations for testing
resource "aws_lambda_function" "sample_functions" {
  count = var.create_sample_functions ? var.sample_function_count : 0

  filename         = data.archive_file.sample_function_zip[0].output_path
  function_name    = "${local.common_name}-sample-function-${count.index + 1}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "sample_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout

  # Use different memory sizes from the variable list
  memory_size = length(var.lambda_memory_sizes) > count.index ? var.lambda_memory_sizes[count.index] : var.lambda_memory_sizes[0]

  source_code_hash = data.archive_file.sample_function_zip[0].output_base64sha256

  # Optional KMS encryption
  kms_key_arn = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  # Optional X-Ray tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  # Environment variables
  environment {
    variables = merge(var.lambda_environment_variables, {
      FUNCTION_INDEX = count.index + 1
      MEMORY_SIZE    = length(var.lambda_memory_sizes) > count.index ? var.lambda_memory_sizes[count.index] : var.lambda_memory_sizes[0]
      PROJECT_NAME   = var.project_name
      ENVIRONMENT    = var.environment
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_groups,
    data.archive_file.sample_function_zip
  ]

  tags = merge(local.common_tags, {
    Description  = "Sample Lambda function ${count.index + 1} for cost optimization testing"
    Component    = "compute"
    FunctionType = "sample"
    MemorySize   = tostring(length(var.lambda_memory_sizes) > count.index ? var.lambda_memory_sizes[count.index] : var.lambda_memory_sizes[0])
  })
}

# Test function with intentionally high memory for optimization demonstration
resource "aws_lambda_function" "test_optimization_function" {
  count = var.create_sample_functions ? 1 : 0

  filename         = data.archive_file.test_function_zip[0].output_path
  function_name    = "${local.common_name}-test-optimization-function"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "test_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout

  # Intentionally high memory to demonstrate optimization opportunities
  memory_size = 1024

  source_code_hash = data.archive_file.test_function_zip[0].output_base64sha256

  # Optional KMS encryption
  kms_key_arn = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  # Optional X-Ray tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  # Environment variables
  environment {
    variables = merge(var.lambda_environment_variables, {
      FUNCTION_PURPOSE = "optimization-testing"
      PROJECT_NAME     = var.project_name
      ENVIRONMENT      = var.environment
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.test_function_log_group,
    data.archive_file.test_function_zip
  ]

  tags = merge(local.common_tags, {
    Description     = "Test Lambda function with high memory for optimization demonstration"
    Component       = "compute"
    FunctionType    = "test"
    MemorySize      = "1024"
    OptimizationCandidate = "true"
  })
}

# Cost analysis function
resource "aws_lambda_function" "cost_analysis_function" {
  count = var.enable_cost_analysis ? 1 : 0

  filename         = data.archive_file.cost_analysis_function_zip[0].output_path
  function_name    = "${local.common_name}-cost-analysis-function"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "cost_analysis_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60

  memory_size = 256

  source_code_hash = data.archive_file.cost_analysis_function_zip[0].output_base64sha256

  # Optional KMS encryption
  kms_key_arn = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  # Environment variables
  environment {
    variables = merge(var.lambda_environment_variables, {
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.cost_analysis_log_group,
    data.archive_file.cost_analysis_function_zip
  ]

  tags = merge(local.common_tags, {
    Description  = "Lambda function for automated cost analysis and reporting"
    Component    = "analytics"
    FunctionType = "cost-analysis"
    MemorySize   = "256"
  })
}

# ================================================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ================================================================================================

resource "aws_sns_topic" "lambda_alerts" {
  count = var.create_sns_topic ? 1 : 0

  name         = "${local.common_name}-lambda-alerts"
  display_name = "Lambda Cost Optimization Alerts"

  # Optional KMS encryption
  kms_master_key_id = var.create_kms_key ? aws_kms_key.lambda_key[0].arn : null

  tags = merge(local.common_tags, {
    Description = "SNS topic for Lambda cost optimization alerts and notifications"
    Component   = "notification"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "lambda_alerts_policy" {
  count = var.create_sns_topic ? 1 : 0

  arn = aws_sns_topic.lambda_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.lambda_alerts[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription (if email provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.create_sns_topic && var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.lambda_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ================================================================================================
# CLOUDWATCH ALARMS
# ================================================================================================

# CloudWatch alarm for Lambda error rate
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.common_name}-lambda-error-rate"
  alarm_description   = "Monitor Lambda error rate after optimization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = var.create_sns_topic ? [aws_sns_topic.lambda_alerts[0].arn] : []
  ok_actions    = var.create_sns_topic ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Description = "CloudWatch alarm for monitoring Lambda function errors"
    Component   = "monitoring"
    AlarmType   = "error-rate"
  })
}

# CloudWatch alarm for Lambda duration increase
resource "aws_cloudwatch_metric_alarm" "lambda_duration_increase" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.common_name}-lambda-duration-increase"
  alarm_description   = "Monitor Lambda duration increase after optimization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.duration_threshold_ms
  treat_missing_data  = "notBreaching"

  alarm_actions = var.create_sns_topic ? [aws_sns_topic.lambda_alerts[0].arn] : []
  ok_actions    = var.create_sns_topic ? [aws_sns_topic.lambda_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Description = "CloudWatch alarm for monitoring Lambda function duration increases"
    Component   = "monitoring"
    AlarmType   = "duration-increase"
  })
}

# ================================================================================================
# EVENTBRIDGE RULE FOR COST ANALYSIS SCHEDULING
# ================================================================================================

resource "aws_cloudwatch_event_rule" "cost_analysis_schedule" {
  count = var.enable_cost_analysis ? 1 : 0

  name                = "${local.common_name}-cost-analysis-schedule"
  description         = "Schedule for running Lambda cost analysis"
  schedule_expression = var.cost_analysis_schedule

  tags = merge(local.common_tags, {
    Description = "EventBridge rule for scheduling cost analysis"
    Component   = "scheduling"
  })
}

resource "aws_cloudwatch_event_target" "cost_analysis_target" {
  count = var.enable_cost_analysis ? 1 : 0

  rule      = aws_cloudwatch_event_rule.cost_analysis_schedule[0].name
  target_id = "CostAnalysisLambdaTarget"
  arn       = aws_lambda_function.cost_analysis_function[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_cost_analysis ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_analysis_function[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_analysis_schedule[0].arn
}

# ================================================================================================
# NULL RESOURCE FOR COMPUTE OPTIMIZER ENROLLMENT
# ================================================================================================

# Note: AWS Compute Optimizer enrollment requires manual action or AWS CLI
# This null_resource provides the command but doesn't automatically enroll
# to avoid potential conflicts with existing Compute Optimizer settings
resource "null_resource" "compute_optimizer_enrollment" {
  count = var.enable_compute_optimizer ? 1 : 0

  triggers = {
    enrollment_status = var.compute_optimizer_enrollment_status
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "==============================================================================="
      echo "AWS Compute Optimizer Enrollment Required"
      echo "==============================================================================="
      echo "To enable AWS Compute Optimizer for Lambda recommendations, run:"
      echo ""
      echo "aws compute-optimizer put-enrollment-status --status ${var.compute_optimizer_enrollment_status}"
      echo ""
      echo "Then verify enrollment with:"
      echo "aws compute-optimizer get-enrollment-status"
      echo ""
      echo "Note: Compute Optimizer requires at least 14 days of Lambda metrics"
      echo "      to generate reliable recommendations."
      echo "==============================================================================="
    EOT
  }
}

# ================================================================================================
# NULL RESOURCE FOR TEST INVOCATIONS (OPTIONAL)
# ================================================================================================

resource "null_resource" "test_invocations" {
  count = var.enable_test_invocations && var.create_sample_functions ? 1 : 0

  depends_on = [
    aws_lambda_function.sample_functions,
    aws_lambda_function.test_optimization_function
  ]

  triggers = {
    # Trigger re-run if function configurations change
    sample_functions_hash = sha256(jsonencode([
      for func in aws_lambda_function.sample_functions : {
        name   = func.function_name
        memory = func.memory_size
      }
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting test invocations to generate Lambda metrics..."
      
      # Invoke sample functions
      for i in {1..${var.sample_function_count}}; do
        func_name="${local.common_name}-sample-function-$i"
        echo "Invoking $func_name..."
        
        for j in {1..${var.test_invocation_count}}; do
          aws lambda invoke \
            --function-name "$func_name" \
            --payload '{"test": true, "invocation": '$j'}' \
            /tmp/response_$i_$j.json > /dev/null 2>&1
          sleep 1
        done
      done
      
      # Invoke test optimization function
      test_func_name="${local.common_name}-test-optimization-function"
      echo "Invoking $test_func_name..."
      
      for j in {1..${var.test_invocation_count}}; do
        aws lambda invoke \
          --function-name "$test_func_name" \
          --payload '{"test": true, "invocation": '$j'}' \
          /tmp/test_response_$j.json > /dev/null 2>&1
        sleep 1
      done
      
      # Cleanup temporary files
      rm -f /tmp/response_*.json /tmp/test_response_*.json
      
      echo "Test invocations completed. Lambda metrics will be available in CloudWatch."
      echo "Wait 14+ days for Compute Optimizer to generate recommendations."
    EOT
  }
}