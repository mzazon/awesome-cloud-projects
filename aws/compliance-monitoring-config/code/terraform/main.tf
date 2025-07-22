# AWS Config Compliance Monitoring Infrastructure
# This file creates a comprehensive compliance monitoring system using AWS Config

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
  random_suffix = random_id.suffix.hex
  
  # Common resource naming
  config_bucket_name    = "${var.project_name}-config-${local.account_id}-${local.random_suffix}"
  config_topic_name     = "${var.project_name}-compliance-topic-${local.random_suffix}"
  config_role_name      = "ConfigServiceRole-${local.random_suffix}"
  remediation_role_name = "ConfigRemediationRole-${local.random_suffix}"
  lambda_role_name      = "ConfigLambdaRole-${local.random_suffix}"
}

#
# S3 Bucket for AWS Config
#
resource "aws_s3_bucket" "config_bucket" {
  bucket        = local.config_bucket_name
  force_destroy = true

  tags = merge(var.default_tags, {
    Name        = local.config_bucket_name
    Environment = var.environment
    Purpose     = "AWS-Config-Storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "config_bucket_pab" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for AWS Config
resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

#
# SNS Topic for Compliance Notifications
#
resource "aws_sns_topic" "config_topic" {
  name = local.config_topic_name

  tags = merge(var.default_tags, {
    Name        = local.config_topic_name
    Environment = var.environment
    Purpose     = "Config-Notifications"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "config_topic_policy" {
  arn = aws_sns_topic.config_topic.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.config_topic.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription for notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.config_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#
# IAM Role for AWS Config Service
#
resource "aws_iam_role" "config_role" {
  name = local.config_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = local.config_role_name
    Environment = var.environment
    Purpose     = "Config-Service-Role"
  })
}

# Attach AWS managed policy for Config service
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# Additional S3 permissions for Config role
resource "aws_iam_role_policy" "config_s3_policy" {
  name = "ConfigS3Policy-${local.random_suffix}"
  role = aws_iam_role.config_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.config_bucket.arn,
          "${aws_s3_bucket.config_bucket.arn}/*"
        ]
      }
    ]
  })
}

#
# AWS Config Configuration Recorder
#
resource "aws_config_configuration_recorder" "recorder" {
  name     = "default"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = var.enable_all_resource_recording
    include_global_resource_types = var.enable_global_resource_recording
  }

  depends_on = [aws_config_delivery_channel.config_delivery_channel]
}

#
# AWS Config Delivery Channel
#
resource "aws_config_delivery_channel" "config_delivery_channel" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket
  sns_topic_arn  = aws_sns_topic.config_topic.arn

  snapshot_delivery_properties {
    delivery_frequency = var.config_delivery_frequency
  }

  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

#
# AWS Managed Config Rules
#
resource "aws_config_config_rule" "s3_bucket_public_access_prohibited" {
  name = "s3-bucket-public-access-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(var.default_tags, {
    Name        = "s3-bucket-public-access-prohibited"
    Environment = var.environment
    RuleType    = "AWS-Managed"
  })
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(var.default_tags, {
    Name        = "encrypted-volumes"
    Environment = var.environment
    RuleType    = "AWS-Managed"
  })
}

resource "aws_config_config_rule" "root_access_key_check" {
  name = "root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(var.default_tags, {
    Name        = "root-access-key-check"
    Environment = var.environment
    RuleType    = "AWS-Managed"
  })
}

resource "aws_config_config_rule" "required_tags_ec2" {
  name = "required-tags-ec2"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    for i, tag_key in keys(var.required_tags) : "tag${i + 1}Key" => tag_key
  })

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(var.default_tags, {
    Name        = "required-tags-ec2"
    Environment = var.environment
    RuleType    = "AWS-Managed"
  })
}

#
# IAM Role for Lambda Functions
#
resource "aws_iam_role" "lambda_role" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = local.lambda_role_name
    Environment = var.environment
    Purpose     = "Lambda-Execution-Role"
  })
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Config rules execution policy
resource "aws_iam_role_policy_attachment" "lambda_config_rules_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRulesExecutionRole"
}

#
# CloudWatch Log Groups for Lambda Functions
#
resource "aws_cloudwatch_log_group" "custom_rule_lambda_logs" {
  name              = "/aws/lambda/ConfigSecurityGroupRule-${local.random_suffix}"
  retention_in_days = var.cloudwatch_retention_days

  tags = merge(var.default_tags, {
    Name        = "ConfigSecurityGroupRule-LogGroup"
    Environment = var.environment
  })
}

resource "aws_cloudwatch_log_group" "remediation_lambda_logs" {
  name              = "/aws/lambda/ConfigRemediation-${local.random_suffix}"
  retention_in_days = var.cloudwatch_retention_days

  tags = merge(var.default_tags, {
    Name        = "ConfigRemediation-LogGroup"
    Environment = var.environment
  })
}

