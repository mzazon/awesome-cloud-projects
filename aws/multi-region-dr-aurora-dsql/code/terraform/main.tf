# Data sources for account information and region validation
data "aws_caller_identity" "current" {}

data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "secondary" {
  provider = aws.secondary
}

data "aws_region" "witness" {
  provider = aws.witness
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# Local values for consistent naming and tagging
locals {
  resource_suffix = random_string.suffix.result
  
  # Common tags
  common_tags = merge(
    {
      Project              = "DisasterRecovery"
      Environment          = var.environment
      CostCenter          = "Infrastructure"
      ManagedBy           = "Terraform"
      TerraformWorkspace  = terraform.workspace
    },
    var.additional_tags
  )
  
  # Resource naming
  cluster_primary_name   = "${var.cluster_prefix}-${local.resource_suffix}-primary"
  cluster_secondary_name = "${var.cluster_prefix}-${local.resource_suffix}-secondary"
  lambda_function_name   = "dr-monitor-${local.resource_suffix}"
  eventbridge_rule_name  = "dr-health-monitor-${local.resource_suffix}"
  sns_topic_name         = "dr-alerts-${local.resource_suffix}"
  dashboard_name         = "${var.dashboard_name}-${local.resource_suffix}"
}

# ========================================
# Aurora DSQL Clusters
# ========================================

# Primary Aurora DSQL cluster
resource "aws_dsql_cluster" "primary" {
  provider = aws.primary
  
  cluster_identifier = local.cluster_primary_name
  
  # Multi-region configuration with witness region
  multi_region_properties {
    witness_region = var.witness_region
    clusters       = []  # Will be updated after secondary cluster creation
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.cluster_primary_name
      Region = "Primary"
      Role   = "PrimaryCluster"
    }
  )
  
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      multi_region_properties[0].clusters  # Managed separately for peering
    ]
  }
}

# Secondary Aurora DSQL cluster
resource "aws_dsql_cluster" "secondary" {
  provider = aws.secondary
  
  cluster_identifier = local.cluster_secondary_name
  
  # Multi-region configuration with witness region
  multi_region_properties {
    witness_region = var.witness_region
    clusters       = []  # Will be updated after primary cluster creation
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = local.cluster_secondary_name
      Region = "Secondary"
      Role   = "SecondaryCluster"
    }
  )
  
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      multi_region_properties[0].clusters  # Managed separately for peering
    ]
  }
}

# Note: Aurora DSQL cluster peering configuration would be managed through
# separate API calls or custom resources once available in Terraform AWS provider

# ========================================
# SNS Topics for Multi-Region Alerting
# ========================================

# KMS key for SNS encryption in primary region
resource "aws_kms_key" "sns_primary" {
  count    = var.enable_sns_encryption ? 1 : 0
  provider = aws.primary
  
  description             = "KMS key for SNS topic encryption in primary region"
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
        Sid    = "Allow SNS service"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(
    local.common_tags,
    {
      Name    = "sns-encryption-key-primary-${local.resource_suffix}"
      Service = "SNS"
      Region  = "Primary"
    }
  )
}

resource "aws_kms_alias" "sns_primary" {
  count         = var.enable_sns_encryption ? 1 : 0
  provider      = aws.primary
  name          = "alias/sns-dr-primary-${local.resource_suffix}"
  target_key_id = aws_kms_key.sns_primary[0].key_id
}

# KMS key for SNS encryption in secondary region
resource "aws_kms_key" "sns_secondary" {
  count    = var.enable_sns_encryption ? 1 : 0
  provider = aws.secondary
  
  description             = "KMS key for SNS topic encryption in secondary region"
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
        Sid    = "Allow SNS service"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(
    local.common_tags,
    {
      Name    = "sns-encryption-key-secondary-${local.resource_suffix}"
      Service = "SNS"
      Region  = "Secondary"
    }
  )
}

