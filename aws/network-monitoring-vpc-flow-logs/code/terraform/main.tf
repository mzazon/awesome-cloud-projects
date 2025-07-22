# VPC Flow Logs Monitoring Infrastructure
# This configuration creates a comprehensive network monitoring solution using VPC Flow Logs

# Data sources
data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  # Use provided VPC ID or default VPC
  id      = var.vpc_id
  default = var.vpc_id == null ? true : null
}

# Generate random suffix for resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming
  name_prefix   = "${var.project_name}-${var.environment}"
  random_suffix = lower(random_id.suffix.hex)
  
  # S3 bucket name (must be globally unique)
  s3_bucket_name = "${local.name_prefix}-flow-logs-${data.aws_caller_identity.current.account_id}-${local.random_suffix}"
  
  # CloudWatch log group name
  log_group_name = "/aws/vpc/flowlogs/${local.name_prefix}"
  
  # SNS topic name
  sns_topic_name = "${local.name_prefix}-alerts-${local.random_suffix}"
  
  # Lambda function name
  lambda_function_name = "${local.name_prefix}-anomaly-detector-${local.random_suffix}"
  
  # IAM role name
  flow_logs_role_name = "${local.name_prefix}-flowlogs-role-${local.random_suffix}"
  lambda_role_name    = "${local.name_prefix}-lambda-role-${local.random_suffix}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Component   = "network-monitoring"
  }
}

# S3 Bucket for Flow Logs Storage
resource "aws_s3_bucket" "flow_logs" {
  count  = var.enable_s3_flow_logs ? 1 : 0
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-flow-logs-bucket"
    Description = "S3 bucket for VPC Flow Logs storage and analytics"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "flow_logs" {
  count  = var.enable_s3_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count  = var.enable_s3_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count  = var.enable_s3_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count  = var.enable_s3_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "flow_logs_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_transition_days + 30
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_cloudwatch_flow_logs ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-flow-logs"
    Description = "CloudWatch Log Group for VPC Flow Logs real-time monitoring"
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_logs" {
  name = local.flow_logs_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-flow-logs-role"
    Description = "IAM role for VPC Flow Logs service"
  })
}

# IAM Role Policy Attachment for VPC Flow Logs
resource "aws_iam_role_policy_attachment" "flow_logs" {
  role       = aws_iam_role.flow_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy"
}

# VPC Flow Logs to CloudWatch
resource "aws_flow_log" "cloudwatch" {
  count                = var.enable_cloudwatch_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_logs.arn
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = data.aws_vpc.selected.id
  
  max_aggregation_interval = var.max_aggregation_interval

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-cloudwatch-flow-log"
    Description = "VPC Flow Log for real-time monitoring via CloudWatch"
  })
}

# VPC Flow Logs to S3
resource "aws_flow_log" "s3" {
  count                = var.enable_s3_flow_logs ? 1 : 0
  log_destination      = "${aws_s3_bucket.flow_logs[0].arn}/vpc-flow-logs/"
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = data.aws_vpc.selected.id
  
  max_aggregation_interval = var.max_aggregation_interval
  
  # Enhanced log format with additional fields for security analysis
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr}"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-s3-flow-log"
    Description = "VPC Flow Log for long-term storage and analytics via S3"
  })
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-alerts"
    Description = "SNS topic for network monitoring alerts"
  })
}

# SNS Topic Subscription (if email provided)
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Metric Filter for Rejected Connections
resource "aws_cloudwatch_log_metric_filter" "rejected_connections" {
  count          = var.enable_cloudwatch_flow_logs ? 1 : 0
  name           = "RejectedConnections"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]"

  metric_transformation {
    name      = "RejectedConnections"
    namespace = "VPC/FlowLogs"
    value     = "1"
  }
}

# CloudWatch Metric Filter for High Data Transfer
resource "aws_cloudwatch_log_metric_filter" "high_data_transfer" {
  count          = var.enable_cloudwatch_flow_logs ? 1 : 0
  name           = "HighDataTransfer"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes>10000000, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name      = "HighDataTransfer"
    namespace = "VPC/FlowLogs"
    value     = "1"
  }
}

# CloudWatch Metric Filter for External Connections
resource "aws_cloudwatch_log_metric_filter" "external_connections" {
  count          = var.enable_cloudwatch_flow_logs ? 1 : 0
  name           = "ExternalConnections"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source!=\"10.*\" && source!=\"172.16.*\" && source!=\"192.168.*\", destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name      = "ExternalConnections"
    namespace = "VPC/FlowLogs"
    value     = "1"
  }
}

# CloudWatch Alarm for Rejected Connections
resource "aws_cloudwatch_metric_alarm" "rejected_connections" {
  count               = var.enable_cloudwatch_flow_logs ? 1 : 0
  alarm_name          = "${local.name_prefix}-high-rejected-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RejectedConnections"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_rejected_connections_threshold
  alarm_description   = "Alert when rejected connections exceed threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-rejected-connections-alarm"
    Description = "Alarm for excessive rejected connections"
  })
}

# CloudWatch Alarm for High Data Transfer
resource "aws_cloudwatch_metric_alarm" "high_data_transfer" {
  count               = var.enable_cloudwatch_flow_logs ? 1 : 0
  alarm_name          = "${local.name_prefix}-high-data-transfer"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HighDataTransfer"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_high_data_transfer_threshold
  alarm_description   = "Alert when high data transfer detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-high-data-transfer-alarm"
    Description = "Alarm for high data transfer events"
  })
}