#
# Custom Lambda Function for Security Group Rules
#
resource "aws_lambda_function" "custom_rule_lambda" {
  filename         = "sg-rule-function.zip"
  function_name    = "ConfigSecurityGroupRule-${local.random_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "sg-rule-function.lambda_handler"
  source_code_hash = data.archive_file.sg_rule_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_config_rules_execution,
    aws_cloudwatch_log_group.custom_rule_lambda_logs,
  ]

  tags = merge(var.default_tags, {
    Name        = "ConfigSecurityGroupRule-${local.random_suffix}"
    Environment = var.environment
    Purpose     = "Custom-Config-Rule"
  })
}

# Archive file for custom rule Lambda
data "archive_file" "sg_rule_zip" {
  type        = "zip"
  output_path = "sg-rule-function.zip"
  source {
    content = <<EOF
import boto3
import json

def lambda_handler(event, context):
    # Initialize AWS Config client
    config = boto3.client('config')
    
    # Get configuration item from event
    configuration_item = event['configurationItem']
    
    # Initialize compliance status
    compliance_status = 'COMPLIANT'
    
    # Check if resource is a Security Group
    if configuration_item['resourceType'] == 'AWS::EC2::SecurityGroup':
        # Get security group configuration
        sg_config = configuration_item['configuration']
        
        # Check for overly permissive ingress rules
        for rule in sg_config.get('ipPermissions', []):
            for ip_range in rule.get('ipRanges', []):
                if ip_range.get('cidrIp') == '0.0.0.0/0':
                    # Check if it's not port 80 or 443
                    if rule.get('fromPort') not in [80, 443]:
                        compliance_status = 'NON_COMPLIANT'
                        break
            if compliance_status == 'NON_COMPLIANT':
                break
    
    # Put evaluation result
    config.put_evaluations(
        Evaluations=[
            {
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': configuration_item['resourceId'],
                'ComplianceType': compliance_status,
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }
        ],
        ResultToken=event['resultToken']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Config rule evaluation completed')
    }
EOF
    filename = "sg-rule-function.py"
  }
}

# Lambda permission for Config to invoke custom rule function
resource "aws_lambda_permission" "allow_config_invoke" {
  statement_id  = "ConfigPermission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custom_rule_lambda.function_name
  principal     = "config.amazonaws.com"
  source_account = local.account_id
}

# Custom Config Rule with Lambda
resource "aws_config_config_rule" "security_group_restricted_ingress" {
  name = "security-group-restricted-ingress"

  source {
    owner                = "CUSTOM_LAMBDA"
    source_identifier    = aws_lambda_function.custom_rule_lambda.arn
    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }

  depends_on = [aws_config_configuration_recorder.recorder, aws_lambda_permission.allow_config_invoke]

  tags = merge(var.default_tags, {
    Name        = "security-group-restricted-ingress"
    Environment = var.environment
    RuleType    = "Custom-Lambda"
  })
}

#
# Remediation Resources (conditional based on enable_remediation variable)
#
resource "aws_iam_role" "remediation_role" {
  count = var.enable_remediation ? 1 : 0
  name  = local.remediation_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = local.remediation_role_name
    Environment = var.environment
    Purpose     = "Remediation-Role"
  })
}

