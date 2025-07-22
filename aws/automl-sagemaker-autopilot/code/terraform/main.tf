# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Resource naming
  resource_prefix = "${var.project_name}-${var.environment}"
  unique_suffix   = random_string.suffix.result
  
  # S3 bucket name (must be globally unique)
  s3_bucket_name = "${local.resource_prefix}-${local.account_id}-${local.unique_suffix}"
  
  # AutoML job name
  autopilot_job_name = "${local.resource_prefix}-autopilot-${local.unique_suffix}"
  
  # IAM role name
  iam_role_name = var.iam_role_config.create_role ? "${local.resource_prefix}-role-${local.unique_suffix}" : var.iam_role_config.role_name
  
  # Model and endpoint names
  model_name = "${local.resource_prefix}-model-${local.unique_suffix}"
  endpoint_config_name = "${local.resource_prefix}-endpoint-config-${local.unique_suffix}"
  endpoint_name = "${local.resource_prefix}-endpoint-${local.unique_suffix}"
  
  # Combined tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Recipe      = "automl-solutions-amazon-sagemaker-autopilot"
    },
    var.additional_tags
  )
}

# KMS key for encryption (optional)
resource "aws_kms_key" "sagemaker_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for SageMaker AutoML resources"
  deletion_window_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "sagemaker_key_alias" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${local.resource_prefix}-sagemaker-key"
  target_key_id = aws_kms_key.sagemaker_key[0].key_id
}

# S3 bucket for data storage and model artifacts
resource "aws_s3_bucket" "sagemaker_bucket" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-bucket"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "sagemaker_bucket_versioning" {
  bucket = aws_s3_bucket.sagemaker_bucket.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "sagemaker_bucket_encryption" {
  bucket = aws_s3_bucket.sagemaker_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.sagemaker_key[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "sagemaker_bucket_pab" {
  bucket = aws_s3_bucket.sagemaker_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket notification configuration for model artifacts
resource "aws_s3_bucket_notification" "sagemaker_bucket_notification" {
  bucket = aws_s3_bucket.sagemaker_bucket.id

  # We'll add notification configurations here if needed for model monitoring
  depends_on = [aws_s3_bucket_public_access_block.sagemaker_bucket_pab]
}

# Sample dataset for demonstration
resource "aws_s3_object" "sample_dataset" {
  count = var.create_sample_dataset ? 1 : 0
  
  bucket       = aws_s3_bucket.sagemaker_bucket.id
  key          = "input/${var.sample_dataset_config.filename}"
  content_type = var.sample_dataset_config.content_type
  
  # Sample customer churn dataset
  content = <<-EOF
customer_id,age,tenure,monthly_charges,total_charges,contract_type,payment_method,churn
1,42,12,65.30,783.60,Month-to-month,Electronic check,Yes
2,35,36,89.15,3209.40,Two year,Mailed check,No
3,28,6,45.20,271.20,Month-to-month,Electronic check,Yes
4,52,24,78.90,1894.80,One year,Credit card,No
5,41,48,95.45,4583.60,Two year,Bank transfer,No
6,29,3,29.85,89.55,Month-to-month,Electronic check,Yes
7,38,60,110.75,6645.00,Two year,Credit card,No
8,33,18,73.25,1318.50,One year,Bank transfer,No
9,45,9,55.40,498.60,Month-to-month,Electronic check,Yes
10,31,72,125.30,9021.60,Two year,Credit card,No
11,26,15,52.70,790.50,Month-to-month,Electronic check,Yes
12,49,42,97.25,4084.50,Two year,Bank transfer,No
13,37,21,68.40,1436.40,One year,Credit card,No
14,44,8,43.90,351.20,Month-to-month,Electronic check,Yes
15,32,54,118.65,6407.10,Two year,Credit card,No
16,27,4,35.15,140.60,Month-to-month,Electronic check,Yes
17,56,66,132.40,8738.40,Two year,Bank transfer,No
18,39,27,82.10,2216.70,One year,Credit card,No
19,46,11,58.30,641.30,Month-to-month,Electronic check,Yes
20,34,78,145.20,11325.60,Two year,Credit card,No
EOF

  tags = merge(local.common_tags, {
    Name = "sample-dataset"
  })
}

# IAM role for SageMaker Autopilot
resource "aws_iam_role" "sagemaker_autopilot_role" {
  count = var.iam_role_config.create_role ? 1 : 0
  
  name = local.iam_role_name
  
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
  
  tags = merge(local.common_tags, {
    Name = local.iam_role_name
  })
}

# IAM policy for SageMaker Autopilot
resource "aws_iam_role_policy" "sagemaker_autopilot_policy" {
  count = var.iam_role_config.create_role ? 1 : 0
  
  name = "${local.iam_role_name}-policy"
  role = aws_iam_role.sagemaker_autopilot_role[0].id
  
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
          aws_s3_bucket.sagemaker_bucket.arn,
          "${aws_s3_bucket.sagemaker_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:CreateEndpoint",
          "sagemaker:CreateTransformJob",
          "sagemaker:CreateTrainingJob",
          "sagemaker:CreateHyperParameterTuningJob",
          "sagemaker:CreateProcessingJob",
          "sagemaker:DescribeModel",
          "sagemaker:DescribeEndpointConfig",
          "sagemaker:DescribeEndpoint",
          "sagemaker:DescribeTransformJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:DescribeHyperParameterTuningJob",
          "sagemaker:DescribeProcessingJob",
          "sagemaker:InvokeEndpoint",
          "sagemaker:ListTags",
          "sagemaker:AddTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
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
      }
    ]
  })
}

