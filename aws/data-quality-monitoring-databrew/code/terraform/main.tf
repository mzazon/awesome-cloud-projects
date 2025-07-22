# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create S3 bucket for DataBrew results
resource "aws_s3_bucket" "databrew_results" {
  bucket = "${var.s3_bucket_prefix}-${var.environment}-${random_string.suffix.result}"

  tags = merge(var.default_tags, {
    Name        = "DataBrew Results Bucket"
    Environment = var.environment
    Purpose     = "Store DataBrew profile and validation results"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "databrew_results" {
  bucket = aws_s3_bucket.databrew_results.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "databrew_results" {
  bucket = aws_s3_bucket.databrew_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "databrew_results" {
  bucket = aws_s3_bucket.databrew_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create sample customer data file (if enabled)
resource "aws_s3_object" "sample_data" {
  count = var.create_sample_data ? 1 : 0
  
  bucket = aws_s3_bucket.databrew_results.id
  key    = "raw-data/customer_data.csv"
  
  content = <<EOF
customer_id,name,email,age,registration_date,account_balance
1,John Smith,john.smith@example.com,25,2023-01-15,1500.00
2,Jane Doe,jane.doe@example.com,32,2023-02-20,2300.50
3,Bob Johnson,,28,2023-03-10,750.25
4,Alice Brown,alice.brown@example.com,45,2023-04-05,3200.75
5,Charlie Wilson,charlie.wilson@example.com,-5,2023-05-12,1800.00
6,Diana Lee,diana.lee@example.com,67,invalid-date,2500.00
7,Frank Miller,frank.miller@example.com,33,2023-07-18,
8,Grace Taylor,grace.taylor@example.com,29,2023-08-25,1200.50
9,Henry Davis,henry.davis@example.com,41,2023-09-30,1750.25
10,Ivy Chen,ivy.chen@example.com,38,2023-10-15,2100.00
EOF

  content_type = "text/csv"
  
  tags = merge(var.default_tags, {
    Name        = "Sample Customer Data"
    Environment = var.environment
    Purpose     = "Sample data for DataBrew testing"
  })
}

# Create IAM role for DataBrew service
resource "aws_iam_role" "databrew_service_role" {
  name = "DataBrewServiceRole-${var.environment}-${random_string.suffix.result}"

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

  tags = merge(var.default_tags, {
    Name        = "DataBrew Service Role"
    Environment = var.environment
    Purpose     = "Allow DataBrew to access S3 and other AWS services"
  })
}

# Attach AWS managed policy for DataBrew
resource "aws_iam_role_policy_attachment" "databrew_service_role_policy" {
  role       = aws_iam_role.databrew_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueDataBrewServiceRole"
}

# Create custom policy for S3 access
resource "aws_iam_policy" "databrew_s3_policy" {
  name        = "DataBrewS3Policy-${var.environment}-${random_string.suffix.result}"
  description = "Policy for DataBrew to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.databrew_results.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.databrew_results.arn
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = "DataBrew S3 Policy"
    Environment = var.environment
    Purpose     = "Grant DataBrew access to S3 bucket"
  })
}

# Attach custom S3 policy to DataBrew role
resource "aws_iam_role_policy_attachment" "databrew_s3_policy_attachment" {
  role       = aws_iam_role.databrew_service_role.name
  policy_arn = aws_iam_policy.databrew_s3_policy.arn
}

# Create DataBrew dataset
resource "aws_databrew_dataset" "customer_dataset" {
  name   = "${var.dataset_name}-${var.environment}-${random_string.suffix.result}"
  format = var.data_format

  # Configure format options based on data format
  format_options {
    dynamic "csv" {
      for_each = var.data_format == "CSV" ? [1] : []
      content {
        delimiter = var.csv_delimiter
      }
    }
    
    dynamic "json" {
      for_each = var.data_format == "JSON" ? [1] : []
      content {
        multi_line = false
      }
    }
  }

  # Configure input location
  input {
    s3_input_definition {
      bucket = aws_s3_bucket.databrew_results.bucket
      key    = var.create_sample_data ? "raw-data/" : "raw-data/"
    }
  }

  tags = merge(var.default_tags, {
    Name        = "Customer Dataset"
    Environment = var.environment
    Purpose     = "DataBrew dataset for customer data quality monitoring"
  })

  depends_on = [aws_s3_object.sample_data]
}

# Create DataBrew ruleset for data quality validation
resource "aws_databrew_ruleset" "data_quality_ruleset" {
  name       = "${var.ruleset_name}-${var.environment}-${random_string.suffix.result}"
  target_arn = aws_databrew_dataset.customer_dataset.arn

  # Create rules from variable configuration
  dynamic "rules" {
    for_each = var.data_quality_rules
    content {
      name             = rules.value.name
      check_expression = rules.value.check_expression
      disabled         = rules.value.disabled
      
      # Optional substitution map for parameterized rules
      substitution_map = {}
      
      # Optional column selectors for column-specific rules
      column_selectors {
        # This can be customized based on specific column requirements
        regex = ".*"
      }
    }
  }

  tags = merge(var.default_tags, {
    Name        = "Data Quality Ruleset"
    Environment = var.environment
    Purpose     = "Define data quality validation rules for customer data"
  })
}

# Create SNS topic for data quality alerts
resource "aws_sns_topic" "data_quality_alerts" {
  name = "data-quality-alerts-${var.environment}-${random_string.suffix.result}"

  tags = merge(var.default_tags, {
    Name        = "Data Quality Alerts"
    Environment = var.environment
    Purpose     = "SNS topic for data quality validation alerts"
  })
}

# Create SNS topic policy
resource "aws_sns_topic_policy" "data_quality_alerts_policy" {
  arn = aws_sns_topic.data_quality_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.data_quality_alerts.arn
      }
    ]
  })
}