# Remediation policy
resource "aws_iam_role_policy" "remediation_policy" {
  count = var.enable_remediation ? 1 : 0
  name  = "ConfigRemediationPolicy-${local.random_suffix}"
  role  = aws_iam_role.remediation_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateTags",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeSecurityGroups",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach basic Lambda execution policy to remediation role
resource "aws_iam_role_policy_attachment" "remediation_lambda_basic" {
  count      = var.enable_remediation ? 1 : 0
  role       = aws_iam_role.remediation_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Remediation Lambda function
resource "aws_lambda_function" "remediation_lambda" {
  count            = var.enable_remediation ? 1 : 0
  filename         = "remediation-function.zip"
  function_name    = "ConfigRemediation-${local.random_suffix}"
  role            = aws_iam_role.remediation_role[0].arn
  handler         = "remediation-function.lambda_handler"
  source_code_hash = data.archive_file.remediation_zip[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout

  depends_on = [
    aws_iam_role_policy_attachment.remediation_lambda_basic,
    aws_cloudwatch_log_group.remediation_lambda_logs,
  ]

  tags = merge(var.default_tags, {
    Name        = "ConfigRemediation-${local.random_suffix}"
    Environment = var.environment
    Purpose     = "Auto-Remediation"
  })
}

# Archive file for remediation Lambda
data "archive_file" "remediation_zip" {
  count       = var.enable_remediation ? 1 : 0
  type        = "zip"
  output_path = "remediation-function.zip"
  source {
    content = <<EOF
import boto3
import json

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    
    # Parse the event
    detail = event['detail']
    config_rule_name = detail['configRuleName']
    compliance_type = detail['newEvaluationResult']['complianceType']
    resource_type = detail['resourceType']
    resource_id = detail['resourceId']
    
    if compliance_type == 'NON_COMPLIANT':
        if config_rule_name == 'required-tags-ec2' and resource_type == 'AWS::EC2::Instance':
            # Add missing tags to EC2 instance
            ec2.create_tags(
                Resources=[resource_id],
                Tags=[
                    {'Key': 'Environment', 'Value': 'Unknown'},
                    {'Key': 'Owner', 'Value': 'Unknown'}
                ]
            )
            print(f"Added missing tags to EC2 instance {resource_id}")
        
        elif config_rule_name == 's3-bucket-public-access-prohibited' and resource_type == 'AWS::S3::Bucket':
            # Block public access on S3 bucket
            s3.put_public_access_block(
                Bucket=resource_id,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )
            print(f"Blocked public access on S3 bucket {resource_id}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Remediation completed')
    }
EOF
    filename = "remediation-function.py"
  }
}

#
# EventBridge Rule for Automatic Remediation
#
resource "aws_cloudwatch_event_rule" "config_compliance_rule" {
  count       = var.enable_remediation ? 1 : 0
  name        = "ConfigComplianceRule-${local.random_suffix}"
  description = "Trigger remediation on Config compliance changes"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = merge(var.default_tags, {
    Name        = "ConfigComplianceRule-${local.random_suffix}"
    Environment = var.environment
    Purpose     = "Auto-Remediation-Trigger"
  })
}

# EventBridge target for remediation Lambda
resource "aws_cloudwatch_event_target" "remediation_target" {
  count     = var.enable_remediation ? 1 : 0
  rule      = aws_cloudwatch_event_rule.config_compliance_rule[0].name
  target_id = "RemediationLambdaTarget"
  arn       = aws_lambda_function.remediation_lambda[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  count         = var.enable_remediation ? 1 : 0
  statement_id  = "EventBridgePermission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_lambda[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance_rule[0].arn
}

#
# CloudWatch Dashboard for Compliance Monitoring
#
resource "aws_cloudwatch_dashboard" "compliance_dashboard" {
  dashboard_name = "ConfigComplianceDashboard-${local.random_suffix}"

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
            ["AWS/Config", "ComplianceByConfigRule", "ConfigRuleName", "s3-bucket-public-access-prohibited"],
            [".", ".", ".", "encrypted-volumes"],
            [".", ".", ".", "root-access-key-check"],
            [".", ".", ".", "required-tags-ec2"],
            [".", ".", ".", "security-group-restricted-ingress"]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = local.region
          title    = "Config Rule Compliance Status"
          period   = 300
          stat     = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = var.enable_remediation ? [
            ["AWS/Lambda", "Invocations", "FunctionName", "ConfigRemediation-${local.random_suffix}"],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ] : [
            ["AWS/Lambda", "Invocations", "FunctionName", "ConfigSecurityGroupRule-${local.random_suffix}"],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = local.region
          title    = var.enable_remediation ? "Remediation Function Metrics" : "Custom Rule Function Metrics"
          period   = 300
        }
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = "ConfigComplianceDashboard-${local.random_suffix}"
    Environment = var.environment
  })
}

#
# CloudWatch Alarms
#
resource "aws_cloudwatch_metric_alarm" "non_compliant_resources" {
  alarm_name          = "ConfigNonCompliantResources-${local.random_suffix}"
  alarm_description   = "Alert when non-compliant resources are detected"
  metric_name         = "ComplianceByConfigRule"
  namespace           = "AWS/Config"
  statistic           = "Sum"
  period              = 300
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  alarm_actions       = [aws_sns_topic.config_topic.arn]

  tags = merge(var.default_tags, {
    Name        = "ConfigNonCompliantResources-${local.random_suffix}"
    Environment = var.environment
  })
}

resource "aws_cloudwatch_metric_alarm" "remediation_errors" {
  count               = var.enable_remediation ? 1 : 0
  alarm_name          = "ConfigRemediationErrors-${local.random_suffix}"
  alarm_description   = "Alert when remediation function encounters errors"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  statistic           = "Sum"
  period              = 300
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  alarm_actions       = [aws_sns_topic.config_topic.arn]

  dimensions = {
    FunctionName = aws_lambda_function.remediation_lambda[0].function_name
  }

  tags = merge(var.default_tags, {
    Name        = "ConfigRemediationErrors-${local.random_suffix}"
    Environment = var.environment
  })
}