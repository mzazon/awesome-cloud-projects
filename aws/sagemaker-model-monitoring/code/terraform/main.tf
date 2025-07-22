# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Use provided suffix or generate one
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Model Monitor analyzer image URI by region
  model_monitor_image_uris = {
    "us-east-1"      = "159807026194.dkr.ecr.us-east-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "us-east-2"      = "777275614329.dkr.ecr.us-east-2.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "us-west-1"      = "890145073186.dkr.ecr.us-west-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "us-west-2"      = "159807026194.dkr.ecr.us-west-2.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "eu-west-1"      = "468650794304.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "eu-central-1"   = "048819808253.dkr.ecr.eu-central-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "ap-southeast-1" = "245545462676.dkr.ecr.ap-southeast-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
    "ap-northeast-1" = "574779866223.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
  }
  
  # SKLearn inference image URI by region
  sklearn_image_uris = {
    "us-east-1"      = "683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "us-east-2"      = "257758044811.dkr.ecr.us-east-2.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "us-west-1"      = "746614075791.dkr.ecr.us-west-1.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "us-west-2"      = "246618743249.dkr.ecr.us-west-2.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "eu-west-1"      = "141502667606.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "eu-central-1"   = "492215442770.dkr.ecr.eu-central-1.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "ap-southeast-1" = "121021644041.dkr.ecr.ap-southeast-1.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
    "ap-northeast-1" = "354813040037.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:0.23-1-cpu-py3"
  }
  
  # Get current AWS account ID and region
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# S3 BUCKET FOR MODEL MONITORING ARTIFACTS
# ==============================================================================

