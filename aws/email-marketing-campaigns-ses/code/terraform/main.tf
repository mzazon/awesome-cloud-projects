# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values
locals {
  bucket_name         = "${var.bucket_name_prefix}-${random_string.suffix.result}"
  config_set_name     = "marketing-campaigns-${random_string.suffix.result}"
  sns_topic_name      = "email-events-${random_string.suffix.result}"
  lambda_function_name = "bounce-handler-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Project     = "EmailMarketingCampaigns"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "email-marketing-campaigns-amazon-ses"
    },
    var.additional_tags
  )
}

# S3 Bucket for templates and subscriber lists
resource "aws_s3_bucket" "email_marketing" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "Storage for email templates and subscriber lists"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "email_marketing" {
  bucket = aws_s3_bucket.email_marketing.id
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Suspended"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "email_marketing" {
  bucket = aws_s3_bucket.email_marketing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "email_marketing" {
  bucket = aws_s3_bucket.email_marketing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "email_marketing" {
  bucket = aws_s3_bucket.email_marketing.id

  rule {
    id     = "cleanup_old_objects"
    status = "Enabled"

    expiration {
      days = var.bucket_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Upload sample subscriber list
resource "aws_s3_object" "sample_subscribers" {
  bucket = aws_s3_bucket.email_marketing.id
  key    = "subscribers/subscribers.json"
  content = jsonencode([
    {
      email       = "subscriber1@example.com"
      name        = "John Doe"
      segment     = "new_customers"
      preferences = ["electronics", "books"]
    },
    {
      email       = "subscriber2@example.com"
      name        = "Jane Smith"
      segment     = "loyal_customers"
      preferences = ["fashion", "home"]
    },
    {
      email       = "subscriber3@example.com"
      name        = "Bob Johnson"
      segment     = "new_customers"
      preferences = ["sports", "electronics"]
    }
  ])
  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name        = "sample-subscribers"
    Description = "Sample subscriber list for email campaigns"
  })
}

# Create empty suppression list
resource "aws_s3_object" "suppression_list" {
  bucket  = aws_s3_bucket.email_marketing.id
  key     = "suppression/bounced-emails.txt"
  content = ""

  tags = merge(local.common_tags, {
    Name        = "suppression-list"
    Description = "List of bounced email addresses"
  })
}

# SNS Topic for email events
resource "aws_sns_topic" "email_events" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Description = "Email bounce and complaint notifications"
  })
}

# SNS Topic subscription for notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  topic_arn = aws_sns_topic.email_events.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SES Domain Identity
resource "aws_ses_domain_identity" "domain" {
  domain = var.sender_domain
}

# SES Domain DKIM
resource "aws_ses_domain_dkim" "domain" {
  count  = var.enable_dkim ? 1 : 0
  domain = aws_ses_domain_identity.domain.domain
}

# SES Email Identity
resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}

# SES Configuration Set
resource "aws_ses_configuration_set" "marketing_campaigns" {
  name = local.config_set_name

  delivery_options {
    tls_policy = var.require_tls ? "Require" : "Optional"
  }

  reputation_options {
    reputation_metrics_enabled = var.reputation_tracking
  }

  suppression_options {
    suppressed_reasons = var.suppression_reasons
  }

  tags = merge(local.common_tags, {
    Name        = local.config_set_name
    Description = "Configuration set for email marketing campaigns"
  })
}

# CloudWatch Event Destination
resource "aws_ses_event_destination" "cloudwatch" {
  name                   = "email-metrics"
  configuration_set_name = aws_ses_configuration_set.marketing_campaigns.name
  enabled                = true
  matching_types         = ["send", "bounce", "complaint", "delivery", "open", "click", "renderingFailure"]

  cloudwatch_destination {
    default_value  = "default"
    dimension_name = "MessageTag"
    value_source   = "messageTag"
  }
}

# SNS Event Destination
resource "aws_ses_event_destination" "sns" {
  name                   = "email-events"
  configuration_set_name = aws_ses_configuration_set.marketing_campaigns.name
  enabled                = true
  matching_types         = ["bounce", "complaint", "delivery", "send", "reject", "open", "click", "renderingFailure", "deliveryDelay"]

  sns_destination {
    topic_arn = aws_sns_topic.email_events.arn
  }
}

