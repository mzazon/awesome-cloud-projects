# Data Sources
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names
  resource_suffix = lower(random_id.suffix.hex)
  bucket_name     = "${var.project_name}-${local.resource_suffix}"
  dataset_name    = "customer-data-${local.resource_suffix}"
  ruleset_name    = "customer-quality-rules-${local.resource_suffix}"
  profile_job_name = "quality-assessment-job-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# ============================================================================
# S3 Resources
# ============================================================================

# S3 Bucket for data and quality reports
resource "aws_s3_bucket" "data_quality_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "S3 bucket for data quality pipeline data and reports"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "data_quality_bucket_versioning" {
  count  = var.s3_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.data_quality_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_quality_bucket_encryption" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_quality_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "data_quality_bucket_pab" {
  bucket = aws_s3_bucket.data_quality_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample data object (optional)
resource "aws_s3_object" "sample_data" {
  count   = var.sample_data_enabled ? 1 : 0
  bucket  = aws_s3_bucket.data_quality_bucket.id
  key     = "raw-data/customer-data.csv"
  content = var.sample_data_content
  
  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name        = "sample-customer-data"
    Description = "Sample customer data for testing data quality pipeline"
  })
}

# ============================================================================
# IAM Resources
# ============================================================================

# IAM Role for DataBrew
resource "aws_iam_role" "databrew_service_role" {
  name = "DataBrewServiceRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "databrew.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "DataBrewServiceRole-${local.resource_suffix}"
    Description = "IAM role for AWS Glue DataBrew service operations"
  })
}

# Attach managed policy to DataBrew role
resource "aws_iam_role_policy_attachment" "databrew_service_role_policy" {
  role       = aws_iam_role.databrew_service_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueDataBrewServiceRole"
}

