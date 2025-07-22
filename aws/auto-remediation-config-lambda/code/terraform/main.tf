# AWS Config Auto-Remediation Infrastructure
# This Terraform configuration creates a complete auto-remediation system using
# AWS Config for compliance monitoring and Lambda functions for automated fixes

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ====================================================================
# S3 BUCKET FOR AWS CONFIG
# ====================================================================

# S3 bucket for storing AWS Config configuration history and snapshots
resource "aws_s3_bucket" "config_bucket" {
  bucket        = "${var.s3_bucket_prefix}-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name        = "AWS Config Bucket"
    Purpose     = "Store configuration history and snapshots"
    Environment = var.environment
  }
}

# Block all public access to the Config bucket
resource "aws_s3_bucket_public_access_block" "config_bucket_pab" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on the Config bucket
resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for the Config bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  count  = var.enable_s3_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Bucket policy to allow AWS Config service access
resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.config_bucket_pab]
}

# ====================================================================
# IAM ROLES AND POLICIES
# ====================================================================

# IAM role for AWS Config service
resource "aws_iam_role" "config_role" {
  name = "${var.project_name}-config-role-${random_string.suffix.result}"

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

  tags = {
    Name        = "AWS Config Service Role"
    Purpose     = "Allow Config service to access AWS resources"
    Environment = var.environment
  }
}

# Attach AWS managed policy for Config service
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/ConfigRole"
}

# IAM role for Lambda remediation functions
resource "aws_iam_role" "lambda_remediation_role" {
  name = "${var.project_name}-lambda-role-${random_string.suffix.result}"

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

  tags = {
    Name        = "Lambda Remediation Role"
    Purpose     = "Execute remediation actions for Config rule violations"
    Environment = var.environment
  }
}

# Custom policy for Lambda remediation functions
resource "aws_iam_policy" "lambda_remediation_policy" {
  name        = "${var.project_name}-lambda-policy-${random_string.suffix.result}"
  description = "Policy for Lambda functions to perform auto-remediation"

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
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutPublicAccessBlock",
          "s3:GetPublicAccessBlock"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "config:PutEvaluations"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.compliance_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetAccountPasswordPolicy",
          "iam:UpdateAccountPasswordPolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_remediation_policy_attachment" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = aws_iam_policy.lambda_remediation_policy.arn
}

# ====================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ====================================================================

# SNS topic for compliance notifications
resource "aws_sns_topic" "compliance_notifications" {
  name         = "${var.project_name}-compliance-alerts-${random_string.suffix.result}"
  display_name = "Config Compliance Notifications"

  tags = {
    Name        = "Compliance Notifications"
    Purpose     = "Send alerts for compliance violations and remediations"
    Environment = var.environment
  }
}

# Email subscriptions for SNS topic
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = length(var.sns_email_notifications)
  topic_arn = aws_sns_topic.compliance_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email_notifications[count.index]
}

# ====================================================================
# AWS CONFIG SETUP
# ====================================================================

# Configuration recorder for AWS Config
resource "aws_config_configuration_recorder" "recorder" {
  name     = "default"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.enable_config_global_recording
    resource_types                = var.resource_types_to_record
  }

  depends_on = [aws_config_delivery_channel.delivery_channel]
}

# Delivery channel for AWS Config
resource "aws_config_delivery_channel" "delivery_channel" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  snapshot_delivery_properties {
    delivery_frequency = var.config_delivery_frequency
  }

  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

# ====================================================================
# LAMBDA FUNCTIONS FOR REMEDIATION
# ====================================================================

# Security Group Remediation Lambda Function
resource "aws_lambda_function" "security_group_remediation" {
  filename         = data.archive_file.sg_remediation_zip.output_path
  function_name    = "${var.project_name}-sg-remediation-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_remediation_role.arn
  handler         = "sg_remediation.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.sg_remediation_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.compliance_notifications.arn
    }
  }

  tags = {
    Name        = "Security Group Remediation"
    Purpose     = "Automatically remediate security group violations"
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_remediation_policy_attachment]
}

# CloudWatch Log Group for Security Group Remediation Lambda
resource "aws_cloudwatch_log_group" "sg_remediation_logs" {
  name              = "/aws/lambda/${aws_lambda_function.security_group_remediation.function_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name        = "SG Remediation Logs"
    Environment = var.environment
  }
}

# S3 Bucket Remediation Lambda Function
resource "aws_lambda_function" "s3_remediation" {
  filename         = data.archive_file.s3_remediation_zip.output_path
  function_name    = "${var.project_name}-s3-remediation-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_remediation_role.arn
  handler         = "s3_remediation.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.s3_remediation_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.compliance_notifications.arn
    }
  }

  tags = {
    Name        = "S3 Bucket Remediation"
    Purpose     = "Automatically remediate S3 bucket public access violations"
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_remediation_policy_attachment]
}