# SES Email Templates
resource "aws_ses_template" "welcome" {
  name    = var.welcome_template.name
  subject = var.welcome_template.subject
  html    = var.welcome_template.html
  text    = var.welcome_template.text

  depends_on = [aws_ses_domain_identity.domain, aws_ses_email_identity.sender]
}

resource "aws_ses_template" "promotion" {
  name    = var.promotion_template.name
  subject = var.promotion_template.subject
  html    = var.promotion_template.html
  text    = var.promotion_template.text

  depends_on = [aws_ses_domain_identity.domain, aws_ses_email_identity.sender]
}

# IAM Role for Lambda bounce handler
resource "aws_iam_role" "bounce_handler_role" {
  count = var.enable_bounce_handler ? 1 : 0
  name  = "bounce-handler-role-${random_string.suffix.result}"

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
    Name        = "bounce-handler-role"
    Description = "IAM role for bounce handler Lambda function"
  })
}

# IAM Policy for bounce handler
resource "aws_iam_role_policy" "bounce_handler_policy" {
  count = var.enable_bounce_handler ? 1 : 0
  name  = "bounce-handler-policy"
  role  = aws_iam_role.bounce_handler_role[0].id

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
          "ses:PutSuppressedDestination",
          "ses:DeleteSuppressedDestination",
          "ses:GetSuppressedDestination"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.email_marketing.arn}/*"
      }
    ]
  })
}

# Lambda function for bounce handling
resource "aws_lambda_function" "bounce_handler" {
  count            = var.enable_bounce_handler ? 1 : 0
  filename         = "bounce_handler.zip"
  function_name    = local.lambda_function_name
  role            = aws_iam_role.bounce_handler_role[0].arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.bounce_handler_zip[0].output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.email_marketing.bucket
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Automated bounce and complaint handling"
  })
}

# Create bounce handler Lambda code
data "archive_file" "bounce_handler_zip" {
  count       = var.enable_bounce_handler ? 1 : 0
  type        = "zip"
  output_path = "bounce_handler.zip"
  source {
    content = <<EOF
import json
import boto3
import os
from urllib.parse import unquote

def lambda_handler(event, context):
    """
    Handle bounce and complaint events from SES via SNS
    """
    ses_client = boto3.client('sesv2')
    s3_client = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        # Parse SNS message
        for record in event['Records']:
            # Handle SNS message
            if 'Sns' in record:
                message = json.loads(record['Sns']['Message'])
                
                # Process bounce events
                if message.get('eventType') == 'bounce':
                    handle_bounce(ses_client, s3_client, bucket_name, message)
                
                # Process complaint events
                elif message.get('eventType') == 'complaint':
                    handle_complaint(ses_client, s3_client, bucket_name, message)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed email events')
        }
    
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_bounce(ses_client, s3_client, bucket_name, message):
    """Handle bounce events"""
    if 'mail' in message and 'destination' in message['mail']:
        for email in message['mail']['destination']:
            # Add to SES suppression list
            try:
                ses_client.put_suppressed_destination(
                    EmailAddress=email,
                    Reason='BOUNCE'
                )
                print(f"Added {email} to suppression list for bounce")
                
                # Add to S3 suppression list
                add_to_s3_suppression_list(s3_client, bucket_name, email, 'bounce')
                
            except Exception as e:
                print(f"Error suppressing bounced email {email}: {str(e)}")

def handle_complaint(ses_client, s3_client, bucket_name, message):
    """Handle complaint events"""
    if 'mail' in message and 'destination' in message['mail']:
        for email in message['mail']['destination']:
            # Add to SES suppression list
            try:
                ses_client.put_suppressed_destination(
                    EmailAddress=email,
                    Reason='COMPLAINT'
                )
                print(f"Added {email} to suppression list for complaint")
                
                # Add to S3 suppression list
                add_to_s3_suppression_list(s3_client, bucket_name, email, 'complaint')
                
            except Exception as e:
                print(f"Error suppressing complaint email {email}: {str(e)}")

def add_to_s3_suppression_list(s3_client, bucket_name, email, reason):
    """Add email to S3 suppression list"""
    try:
        # Read current suppression list
        try:
            response = s3_client.get_object(
                Bucket=bucket_name,
                Key='suppression/bounced-emails.txt'
            )
            current_content = response['Body'].read().decode('utf-8')
        except:
            current_content = ""
        
        # Add new email if not already present
        if email not in current_content:
            new_content = f"{current_content}\n{email} ({reason})" if current_content else f"{email} ({reason})"
            
            # Update S3 object
            s3_client.put_object(
                Bucket=bucket_name,
                Key='suppression/bounced-emails.txt',
                Body=new_content.encode('utf-8'),
                ContentType='text/plain'
            )
            print(f"Added {email} to S3 suppression list")
    
    except Exception as e:
        print(f"Error updating S3 suppression list: {str(e)}")
EOF
    filename = "index.py"
  }
}

# Lambda permission for SNS
resource "aws_lambda_permission" "allow_sns" {
  count         = var.enable_bounce_handler ? 1 : 0
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bounce_handler[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.email_events.arn
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "bounce_handler_lambda" {
  count     = var.enable_bounce_handler ? 1 : 0
  topic_arn = aws_sns_topic.email_events.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.bounce_handler[0].arn
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "email_marketing" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "EmailMarketingDashboard-${random_string.suffix.result}"

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
            ["AWS/SES", "Send"],
            ["AWS/SES", "Bounce"],
            ["AWS/SES", "Complaint"],
            ["AWS/SES", "Delivery"],
            ["AWS/SES", "Open"],
            ["AWS/SES", "Click"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Email Campaign Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/SES", "Bounce"],
            ["AWS/SES", "Complaint"]
          ]
          period = 3600
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Bounce and Complaint Rates"
          view   = "singleValue"
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 6
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/SES", "Open"],
            ["AWS/SES", "Click"]
          ]
          period = 3600
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Engagement Metrics"
          view   = "singleValue"
        }
      }
    ]
  })
}

# CloudWatch Alarm for bounce rate
resource "aws_cloudwatch_metric_alarm" "high_bounce_rate" {
  alarm_name          = "EmailMarketing-HighBounceRate-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Bounce"
  namespace           = "AWS/SES"
  period              = "3600"
  statistic           = "Sum"
  threshold           = var.bounce_rate_threshold
  alarm_description   = "This metric monitors email bounce rate"
  alarm_actions       = [aws_sns_topic.email_events.arn]

  tags = merge(local.common_tags, {
    Name        = "high-bounce-rate-alarm"
    Description = "Alarm for high email bounce rate"
  })
}

# CloudWatch Alarm for complaint rate
resource "aws_cloudwatch_metric_alarm" "high_complaint_rate" {
  alarm_name          = "EmailMarketing-HighComplaintRate-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Complaint"
  namespace           = "AWS/SES"
  period              = "3600"
  statistic           = "Sum"
  threshold           = var.complaint_rate_threshold
  alarm_description   = "This metric monitors email complaint rate"
  alarm_actions       = [aws_sns_topic.email_events.arn]

  tags = merge(local.common_tags, {
    Name        = "high-complaint-rate-alarm"
    Description = "Alarm for high email complaint rate"
  })
}

# IAM Role for EventBridge campaign automation
resource "aws_iam_role" "campaign_automation_role" {
  count = var.enable_campaign_automation ? 1 : 0
  name  = "campaign-automation-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "campaign-automation-role"
    Description = "IAM role for EventBridge campaign automation"
  })
}

# IAM Policy for campaign automation
resource "aws_iam_role_policy" "campaign_automation_policy" {
  count = var.enable_campaign_automation ? 1 : 0
  name  = "campaign-automation-policy"
  role  = aws_iam_role.campaign_automation_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendBulkEmail",
          "ses:SendEmail",
          "ses:SendTemplatedEmail"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.email_marketing.arn}/*"
      }
    ]
  })
}

# EventBridge Rule for campaign automation
resource "aws_cloudwatch_event_rule" "campaign_automation" {
  count               = var.enable_campaign_automation ? 1 : 0
  name                = "WeeklyEmailCampaign-${random_string.suffix.result}"
  description         = "Trigger weekly email campaigns"
  schedule_expression = var.campaign_schedule

  tags = merge(local.common_tags, {
    Name        = "weekly-campaign-rule"
    Description = "EventBridge rule for automated email campaigns"
  })
}