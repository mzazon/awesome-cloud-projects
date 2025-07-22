# Main Terraform configuration for Custom Entity Recognition and Classification with Amazon Comprehend
# This configuration creates a complete ML pipeline for custom NLP model training and inference

# Get current AWS region and account information
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed resource names and configurations
locals {
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  bucket_name     = "${local.resource_prefix}-models"
  
  common_tags = merge(var.custom_tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "custom-entity-recognition-comprehend-classification"
    ManagedBy   = "Terraform"
  })
}

# S3 bucket for storing training data, models, and processed documents
resource "aws_s3_bucket" "comprehend_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-bucket"
    Description = "Storage for Comprehend training data and model artifacts"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "comprehend_bucket_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.comprehend_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "comprehend_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.comprehend_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block configuration
resource "aws_s3_bucket_public_access_block" "comprehend_bucket_pab" {
  bucket = aws_s3_bucket.comprehend_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample training data objects for entity recognition
resource "aws_s3_object" "entity_training_data" {
  bucket = aws_s3_bucket.comprehend_bucket.id
  key    = "training-data/entities.csv"
  content = "Text,File,Line,BeginOffset,EndOffset,Type\n\"The S&P 500 index rose 2.3% yesterday.\",entities_sample.txt,0,4,11,STOCK_INDEX\n\"Apple Inc. (AAPL) reported strong quarterly earnings.\",entities_sample.txt,1,13,17,STOCK_SYMBOL\n\"The Federal Reserve raised interest rates by 0.25%.\",entities_sample.txt,2,4,17,CENTRAL_BANK\n\"Goldman Sachs upgraded Microsoft to a buy rating.\",entities_sample.txt,3,0,13,INVESTMENT_BANK\n\"Bitcoin hit a new high of $65,000 per coin.\",entities_sample.txt,4,0,7,CRYPTOCURRENCY\n\"The NASDAQ composite closed up 150 points.\",entities_sample.txt,5,4,10,STOCK_INDEX\n\"JPMorgan Chase announced a new credit facility.\",entities_sample.txt,6,0,14,FINANCIAL_INSTITUTION\n\"Tesla (TSLA) stock volatility increased significantly.\",entities_sample.txt,7,7,11,STOCK_SYMBOL"
  content_type = "text/csv"

  tags = merge(local.common_tags, {
    Name = "Entity Training Data"
    Type = "TrainingData"
  })
}

# Sample text file for entity training
resource "aws_s3_object" "entity_text_file" {
  bucket = aws_s3_bucket.comprehend_bucket.id
  key    = "training-data/entities_sample.txt"
  content = "The S&P 500 index rose 2.3% yesterday.\nApple Inc. (AAPL) reported strong quarterly earnings.\nThe Federal Reserve raised interest rates by 0.25%.\nGoldman Sachs upgraded Microsoft to a buy rating.\nBitcoin hit a new high of $65,000 per coin.\nThe NASDAQ composite closed up 150 points.\nJPMorgan Chase announced a new credit facility.\nTesla (TSLA) stock volatility increased significantly."
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "Entity Text File"
    Type = "TrainingData"
  })
}

# Sample classification training data
resource "aws_s3_object" "classification_training_data" {
  bucket = aws_s3_bucket.comprehend_bucket.id
  key    = "training-data/classification.csv"
  content = "Text,Label\n\"Quarterly earnings report shows strong revenue growth and improved margins across all business segments.\",EARNINGS_REPORT\n\"The Federal Reserve announced a 0.25% interest rate increase following their latest policy meeting.\",MONETARY_POLICY\n\"New regulatory guidelines require enhanced disclosure for cryptocurrency trading platforms.\",REGULATORY_NEWS\n\"Company announces acquisition of fintech startup for $500 million in cash and stock.\",MERGER_ACQUISITION\n\"Market volatility increased following geopolitical tensions and inflation concerns.\",MARKET_ANALYSIS\n\"Annual shareholder meeting scheduled for next month with executive compensation on agenda.\",CORPORATE_GOVERNANCE\n\"Credit rating agency downgrades bank following loan loss provisions.\",CREDIT_RATING\n\"Technology patent approval strengthens company's intellectual property portfolio.\",INTELLECTUAL_PROPERTY\n\"Environmental impact assessment reveals need for sustainable business practices.\",ESG_REPORT\n\"Insider trading investigation launched by securities regulators.\",COMPLIANCE_ISSUE"
  content_type = "text/csv"

  tags = merge(local.common_tags, {
    Name = "Classification Training Data"
    Type = "TrainingData"
  })
}