# CloudWatch Log Group for S3 Remediation Lambda
resource "aws_cloudwatch_log_group" "s3_remediation_logs" {
  name              = "/aws/lambda/${aws_lambda_function.s3_remediation.function_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name        = "S3 Remediation Logs"
    Environment = var.environment
  }
}

# Lambda function source code archives
data "archive_file" "sg_remediation_zip" {
  type        = "zip"
  output_path = "${path.module}/sg_remediation.zip"
  source {
    content = local.sg_remediation_code
    filename = "sg_remediation.py"
  }
}

data "archive_file" "s3_remediation_zip" {
  type        = "zip"
  output_path = "${path.module}/s3_remediation.zip"
  source {
    content = local.s3_remediation_code
    filename = "s3_remediation.py"
  }
}

# ====================================================================
# CONFIG RULES
# ====================================================================

# Config rule: Security groups should not allow unrestricted SSH access
resource "aws_config_config_rule" "security_group_ssh_restricted" {
  count = var.config_rules_enabled.security_group_ssh_restricted ? 1 : 0
  name  = "security-group-ssh-restricted"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::SecurityGroup"]
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = {
    Name        = "SSH Restricted Rule"
    Purpose     = "Monitor security groups for unrestricted SSH access"
    Environment = var.environment
  }
}

# Config rule: S3 buckets should prohibit public access
resource "aws_config_config_rule" "s3_bucket_public_access_prohibited" {
  count = var.config_rules_enabled.s3_bucket_public_access_prohibited ? 1 : 0
  name  = "s3-bucket-public-access-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
  }

  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = {
    Name        = "S3 Public Access Rule"
    Purpose     = "Monitor S3 buckets for public access violations"
    Environment = var.environment
  }
}

# Config rule: Root user should not have access keys
resource "aws_config_config_rule" "root_access_key_check" {
  count = var.config_rules_enabled.root_access_key_check ? 1 : 0
  name  = "root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = {
    Name        = "Root Access Key Rule"
    Purpose     = "Monitor for root user access keys"
    Environment = var.environment
  }
}

# Config rule: IAM password policy check
resource "aws_config_config_rule" "iam_password_policy" {
  count = var.config_rules_enabled.iam_password_policy ? 1 : 0
  name  = "iam-password-policy"

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols            = "true"
    RequireNumbers            = "true"
    MinimumPasswordLength     = "8"
    PasswordReusePrevention   = "12"
    MaxPasswordAge            = "90"
  })

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = {
    Name        = "IAM Password Policy Rule"
    Purpose     = "Monitor IAM password policy compliance"
    Environment = var.environment
  }
}

# ====================================================================
# AUTO-REMEDIATION CONFIGURATIONS
# ====================================================================

# Auto-remediation for security group SSH rule
resource "aws_config_remediation_configuration" "sg_ssh_remediation" {
  count           = var.auto_remediation_enabled && var.config_rules_enabled.security_group_ssh_restricted ? 1 : 0
  config_rule_name = aws_config_config_rule.security_group_ssh_restricted[0].name

  resource_type    = "AWS::EC2::SecurityGroup"
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWSConfigRemediation-RemoveUnrestrictedSourceInSecurityGroup"
  target_version   = "1"
  automatic        = true
  maximum_automatic_attempts = var.max_remediation_attempts

  parameter {
    name           = "AutomationAssumeRole"
    static_value   = aws_iam_role.lambda_remediation_role.arn
  }

  parameter {
    name                = "GroupId"
    resource_value      = "RESOURCE_ID"
  }

  depends_on = [aws_config_config_rule.security_group_ssh_restricted]
}

# Auto-remediation for S3 bucket public access
resource "aws_config_remediation_configuration" "s3_public_access_remediation" {
  count           = var.auto_remediation_enabled && var.config_rules_enabled.s3_bucket_public_access_prohibited ? 1 : 0
  config_rule_name = aws_config_config_rule.s3_bucket_public_access_prohibited[0].name

  resource_type    = "AWS::S3::Bucket"
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWSConfigRemediation-ConfigureS3PublicAccessBlock"
  target_version   = "1"
  automatic        = true
  maximum_automatic_attempts = var.max_remediation_attempts

  parameter {
    name           = "AutomationAssumeRole"
    static_value   = aws_iam_role.lambda_remediation_role.arn
  }

  parameter {
    name                = "BucketName"
    resource_value      = "RESOURCE_ID"
  }

  depends_on = [aws_config_config_rule.s3_bucket_public_access_prohibited]
}

# ====================================================================
# CLOUDWATCH DASHBOARD
# ====================================================================