# CloudWatch Alarm for External Connections
resource "aws_cloudwatch_metric_alarm" "external_connections" {
  count               = var.enable_cloudwatch_flow_logs ? 1 : 0
  alarm_name          = "${local.name_prefix}-external-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ExternalConnections"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_external_connections_threshold
  alarm_description   = "Alert when external connections exceed threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-external-connections-alarm"
    Description = "Alarm for excessive external connections"
  })
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda" {
  count = var.enable_lambda_analysis ? 1 : 0
  name  = local.lambda_role_name

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
    Name        = "${local.name_prefix}-lambda-role"
    Description = "IAM role for Lambda function anomaly detection"
  })
}

# IAM Policy for Lambda Function
resource "aws_iam_role_policy" "lambda" {
  count = var.enable_lambda_analysis ? 1 : 0
  name  = "${local.lambda_role_name}-policy"
  role  = aws_iam_role.lambda[0].id

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
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# Lambda Function for Advanced Analysis
resource "aws_lambda_function" "anomaly_detector" {
  count            = var.enable_lambda_analysis ? 1 : 0
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda[0].arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-anomaly-detector"
    Description = "Lambda function for advanced VPC Flow Logs analysis"
  })
}

# Lambda Function Code
data "archive_file" "lambda_zip" {
  count       = var.enable_lambda_analysis ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      sns_topic_arn = aws_sns_topic.alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Create Lambda function code file
resource "local_file" "lambda_function" {
  count    = var.enable_lambda_analysis ? 1 : 0
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import boto3
import gzip
import base64
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Advanced analysis function for VPC Flow Logs anomaly detection.
    Processes CloudWatch Logs data and detects suspicious patterns.
    """
    
    # Decode and decompress CloudWatch Logs data
    try:
        compressed_payload = base64.b64decode(event['awslogs']['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
    except Exception as e:
        print(f"Error processing log data: {str(e)}")
        return {
            'statusCode': 400,
            'body': json.dumps('Error processing log data')
        }
    
    anomalies = []
    
    # Process each log event
    for log_event in log_data['logEvents']:
        message = log_event['message']
        fields = message.split(' ')
        
        if len(fields) >= 14:
            try:
                srcaddr = fields[3]
                dstaddr = fields[4]
                srcport = fields[5]
                dstport = fields[6]
                protocol = fields[7]
                bytes_transferred = int(fields[9]) if fields[9].isdigit() else 0
                action = fields[12]
                
                # Detect potential anomalies
                
                # High data transfer anomaly (>50MB)
                if bytes_transferred > 50000000:
                    anomalies.append({
                        'type': 'high_data_transfer',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'bytes': bytes_transferred,
                        'timestamp': log_event['timestamp']
                    })
                
                # Rejected TCP connections
                if action == 'REJECT' and protocol == '6':
                    anomalies.append({
                        'type': 'rejected_tcp',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'port': dstport,
                        'timestamp': log_event['timestamp']
                    })
                
                # Suspicious port scanning (common attack ports)
                suspicious_ports = ['22', '23', '25', '53', '80', '110', '443', '993', '995']
                if action == 'REJECT' and dstport in suspicious_ports:
                    anomalies.append({
                        'type': 'port_scan_attempt',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'port': dstport,
                        'timestamp': log_event['timestamp']
                    })
                
            except (ValueError, IndexError) as e:
                print(f"Error parsing log event: {str(e)}")
                continue
    
    # Send notifications for detected anomalies
    if anomalies:
        try:
            sns = boto3.client('sns')
            message = f"Network anomalies detected:\\n\\n{json.dumps(anomalies, indent=2)}"
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=message,
                Subject=f'Network Anomaly Alert - {len(anomalies)} anomalies detected'
            )
            
            print(f"Sent notification for {len(anomalies)} anomalies")
            
        except Exception as e:
            print(f"Error sending SNS notification: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Analysis complete',
            'anomalies_detected': len(anomalies)
        })
    }
EOF
}

# Athena Workgroup for Flow Logs Analysis
resource "aws_athena_workgroup" "flow_logs" {
  count = var.enable_athena_analysis && var.enable_s3_flow_logs ? 1 : 0
  name  = "${local.name_prefix}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.flow_logs[0].bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-athena-workgroup"
    Description = "Athena workgroup for VPC Flow Logs analysis"
  })
}

# Athena Database
resource "aws_athena_database" "flow_logs" {
  count  = var.enable_athena_analysis && var.enable_s3_flow_logs ? 1 : 0
  name   = replace("${local.name_prefix}_flow_logs", "-", "_")
  bucket = aws_s3_bucket.flow_logs[0].bucket
}

# CloudWatch Dashboard for Network Monitoring
resource "aws_cloudwatch_dashboard" "network_monitoring" {
  count          = var.enable_cloudwatch_flow_logs ? 1 : 0
  dashboard_name = "${local.name_prefix}-monitoring"

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
            ["VPC/FlowLogs", "RejectedConnections"],
            [".", "HighDataTransfer"],
            [".", "ExternalConnections"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Network Security Metrics"
          period  = 300
          stat    = "Sum"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.flow_logs[0].name}' | fields @timestamp, @message | filter @message like /REJECT/ | stats count() by bin(5m)"
          region  = var.aws_region
          title   = "Rejected Connections Over Time"
        }
      }
    ]
  })
}