# IAM role for Comprehend, Lambda, and Step Functions
resource "aws_iam_role" "comprehend_role" {
  name = "${local.resource_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "comprehend.amazonaws.com",
            "lambda.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-role"
    Description = "IAM role for Comprehend custom model training and inference"
  })
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "s3_access_policy" {
  name = "${local.resource_prefix}-s3-policy"
  role = aws_iam_role.comprehend_role.id

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
          aws_s3_bucket.comprehend_bucket.arn,
          "${aws_s3_bucket.comprehend_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "comprehend_full_access" {
  role       = aws_iam_role.comprehend_role.name
  policy_arn = "arn:aws:iam::aws:policy/ComprehendFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.comprehend_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "step_functions_full_access" {
  role       = aws_iam_role.comprehend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

# DynamoDB table for storing inference results
resource "aws_dynamodb_table" "inference_results" {
  name           = "${local.resource_prefix}-results"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  global_secondary_index {
    name               = "timestamp-index"
    hash_key           = "timestamp"
    projection_type    = "ALL"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-results"
    Description = "Storage for Comprehend inference results"
  })
}

# CloudWatch Log Group for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset([
    "data-preprocessor",
    "model-trainer", 
    "status-checker",
    "inference-api"
  ])
  
  name              = "/aws/lambda/${local.resource_prefix}-${each.key}"
  retention_in_days = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : null

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-${each.key}-logs"
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/stepfunctions/${local.resource_prefix}-training-pipeline"
  retention_in_days = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : null

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-stepfunctions-logs"
  })
}

# Data preprocessing Lambda function
data "archive_file" "data_preprocessor_zip" {
  type        = "zip"
  output_path = "${path.module}/data_preprocessor.zip"
  
  source {
    content = file("${path.module}/lambda_templates/data_preprocessor.py.tpl")
    filename = "data_preprocessor.py"
  }
}

resource "aws_lambda_function" "data_preprocessor" {
  filename         = data.archive_file.data_preprocessor_zip.output_path
  function_name    = "${local.resource_prefix}-data-preprocessor"
  role            = aws_iam_role.comprehend_role.arn
  handler         = "data_preprocessor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.data_preprocessor_zip.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.comprehend_bucket.id
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-data-preprocessor"
    Description = "Preprocesses training data for Comprehend models"
  })
}

# Model trainer Lambda function
data "archive_file" "model_trainer_zip" {
  type        = "zip"
  output_path = "${path.module}/model_trainer.zip"
  
  source {
    content = file("${path.module}/lambda_templates/model_trainer.py.tpl")
    filename = "model_trainer.py"
  }
}

resource "aws_lambda_function" "model_trainer" {
  filename         = data.archive_file.model_trainer_zip.output_path
  function_name    = "${local.resource_prefix}-model-trainer"
  role            = aws_iam_role.comprehend_role.arn
  handler         = "model_trainer.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.model_trainer_zip.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.comprehend_bucket.id
      LANGUAGE_CODE = var.comprehend_language_code
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-model-trainer"
    Description = "Initiates Comprehend custom model training"
  })
}

# Status checker Lambda function
data "archive_file" "status_checker_zip" {
  type        = "zip"
  output_path = "${path.module}/status_checker.zip"
  
  source {
    content = file("${path.module}/lambda_functions/status_checker.py")
    filename = "status_checker.py"
  }
}

resource "aws_lambda_function" "status_checker" {
  filename         = data.archive_file.status_checker_zip.output_path
  function_name    = "${local.resource_prefix}-status-checker"
  role            = aws_iam_role.comprehend_role.arn
  handler         = "status_checker.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.status_checker_zip.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-status-checker"
    Description = "Checks Comprehend model training status"
  })
}

# Inference API Lambda function
data "archive_file" "inference_api_zip" {
  type        = "zip"
  output_path = "${path.module}/inference_api.zip"
  
  source {
    content = file("${path.module}/lambda_templates/inference_api.py.tpl")
    filename = "inference_api.py"
  }
}

resource "aws_lambda_function" "inference_api" {
  filename         = data.archive_file.inference_api_zip.output_path
  function_name    = "${local.resource_prefix}-inference-api"
  role            = aws_iam_role.comprehend_role.arn
  handler         = "inference_api.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.inference_api_zip.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  environment {
    variables = {
      RESULTS_TABLE = aws_dynamodb_table.inference_results.name
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-inference-api"
    Description = "Provides real-time inference using custom Comprehend models"
  })
}

# IAM policy for Lambda to access DynamoDB
resource "aws_iam_role_policy" "dynamodb_access_policy" {
  name = "${local.resource_prefix}-dynamodb-policy"
  role = aws_iam_role.comprehend_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.inference_results.arn,
          "${aws_dynamodb_table.inference_results.arn}/index/*"
        ]
      }
    ]
  })
}

