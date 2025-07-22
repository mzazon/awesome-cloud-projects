# AWS Serverless Email Processing System with SES and Lambda
# This infrastructure creates a complete email processing system using AWS services

# Get current AWS region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Use provided bucket name or generate one with random suffix
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "email-processing-${random_string.suffix.result}"
  
  # Use provided SES region or current region
  ses_region = var.ses_region != "" ? var.ses_region : data.aws_region.current.name
  
  # Default email addresses if none provided
  email_addresses = length(var.email_addresses) > 0 ? var.email_addresses : [
    "support@${var.domain_name}",
    "invoices@${var.domain_name}"
  ]
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Project     = "ServerlessEmailProcessing"
    Environment = var.environment
    Domain      = var.domain_name
  })
}

# ============================================================================
# S3 BUCKET FOR EMAIL STORAGE
# ============================================================================

# S3 bucket to store incoming emails
resource "aws_s3_bucket" "email_storage" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = "Email Storage Bucket"
    Purpose     = "Store incoming emails for processing"
    Service     = "S3"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "email_storage" {
  bucket = aws_s3_bucket.email_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "email_storage" {
  count  = var.enable_email_encryption ? 1 : 0
  bucket = aws_s3_bucket.email_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Configure S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "email_storage" {
  bucket = aws_s3_bucket.email_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure S3 bucket lifecycle to manage email retention
resource "aws_s3_bucket_lifecycle_configuration" "email_storage" {
  bucket = aws_s3_bucket.email_storage.id

  rule {
    id     = "email_retention"
    status = "Enabled"

    expiration {
      days = var.email_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 bucket policy to allow SES to write emails
resource "aws_s3_bucket_policy" "email_storage" {
  bucket = aws_s3_bucket.email_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSESWriteAccess"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.email_storage.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "AWS:SourceArn" = "arn:aws:ses:${local.ses_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

# ============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ============================================================================

# SNS topic for email processing notifications
resource "aws_sns_topic" "email_notifications" {
  name = "email-notifications-${random_string.suffix.result}"

  tags = merge(local.common_tags, {
    Name    = "Email Processing Notifications"
    Purpose = "Notify about email processing events"
    Service = "SNS"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "email_notifications" {
  arn = aws_sns_topic.email_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution.arn
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.email_notifications.arn
      }
    ]
  })
}

# Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.create_sns_subscription ? 1 : 0
  topic_arn = aws_sns_topic.email_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# IAM ROLE AND POLICIES FOR LAMBDA
# ============================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution" {
  name = "EmailProcessorRole-${random_string.suffix.result}"

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
    Name    = "Lambda Execution Role"
    Purpose = "Allow Lambda to access AWS services for email processing"
    Service = "IAM"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for email processing permissions
resource "aws_iam_policy" "email_processor" {
  name        = "EmailProcessorPolicy-${random_string.suffix.result}"
  description = "Policy for Lambda email processing function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.email_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.email_notifications.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "Email Processor Policy"
    Purpose = "Permissions for Lambda email processing"
    Service = "IAM"
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "email_processor" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.email_processor.arn
}

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

# Create Lambda function source code
resource "local_file" "lambda_source" {
  filename = "${path.module}/email-processor.py"
  content  = <<EOF
import json
import boto3
import email
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

s3 = boto3.client('s3')
ses = boto3.client('ses')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """Main Lambda handler for processing SES email events"""
    try:
        # Parse SES event
        ses_event = event['Records'][0]['ses']
        message_id = ses_event['mail']['messageId']
        receipt = ses_event['receipt']
        
        # Get email from S3 if stored there
        bucket_name = os.environ.get('BUCKET_NAME')
        
        # Get email object from S3
        s3_key = f"emails/{message_id}"
        response = s3.get_object(Bucket=bucket_name, Key=s3_key)
        raw_email = response['Body'].read()
        
        # Parse email
        email_message = email.message_from_bytes(raw_email)
        
        # Extract email details
        sender = email_message.get('From', 'Unknown')
        subject = email_message.get('Subject', 'No Subject')
        recipient = receipt['recipients'][0] if receipt['recipients'] else 'Unknown'
        
        print(f"Processing email from {sender} with subject: {subject}")
        
        # Process email based on subject or content
        if 'support' in subject.lower():
            process_support_email(sender, subject, email_message)
        elif 'invoice' in subject.lower():
            process_invoice_email(sender, subject, email_message)
        else:
            process_general_email(sender, subject, email_message)
        
        # Send notification
        notify_processing_complete(message_id, sender, subject)
        
        return {'statusCode': 200, 'body': 'Email processed successfully'}
        
    except Exception as e:
        print(f"Error processing email: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def process_support_email(sender, subject, email_message):
    """Process support-related emails"""
    print(f"Processing support email from {sender}")
    
    # Generate ticket ID
    ticket_id = f"TICKET-{hash(sender) % 10000}"
    
    # Send auto-reply
    reply_subject = f"Re: {subject} - Ticket Created"
    reply_body = f"""Thank you for contacting our support team.

Your ticket has been created and assigned ID: {ticket_id}

We will respond within 24 hours.

Best regards,
Support Team"""
    
    send_reply(sender, reply_subject, reply_body)
    
    # Notify support team via SNS
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject=f"New Support Ticket: {subject}",
        Message=f"From: {sender}\nSubject: {subject}\nTicket ID: {ticket_id}\nPlease check email processing system."
    )

def process_invoice_email(sender, subject, email_message):
    """Process invoice-related emails"""
    print(f"Processing invoice email from {sender}")
    
    # Generate invoice reference
    invoice_ref = f"INV-{hash(sender) % 10000}"
    
    # Send confirmation
    reply_subject = f"Invoice Received: {subject}"
    reply_body = f"""We have received your invoice.

Invoice will be processed within 5 business days.
Reference: {invoice_ref}

Accounts Payable Team"""
    
    send_reply(sender, reply_subject, reply_body)

def process_general_email(sender, subject, email_message):
    """Process general emails"""
    print(f"Processing general email from {sender}")
    
    # Send general acknowledgment
    reply_subject = f"Re: {subject}"
    reply_body = f"""Thank you for your email.

We have received your message and will respond appropriately.

Best regards,
Customer Service"""
    
    send_reply(sender, reply_subject, reply_body)

def send_reply(to_email, subject, body):
    """Send automated reply via SES"""
    try:
        from_email = os.environ.get('FROM_EMAIL', f'noreply@{os.environ.get("DOMAIN_NAME", "example.com")}')
        
        ses.send_email(
            Source=from_email,
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject},
                'Body': {'Text': {'Data': body}}
            }
        )
        print(f"Sent reply to {to_email}")
    except Exception as e:
        print(f"Error sending reply: {str(e)}")

def notify_processing_complete(message_id, sender, subject):
    """Send processing notification via SNS"""
    try:
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject="Email Processed",
            Message=f"Message ID: {message_id}\nFrom: {sender}\nSubject: {subject}"
        )
        print(f"Sent notification for message {message_id}")
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
EOF
}

# Create ZIP archive for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/email-processor.zip"
  depends_on  = [local_file.lambda_source]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/email-processor-${random_string.suffix.result}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name    = "Lambda Email Processor Logs"
    Purpose = "Store Lambda function execution logs"
    Service = "CloudWatch"
  })
}

# Lambda function for email processing
resource "aws_lambda_function" "email_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "email-processor-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "email-processor.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      BUCKET_NAME     = aws_s3_bucket.email_storage.bucket
      SNS_TOPIC_ARN   = aws_sns_topic.email_notifications.arn
      FROM_EMAIL      = "noreply@${var.domain_name}"
      DOMAIN_NAME     = var.domain_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.email_processor,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name    = "Email Processor Function"
    Purpose = "Process incoming emails and send automated responses"
    Service = "Lambda"
  })
}

