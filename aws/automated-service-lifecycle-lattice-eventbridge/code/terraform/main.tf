# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming
locals {
  name_prefix             = "${var.project_name}-${var.environment}"
  random_suffix          = random_string.suffix.result
  service_network_name   = var.service_network_name != "" ? var.service_network_name : "${local.name_prefix}-network-${local.random_suffix}"
  event_bus_name         = var.custom_event_bus_name != "" ? var.custom_event_bus_name : "${local.name_prefix}-bus-${local.random_suffix}"
  lambda_role_name       = "${local.name_prefix}-lambda-role-${local.random_suffix}"
  log_group_name         = "/aws/vpclattice/${local.name_prefix}-${local.random_suffix}"
  
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# CloudWatch Log Group for VPC Lattice access logs
resource "aws_cloudwatch_log_group" "vpc_lattice_logs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-lattice-logs"
  })
}

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = local.service_network_name
  auth_type = var.service_network_auth_type
  
  tags = merge(local.common_tags, {
    Name = local.service_network_name
  })
}

# VPC Lattice Access Log Subscription
resource "aws_vpclattice_access_log_subscription" "main" {
  resource_identifier = aws_vpclattice_service_network.main.id
  destination_arn     = aws_cloudwatch_log_group.vpc_lattice_logs.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-access-log-subscription"
  })
}

# Custom EventBridge Bus
resource "aws_cloudwatch_event_bus" "service_lifecycle" {
  name = local.event_bus_name
  
  tags = merge(local.common_tags, {
    Name = local.event_bus_name
  })
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = local.lambda_role_name
  
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
    Name = local.lambda_role_name
  })
}

# IAM Policy for Lambda Functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.lambda_role_name}-policy"
  role = aws_iam_role.lambda_role.id
  
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
          "vpc-lattice:*"
        ]
        Resource = "*"
      },
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
          "events:PutEvents"
        ]
        Resource = [
          aws_cloudwatch_event_bus.service_lifecycle.arn,
          "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:SetDesiredCapacity"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "health_monitor_logs" {
  name              = "/aws/lambda/${local.name_prefix}-health-monitor-${local.random_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-health-monitor-logs"
  })
}

resource "aws_cloudwatch_log_group" "auto_scaler_logs" {
  name              = "/aws/lambda/${local.name_prefix}-auto-scaler-${local.random_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-auto-scaler-logs"
  })
}

# Health Monitor Lambda Function Code
data "archive_file" "health_monitor" {
  type        = "zip"
  output_path = "${path.module}/health_monitor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    lattice = boto3.client('vpc-lattice')
    cloudwatch = boto3.client('cloudwatch')
    eventbridge = boto3.client('events')
    
    service_network_id = os.environ['SERVICE_NETWORK_ID']
    event_bus_name = os.environ['EVENT_BUS_NAME']
    
    try:
        # Get service network services
        services = lattice.list_services(
            serviceNetworkIdentifier=service_network_id
        )
        
        for service in services.get('items', []):
            service_id = service['id']
            service_name = service['name']
            
            # Get CloudWatch metrics for service health
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=5)
            
            metrics = cloudwatch.get_metric_statistics(
                Namespace='AWS/VpcLattice',
                MetricName='RequestCount',
                Dimensions=[
                    {'Name': 'ServiceId', 'Value': service_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=300,
                Statistics=['Sum']
            )
            
            # Determine service health based on metrics
            request_count = sum([point['Sum'] for point in metrics['Datapoints']])
            health_status = 'healthy' if request_count > 0 else 'unhealthy'
            
            # Publish service health event
            event_detail = {
                'serviceId': service_id,
                'serviceName': service_name,
                'healthStatus': health_status,
                'requestCount': request_count,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'vpc-lattice.health-monitor',
                        'DetailType': 'Service Health Check',
                        'Detail': json.dumps(event_detail),
                        'EventBusName': event_bus_name
                    }
                ]
            )
        
        return {'statusCode': 200, 'body': 'Health check completed'}
        
    except Exception as e:
        print(f"Error in health monitoring: {str(e)}")
        return {'statusCode': 500, 'body': f"Error: {str(e)}"}
EOF
    filename = "health_monitor.py"
  }
}

# Health Monitor Lambda Function
resource "aws_lambda_function" "health_monitor" {
  filename         = data.archive_file.health_monitor.output_path
  function_name    = "${local.name_prefix}-health-monitor-${local.random_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "health_monitor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.health_monitor.output_base64sha256
  
  environment {
    variables = {
      SERVICE_NETWORK_ID = aws_vpclattice_service_network.main.id
      EVENT_BUS_NAME     = aws_cloudwatch_event_bus.service_lifecycle.name
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.health_monitor_logs,
    aws_iam_role.lambda_role
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-health-monitor"
  })
}