resource "aws_kms_alias" "sns_secondary" {
  count         = var.enable_sns_encryption ? 1 : 0
  provider      = aws.secondary
  name          = "alias/sns-dr-secondary-${local.resource_suffix}"
  target_key_id = aws_kms_key.sns_secondary[0].key_id
}

# SNS topic in primary region
resource "aws_sns_topic" "primary" {
  provider = aws.primary
  
  name         = "${local.sns_topic_name}-primary"
  display_name = "DR Alerts Primary"
  
  kms_master_key_id = var.enable_sns_encryption ? aws_kms_key.sns_primary[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.sns_topic_name}-primary"
      Region = "Primary"
      Role   = "AlertingTopic"
    }
  )
}

# SNS topic in secondary region
resource "aws_sns_topic" "secondary" {
  provider = aws.secondary
  
  name         = "${local.sns_topic_name}-secondary"
  display_name = "DR Alerts Secondary"
  
  kms_master_key_id = var.enable_sns_encryption ? aws_kms_key.sns_secondary[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.sns_topic_name}-secondary"
      Region = "Secondary"
      Role   = "AlertingTopic"
    }
  )
}

# Email subscriptions (conditional)
resource "aws_sns_topic_subscription" "primary_email" {
  count    = var.sns_email_endpoint != "" ? 1 : 0
  provider = aws.primary
  
  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

resource "aws_sns_topic_subscription" "secondary_email" {
  count    = var.sns_email_endpoint != "" ? 1 : 0
  provider = aws.secondary
  
  topic_arn = aws_sns_topic.secondary.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# ========================================
# IAM Role for Lambda Functions
# ========================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution" {
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
  
  tags = merge(
    local.common_tags,
    {
      Name    = "${local.lambda_function_name}-role"
      Service = "Lambda"
      Role    = "ExecutionRole"
    }
  )
}

# Enhanced IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.lambda_function_name}-policy"
  role = aws_iam_role.lambda_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:GetCluster",
          "dsql:ListClusters",
          "dsql:DescribeCluster"
        ]
        Resource = [
          aws_dsql_cluster.primary.arn,
          aws_dsql_cluster.secondary.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.primary.arn,
          aws_sns_topic.secondary.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.cloudwatch_metric_namespace
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = concat(
          var.enable_sns_encryption ? [aws_kms_key.sns_primary[0].arn] : [],
          var.enable_sns_encryption ? [aws_kms_key.sns_secondary[0].arn] : []
        )
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ========================================
# Lambda Function Code
# ========================================

# Lambda function code package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      cloudwatch_namespace = var.cloudwatch_metric_namespace
    })
    filename = "lambda_function.py"
  }
  
  depends_on = [local_file.lambda_function]
}

# Lambda function template file
resource "local_file" "lambda_function" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    cloudwatch_namespace = var.cloudwatch_metric_namespace
  })
  filename = "${path.module}/lambda_function.py.tpl"
}

# Lambda function template content
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOF
import json
import boto3
import os
import time
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Monitor Aurora DSQL cluster health and send alerts
    """
    dsql_client = boto3.client('dsql')
    sns_client = boto3.client('sns')
    cloudwatch_client = boto3.client('cloudwatch')
    
    cluster_id = os.environ['CLUSTER_ID']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    region = os.environ['AWS_REGION']
    
    try:
        # Check cluster status with retry logic
        max_retries = 3
        for attempt in range(max_retries):
            try:
                response = dsql_client.get_cluster(identifier=cluster_id)
                break
            except ClientError as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise e
        
        cluster_status = response['status']
        cluster_arn = response['arn']
        
        # Create comprehensive health report
        health_report = {
            'timestamp': datetime.now().isoformat(),
            'region': region,
            'cluster_id': cluster_id,
            'cluster_arn': cluster_arn,
            'status': cluster_status,
            'healthy': cluster_status == 'ACTIVE',
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        }
        
        # Publish custom CloudWatch metric
        cloudwatch_client.put_metric_data(
            Namespace='${cloudwatch_namespace}',
            MetricData=[
                {
                    'MetricName': 'ClusterHealth',
                    'Value': 1.0 if cluster_status == 'ACTIVE' else 0.0,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'ClusterID',
                            'Value': cluster_id
                        },
                        {
                            'Name': 'Region',
                            'Value': region
                        }
                    ]
                }
            ]
        )
        
        # Send alert if cluster is not healthy
        if cluster_status != 'ACTIVE':
            alert_message = f"""