# CloudWatch Dashboard for compliance monitoring
resource "aws_cloudwatch_dashboard" "compliance_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${var.project_name}-compliance-dashboard-${random_string.suffix.result}"

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
            ["AWS/Config", "ComplianceByConfigRule", "ConfigRuleName", "security-group-ssh-restricted", "ComplianceType", "COMPLIANT"],
            ["...", "NON_COMPLIANT"],
            ["...", "s3-bucket-public-access-prohibited", ".", "COMPLIANT"],
            ["...", "NON_COMPLIANT"]
          ]
          period = 300
          stat   = "Maximum"
          region = var.aws_region
          title  = "Config Rule Compliance Status"
          view   = "timeSeries"
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.security_group_remediation.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."],
            [".", "Invocations", "FunctionName", aws_lambda_function.s3_remediation.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Remediation Function Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.security_group_remediation.function_name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
          region  = var.aws_region
          title   = "Recent Remediation Actions"
        }
      }
    ]
  })

  tags = {
    Name        = "Compliance Dashboard"
    Purpose     = "Monitor Config compliance and remediation metrics"
    Environment = var.environment
  }
}

# ====================================================================
# LAMBDA FUNCTION SOURCE CODE
# ====================================================================

# Security Group Remediation Lambda function code
locals {
  sg_remediation_code = <<EOF
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Remediate security groups that allow unrestricted access (0.0.0.0/0)
    """
    
    try:
        # Parse the Config rule evaluation
        config_item = event['configurationItem']
        resource_id = config_item['resourceId']
        resource_type = config_item['resourceType']
        
        logger.info(f"Processing remediation for {resource_type}: {resource_id}")
        
        if resource_type != 'AWS::EC2::SecurityGroup':
            return {
                'statusCode': 400,
                'body': json.dumps('This function only handles Security Groups')
            }
        
        # Get security group details
        response = ec2.describe_security_groups(GroupIds=[resource_id])
        security_group = response['SecurityGroups'][0]
        
        remediation_actions = []
        
        # Check inbound rules for unrestricted access
        for rule in security_group['IpPermissions']:
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    # Remove unrestricted inbound rule
                    try:
                        ec2.revoke_security_group_ingress(
                            GroupId=resource_id,
                            IpPermissions=[rule]
                        )
                        remediation_actions.append(f"Removed unrestricted inbound rule: {rule}")
                        logger.info(f"Removed unrestricted inbound rule from {resource_id}")
                    except Exception as e:
                        logger.error(f"Failed to remove inbound rule: {e}")
        
        # Add tag to indicate remediation
        ec2.create_tags(
            Resources=[resource_id],
            Tags=[
                {
                    'Key': 'AutoRemediated',
                    'Value': 'true'
                },
                {
                    'Key': 'RemediationDate',
                    'Value': datetime.now().isoformat()
                }
            ]
        )
        
        # Send notification if remediation occurred
        if remediation_actions:
            message = {
                'resource_id': resource_id,
                'resource_type': resource_type,
                'remediation_actions': remediation_actions,
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to SNS topic
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if topic_arn:
                sns.publish(
                    TopicArn=topic_arn,
                    Subject=f'Security Group Auto-Remediation: {resource_id}',
                    Message=json.dumps(message, indent=2)
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': resource_id,
                'actions_taken': len(remediation_actions)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF

  s3_remediation_code = <<EOF
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Remediate S3 buckets with public access violations
    """
    
    try:
        # Parse the Config rule evaluation
        config_item = event['configurationItem']
        resource_id = config_item['resourceId']
        resource_type = config_item['resourceType']
        
        logger.info(f"Processing remediation for {resource_type}: {resource_id}")
        
        if resource_type != 'AWS::S3::Bucket':
            return {
                'statusCode': 400,
                'body': json.dumps('This function only handles S3 Buckets')
            }
        
        remediation_actions = []
        
        # Apply public access block to bucket
        try:
            s3.put_public_access_block(
                Bucket=resource_id,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )
            remediation_actions.append("Applied S3 public access block configuration")
            logger.info(f"Applied public access block to bucket {resource_id}")
        except Exception as e:
            logger.error(f"Failed to apply public access block: {e}")
        
        # Add tags to indicate remediation
        try:
            s3.put_bucket_tagging(
                Bucket=resource_id,
                Tagging={
                    'TagSet': [
                        {
                            'Key': 'AutoRemediated',
                            'Value': 'true'
                        },
                        {
                            'Key': 'RemediationDate',
                            'Value': datetime.now().isoformat()
                        }
                    ]
                }
            )
        except Exception as e:
            logger.warning(f"Failed to add tags to bucket {resource_id}: {e}")
        
        # Send notification if remediation occurred
        if remediation_actions:
            message = {
                'resource_id': resource_id,
                'resource_type': resource_type,
                'remediation_actions': remediation_actions,
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to SNS topic
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if topic_arn:
                sns.publish(
                    TopicArn=topic_arn,
                    Subject=f'S3 Bucket Auto-Remediation: {resource_id}',
                    Message=json.dumps(message, indent=2)
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': resource_id,
                'actions_taken': len(remediation_actions)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
}