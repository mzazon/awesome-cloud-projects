# main.tf
# AWS Resource Tagging Automation with Lambda and EventBridge

# Get current AWS region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate resource name suffix
  name_suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_string.suffix.result
  
  # Common resource names
  lambda_function_name    = "${var.project_name}-${local.name_suffix}"
  iam_role_name          = "${var.project_name}-role-${local.name_suffix}"
  eventbridge_rule_name  = "${var.project_name}-rule-${local.name_suffix}"
  resource_group_name    = "${var.project_name}-group-${local.name_suffix}"
  
  # Standard tags that will be applied by the Lambda function
  automated_tags = merge(var.standard_tags, {
    Environment = var.environment
    CostCenter  = var.cost_center
    Department  = var.department
    Contact     = var.contact_email
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# ============================================================================
# IAM Role and Policies for Lambda Function
# ============================================================================

# IAM role for the Lambda function
resource "aws_iam_role" "lambda_role" {
  name        = local.iam_role_name
  description = "IAM role for automated resource tagging Lambda function"

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

  tags = {
    Name        = local.iam_role_name
    Description = "Lambda execution role for resource tagging automation"
  }
}

# IAM policy for Lambda function permissions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "AutoTaggingPolicy"
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
          # EC2 permissions
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeVolumes",
          # S3 permissions
          "s3:PutBucketTagging",
          "s3:GetBucketTagging",
          # RDS permissions
          "rds:AddTagsToResource",
          "rds:ListTagsForResource",
          "rds:DescribeDBInstances",
          # Lambda permissions
          "lambda:TagResource",
          "lambda:ListTags",
          "lambda:GetFunction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          # Resource Groups and Tagging API permissions
          "resource-groups:Tag",
          "resource-groups:GetTags",
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources",
          "tag:GetTagKeys",
          "tag:GetTagValues"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# Lambda Function for Automated Tagging
# ============================================================================

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      standard_tags = jsonencode(local.automated_tags)
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for automated resource tagging
resource "aws_lambda_function" "auto_tagger" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Automated resource tagging function for ${var.project_name}"
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables for configuration
  environment {
    variables = {
      ENVIRONMENT   = var.environment
      COST_CENTER   = var.cost_center
      DEPARTMENT    = var.department
      CONTACT_EMAIL = var.contact_email
      PROJECT_NAME  = var.project_name
    }
  }

  # Enable detailed monitoring if specified
  tracing_config {
    mode = var.enable_detailed_monitoring ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = {
    Name        = local.lambda_function_name
    Description = "Automated resource tagging Lambda function"
  }
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${local.lambda_function_name}-logs"
    Description = "Log group for automated tagging Lambda function"
  }
}

# ============================================================================
# EventBridge Rule and Target Configuration
# ============================================================================

# EventBridge rule to capture resource creation events
resource "aws_cloudwatch_event_rule" "resource_creation" {
  name        = local.eventbridge_rule_name
  description = var.eventbridge_rule_description
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = var.aws_services
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = var.cloudtrail_events
      eventSource = [
        "ec2.amazonaws.com",
        "s3.amazonaws.com", 
        "rds.amazonaws.com",
        "lambda.amazonaws.com"
      ]
    }
  })

  tags = {
    Name        = local.eventbridge_rule_name
    Description = "EventBridge rule for resource creation monitoring"
  }
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.resource_creation.name
  target_id = "AutoTaggerLambdaTarget"
  arn       = aws_lambda_function.auto_tagger.arn

  # Add retry policy for failed invocations
  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }

  # Dead letter configuration for failed events
  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

# Grant EventBridge permission to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_tagger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.resource_creation.arn
}

# ============================================================================
# Dead Letter Queue for Failed Events
# ============================================================================

# SQS Dead Letter Queue for failed EventBridge events
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.lambda_function_name}-dlq"
  message_retention_seconds = 1209600 # 14 days
  
  tags = {
    Name        = "${local.lambda_function_name}-dlq"
    Description = "Dead letter queue for failed tagging events"
  }
}

# SQS queue policy to allow EventBridge to send messages
resource "aws_sqs_queue_policy" "dlq_policy" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ============================================================================
# Resource Group for Tagged Resources
# ============================================================================

# Resource Group to organize auto-tagged resources
resource "aws_resourcegroups_group" "auto_tagged" {
  count = var.enable_resource_group ? 1 : 0
  
  name        = local.resource_group_name
  description = "Resources automatically tagged by Lambda function"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "AutoTagged"
          Values = ["true"]
        }
      ]
    })
  }

  tags = {
    Name        = local.resource_group_name
    Description = "Resource group for automatically tagged resources"
    Purpose     = "automation"
  }
}

# ============================================================================
# CloudWatch Alarms for Monitoring
# ============================================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors for auto-tagging"
  alarm_actions       = [] # Add SNS topic ARN here if needed

  dimensions = {
    FunctionName = aws_lambda_function.auto_tagger.function_name
  }

  tags = {
    Name        = "${local.lambda_function_name}-error-alarm"
    Description = "CloudWatch alarm for Lambda function errors"
  }
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8) # 80% of timeout
  alarm_description   = "This metric monitors Lambda function duration for auto-tagging"
  alarm_actions       = [] # Add SNS topic ARN here if needed

  dimensions = {
    FunctionName = aws_lambda_function.auto_tagger.function_name
  }

  tags = {
    Name        = "${local.lambda_function_name}-duration-alarm"
    Description = "CloudWatch alarm for Lambda function duration"
  }
}