# Subscribe email to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.data_quality_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Create EventBridge rule for DataBrew validation events
resource "aws_cloudwatch_event_rule" "databrew_validation_rule" {
  count = var.eventbridge_rule_config.enabled ? 1 : 0
  
  name        = "DataBrewQualityValidation-${var.environment}-${random_string.suffix.result}"
  description = var.eventbridge_rule_config.description

  event_pattern = jsonencode({
    source      = ["aws.databrew"]
    detail-type = ["DataBrew Ruleset Validation Result"]
    detail = {
      validationState = var.eventbridge_rule_config.failure_notifications ? (
        var.eventbridge_rule_config.success_notifications ? ["FAILED", "SUCCEEDED"] : ["FAILED"]
      ) : (
        var.eventbridge_rule_config.success_notifications ? ["SUCCEEDED"] : []
      )
    }
  })

  tags = merge(var.default_tags, {
    Name        = "DataBrew Validation Rule"
    Environment = var.environment
    Purpose     = "Monitor DataBrew data quality validation results"
  })
}

# Create EventBridge target for SNS
resource "aws_cloudwatch_event_target" "sns_target" {
  count = var.eventbridge_rule_config.enabled ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.databrew_validation_rule[0].name
  target_id = "SNSTarget"
  arn       = aws_sns_topic.data_quality_alerts.arn

  # Transform the event message for better readability
  input_transformer {
    input_paths = {
      dataset    = "$.detail.datasetName"
      ruleset    = "$.detail.rulesetName"
      state      = "$.detail.validationState"
      timestamp  = "$.time"
      region     = "$.detail.region"
      account    = "$.account"
    }
    input_template = jsonencode({
      notification_type = "DataBrew Data Quality Alert"
      severity         = "HIGH"
      timestamp        = "<timestamp>"
      account_id       = "<account>"
      region           = "<region>"
      dataset_name     = "<dataset>"
      ruleset_name     = "<ruleset>"
      validation_state = "<state>"
      message          = "Data quality validation <state> for dataset: <dataset>, ruleset: <ruleset>"
      action_required  = "Review data quality report and take corrective action if needed"
    })
  }
}