ALERT: Aurora DSQL Cluster Health Issue

Region: {region}
Cluster ID: {cluster_id}
Cluster ARN: {cluster_arn}
Status: {cluster_status}
Timestamp: {health_report['timestamp']}
Function: {context.function_name}
Request ID: {context.aws_request_id}

Immediate investigation required.
Check Aurora DSQL console for detailed status information.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Alert - {region}',
                Message=alert_message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"""
ERROR: Aurora DSQL Health Check Failed

Region: {region}
Cluster ID: {cluster_id}
Error: {str(e)}
Error Type: {type(e).__name__}
Timestamp: {datetime.now().isoformat()}
Function: {context.function_name}
Request ID: {context.aws_request_id}

This error indicates a potential issue with the monitoring infrastructure.
Verify Lambda function permissions and Aurora DSQL cluster accessibility.
        """
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Health Check Error - {region}',
                Message=error_message
            )
        except Exception as sns_error:
            print(f"Failed to send SNS alert: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
EOF
}

# ========================================
# Lambda Functions
# ========================================

# Lambda function in primary region
resource "aws_lambda_function" "primary" {
  provider = aws.primary
  
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.lambda_function_name}-primary"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      CLUSTER_ID      = aws_dsql_cluster.primary.cluster_identifier
      SNS_TOPIC_ARN   = aws_sns_topic.primary.arn
    }
  }
  
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.lambda_function_name}-primary"
      Region = "Primary"
      Role   = "HealthMonitor"
    }
  )
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.primary
  ]
}

# Lambda function in secondary region
resource "aws_lambda_function" "secondary" {
  provider = aws.secondary
  
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.lambda_function_name}-secondary"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      CLUSTER_ID      = aws_dsql_cluster.secondary.cluster_identifier
      SNS_TOPIC_ARN   = aws_sns_topic.secondary.arn
    }
  }
  
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.lambda_function_name}-secondary"
      Region = "Secondary"
      Role   = "HealthMonitor"
    }
  )
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.secondary
  ]
}

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary
  
  name              = "/aws/lambda/${local.lambda_function_name}-primary"
  retention_in_days = 14
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.lambda_function_name}-primary-logs"
      Region = "Primary"
    }
  )
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary
  
  name              = "/aws/lambda/${local.lambda_function_name}-secondary"
  retention_in_days = 14
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.lambda_function_name}-secondary-logs"
      Region = "Secondary"
    }
  )
}

# ========================================
# EventBridge Rules
# ========================================

# EventBridge rule for primary region
resource "aws_cloudwatch_event_rule" "primary" {
  provider = aws.primary
  
  name                = "${local.eventbridge_rule_name}-primary"
  description         = "Aurora DSQL health monitoring for primary region"
  schedule_expression = var.monitoring_schedule
  state               = "ENABLED"
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.eventbridge_rule_name}-primary"
      Region = "Primary"
      Role   = "MonitoringScheduler"
    }
  )
}

# EventBridge rule for secondary region
resource "aws_cloudwatch_event_rule" "secondary" {
  provider = aws.secondary
  
  name                = "${local.eventbridge_rule_name}-secondary"
  description         = "Aurora DSQL health monitoring for secondary region"
  schedule_expression = var.monitoring_schedule
  state               = "ENABLED"
  
  tags = merge(
    local.common_tags,
    {
      Name   = "${local.eventbridge_rule_name}-secondary"
      Region = "Secondary"
      Role   = "MonitoringScheduler"
    }
  )
}

# EventBridge targets for Lambda functions
resource "aws_cloudwatch_event_target" "primary" {
  provider = aws.primary
  
  rule      = aws_cloudwatch_event_rule.primary.name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.primary.arn
  
  retry_policy {
    maximum_retry_attempts = 3
    maximum_event_age      = 3600
  }
}