# Step Functions state machine for training pipeline
resource "aws_sfn_state_machine" "training_pipeline" {
  name     = "${local.resource_prefix}-training-pipeline"
  role_arn = aws_iam_role.comprehend_role.arn

  definition = jsonencode({
    Comment = "Comprehend Custom Model Training Pipeline"
    StartAt = "PreprocessData"
    States = {
      PreprocessData = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.data_preprocessor.function_name
          Payload = {
            bucket = aws_s3_bucket.comprehend_bucket.id
            entity_training_data = "training-data/entities.csv"
            classification_training_data = "training-data/classification.csv"
          }
        }
        ResultPath = "$.preprocessing_result"
        Next = "TrainEntityModel"
      }
      
      TrainEntityModel = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.model_trainer.function_name
          Payload = {
            bucket = aws_s3_bucket.comprehend_bucket.id
            model_type = "entity"
            project_name = local.resource_prefix
            role_arn = aws_iam_role.comprehend_role.arn
            "entity_training_ready.$" = "$.preprocessing_result.Payload.entity_training_ready"
          }
        }
        ResultPath = "$.entity_training_result"
        Next = "TrainClassificationModel"
      }
      
      TrainClassificationModel = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.model_trainer.function_name
          Payload = {
            bucket = aws_s3_bucket.comprehend_bucket.id
            model_type = "classification"
            project_name = local.resource_prefix
            role_arn = aws_iam_role.comprehend_role.arn
            "classification_training_ready.$" = "$.preprocessing_result.Payload.classification_training_ready"
          }
        }
        ResultPath = "$.classification_training_result"
        Next = "WaitForTraining"
      }
      
      WaitForTraining = {
        Type = "Wait"
        Seconds = 300
        Next = "CheckEntityModelStatus"
      }
      
      CheckEntityModelStatus = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.status_checker.function_name
          Payload = {
            model_type = "entity"
            "training_job_arn.$" = "$.entity_training_result.Payload.training_job_arn"
          }
        }
        ResultPath = "$.entity_status_result"
        Next = "CheckClassificationModelStatus"
      }
      
      CheckClassificationModelStatus = {
        Type = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.status_checker.function_name
          Payload = {
            model_type = "classification"
            "training_job_arn.$" = "$.classification_training_result.Payload.training_job_arn"
          }
        }
        ResultPath = "$.classification_status_result"
        Next = "CheckAllModelsComplete"
      }
      
      CheckAllModelsComplete = {
        Type = "Choice"
        Choices = [
          {
            And = [
              {
                Variable = "$.entity_status_result.Payload.is_complete"
                BooleanEquals = true
              }
              {
                Variable = "$.classification_status_result.Payload.is_complete"
                BooleanEquals = true
              }
            ]
            Next = "TrainingComplete"
          }
        ]
        Default = "WaitForTraining"
      }
      
      TrainingComplete = {
        Type = "Pass"
        Result = "Training pipeline completed successfully"
        End = true
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
    include_execution_data = true
    level                  = var.step_functions_log_level
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-training-pipeline"
    Description = "Step Functions workflow for Comprehend model training"
  })
}

# API Gateway for inference endpoints
resource "aws_apigatewayv2_api" "inference_api" {
  name          = "${local.resource_prefix}-inference-api"
  protocol_type = "HTTP"
  description   = "API Gateway for Comprehend inference endpoints"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["content-type", "x-amz-date", "authorization", "x-api-key"]
    allow_methods     = ["*"]
    allow_origins     = ["*"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-inference-api"
    Description = "API Gateway for Comprehend custom model inference"
  })
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.inference_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.inference_api.invoke_arn
}

# API Gateway route
resource "aws_apigatewayv2_route" "inference_route" {
  api_id    = aws_apigatewayv2_api.inference_api.id
  route_key = "POST /inference"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "inference_stage" {
  api_id      = aws_apigatewayv2_api.inference_api.id
  name        = var.api_gateway_stage_name
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.api_gateway_throttle_rate_limit
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
  }

  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        ip             = "$context.identity.sourceIp"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        routeKey       = "$context.routeKey"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
      })
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-inference-stage"
  })
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${local.resource_prefix}-inference-api"
  retention_in_days = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : null

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-api-gateway-logs"
  })
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inference_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.inference_api.execution_arn}/*/*"
}

# SNS topic for notifications (optional)
resource "aws_sns_topic" "training_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.resource_prefix}-training-notifications"

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-training-notifications"
    Description = "SNS topic for Comprehend training notifications"
  })
}

# SNS topic subscription (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.training_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Dashboard (optional)
resource "aws_cloudwatch_dashboard" "monitoring_dashboard" {
  count          = var.enable_monitoring_dashboard ? 1 : 0
  dashboard_name = "${local.resource_prefix}-monitoring"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.data_preprocessor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Data Preprocessor Lambda Metrics"
          period  = 300
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.inference_api.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Inference API Lambda Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.inference_results.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "DynamoDB Metrics"
          period  = 300
        }
      }
    ]
  })
}