# Create DataBrew profile job
resource "aws_databrew_job" "profile_job" {
  name         = "${var.profile_job_name}-${var.environment}-${random_string.suffix.result}"
  dataset_name = aws_databrew_dataset.customer_dataset.name
  role_arn     = aws_iam_role.databrew_service_role.arn
  type         = "PROFILE"

  # Configure job capacity and timeout
  max_capacity = var.profile_job_configuration.max_capacity
  max_retries  = var.profile_job_configuration.max_retries
  timeout      = var.profile_job_configuration.timeout

  # Configure output location
  output_location {
    bucket = aws_s3_bucket.databrew_results.bucket
    key    = "profile-results/"
  }

  # Configure profiling settings
  profile_configuration {
    dataset_statistics_configuration {
      included_statistics = var.profile_job_configuration.include_all_stats ? ["ALL"] : [
        "MEAN", "MEDIAN", "MODE", "STANDARD_DEVIATION", "MIN", "MAX", "COUNT", "DISTINCT_COUNT"
      ]
    }

    # Configure column-level profiling
    profile_columns {
      name = "*"
      
      statistics_configuration {
        included_statistics = var.profile_job_configuration.include_all_stats ? ["ALL"] : [
          "MEAN", "MEDIAN", "MODE", "STANDARD_DEVIATION", "MIN", "MAX", "COUNT", "DISTINCT_COUNT"
        ]
      }
    }

    # Configure job sampling
    dynamic "job_sample" {
      for_each = var.profile_job_configuration.job_sample_size > 0 ? [1] : []
      content {
        mode = "CUSTOM_ROWS"
        size = var.profile_job_configuration.job_sample_size
      }
    }
  }

  # Configure data quality validation
  validation_configurations {
    ruleset_arn      = aws_databrew_ruleset.data_quality_ruleset.arn
    validation_mode  = "CHECK_ALL"
  }

  tags = merge(var.default_tags, {
    Name        = "Customer Data Profile Job"
    Environment = var.environment
    Purpose     = "Profile customer data and validate quality rules"
  })
}

# Create CloudWatch log group for DataBrew job logs
resource "aws_cloudwatch_log_group" "databrew_job_logs" {
  name              = "/aws/databrew/jobs/${aws_databrew_job.profile_job.name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(var.default_tags, {
    Name        = "DataBrew Job Logs"
    Environment = var.environment
    Purpose     = "Store DataBrew job execution logs"
  })
}

# Create IAM role for Lambda function (if needed for advanced processing)
resource "aws_iam_role" "lambda_execution_role" {
  name = "DataBrewLambdaRole-${var.environment}-${random_string.suffix.result}"

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

  tags = merge(var.default_tags, {
    Name        = "DataBrew Lambda Execution Role"
    Environment = var.environment
    Purpose     = "Allow Lambda to process DataBrew events"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create Lambda function for advanced event processing
resource "aws_lambda_function" "databrew_event_processor" {
  filename         = "databrew_event_processor.zip"
  function_name    = "databrew-event-processor-${var.environment}-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  # Create the Lambda deployment package
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.data_quality_alerts.arn
      ENVIRONMENT   = var.environment
      S3_BUCKET     = aws_s3_bucket.databrew_results.bucket
    }
  }

  tags = merge(var.default_tags, {
    Name        = "DataBrew Event Processor"
    Environment = var.environment
    Purpose     = "Process DataBrew validation events and send notifications"
  })
}

# Create the Lambda function code
resource "local_file" "lambda_function_code" {
  content = <<EOF
import json
import boto3
import os
from datetime import datetime

def handler(event, context):
    """
    Process DataBrew validation events and send detailed notifications
    """
    sns = boto3.client('sns')
    
    # Extract event details
    detail = event.get('detail', {})
    dataset_name = detail.get('datasetName', 'Unknown')
    ruleset_name = detail.get('rulesetName', 'Unknown')
    validation_state = detail.get('validationState', 'Unknown')
    timestamp = event.get('time', datetime.now().isoformat())
    
    # Create detailed message
    message = {
        'timestamp': timestamp,
        'dataset_name': dataset_name,
        'ruleset_name': ruleset_name,
        'validation_state': validation_state,
        'environment': os.environ.get('ENVIRONMENT', 'unknown'),
        'account': event.get('account', 'unknown'),
        'region': event.get('region', 'unknown')
    }
    
    # Send SNS notification
    try:
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(message, indent=2),
            Subject=f"DataBrew Data Quality Alert - {validation_state}"
        )
        
        print(f"SNS notification sent: {response['MessageId']}")
        
    except Exception as e:
        print(f"Error sending SNS notification: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Event processed successfully')
    }
EOF
  filename = "${path.module}/lambda_function.py"
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_function_code.filename
  output_path = "${path.module}/databrew_event_processor.zip"
  depends_on  = [local_file.lambda_function_code]
}

# Grant permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "eventbridge_invoke_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.databrew_event_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.eventbridge_rule_config.enabled ? aws_cloudwatch_event_rule.databrew_validation_rule[0].arn : null
}

# Create EventBridge target for Lambda (optional advanced processing)
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.eventbridge_rule_config.enabled ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.databrew_validation_rule[0].name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.databrew_event_processor.arn
}