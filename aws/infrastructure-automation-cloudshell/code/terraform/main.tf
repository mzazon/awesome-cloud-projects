# Infrastructure Management Automation with CloudShell PowerShell
# This Terraform configuration creates a complete serverless automation solution
# for infrastructure management using AWS CloudShell, Lambda, Systems Manager,
# EventBridge, and CloudWatch monitoring.

# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 6
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM role for automation services (Lambda and Systems Manager)
resource "aws_iam_role" "automation_role" {
  name = local.automation_role_name
  path = "/"
  
  # Trust policy allowing Lambda and SSM to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ssm.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = local.automation_role_name
    Component = "IAM"
  })
}

# Custom IAM policy for infrastructure automation permissions
resource "aws_iam_role_policy" "automation_policy" {
  name = "InfrastructureAutomationPolicy"
  role = aws_iam_role.automation_role.id
  
  # Policy allowing comprehensive infrastructure read access and automation
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # EC2 permissions for instance health checks
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          
          # S3 permissions for compliance checks
          "s3:ListAllMyBuckets",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning",
          "s3:GetBucketLogging",
          "s3:GetBucketTagging",
          
          # RDS permissions for database health
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:DescribeDBSnapshots",
          
          # IAM permissions for security auditing
          "iam:ListRoles",
          "iam:ListUsers",
          "iam:ListPolicies",
          "iam:GetRole",
          "iam:GetUser",
          "iam:GetPolicy",
          
          # CloudWatch permissions for metrics and alarms
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          
          # CloudWatch Logs permissions
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          # Systems Manager automation execution
          "ssm:StartAutomationExecution",
          "ssm:GetAutomationExecution",
          "ssm:DescribeAutomationExecutions",
          "ssm:DescribeAutomationStepExecutions",
          "ssm:StopAutomationExecution",
          
          # Parameter Store access for configuration
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policies for Lambda execution and Systems Manager
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ssm_automation" {
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
}

# ==============================================================================
# CLOUDWATCH LOGS
# ==============================================================================

# CloudWatch log group for automation logs
resource "aws_cloudwatch_log_group" "automation_logs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = local.log_group_name
    Component = "Logging"
  })
}

# CloudWatch log group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Component = "Lambda"
  })
}

# ==============================================================================
# SYSTEMS MANAGER AUTOMATION DOCUMENT
# ==============================================================================

# PowerShell script content for infrastructure health checks
locals {
  powershell_script = <<-EOF
param(
    [string]$Region = "${data.aws_region.current.name}",
    [string]$LogGroup = "${local.log_group_name}"
)

# Function to write structured logs
function Write-AutomationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        message = $Message
        region = $Region
    } | ConvertTo-Json -Compress
    
    Write-Host $logEntry
}