# Auto Scaler Lambda Function Code
data "archive_file" "auto_scaler" {
  type        = "zip"
  output_path = "${path.module}/auto_scaler.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os

def lambda_handler(event, context):
    lattice = boto3.client('vpc-lattice')
    ecs = boto3.client('ecs')
    
    try:
        # Parse EventBridge event
        detail = json.loads(event['detail']) if isinstance(event['detail'], str) else event['detail']
        service_id = detail['serviceId']
        service_name = detail['serviceName']
        health_status = detail['healthStatus']
        request_count = detail['requestCount']
        
        print(f"Processing scaling event for service: {service_name}")
        print(f"Health status: {health_status}, Request count: {request_count}")
        
        # Get target groups for the service
        target_groups = lattice.list_target_groups(
            serviceIdentifier=service_id
        )
        
        for tg in target_groups.get('items', []):
            tg_id = tg['id']
            
            # Get current target count
            targets = lattice.list_targets(
                targetGroupIdentifier=tg_id
            )
            current_count = len(targets.get('items', []))
            
            # Determine scaling action
            if health_status == 'unhealthy' and current_count < 5:
                # Scale up if unhealthy and below max capacity
                print(f"Triggering scale-up for target group: {tg_id}")
                # In real implementation, trigger ECS/ASG scaling
                
            elif health_status == 'healthy' and request_count < 10 and current_count > 1:
                # Scale down if healthy with low traffic
                print(f"Triggering scale-down for target group: {tg_id}")
                # In real implementation, trigger ECS/ASG scaling
        
        return {'statusCode': 200, 'body': 'Scaling evaluation completed'}
        
    except Exception as e:
        print(f"Error in auto-scaling: {str(e)}")
        return {'statusCode': 500, 'body': f"Error: {str(e)}"}
EOF
    filename = "auto_scaler.py"
  }
}

# Auto Scaler Lambda Function
resource "aws_lambda_function" "auto_scaler" {
  filename         = data.archive_file.auto_scaler.output_path
  function_name    = "${local.name_prefix}-auto-scaler-${local.random_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "auto_scaler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.auto_scaler.output_base64sha256
  
  depends_on = [
    aws_cloudwatch_log_group.auto_scaler_logs,
    aws_iam_role.lambda_role
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-auto-scaler"
  })
}

# EventBridge Rule for Health Monitoring Events
resource "aws_cloudwatch_event_rule" "health_monitoring" {
  name           = "${local.name_prefix}-health-monitoring-${local.random_suffix}"
  event_bus_name = aws_cloudwatch_event_bus.service_lifecycle.name
  
  event_pattern = jsonencode({
    source       = ["vpc-lattice.health-monitor"]
    detail-type  = ["Service Health Check"]
    detail = {
      healthStatus = ["unhealthy", "healthy"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-health-monitoring-rule"
  })
}

# EventBridge Target for Health Monitoring Rule
resource "aws_cloudwatch_event_target" "health_monitoring_target" {
  rule           = aws_cloudwatch_event_rule.health_monitoring.name
  event_bus_name = aws_cloudwatch_event_bus.service_lifecycle.name
  target_id      = "HealthMonitoringTarget"
  arn            = aws_lambda_function.auto_scaler.arn
}

# Lambda Permission for EventBridge Health Monitoring Rule
resource "aws_lambda_permission" "eventbridge_health_monitoring" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_scaler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_monitoring.arn
}

# CloudWatch Events Rule for Scheduled Health Checks
resource "aws_cloudwatch_event_rule" "scheduled_health_check" {
  name                = "${local.name_prefix}-scheduled-health-check-${local.random_suffix}"
  schedule_expression = var.health_check_schedule
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-scheduled-health-check"
  })
}

# CloudWatch Events Target for Scheduled Health Checks
resource "aws_cloudwatch_event_target" "scheduled_health_check_target" {
  rule      = aws_cloudwatch_event_rule.scheduled_health_check.name
  target_id = "ScheduledHealthCheckTarget"
  arn       = aws_lambda_function.health_monitor.arn
}

# Lambda Permission for CloudWatch Events Scheduled Rule
resource "aws_lambda_permission" "cloudwatch_scheduled" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled_health_check.arn
}

# CloudWatch Dashboard for Service Lifecycle Monitoring
resource "aws_cloudwatch_dashboard" "service_lifecycle" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-ServiceLifecycle-${local.random_suffix}"
  
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
            ["AWS/VpcLattice", "RequestCount"],
            ["AWS/VpcLattice", "ResponseTime"],
            ["AWS/VpcLattice", "TargetResponseTime"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "VPC Lattice Service Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE \"${aws_cloudwatch_log_group.health_monitor_logs.name}\" | fields @timestamp, @message | sort @timestamp desc | limit 20"
          region = data.aws_region.current.name
          title  = "Health Monitor Logs"
        }
      }
    ]
  })
}