resource "aws_cloudwatch_event_target" "secondary" {
  provider = aws.secondary
  
  rule      = aws_cloudwatch_event_rule.secondary.name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.secondary.arn
  
  retry_policy {
    maximum_retry_attempts = 3
    maximum_event_age      = 3600
  }
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_primary" {
  provider = aws.primary
  
  statement_id  = "allow-eventbridge-primary"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.primary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.primary.arn
}

resource "aws_lambda_permission" "allow_eventbridge_secondary" {
  provider = aws.secondary
  
  statement_id  = "allow-eventbridge-secondary"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secondary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.secondary.arn
}

# ========================================
# CloudWatch Dashboard
# ========================================

resource "aws_cloudwatch_dashboard" "dr_dashboard" {
  provider = aws.primary
  
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.primary.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.secondary.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Lambda Function Invocations"
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
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.primary.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.secondary.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.primary.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.secondary.function_name]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Lambda Function Errors and Duration"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.primary.name],
            ["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.secondary.name],
            ["AWS/Events", "SuccessfulInvocations", "RuleName", aws_cloudwatch_event_rule.primary.name],
            ["AWS/Events", "SuccessfulInvocations", "RuleName", aws_cloudwatch_event_rule.secondary.name]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "EventBridge Rule Executions and Success Rate"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          metrics = [
            [var.cloudwatch_metric_namespace, "ClusterHealth", "ClusterID", aws_dsql_cluster.primary.cluster_identifier, "Region", var.primary_region],
            [var.cloudwatch_metric_namespace, "ClusterHealth", "ClusterID", aws_dsql_cluster.secondary.cluster_identifier, "Region", var.secondary_region]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Aurora DSQL Cluster Health Status"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
        }
      }
    ]
  })
}

# ========================================
# CloudWatch Alarms
# ========================================

# Lambda function error alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors_primary" {
  provider = aws.primary
  
  alarm_name          = "Aurora-DSQL-Lambda-Errors-Primary-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors in primary region"
  alarm_actions       = [aws_sns_topic.primary.arn]
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    FunctionName = aws_lambda_function.primary.function_name
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = "lambda-errors-primary-${local.resource_suffix}"
      Region = "Primary"
      Type   = "LambdaAlarm"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_secondary" {
  provider = aws.secondary
  
  alarm_name          = "Aurora-DSQL-Lambda-Errors-Secondary-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors in secondary region"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    FunctionName = aws_lambda_function.secondary.function_name
  }
  
  tags = merge(
    local.common_tags,
    {
      Name   = "lambda-errors-secondary-${local.resource_suffix}"
      Region = "Secondary"
      Type   = "LambdaAlarm"
    }
  )
}

# Aurora DSQL cluster health alarm
resource "aws_cloudwatch_metric_alarm" "cluster_health" {
  provider = aws.primary
  
  alarm_name          = "Aurora-DSQL-Cluster-Health-${local.resource_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ClusterHealth"
  namespace           = var.cloudwatch_metric_namespace
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = "0.5"
  alarm_description   = "This metric monitors Aurora DSQL cluster health"
  alarm_actions       = [aws_sns_topic.primary.arn]
  treat_missing_data  = "breaching"
  
  tags = merge(
    local.common_tags,
    {
      Name = "cluster-health-${local.resource_suffix}"
      Type = "ClusterHealthAlarm"
    }
  )
}

# EventBridge rule failure alarm
resource "aws_cloudwatch_metric_alarm" "eventbridge_failures" {
  provider = aws.primary
  
  alarm_name          = "Aurora-DSQL-EventBridge-Failures-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors EventBridge rule failures"
  alarm_actions       = [aws_sns_topic.primary.arn]
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    RuleName = aws_cloudwatch_event_rule.primary.name
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "eventbridge-failures-${local.resource_suffix}"
      Type = "EventBridgeAlarm"
    }
  )
}