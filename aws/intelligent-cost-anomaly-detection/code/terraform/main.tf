# ==========================================
# Data Sources
# ==========================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# ==========================================
# SNS Topic for Cost Anomaly Notifications
# ==========================================

resource "aws_sns_topic" "cost_anomaly_alerts" {
  name         = "${var.project_name}-alerts-${random_id.suffix.hex}"
  display_name = "Cost Anomaly Alerts"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-alerts-${random_id.suffix.hex}"
    Description = "SNS topic for cost anomaly detection notifications"
  })
}

# SNS topic policy to allow Cost Anomaly Detection service to publish
resource "aws_sns_topic_policy" "cost_anomaly_alerts_policy" {
  arn = aws_sns_topic.cost_anomaly_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCostAnomalyDetectionPublish"
        Effect = "Allow"
        Principal = {
          Service = "costalerts.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cost_anomaly_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution_role.arn
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cost_anomaly_alerts.arn
      }
    ]
  })
}

# Primary email subscription
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.cost_anomaly_alerts.arn
  protocol  = "email"
  endpoint  = var.email_address
}

# Additional SNS subscriptions
resource "aws_sns_topic_subscription" "additional_notifications" {
  count     = length(var.additional_sns_endpoints)
  topic_arn = aws_sns_topic.cost_anomaly_alerts.arn
  protocol  = var.additional_sns_endpoints[count.index].protocol
  endpoint  = var.additional_sns_endpoints[count.index].endpoint
}

# ==========================================
# IAM Role and Policies for Lambda Function
# ==========================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "CostAnomalyLambdaRole-${random_id.suffix.hex}"

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

  tags = merge(var.tags, {
    Name        = "CostAnomalyLambdaRole-${random_id.suffix.hex}"
    Description = "IAM role for Cost Anomaly Detection Lambda function"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for cost operations
resource "aws_iam_policy" "cost_anomaly_policy" {
  name        = "CostAnomalyPolicy-${random_id.suffix.hex}"
  description = "Policy for Cost Anomaly Detection Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:GetDimensionValues",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization",
          "ce:ListCostCategoryDefinitions",
          "ce:GetRightsizingRecommendation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_anomaly_alerts.arn
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "CostAnomalyPolicy-${random_id.suffix.hex}"
    Description = "IAM policy for Cost Anomaly Detection operations"
  })
}

# Attach custom policy to role
resource "aws_iam_role_policy_attachment" "cost_anomaly_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.cost_anomaly_policy.arn
}

# ==========================================
# Lambda Function for Cost Anomaly Processing
# ==========================================

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/cost_anomaly_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      sns_topic_arn = aws_sns_topic.cost_anomaly_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "cost_anomaly_processor" {
  function_name    = "${var.project_name}-processor-${random_id.suffix.hex}"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Enhanced Cost Anomaly Detection processor"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_anomaly_alerts.arn
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-processor-${random_id.suffix.hex}"
    Description = "Lambda function for processing cost anomaly events"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.cost_anomaly_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-processor-${random_id.suffix.hex}"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name        = "lambda-logs-${var.project_name}-${random_id.suffix.hex}"
    Description = "CloudWatch log group for Cost Anomaly Lambda function"
  })
}

# ==========================================
# Cost Anomaly Detection Monitor
# ==========================================

resource "aws_ce_anomaly_monitor" "cost_monitor" {
  name         = "${var.project_name}-monitor-${random_id.suffix.hex}"
  monitor_type = "DIMENSIONAL"

  specification = jsonencode({
    Dimension    = var.monitor_dimension
    MatchOptions = ["EQUALS"]
    Values       = var.monitored_services
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-monitor-${random_id.suffix.hex}"
    Description = "Cost Anomaly Detection monitor for ${join(", ", var.monitored_services)}"
  })
}

# ==========================================
# EventBridge Rule for Cost Anomalies
# ==========================================

resource "aws_cloudwatch_event_rule" "cost_anomaly_rule" {
  name        = "cost-anomaly-rule-${random_id.suffix.hex}"
  description = "Rule to capture Cost Anomaly Detection events"

  event_pattern = jsonencode({
    source      = ["aws.ce"]
    detail-type = ["Anomaly Detected"]
  })

  tags = merge(var.tags, {
    Name        = "cost-anomaly-rule-${random_id.suffix.hex}"
    Description = "EventBridge rule for cost anomaly detection events"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cost_anomaly_rule.name
  target_id = "CostAnomalyLambdaTarget"
  arn       = aws_lambda_function.cost_anomaly_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge_invoke_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_anomaly_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_anomaly_rule.arn
}

# ==========================================
# Cost Anomaly Detector
# ==========================================

resource "aws_ce_anomaly_detector" "cost_detector" {
  name      = "${var.project_name}-detector-${random_id.suffix.hex}"
  frequency = var.detection_frequency
  threshold = var.anomaly_threshold

  monitor_arn_list = [
    aws_ce_anomaly_monitor.cost_monitor.arn
  ]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_anomaly_alerts.arn
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-detector-${random_id.suffix.hex}"
    Description = "Cost Anomaly Detector with $${var.anomaly_threshold} threshold"
  })

  depends_on = [aws_sns_topic_policy.cost_anomaly_alerts_policy]
}