# S3 bucket for storing model artifacts, captured data, and monitoring results
resource "aws_s3_bucket" "model_monitor_bucket" {
  bucket        = "${local.name_prefix}-bucket-${local.resource_suffix}"
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(var.additional_tags, {
    Name        = "${local.name_prefix}-bucket-${local.resource_suffix}"
    Purpose     = "Model monitoring artifacts and data storage"
    Component   = "Storage"
  })
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "model_monitor_bucket_versioning" {
  bucket = aws_s3_bucket.model_monitor_bucket.id
  versioning_configuration {
    status = var.s3_bucket_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "model_monitor_bucket_pab" {
  bucket = aws_s3_bucket.model_monitor_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "model_monitor_bucket_encryption" {
  bucket = aws_s3_bucket.model_monitor_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Create directory structure in S3 bucket
resource "aws_s3_object" "baseline_data_prefix" {
  bucket       = aws_s3_bucket.model_monitor_bucket.id
  key          = "baseline-data/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "captured_data_prefix" {
  bucket       = aws_s3_bucket.model_monitor_bucket.id
  key          = "captured-data/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "monitoring_results_prefix" {
  bucket       = aws_s3_bucket.model_monitor_bucket.id
  key          = "monitoring-results/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "model_artifacts_prefix" {
  bucket       = aws_s3_bucket.model_monitor_bucket.id
  key          = "model-artifacts/"
  content_type = "application/x-directory"
}

# Upload sample baseline data
resource "aws_s3_object" "baseline_data" {
  bucket = aws_s3_bucket.model_monitor_bucket.id
  key    = "baseline-data/baseline-data.csv"
  content = "feature_1,feature_2,feature_3,target\n0.1,0.2,0.3,0.15\n0.2,0.3,0.4,0.25\n0.3,0.4,0.5,0.35\n0.4,0.5,0.6,0.45\n0.5,0.6,0.7,0.55\n0.6,0.7,0.8,0.65\n0.7,0.8,0.9,0.75\n0.8,0.9,1.0,0.85\n0.9,1.0,1.1,0.95\n1.0,1.1,1.2,1.05"
  content_type = "text/csv"

  tags = {
    Purpose = "Sample baseline data for model monitoring"
  }
}

# Upload model inference script
resource "aws_s3_object" "model_inference_script" {
  bucket = aws_s3_bucket.model_monitor_bucket.id
  key    = "model-artifacts/inference.py"
  content = file("${path.module}/model_artifacts/inference.py")
  content_type = "text/x-python"

  tags = {
    Purpose = "Model inference script"
  }
}

# Create and upload model tarball
data "archive_file" "model_tarball" {
  type        = "tar"
  output_path = "${path.module}/model.tar.gz"
  source_dir  = "${path.module}/model_artifacts/"
  
  depends_on = [
    local_file.model_inference_script
  ]
}

resource "aws_s3_object" "model_tarball" {
  bucket = aws_s3_bucket.model_monitor_bucket.id
  key    = "model-artifacts/model.tar.gz"
  source = data.archive_file.model_tarball.output_path
  content_type = "application/gzip"

  tags = {
    Purpose = "Model artifacts package"
  }
}

# Create local model inference script file for packaging
resource "local_file" "model_inference_script" {
  filename = "${path.module}/model_artifacts/inference.py"
  content = <<EOF
import joblib
import json
import numpy as np

def model_fn(model_dir):
    """Load a simple model for demonstration purposes"""
    return {"type": "demo_model"}

def input_fn(request_body, request_content_type):
    """Transform request input to numpy array"""
    if request_content_type == 'application/json':
        data = json.loads(request_body)
        return np.array(data['instances'])
    else:
        raise ValueError(f"Unsupported content type: {request_content_type}")

def predict_fn(input_data, model):
    """Simple prediction logic for demonstration"""
    predictions = np.random.random(len(input_data))
    return predictions

def output_fn(prediction, content_type):
    """Transform prediction output to JSON"""
    if content_type == 'application/json':
        return json.dumps({"predictions": prediction.tolist()})
    else:
        raise ValueError(f"Unsupported content type: {content_type}")
EOF
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM role for SageMaker Model Monitor
resource "aws_iam_role" "sagemaker_model_monitor_role" {
  name = "${local.name_prefix}-model-monitor-role-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-model-monitor-role-${local.resource_suffix}"
    Purpose   = "SageMaker Model Monitor execution role"
    Component = "IAM"
  })
}

# Attach AWS managed policy for SageMaker execution
resource "aws_iam_role_policy_attachment" "sagemaker_execution_role" {
  role       = aws_iam_role.sagemaker_model_monitor_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Custom policy for Model Monitor S3 access
resource "aws_iam_role_policy" "model_monitor_s3_policy" {
  name = "${local.name_prefix}-model-monitor-s3-policy"
  role = aws_iam_role.sagemaker_model_monitor_role.id

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
          aws_s3_bucket.model_monitor_bucket.arn,
          "${aws_s3_bucket.model_monitor_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.resource_suffix}"

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

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-lambda-role-${local.resource_suffix}"
    Purpose   = "Lambda execution role for model monitor alerts"
    Component = "IAM"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda function
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.model_monitor_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:DescribeMonitoringSchedule",
          "sagemaker:DescribeProcessingJob",
          "sagemaker:ListMonitoringExecutions"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# SAGEMAKER MODEL AND ENDPOINT
# ==============================================================================

# SageMaker model
resource "aws_sagemaker_model" "demo_model" {
  name               = "${local.name_prefix}-demo-model-${local.resource_suffix}"
  execution_role_arn = aws_iam_role.sagemaker_model_monitor_role.arn

  primary_container {
    image          = lookup(local.sklearn_image_uris, local.region, local.sklearn_image_uris["us-east-1"])
    model_data_url = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/${aws_s3_object.model_tarball.key}"
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-demo-model-${local.resource_suffix}"
    Purpose   = "Demo model for monitoring"
    Component = "SageMaker"
  })

  depends_on = [aws_s3_object.model_tarball]
}

# SageMaker endpoint configuration with data capture
resource "aws_sagemaker_endpoint_configuration" "demo_endpoint_config" {
  name = "${local.name_prefix}-endpoint-config-${local.resource_suffix}"

  production_variants {
    variant_name           = "Primary"
    model_name            = aws_sagemaker_model.demo_model.name
    initial_instance_count = var.model_initial_instance_count
    instance_type         = var.model_instance_type
    initial_variant_weight = 1.0
  }

  data_capture_config {
    enable_capture                = true
    initial_sampling_percentage   = var.data_capture_sampling_percentage
    destination_s3_uri           = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/captured-data"
    
    capture_options {
      capture_mode = "Input"
    }
    
    capture_options {
      capture_mode = "Output"
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-endpoint-config-${local.resource_suffix}"
    Purpose   = "Endpoint configuration with data capture"
    Component = "SageMaker"
  })
}

# SageMaker endpoint
resource "aws_sagemaker_endpoint" "demo_endpoint" {
  name                 = "${local.name_prefix}-endpoint-${local.resource_suffix}"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.demo_endpoint_config.name

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-endpoint-${local.resource_suffix}"
    Purpose   = "Demo endpoint for model monitoring"
    Component = "SageMaker"
  })
}

# ==============================================================================
# SNS TOPIC FOR ALERTS
# ==============================================================================

# SNS topic for model monitor alerts
resource "aws_sns_topic" "model_monitor_alerts" {
  name = "${local.name_prefix}-alerts-${local.resource_suffix}"

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-alerts-${local.resource_suffix}"
    Purpose   = "Model monitor alert notifications"
    Component = "SNS"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "model_monitor_alerts_policy" {
  arn = aws_sns_topic.model_monitor_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.model_monitor_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Email subscription (conditional)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_email_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.model_monitor_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# LAMBDA FUNCTION FOR AUTOMATED RESPONSE
# ==============================================================================

# Create Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to handle Model Monitor alerts and trigger automated responses
    """
    sns = boto3.client('sns')
    sagemaker = boto3.client('sagemaker')
    
    try:
        # Parse the CloudWatch alarm from SNS
        if 'Records' in event and len(event['Records']) > 0:
            message = json.loads(event['Records'][0]['Sns']['Message'])
        else:
            # Direct invocation for testing
            message = event
        
        alarm_name = message.get('AlarmName', 'Unknown')
        alarm_description = message.get('AlarmDescription', 'No description')
        new_state = message.get('NewStateValue', 'UNKNOWN')
        
        logger.info(f"Received alarm: {alarm_name} - {new_state}")
        
        # Check if this is a model drift alarm
        if new_state == 'ALARM' and 'ModelMonitor' in alarm_name:
            logger.warning(f"Model drift detected: {alarm_description}")
            
            # Send detailed notification
            notification_message = f"""
Model Monitor Alert - Action Required

Alarm: {alarm_name}
Status: {new_state}
Description: {alarm_description}
Time: {message.get('StateChangeTime', 'Unknown')}
Region: {message.get('Region', 'Unknown')}

Recommended Actions:
1. Review monitoring results in S3
2. Analyze captured data for drift patterns
3. Consider retraining the model
4. Update baseline statistics if appropriate

AWS Console Links:
- SageMaker Console: https://console.aws.amazon.com/sagemaker/
- CloudWatch Console: https://console.aws.amazon.com/cloudwatch/
"""
            
            # Publish to SNS topic
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'Model Monitor Alert: {alarm_name}',
                Message=notification_message
            )
            
            logger.info("Alert notification sent successfully")
            
            # Additional automated actions could be added here:
            # - Trigger model retraining pipeline
            # - Update model endpoint configuration
            # - Send alerts to external monitoring systems
            # - Create incident tickets
            
        elif new_state == 'OK':
            logger.info(f"Alarm {alarm_name} returned to OK state")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Alert processed successfully',
                'alarm': alarm_name,
                'state': new_state
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process alert'
            })
        }
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "model_monitor_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-handler-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.model_monitor_alerts.arn
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-handler-${local.resource_suffix}"
    Purpose   = "Automated response to model monitor alerts"
    Component = "Lambda"
  })
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.model_monitor_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.model_monitor_handler.arn
}

# Permission for SNS to invoke Lambda
resource "aws_lambda_permission" "sns_invoke_lambda" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.model_monitor_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.model_monitor_alerts.arn
}

# ==============================================================================
# BASELINE STATISTICS PROCESSING JOB
# ==============================================================================

# Processing job to create baseline statistics
resource "aws_sagemaker_processing_job" "baseline_job" {
  processing_job_name = "${local.name_prefix}-baseline-${local.resource_suffix}"
  role_arn           = aws_iam_role.sagemaker_model_monitor_role.arn

  app_specification {
    image_uri = lookup(local.model_monitor_image_uris, local.region, local.model_monitor_image_uris["us-east-1"])
  }

  processing_inputs {
    input_name = "baseline_dataset"
    s3_input {
      s3_uri                    = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/baseline-data"
      local_path               = "/opt/ml/processing/input"
      s3_data_type            = "S3Prefix"
      s3_input_mode           = "File"
      s3_data_distribution_type = "FullyReplicated"
    }
  }

  processing_output_config {
    outputs {
      output_name = "statistics"
      s3_output {
        s3_uri        = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/statistics"
        local_path    = "/opt/ml/processing/output/statistics"
        s3_upload_mode = "EndOfJob"
      }
    }
    
    outputs {
      output_name = "constraints"
      s3_output {
        s3_uri        = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/constraints"
        local_path    = "/opt/ml/processing/output/constraints"
        s3_upload_mode = "EndOfJob"
      }
    }
  }

  processing_resources {
    cluster_config {
      instance_type   = var.monitoring_instance_type
      instance_count  = var.monitoring_instance_count
      volume_size_in_gb = var.monitoring_volume_size_gb
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-baseline-${local.resource_suffix}"
    Purpose   = "Generate baseline statistics for model monitoring"
    Component = "SageMaker"
  })

  depends_on = [
    aws_s3_object.baseline_data,
    aws_iam_role_policy.model_monitor_s3_policy
  ]
}

# ==============================================================================
# MONITORING SCHEDULES
# ==============================================================================

# Data Quality Monitoring Schedule
resource "aws_sagemaker_data_quality_job_definition" "data_quality_job_def" {
  name     = "${local.name_prefix}-data-quality-job-def-${local.resource_suffix}"
  role_arn = aws_iam_role.sagemaker_model_monitor_role.arn

  data_quality_app_specification {
    image_uri = lookup(local.model_monitor_image_uris, local.region, local.model_monitor_image_uris["us-east-1"])
  }

  data_quality_job_input {
    endpoint_input {
      endpoint_name            = aws_sagemaker_endpoint.demo_endpoint.name
      local_path              = "/opt/ml/processing/input/endpoint"
      s3_input_mode           = "File"
      s3_data_distribution_type = "FullyReplicated"
    }
  }

  data_quality_job_output_config {
    monitoring_outputs {
      s3_output {
        s3_uri        = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/data-quality"
        local_path    = "/opt/ml/processing/output"
        s3_upload_mode = "EndOfJob"
      }
    }
  }

  job_resources {
    cluster_config {
      instance_type     = var.monitoring_instance_type
      instance_count    = var.monitoring_instance_count
      volume_size_in_gb = var.monitoring_volume_size_gb
    }
  }

  data_quality_baseline_config {
    statistics_resource {
      s3_uri = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/statistics"
    }
    constraints_resource {
      s3_uri = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/constraints"
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-data-quality-job-def-${local.resource_suffix}"
    Purpose   = "Data quality monitoring job definition"
    Component = "SageMaker"
  })

  depends_on = [aws_sagemaker_processing_job.baseline_job]
}

# Data Quality Monitoring Schedule
resource "aws_sagemaker_monitoring_schedule" "data_quality_schedule" {
  monitoring_schedule_name = "${local.name_prefix}-data-quality-schedule-${local.resource_suffix}"

  monitoring_schedule_config {
    schedule_config {
      schedule_expression = var.data_quality_schedule_expression
    }

    monitoring_job_definition_name = aws_sagemaker_data_quality_job_definition.data_quality_job_def.name
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-data-quality-schedule-${local.resource_suffix}"
    Purpose   = "Data quality monitoring schedule"
    Component = "SageMaker"
  })
}

# Model Quality Monitoring Schedule (conditional)
resource "aws_sagemaker_model_quality_job_definition" "model_quality_job_def" {
  count    = var.enable_model_quality_monitoring ? 1 : 0
  name     = "${local.name_prefix}-model-quality-job-def-${local.resource_suffix}"
  role_arn = aws_iam_role.sagemaker_model_monitor_role.arn

  model_quality_app_specification {
    image_uri = lookup(local.model_monitor_image_uris, local.region, local.model_monitor_image_uris["us-east-1"])
  }

  model_quality_job_input {
    endpoint_input {
      endpoint_name            = aws_sagemaker_endpoint.demo_endpoint.name
      local_path              = "/opt/ml/processing/input/endpoint"
      s3_input_mode           = "File"
      s3_data_distribution_type = "FullyReplicated"
    }
  }

  model_quality_job_output_config {
    monitoring_outputs {
      s3_output {
        s3_uri        = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/model-quality"
        local_path    = "/opt/ml/processing/output"
        s3_upload_mode = "EndOfJob"
      }
    }
  }

  job_resources {
    cluster_config {
      instance_type     = var.monitoring_instance_type
      instance_count    = var.monitoring_instance_count
      volume_size_in_gb = var.monitoring_volume_size_gb
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-model-quality-job-def-${local.resource_suffix}"
    Purpose   = "Model quality monitoring job definition"
    Component = "SageMaker"
  })
}

resource "aws_sagemaker_monitoring_schedule" "model_quality_schedule" {
  count                    = var.enable_model_quality_monitoring ? 1 : 0
  monitoring_schedule_name = "${local.name_prefix}-model-quality-schedule-${local.resource_suffix}"

  monitoring_schedule_config {
    schedule_config {
      schedule_expression = var.model_quality_schedule_expression
    }

    monitoring_job_definition_name = aws_sagemaker_model_quality_job_definition.model_quality_job_def[0].name
  }

  tags = merge(var.additional_tags, {
    Name      = "${local.name_prefix}-model-quality-schedule-${local.resource_suffix}"
    Purpose   = "Model quality monitoring schedule"
    Component = "SageMaker"
  })
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

# CloudWatch alarm for constraint violations
resource "aws_cloudwatch_metric_alarm" "constraint_violations" {
  alarm_name          = "ModelMonitor-ConstraintViolations-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "constraint_violations"
  namespace           = "AWS/SageMaker/ModelMonitor"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.constraint_violation_threshold
  alarm_description   = "Alert when model monitor detects constraint violations"
  alarm_actions       = [aws_sns_topic.model_monitor_alerts.arn]

  dimensions = {
    MonitoringSchedule = aws_sagemaker_monitoring_schedule.data_quality_schedule.monitoring_schedule_name
  }

  tags = merge(var.additional_tags, {
    Name      = "ModelMonitor-ConstraintViolations-${local.resource_suffix}"
    Purpose   = "Monitor constraint violations in model data"
    Component = "CloudWatch"
  })
}

# CloudWatch alarm for monitoring job failures
resource "aws_cloudwatch_metric_alarm" "monitoring_job_failures" {
  alarm_name          = "ModelMonitor-JobFailures-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "monitoring_job_failures"
  namespace           = "AWS/SageMaker/ModelMonitor"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when model monitor jobs fail"
  alarm_actions       = [aws_sns_topic.model_monitor_alerts.arn]

  dimensions = {
    MonitoringSchedule = aws_sagemaker_monitoring_schedule.data_quality_schedule.monitoring_schedule_name
  }

  tags = merge(var.additional_tags, {
    Name      = "ModelMonitor-JobFailures-${local.resource_suffix}"
    Purpose   = "Monitor model monitor job failures"
    Component = "CloudWatch"
  })
}

# ==============================================================================
# CLOUDWATCH DASHBOARD (OPTIONAL)
# ==============================================================================

# CloudWatch Dashboard for Model Monitoring
resource "aws_cloudwatch_dashboard" "model_monitor_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "ModelMonitor-Dashboard-${local.resource_suffix}"

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
            ["AWS/SageMaker/ModelMonitor", "constraint_violations", "MonitoringSchedule", aws_sagemaker_monitoring_schedule.data_quality_schedule.monitoring_schedule_name],
            [".", "monitoring_job_failures", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Model Monitor Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query  = "SOURCE '/aws/sagemaker/ProcessingJobs' | fields @timestamp, @message | filter @message like /constraint/ | sort @timestamp desc | limit 100"
          region = local.region
          title  = "Model Monitor Logs - Constraint Violations"
          view   = "table"
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
            ["AWS/SageMaker/Endpoints", "Invocations", "EndpointName", aws_sagemaker_endpoint.demo_endpoint.name],
            [".", "ModelLatency", ".", "."],
            [".", "OverheadLatency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Endpoint Performance Metrics"
          view   = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}