# Attach AWS managed policy for SageMaker execution
resource "aws_iam_role_policy_attachment" "sagemaker_execution_policy" {
  count = var.iam_role_config.create_role ? 1 : 0
  
  role       = aws_iam_role.sagemaker_autopilot_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# KMS policy attachment for encryption
resource "aws_iam_role_policy" "sagemaker_kms_policy" {
  count = var.iam_role_config.create_role && var.enable_kms_encryption ? 1 : 0
  
  name = "${local.iam_role_name}-kms-policy"
  role = aws_iam_role.sagemaker_autopilot_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.sagemaker_key[0].arn
      }
    ]
  })
}

# SageMaker Autopilot Job
resource "aws_sagemaker_auto_ml_job_v2" "autopilot_job" {
  auto_ml_job_name = local.autopilot_job_name
  role_arn         = var.iam_role_config.create_role ? aws_iam_role.sagemaker_autopilot_role[0].arn : var.iam_role_config.role_arn
  
  auto_ml_job_input_data_config {
    channel_type    = "training"
    content_type    = "text/csv;header=present"
    compression_type = "None"
    
    data_source {
      s3_data_source {
        s3_data_type = "S3Prefix"
        s3_uri       = "s3://${aws_s3_bucket.sagemaker_bucket.id}/input/"
      }
    }
  }
  
  output_data_config {
    s3_output_path = "s3://${aws_s3_bucket.sagemaker_bucket.id}/output/"
    kms_key_id     = var.enable_kms_encryption ? aws_kms_key.sagemaker_key[0].arn : null
  }
  
  auto_ml_problem_type_config {
    tabular_job_config {
      target_attribute_name = var.autopilot_job_config.target_attribute_name
      problem_type         = var.autopilot_job_config.problem_type
      
      completion_criteria {
        max_candidates                     = var.autopilot_job_config.max_candidates
        max_runtime_per_training_job_in_seconds = var.autopilot_job_config.max_runtime_per_training_job
        max_auto_ml_job_runtime_in_seconds = var.autopilot_job_config.max_automl_job_runtime
      }
      
      # Optional: Feature specification for advanced use cases
      # feature_specification_s3_uri = "s3://${aws_s3_bucket.sagemaker_bucket.id}/feature-spec.json"
    }
  }
  
  # Optional: VPC configuration
  dynamic "vpc_config" {
    for_each = var.vpc_config.enable_vpc ? [1] : []
    
    content {
      subnets            = var.vpc_config.subnet_ids
      security_group_ids = var.vpc_config.security_group_ids
    }
  }
  
  # Optional: Model deployment configuration
  model_deploy_config {
    auto_generate_endpoint_name = true
    endpoint_name              = var.deploy_endpoint ? local.endpoint_name : null
  }
  
  tags = merge(local.common_tags, {
    Name = local.autopilot_job_name
  })
  
  depends_on = [
    aws_s3_object.sample_dataset,
    aws_iam_role_policy.sagemaker_autopilot_policy,
    aws_iam_role_policy_attachment.sagemaker_execution_policy
  ]
}