# ==========================================
# CloudWatch Dashboard (Optional)
# ==========================================

resource "aws_cloudwatch_dashboard" "cost_anomaly_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "CostAnomalyDetection-${random_id.suffix.hex}"

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
            ["AWS/CostAnomaly", "AnomalyImpact"],
            [".", "AnomalyPercentage"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Cost Anomaly Metrics"
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.cost_anomaly_processor.function_name],
            [".", "Duration", ".", "."],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.cost_anomaly_processor.function_name}'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 20"
          region  = data.aws_region.current.name
          title   = "Recent Lambda Logs"
        }
      }
    ]
  })
}

# ==========================================
# Lambda Function Code File
# ==========================================

# Create the Lambda function Python code
resource "local_file" "lambda_function_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<-EOF
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Process Cost Anomaly Detection events with enhanced analysis
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    # Initialize AWS clients
    ce_client = boto3.client('ce')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Extract anomaly details from EventBridge event
        detail = event['detail']
        anomaly_id = detail['anomalyId']
        total_impact = detail['impact']['totalImpact']
        account_name = detail['accountName']
        dimension_value = detail.get('dimensionValue', 'N/A')
        
        # Calculate percentage impact
        total_actual = detail['impact']['totalActualSpend']
        total_expected = detail['impact']['totalExpectedSpend']
        impact_percentage = detail['impact']['totalImpactPercentage']
        
        # Get additional cost breakdown
        cost_breakdown = get_cost_breakdown(ce_client, detail)
        
        # Publish custom CloudWatch metrics
        publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage)
        
        # Send enhanced notification
        send_enhanced_notification(sns, detail, cost_breakdown)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed anomaly {anomaly_id}',
                'total_impact': float(total_impact),
                'impact_percentage': float(impact_percentage)
            })
        }
        
    except Exception as e:
        print(f"Error processing anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_breakdown(ce_client, detail):
    """Get detailed cost breakdown for the anomaly period"""
    try:
        end_date = detail['anomalyEndDate'][:10]  # YYYY-MM-DD
        start_date = detail['anomalyStartDate'][:10]
        
        # Get cost and usage data
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response.get('ResultsByTime', [])
        
    except Exception as e:
        print(f"Error getting cost breakdown: {str(e)}")
        return []

def publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage):
    """Publish custom CloudWatch metrics for anomaly tracking"""
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/CostAnomaly',
            MetricData=[
                {
                    'MetricName': 'AnomalyImpact',
                    'Value': float(total_impact),
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                },
                {
                    'MetricName': 'AnomalyPercentage',
                    'Value': float(impact_percentage),
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                }
            ]
        )
        print("✅ Custom metrics published to CloudWatch")
        
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def send_enhanced_notification(sns, detail, cost_breakdown):
    """Send enhanced notification with detailed analysis"""
    try:
        # Format the notification message
        message = format_notification_message(detail, cost_breakdown)
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"🚨 AWS Cost Anomaly Detected - $${detail['impact']['totalImpact']:.2f}",
            Message=message
        )
        
        print(f"✅ Notification sent: {response['MessageId']}")
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")

def format_notification_message(detail, cost_breakdown):
    """Format detailed notification message"""
    impact = detail['impact']
    
    message = f"""
AWS Cost Anomaly Detection Alert
================================

Anomaly ID: {detail['anomalyId']}
Account: {detail['accountName']}
Service: {detail.get('dimensionValue', 'Multiple Services')}

Cost Impact:
- Total Impact: ${impact['totalImpact']:.2f}
- Actual Spend: ${impact['totalActualSpend']:.2f}
- Expected Spend: ${impact['totalExpectedSpend']:.2f}
- Percentage Increase: {impact['totalImpactPercentage']:.1f}%

Period:
- Start: {detail['anomalyStartDate']}
- End: {detail['anomalyEndDate']}

Anomaly Score:
- Current: {detail['anomalyScore']['currentScore']:.3f}
- Maximum: {detail['anomalyScore']['maxScore']:.3f}

Root Causes:
"""
    
    # Add root cause analysis
    for cause in detail.get('rootCauses', []):
        message += f"""
- Account: {cause.get('linkedAccountName', 'N/A')}
  Service: {cause.get('service', 'N/A')}
  Region: {cause.get('region', 'N/A')}
  Usage Type: {cause.get('usageType', 'N/A')}
  Contribution: ${cause.get('impact', {}).get('contribution', 0):.2f}
"""
    
    message += f"""

Next Steps:
1. Review the affected services and usage patterns
2. Check for any unauthorized usage or misconfigurations
3. Consider implementing cost controls if needed
4. Monitor for additional anomalies

AWS Console Links:
- Cost Explorer: https://console.aws.amazon.com/billing/home#/costexplorer
- Cost Anomaly Detection: https://console.aws.amazon.com/billing/home#/anomaly-detection

Generated by: AWS Cost Anomaly Detection Lambda
Timestamp: {datetime.now().isoformat()}
    """
    
    return message
EOF
}