# Check EC2 instance health
function Test-EC2Health {
    Write-AutomationLog "Starting EC2 health assessment"
    try {
        $instances = Get-EC2Instance -Region $Region
        $healthReport = @()
        
        foreach ($reservation in $instances) {
            foreach ($instance in $reservation.Instances) {
                $healthStatus = @{
                    InstanceId = $instance.InstanceId
                    State = $instance.State.Name
                    Type = $instance.InstanceType
                    LaunchTime = $instance.LaunchTime
                    PublicIP = $instance.PublicIpAddress
                    PrivateIP = $instance.PrivateIpAddress
                    SecurityGroups = ($instance.SecurityGroups | ForEach-Object { $_.GroupName }) -join ","
                }
                $healthReport += $healthStatus
            }
        }
        
        Write-AutomationLog "Found $($healthReport.Count) EC2 instances"
        return $healthReport
    }
    catch {
        Write-AutomationLog "EC2 health check failed: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Check S3 bucket compliance
function Test-S3Compliance {
    Write-AutomationLog "Starting S3 compliance assessment"
    try {
        $buckets = Get-S3Bucket -Region $Region
        $complianceReport = @()
        
        foreach ($bucket in $buckets) {
            $encryption = Get-S3BucketEncryption -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
            $versioning = Get-S3BucketVersioning -BucketName $bucket.BucketName
            $logging = Get-S3BucketLogging -BucketName $bucket.BucketName
            
            $complianceStatus = @{
                BucketName = $bucket.BucketName
                CreationDate = $bucket.CreationDate
                EncryptionEnabled = $null -ne $encryption
                VersioningEnabled = $versioning.Status -eq "Enabled"
                LoggingEnabled = $null -ne $logging.LoggingEnabled
            }
            $complianceReport += $complianceStatus
        }
        
        Write-AutomationLog "Assessed $($complianceReport.Count) S3 buckets"
        return $complianceReport
    }
    catch {
        Write-AutomationLog "S3 compliance check failed: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Main execution
try {
    Write-AutomationLog "Infrastructure health check started"
    
    # Import required modules
    Import-Module AWS.Tools.EC2 -Force
    Import-Module AWS.Tools.S3 -Force
    
    $ec2Health = Test-EC2Health
    $s3Compliance = Test-S3Compliance
    
    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        Region = $Region
        EC2Health = $ec2Health
        S3Compliance = $s3Compliance
        Summary = @{
            EC2InstanceCount = $ec2Health.Count
            S3BucketCount = $s3Compliance.Count
            HealthyInstances = ($ec2Health | Where-Object { $_.State -eq "running" }).Count
            CompliantBuckets = ($s3Compliance | Where-Object { $_.EncryptionEnabled -and $_.VersioningEnabled }).Count
        }
    }
    
    Write-AutomationLog "Health check completed successfully"
    Write-AutomationLog ($report.Summary | ConvertTo-Json)
    
    # Return the report
    return $report
    
} catch {
    Write-AutomationLog "Health check failed: $($_.Exception.Message)" "ERROR"
    throw
}
EOF
}

# Systems Manager automation document for PowerShell execution
resource "aws_ssm_document" "automation_document" {
  name          = local.automation_document_name
  document_type = "Automation"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Infrastructure Health Check Automation with PowerShell"
    assumeRole    = aws_iam_role.automation_role.arn
    parameters = {
      Region = {
        type        = "String"
        description = "AWS Region for health check"
        default     = data.aws_region.current.name
      }
      LogGroupName = {
        type        = "String"
        description = "CloudWatch Log Group for automation logs"
        default     = local.log_group_name
      }
    }
    mainSteps = [
      {
        name   = "CreateLogGroup"
        action = "aws:executeAwsApi"
        inputs = {
          Service      = "logs"
          Api          = "CreateLogGroup"
          logGroupName = "{{ LogGroupName }}"
        }
        onFailure = "Continue"
      },
      {
        name   = "ExecuteHealthCheck"
        action = "aws:executeScript"
        inputs = {
          Runtime = "PowerShell Core 6.0"
          Script  = local.powershell_script
          InputPayload = {
            Region   = "{{ Region }}"
            LogGroup = "{{ LogGroupName }}"
          }
        }
      }
    ]
    outputs = [
      "ExecuteHealthCheck.Payload"
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = local.automation_document_name
    Component = "SystemsManager"
  })
}

# ==============================================================================
# LAMBDA FUNCTION
# ==============================================================================

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-automation.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to orchestrate infrastructure automation
    """
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    
    automation_document = os.environ['AUTOMATION_DOCUMENT_NAME']
    region = os.environ.get('AWS_REGION', '${data.aws_region.current.name}')
    
    try:
        # Execute automation document
        response = ssm.start_automation_execution(
            DocumentName=automation_document,
            Parameters={
                'Region': [region],
                'LogGroupName': ['${local.log_group_name}']
            }
        )
        
        execution_id = response['AutomationExecutionId']
        
        # Send custom metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Automation',
            MetricData=[
                {
                    'MetricName': 'AutomationExecutions',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DocumentName',
                            'Value': automation_document
                        }
                    ]
                }
            ]
        )
        
        print(f"Successfully started automation execution: {execution_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Automation started successfully',
                'executionId': execution_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        # Send error metric
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Automation',
            MetricData=[
                {
                    'MetricName': 'AutomationErrors',
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        print(f"Error executing automation: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
EOF
    filename = "lambda-automation.py"
  }
}

# Lambda function for automation orchestration
resource "aws_lambda_function" "automation_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.automation_role.arn
  handler         = "lambda-automation.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      AUTOMATION_DOCUMENT_NAME = aws_ssm_document.automation_document.name
      LOG_GROUP_NAME          = local.log_group_name
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Component = "Lambda"
  })
}

# ==============================================================================
# EVENTBRIDGE SCHEDULING
# ==============================================================================

# EventBridge rule for scheduled automation
resource "aws_cloudwatch_event_rule" "automation_schedule" {
  name                = local.schedule_rule_name
  description         = "Daily infrastructure health check automation"
  schedule_expression = var.schedule_expression
  state              = "ENABLED"
  
  tags = merge(local.common_tags, {
    Name = local.schedule_rule_name
    Component = "EventBridge"
  })
}

# EventBridge target pointing to Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.automation_schedule.name
  target_id = "InfrastructureAutomationLambdaTarget"
  arn       = aws_lambda_function.automation_lambda.arn
}

# Lambda permission for EventBridge to invoke the function
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.automation_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.automation_schedule.arn
}

# ==============================================================================
# SNS NOTIFICATIONS (OPTIONAL)
# ==============================================================================

# SNS topic for automation alerts (only created if notification_email is provided)
resource "aws_sns_topic" "automation_alerts" {
  count = var.notification_email != "" ? 1 : 0
  
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
    Component = "SNS"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.automation_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# CLOUDWATCH MONITORING
# ==============================================================================

# CloudWatch alarm for automation errors
resource "aws_cloudwatch_metric_alarm" "automation_errors" {
  count = var.enable_alarms ? 1 : 0
  
  alarm_name          = "InfrastructureAutomationErrors-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "AutomationErrors"
  namespace           = "Infrastructure/Automation"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors infrastructure automation errors"
  treat_missing_data  = "notBreaching"
  
  alarm_actions = var.notification_email != "" ? [aws_sns_topic.automation_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "InfrastructureAutomationErrors-${local.resource_suffix}"
    Component = "CloudWatch"
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_alarms ? 1 : 0
  
  alarm_name          = "LambdaAutomationErrors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda function errors"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    FunctionName = aws_lambda_function.automation_lambda.function_name
  }
  
  alarm_actions = var.notification_email != "" ? [aws_sns_topic.automation_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "LambdaAutomationErrors-${local.resource_suffix}"
    Component = "CloudWatch"
  })
}

# CloudWatch dashboard for automation monitoring
resource "aws_cloudwatch_dashboard" "automation_dashboard" {
  count = var.enable_dashboard ? 1 : 0
  
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
            ["Infrastructure/Automation", "AutomationExecutions"],
            [".", "AutomationErrors"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Infrastructure Automation Metrics"
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.automation_lambda.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Performance"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${local.log_group_name}' | fields @timestamp, level, message | sort @timestamp desc | limit 100"
          region = data.aws_region.current.name
          title  = "Automation Logs"
        }
      }
    ]
  })
}