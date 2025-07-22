# Main Terraform configuration for CloudWatch Evidently feature flags implementation
# This infrastructure demonstrates feature flag management with gradual rollouts and A/B testing

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# CloudWatch Log Group for Evidently evaluations (optional)
resource "aws_cloudwatch_log_group" "evidently_evaluations" {
  count             = var.enable_data_delivery ? 1 : 0
  name              = "/aws/evidently/evaluations"
  retention_in_days = var.log_retention_days

  tags = merge(var.default_tags, {
    Name = "evidently-evaluations-${random_id.suffix.hex}"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}-${random_id.suffix.hex}"
  retention_in_days = var.log_retention_days

  tags = merge(var.default_tags, {
    Name = "lambda-logs-${var.lambda_function_name}-${random_id.suffix.hex}"
  })
}

# CloudWatch Evidently Project
# Projects serve as containers for feature flags and launch configurations
resource "aws_evidently_project" "main" {
  name        = "${var.project_name}-${random_id.suffix.hex}"
  description = "Feature flag demonstration project for gradual rollouts and A/B testing"

  # Configure data delivery to CloudWatch Logs for evaluation tracking
  dynamic "data_delivery" {
    for_each = var.enable_data_delivery ? [1] : []
    content {
      cloudwatch_logs {
        log_group = aws_cloudwatch_log_group.evidently_evaluations[0].name
      }
    }
  }

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-${random_id.suffix.hex}"
    Description = "Evidently project for feature flag management"
  })
}

# Feature Flag with Boolean Variations
# This feature controls the visibility of the new checkout experience
resource "aws_evidently_feature" "checkout_flow" {
  name        = var.feature_flag_name
  project     = aws_evidently_project.main.name
  description = "Controls visibility of the new checkout experience for gradual rollout testing"

  # Define feature variations - enabled and disabled states
  variations {
    name = "enabled"
    value {
      bool_value = true
    }
  }

  variations {
    name = "disabled"
    value {
      bool_value = false
    }
  }

  # Set conservative default to disabled for safety
  default_variation = "disabled"

  tags = merge(var.default_tags, {
    Name    = var.feature_flag_name
    Feature = "checkout-flow"
  })
}

# Launch Configuration for Gradual Traffic Rollout
# Manages traffic splitting between control and treatment groups
resource "aws_evidently_launch" "gradual_rollout" {
  name        = var.launch_name
  project     = aws_evidently_project.main.name
  description = "Gradual rollout of new checkout flow with ${var.treatment_traffic_percentage}% traffic allocation"

  # Control group - users with existing checkout flow (disabled feature)
  groups {
    name        = "control-group"
    description = "Users with existing checkout flow (control group)"
    feature     = aws_evidently_feature.checkout_flow.name
    variation   = "disabled"
  }

  # Treatment group - users with new checkout flow (enabled feature)
  groups {
    name        = "treatment-group"
    description = "Users with new checkout flow (treatment group)"
    feature     = aws_evidently_feature.checkout_flow.name
    variation   = "enabled"
  }

  # Configure traffic splitting with specified percentages
  scheduled_splits_config {
    steps {
      group_weights = {
        "control-group"   = 100 - var.treatment_traffic_percentage
        "treatment-group" = var.treatment_traffic_percentage
      }
      start_time = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())
    }
  }

  tags = merge(var.default_tags, {
    Name               = var.launch_name
    TreatmentPercentage = var.treatment_traffic_percentage
  })

  depends_on = [aws_evidently_feature.checkout_flow]
}

# IAM Role for Lambda Function
# Provides necessary permissions for Evidently evaluation and CloudWatch logging
resource "aws_iam_role" "lambda_role" {
  name = "evidently-lambda-role-${random_id.suffix.hex}"

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
    Name = "evidently-lambda-role-${random_id.suffix.hex}"
  })
}

# IAM Policy for CloudWatch Evidently access
resource "aws_iam_policy" "evidently_policy" {
  name        = "evidently-access-policy-${random_id.suffix.hex}"
  description = "Policy for Lambda function to access CloudWatch Evidently"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "evidently:EvaluateFeature",
          "evidently:GetFeature",
          "evidently:GetProject",
          "evidently:GetLaunch"
        ]
        Resource = [
          aws_evidently_project.main.arn,
          "${aws_evidently_project.main.arn}/*"
        ]
      }
    ]
  })

  tags = var.default_tags
}

# Attach CloudWatch Evidently policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_evidently_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.evidently_policy.arn
}

# Attach basic Lambda execution policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function Code Archive
# Creates a ZIP package containing the feature evaluation logic
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }

  depends_on = [aws_evidently_project.main, aws_evidently_feature.checkout_flow]
}

# Lambda Function for Feature Flag Evaluation
# Demonstrates how applications integrate with Evidently for feature evaluation
resource "aws_lambda_function" "evidently_demo" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables for the Lambda function
  environment {
    variables = {
      PROJECT_NAME = aws_evidently_project.main.name
      FEATURE_NAME = aws_evidently_feature.checkout_flow.name
      AWS_REGION   = data.aws_region.current.name
    }
  }

  # Ensure CloudWatch log group exists before Lambda function
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_evidently_policy
  ]

  tags = merge(var.default_tags, {
    Name     = "${var.lambda_function_name}-${random_id.suffix.hex}"
    Function = "feature-evaluation"
  })
}


# Note: To start the launch, use the AWS CLI command:
# aws evidently start-launch --project <project-name> --launch <launch-name>
# This can be automated using local-exec provisioner if needed