# Lambda permission for SES to invoke the function
resource "aws_lambda_permission" "ses_invoke" {
  statement_id  = "AllowExecutionFromSES"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_processor.function_name
  principal     = "ses.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

# ============================================================================
# SES CONFIGURATION
# ============================================================================

# Verify domain identity for SES
resource "aws_ses_domain_identity" "domain" {
  domain = var.domain_name
}

# Domain verification record
resource "aws_ses_domain_identity_verification" "domain_verification" {
  domain = aws_ses_domain_identity.domain.id
}

# Create SES receipt rule set
resource "aws_ses_receipt_rule_set" "email_processing" {
  rule_set_name = "EmailProcessingRuleSet-${random_string.suffix.result}"
}

# Set the rule set as active
resource "aws_ses_active_receipt_rule_set" "email_processing" {
  rule_set_name = aws_ses_receipt_rule_set.email_processing.rule_set_name
}

# SES receipt rule for email processing
resource "aws_ses_receipt_rule" "email_processing" {
  name          = "EmailProcessingRule-${random_string.suffix.result}"
  rule_set_name = aws_ses_receipt_rule_set.email_processing.rule_set_name
  recipients    = local.email_addresses
  enabled       = true
  scan_enabled  = true
  tls_policy    = "Optional"

  # Store email in S3
  s3_action {
    bucket_name       = aws_s3_bucket.email_storage.bucket
    object_key_prefix = "emails/"
    position          = 1
  }

  # Invoke Lambda function
  lambda_action {
    function_arn    = aws_lambda_function.email_processor.arn
    invocation_type = "Event"
    position        = 2
  }

  depends_on = [
    aws_lambda_permission.ses_invoke,
    aws_s3_bucket_policy.email_storage
  ]
}

# ============================================================================
# OUTPUTS FOR VERIFICATION AND INTEGRATION
# ============================================================================

# Output important resource information for verification and integration