# SageMaker Model (created after Autopilot job completes)
resource "aws_sagemaker_model" "autopilot_model" {
  count = var.deploy_endpoint ? 1 : 0
  
  name               = local.model_name
  execution_role_arn = var.iam_role_config.create_role ? aws_iam_role.sagemaker_autopilot_role[0].arn : var.iam_role_config.role_arn
  
  primary_container {
    # Note: These values would typically come from the Autopilot job results
    # In a real deployment, you'd use the best candidate from the Autopilot job
    image          = "246618743249.dkr.ecr.us-west-2.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
    model_data_url = "s3://${aws_s3_bucket.sagemaker_bucket.id}/output/model.tar.gz"
  }
  
  vpc_config {
    subnets            = var.vpc_config.enable_vpc ? var.vpc_config.subnet_ids : []
    security_group_ids = var.vpc_config.enable_vpc ? var.vpc_config.security_group_ids : []
  }
  
  tags = merge(local.common_tags, {
    Name = local.model_name
  })
  
  depends_on = [aws_sagemaker_auto_ml_job_v2.autopilot_job]
}

# SageMaker Endpoint Configuration
resource "aws_sagemaker_endpoint_configuration" "autopilot_endpoint_config" {
  count = var.deploy_endpoint ? 1 : 0
  
  name = local.endpoint_config_name
  
  production_variants {
    variant_name           = var.endpoint_config.variant_name
    model_name            = aws_sagemaker_model.autopilot_model[0].name
    initial_instance_count = var.endpoint_config.instance_count
    instance_type         = var.endpoint_config.instance_type
  }
  
  # Optional: KMS encryption for endpoint
  dynamic "kms_key_id" {
    for_each = var.enable_kms_encryption ? [1] : []
    
    content {
      kms_key_id = aws_kms_key.sagemaker_key[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.endpoint_config_name
  })
  
  depends_on = [aws_sagemaker_model.autopilot_model]
}

# SageMaker Endpoint
resource "aws_sagemaker_endpoint" "autopilot_endpoint" {
  count = var.deploy_endpoint ? 1 : 0
  
  name                 = local.endpoint_name
  endpoint_config_name = aws_sagemaker_endpoint_configuration.autopilot_endpoint_config[0].name
  
  tags = merge(local.common_tags, {
    Name = local.endpoint_name
  })
  
  depends_on = [aws_sagemaker_endpoint_configuration.autopilot_endpoint_config]
}

# CloudWatch Log Group for SageMaker training jobs
resource "aws_cloudwatch_log_group" "sagemaker_log_group" {
  name              = "/aws/sagemaker/TrainingJobs"
  retention_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "sagemaker-training-logs"
  })
}

# CloudWatch Log Group for SageMaker endpoints
resource "aws_cloudwatch_log_group" "sagemaker_endpoint_log_group" {
  count = var.deploy_endpoint ? 1 : 0
  
  name              = "/aws/sagemaker/Endpoints/${local.endpoint_name}"
  retention_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "sagemaker-endpoint-logs"
  })
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "endpoint_invocation_errors" {
  count = var.deploy_endpoint ? 1 : 0
  
  alarm_name          = "${local.endpoint_name}-invocation-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Invocation4XXErrors"
  namespace           = "AWS/SageMaker"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors SageMaker endpoint invocation errors"
  
  dimensions = {
    EndpointName = local.endpoint_name
    VariantName  = var.endpoint_config.variant_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.endpoint_name}-invocation-errors-alarm"
  })
  
  depends_on = [aws_sagemaker_endpoint.autopilot_endpoint]
}

# S3 bucket for batch transform input/output (optional)
resource "aws_s3_bucket" "batch_transform_bucket" {
  bucket        = "${local.s3_bucket_name}-batch-transform"
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-batch-transform-bucket"
  })
}

# S3 bucket public access block for batch transform bucket
resource "aws_s3_bucket_public_access_block" "batch_transform_bucket_pab" {
  bucket = aws_s3_bucket.batch_transform_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket server-side encryption for batch transform bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "batch_transform_bucket_encryption" {
  bucket = aws_s3_bucket.batch_transform_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.sagemaker_key[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}