# Custom policy for DataBrew S3 access
resource "aws_iam_role_policy" "databrew_s3_access" {
  name = "DataBrewS3Access-${local.resource_suffix}"
  role = aws_iam_role.databrew_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_quality_bucket.arn,
          "${aws_s3_bucket.data_quality_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "DataQualityLambdaRole-${local.resource_suffix}"
  
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
    Name        = "DataQualityLambdaRole-${local.resource_suffix}"
    Description = "IAM role for data quality Lambda function"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "DataQualityLambdaPermissions-${local.resource_suffix}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.notification_email != "" ? [aws_sns_topic.data_quality_notifications[0].arn] : []
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.data_quality_bucket.arn}/quarantine/*",
          "${aws_s3_bucket.data_quality_bucket.arn}/quality-reports/*"
        ]
      }
    ]
  })
}

# ============================================================================
# SNS Resources (Optional)
# ============================================================================

# SNS Topic for notifications
resource "aws_sns_topic" "data_quality_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "data-quality-notifications-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name        = "data-quality-notifications-${local.resource_suffix}"
    Description = "SNS topic for data quality pipeline notifications"
  })
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "data_quality_email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.data_quality_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# Lambda Resources
# ============================================================================

# Lambda function code
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda-function.py"
  content  = templatefile("${path.module}/lambda-function.py.tpl", {
    sns_topic_arn = var.notification_email != "" ? aws_sns_topic.data_quality_notifications[0].arn : ""
  })
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda-function.zip"
  
  depends_on = [local_file.lambda_code]
}

# Lambda function
resource "aws_lambda_function" "data_quality_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "DataQualityProcessor-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda-function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      SNS_TOPIC_ARN = var.notification_email != "" ? aws_sns_topic.data_quality_notifications[0].arn : ""
      S3_BUCKET     = aws_s3_bucket.data_quality_bucket.id
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "DataQualityProcessor-${local.resource_suffix}"
    Description = "Lambda function for processing data quality events"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_custom_policy
  ]
}

# Lambda function template
resource "local_file" "lambda_template" {
  filename = "${path.module}/lambda-function.py.tpl"
  content  = <<-EOF
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event, default=str)}")
    
    # Extract DataBrew validation result details
    detail = event.get('detail', {})
    validation_state = detail.get('validationState')
    dataset_name = detail.get('datasetName')
    job_name = detail.get('jobName')
    ruleset_name = detail.get('rulesetName')
    
    if validation_state == 'FAILED':
        # Initialize AWS clients
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        s3_bucket = os.environ.get('S3_BUCKET')
        
        if sns_topic_arn:
            sns = boto3.client('sns')
            
            # Send notification
            message = f"""
Data Quality Alert - Validation Failed

Dataset: {dataset_name}
Job: {job_name}
Ruleset: {ruleset_name}
Timestamp: {datetime.now().isoformat()}

Action Required: Review data quality report and investigate source data issues.
S3 Bucket: {s3_bucket}
"""
            
            # Publish to SNS
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='Data Quality Validation Failed',
                Message=message
            )
            
            print(f"Notification sent to SNS topic: {sns_topic_arn}")
        
        # Additional processing could be added here:
        # - Move data to quarantine bucket
        # - Update data quality metrics
        # - Trigger remediation workflows
        
        print(f"Data quality validation failed for dataset: {dataset_name}")
        
    elif validation_state == 'SUCCEEDED':
        print(f"Data quality validation succeeded for dataset: {dataset_name}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed validation result: {validation_state}')
    }
EOF
}

# ============================================================================
# EventBridge Resources
# ============================================================================

# EventBridge Rule for DataBrew validation events
resource "aws_cloudwatch_event_rule" "databrew_validation_rule" {
  name        = "DataBrewValidationRule-${local.resource_suffix}"
  description = "Route DataBrew validation events to Lambda function"
  state       = "ENABLED"
  
  event_pattern = jsonencode({
    source      = ["aws.databrew"]
    detail-type = ["DataBrew Ruleset Validation Result"]
    detail = {
      validationState = ["FAILED", "SUCCEEDED"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name        = "DataBrewValidationRule-${local.resource_suffix}"
    Description = "EventBridge rule for DataBrew validation events"
  })
}

# EventBridge Target - Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.databrew_validation_rule.name
  target_id = "DataQualityLambdaTarget"
  arn       = aws_lambda_function.data_quality_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_quality_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.databrew_validation_rule.arn
}

# ============================================================================
# DataBrew Resources
# ============================================================================

# DataBrew Dataset
resource "aws_databrew_dataset" "customer_data" {
  name   = local.dataset_name
  format = "CSV"
  
  format_options {
    csv {
      delimiter  = ","
      header_row = true
    }
  }
  
  input {
    s3_input_definition {
      bucket = aws_s3_bucket.data_quality_bucket.id
      key    = var.sample_data_enabled ? "raw-data/customer-data.csv" : "raw-data/"
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.dataset_name
    Description = "DataBrew dataset for customer data quality assessment"
  })
  
  depends_on = [aws_s3_object.sample_data]
}

# DataBrew Ruleset
resource "aws_databrew_ruleset" "customer_quality_rules" {
  name       = local.ruleset_name
  target_arn = aws_databrew_dataset.customer_data.arn
  
  rules {
    name             = "EmailFormatValidation"
    check_expression = ":col1 matches \"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\\\.[a-zA-Z]{2,}$\""
    
    substitution_map = {
      ":col1" = "`email`"
    }
    
    threshold {
      value = var.email_validation_threshold
      type  = "GREATER_THAN_OR_EQUAL"
      unit  = "PERCENTAGE"
    }
  }
  
  rules {
    name             = "AgeRangeValidation"
    check_expression = ":col1 between :val1 and :val2"
    
    substitution_map = {
      ":col1" = "`age`"
      ":val1" = tostring(var.age_min_value)
      ":val2" = tostring(var.age_max_value)
    }
    
    threshold {
      value = var.age_validation_threshold
      type  = "GREATER_THAN_OR_EQUAL"
      unit  = "PERCENTAGE"
    }
  }
  
  rules {
    name             = "PurchaseAmountNotNull"
    check_expression = ":col1 is not null"
    
    substitution_map = {
      ":col1" = "`purchase_amount`"
    }
    
    threshold {
      value = var.purchase_amount_threshold
      type  = "GREATER_THAN_OR_EQUAL"
      unit  = "PERCENTAGE"
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.ruleset_name
    Description = "DataBrew ruleset for customer data quality validation"
  })
}

# DataBrew Profile Job
resource "aws_databrew_profile_job" "quality_assessment" {
  name         = local.profile_job_name
  dataset_name = aws_databrew_dataset.customer_data.name
  role_arn     = aws_iam_role.databrew_service_role.arn
  max_capacity = var.databrew_job_max_capacity
  timeout      = var.databrew_job_timeout
  
  output_location {
    bucket = aws_s3_bucket.data_quality_bucket.id
    key    = "quality-reports/"
  }
  
  validation_configurations {
    ruleset_arn       = aws_databrew_ruleset.customer_quality_rules.arn
    validation_mode   = "CHECK_ALL"
  }
  
  configuration {
    dataset_statistics_configuration {
      included_statistics = [
        "COMPLETENESS",
        "VALIDITY",
        "UNIQUENESS",
        "CORRELATION"
      ]
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.profile_job_name
    Description = "DataBrew profile job for data quality assessment"
  })
  
  depends_on = [
    aws_databrew_dataset.customer_data,
    aws_databrew_ruleset.customer_quality_rules,
    aws_iam_role_policy_attachment.databrew_service_role_policy,
    aws_iam_role_policy.databrew_s3_access
  ]
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/DataQualityProcessor-${local.resource_suffix}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/DataQualityProcessor-${local.resource_suffix}"
    Description = "CloudWatch log group for data quality Lambda function"
  })
}