# ============================================================================
# Create Lambda Function Template File
# ============================================================================

# Create the Lambda function Python code template
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOF
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Standard tags configuration
STANDARD_TAGS = json.loads('${standard_tags}')

def lambda_handler(event, context):
    """
    Process CloudTrail events and apply tags to newly created resources
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        source_ip_address = detail.get('sourceIPAddress', 'unknown')
        user_identity = detail.get('userIdentity', {})
        user_name = user_identity.get('userName', user_identity.get('type', 'unknown'))
        
        logger.info(f"Processing event: {event_name} by user: {user_name}")
        
        # Create dynamic tags with current information
        dynamic_tags = STANDARD_TAGS.copy()
        dynamic_tags.update({
            'CreatedBy': user_name,
            'CreatedDate': datetime.now().strftime('%Y-%m-%d'),
            'SourceIP': source_ip_address[:15] if len(source_ip_address) <= 15 else 'unknown'
        })
        
        # Process different resource types
        resources_tagged = 0
        
        if event_name == 'RunInstances':
            resources_tagged += tag_ec2_instances(detail, dynamic_tags)
        elif event_name == 'CreateBucket':
            resources_tagged += tag_s3_bucket(detail, dynamic_tags)
        elif event_name == 'CreateDBInstance':
            resources_tagged += tag_rds_instance(detail, dynamic_tags)
        elif event_name == 'CreateFunction20150331':
            resources_tagged += tag_lambda_function(detail, dynamic_tags)
        else:
            logger.warning(f"Unsupported event type: {event_name}")
        
        logger.info(f"Successfully tagged {resources_tagged} resources")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Tagged {resources_tagged} resources',
                'event': event_name,
                'user': user_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'event': event.get('detail', {}).get('eventName', 'unknown')
            })
        }

def tag_ec2_instances(detail, tags):
    """Tag EC2 instances with error handling"""
    try:
        ec2 = boto3.client('ec2')
        instance_ids = []
        
        # Extract instance IDs from response elements
        response_elements = detail.get('responseElements', {})
        instances = response_elements.get('instancesSet', {}).get('items', [])
        
        for instance in instances:
            if 'instanceId' in instance:
                instance_ids.append(instance['instanceId'])
        
        if instance_ids:
            tag_list = [{'Key': k, 'Value': str(v)} for k, v in tags.items()]
            ec2.create_tags(Resources=instance_ids, Tags=tag_list)
            logger.info(f"Tagged EC2 instances: {instance_ids}")
            return len(instance_ids)
            
    except Exception as e:
        logger.error(f"Error tagging EC2 instances: {str(e)}")
    
    return 0

def tag_s3_bucket(detail, tags):
    """Tag S3 bucket with error handling"""
    try:
        s3 = boto3.client('s3')
        
        # Extract bucket name
        request_params = detail.get('requestParameters', {})
        bucket_name = request_params.get('bucketName')
        
        if bucket_name:
            # Get existing tags to avoid overwriting
            try:
                existing_tags = s3.get_bucket_tagging(Bucket=bucket_name).get('TagSet', [])
                existing_tag_dict = {tag['Key']: tag['Value'] for tag in existing_tags}
            except s3.exceptions.ClientError:
                existing_tag_dict = {}
            
            # Merge with new tags (new tags take precedence)
            merged_tags = {**existing_tag_dict, **tags}
            tag_set = [{'Key': k, 'Value': str(v)} for k, v in merged_tags.items()]
            
            s3.put_bucket_tagging(
                Bucket=bucket_name,
                Tagging={'TagSet': tag_set}
            )
            logger.info(f"Tagged S3 bucket: {bucket_name}")
            return 1
            
    except Exception as e:
        logger.error(f"Error tagging S3 bucket: {str(e)}")
    
    return 0

def tag_rds_instance(detail, tags):
    """Tag RDS instance with error handling"""
    try:
        rds = boto3.client('rds')
        
        # Extract DB instance identifier
        response_elements = detail.get('responseElements', {})
        db_instance = response_elements.get('dBInstance', {})
        db_instance_arn = db_instance.get('dBInstanceArn')
        
        if db_instance_arn:
            tag_list = [{'Key': k, 'Value': str(v)} for k, v in tags.items()]
            rds.add_tags_to_resource(
                ResourceName=db_instance_arn,
                Tags=tag_list
            )
            logger.info(f"Tagged RDS instance: {db_instance_arn}")
            return 1
            
    except Exception as e:
        logger.error(f"Error tagging RDS instance: {str(e)}")
    
    return 0

def tag_lambda_function(detail, tags):
    """Tag Lambda function with error handling"""
    try:
        lambda_client = boto3.client('lambda')
        
        # Extract function name/ARN
        response_elements = detail.get('responseElements', {})
        function_arn = response_elements.get('functionArn')
        
        if function_arn:
            # Convert tags to string values as required by Lambda
            string_tags = {k: str(v) for k, v in tags.items()}
            
            lambda_client.tag_resource(
                Resource=function_arn,
                Tags=string_tags
            )
            logger.info(f"Tagged Lambda function: {function_arn}")
            return 1
            
    except Exception as e:
        logger.error(f"Error tagging Lambda function: {str(e)}")
    
    return 0
EOF
}