# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for consistent naming
locals {
  # Generate unique resource names
  project_prefix = "${var.project_name}-${var.environment}"
  unique_suffix  = random_string.suffix.result
  
  # Resource names
  s3_bucket_name             = "${var.s3_bucket_name}-${local.unique_suffix}"
  sagemaker_role_name        = "SageMakerMLPipelineRole-${local.unique_suffix}"
  stepfunctions_role_name    = "StepFunctionsMLRole-${local.unique_suffix}"
  lambda_role_name           = "LambdaEvaluateModelRole-${local.unique_suffix}"
  pipeline_name              = "${local.project_prefix}-${local.unique_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==========================================
# S3 BUCKET FOR ML ARTIFACTS
# ==========================================

# S3 bucket for storing ML pipeline artifacts
resource "aws_s3_bucket" "ml_artifacts" {
  bucket = local.s3_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "ml_artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "ml_artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "ml_artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "ml_artifacts" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.ml_artifacts.id

  rule {
    id     = "ml_artifacts_lifecycle"
    status = "Enabled"

    # Transition to Standard-IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# Create S3 folder structure using objects
resource "aws_s3_object" "raw_data_folder" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "raw-data/"
  source = "/dev/null"
  tags   = local.common_tags
}

resource "aws_s3_object" "processed_data_folder" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "processed-data/"
  source = "/dev/null"
  tags   = local.common_tags
}

resource "aws_s3_object" "model_artifacts_folder" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "model-artifacts/"
  source = "/dev/null"
  tags   = local.common_tags
}

resource "aws_s3_object" "code_folder" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "code/"
  source = "/dev/null"
  tags   = local.common_tags
}

# ==========================================
# IAM ROLES AND POLICIES
# ==========================================

# SageMaker execution role
resource "aws_iam_role" "sagemaker_role" {
  name = local.sagemaker_role_name
  tags = local.common_tags

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
}

# Attach managed policies to SageMaker role
resource "aws_iam_role_policy_attachment" "sagemaker_execution_policy" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Custom S3 policy for SageMaker role
resource "aws_iam_role_policy" "sagemaker_s3_policy" {
  name = "SageMakerS3Access"
  role = aws_iam_role.sagemaker_role.id

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
          aws_s3_bucket.ml_artifacts.arn,
          "${aws_s3_bucket.ml_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Step Functions execution role
resource "aws_iam_role" "stepfunctions_role" {
  name = local.stepfunctions_role_name
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

# Custom policy for Step Functions SageMaker integration
resource "aws_iam_role_policy" "stepfunctions_sagemaker_policy" {
  name = "StepFunctionsSageMakerPolicy"
  role = aws_iam_role.stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:CreateProcessingJob",
          "sagemaker:CreateTrainingJob",
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:CreateEndpoint",
          "sagemaker:UpdateEndpoint",
          "sagemaker:DeleteEndpoint",
          "sagemaker:DescribeProcessingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:DescribeModel",
          "sagemaker:DescribeEndpoint",
          "sagemaker:ListTags",
          "sagemaker:AddTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ml_artifacts.arn,
          "${aws_s3_bucket.ml_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.sagemaker_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.evaluate_model.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_sns_notifications ? aws_sns_topic.pipeline_notifications[0].arn : "*"
      }
    ]
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = local.lambda_role_name
  tags = local.common_tags

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
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom S3 policy for Lambda role
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "LambdaS3Access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ml_artifacts.arn,
          "${aws_s3_bucket.ml_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# ==========================================
# LAMBDA FUNCTION FOR MODEL EVALUATION
# ==========================================

# Lambda function code
data "archive_file" "evaluate_model_zip" {
  type        = "zip"
  output_path = "${path.module}/evaluate_model.zip"

  source {
    content = <<EOF
import json
import boto3
import os

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    # Get training job name and S3 bucket from event
    training_job_name = event['TrainingJobName']
    s3_bucket = event['S3Bucket']
    
    try:
        # Download evaluation metrics from S3
        evaluation_key = f"model-artifacts/{training_job_name}/output/evaluation.json"
        response = s3.get_object(Bucket=s3_bucket, Key=evaluation_key)
        evaluation_data = json.loads(response['Body'].read())
        
        return {
            'statusCode': 200,
            'body': evaluation_data
        }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }
EOF
    filename = "evaluate_model.py"
  }
}

# Lambda function for model evaluation
resource "aws_lambda_function" "evaluate_model" {
  filename         = data.archive_file.evaluate_model_zip.output_path
  function_name    = "EvaluateModel-${local.unique_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "evaluate_model.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.evaluate_model_zip.output_base64sha256
  
  tags = local.common_tags
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.evaluate_model.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

# ==========================================
# SNS TOPIC FOR NOTIFICATIONS (OPTIONAL)
# ==========================================

# SNS topic for pipeline notifications
resource "aws_sns_topic" "pipeline_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.project_prefix}-notifications"
  tags  = local.common_tags
}

# SNS topic subscription (if email provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.pipeline_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==========================================
# STEP FUNCTIONS STATE MACHINE
# ==========================================

# Step Functions state machine definition
resource "aws_sfn_state_machine" "ml_pipeline" {
  name     = local.pipeline_name
  role_arn = aws_iam_role.stepfunctions_role.arn
  tags     = local.common_tags

  definition = jsonencode({
    Comment = "ML Pipeline with SageMaker and Step Functions"
    StartAt = "DataPreprocessing"
    States = {
      DataPreprocessing = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createProcessingJob.sync"
        Parameters = {
          "ProcessingJobName.$" = "$.PreprocessingJobName"
          RoleArn               = aws_iam_role.sagemaker_role.arn
          AppSpecification = {
            ImageUri = "683313688378.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
            ContainerEntrypoint = [
              "python3",
              "/opt/ml/processing/input/code/preprocessing.py"
            ]
            ContainerArguments = [
              "--input-data",
              "/opt/ml/processing/input/data/train.csv",
              "--output-data",
              "/opt/ml/processing/output/train_processed.csv"
            ]
          }
          ProcessingInputs = [
            {
              InputName = "data"
              S3Input = {
                S3Uri       = "s3://${aws_s3_bucket.ml_artifacts.id}/raw-data"
                LocalPath   = "/opt/ml/processing/input/data"
                S3DataType  = "S3Prefix"
              }
            },
            {
              InputName = "code"
              S3Input = {
                S3Uri       = "s3://${aws_s3_bucket.ml_artifacts.id}/code"
                LocalPath   = "/opt/ml/processing/input/code"
                S3DataType  = "S3Prefix"
              }
            }
          ]
          ProcessingOutputs = [
            {
              OutputName = "processed_data"
              S3Output = {
                S3Uri     = "s3://${aws_s3_bucket.ml_artifacts.id}/processed-data"
                LocalPath = "/opt/ml/processing/output"
              }
            }
          ]
          ProcessingResources = {
            ClusterConfig = {
              InstanceCount   = 1
              InstanceType    = var.sagemaker_processing_instance_type
              VolumeSizeInGB  = var.sagemaker_volume_size
            }
          }
        }
        Next = "ModelTraining"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ProcessingJobFailed"
          }
        ]
      }
      ModelTraining = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createTrainingJob.sync"
        Parameters = {
          "TrainingJobName.$" = "$.TrainingJobName"
          RoleArn             = aws_iam_role.sagemaker_role.arn
          AlgorithmSpecification = {
            TrainingImage     = "683313688378.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
            TrainingInputMode = "File"
          }
          InputDataConfig = [
            {
              ChannelName = "train"
              DataSource = {
                S3DataSource = {
                  S3DataType         = "S3Prefix"
                  S3Uri              = "s3://${aws_s3_bucket.ml_artifacts.id}/processed-data"
                  S3DataDistributionType = "FullyReplicated"
                }
              }
            },
            {
              ChannelName = "test"
              DataSource = {
                S3DataSource = {
                  S3DataType         = "S3Prefix"
                  S3Uri              = "s3://${aws_s3_bucket.ml_artifacts.id}/raw-data"
                  S3DataDistributionType = "FullyReplicated"
                }
              }
            },
            {
              ChannelName = "code"
              DataSource = {
                S3DataSource = {
                  S3DataType         = "S3Prefix"
                  S3Uri              = "s3://${aws_s3_bucket.ml_artifacts.id}/code"
                  S3DataDistributionType = "FullyReplicated"
                }
              }
            }
          ]
          OutputDataConfig = {
            S3OutputPath = "s3://${aws_s3_bucket.ml_artifacts.id}/model-artifacts"
          }
          ResourceConfig = {
            InstanceType   = var.sagemaker_training_instance_type
            InstanceCount  = 1
            VolumeSizeInGB = var.sagemaker_volume_size
          }
          StoppingCondition = {
            MaxRuntimeInSeconds = var.sagemaker_max_runtime_seconds
          }
          HyperParameters = {
            sagemaker_program           = "training.py"
            sagemaker_submit_directory  = "/opt/ml/input/data/code"
          }
        }
        Next = "ModelEvaluation"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "TrainingJobFailed"
          }
        ]
      }
      ModelEvaluation = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.evaluate_model.function_name
          Payload = {
            "TrainingJobName.$" = "$.TrainingJobName"
            S3Bucket            = aws_s3_bucket.ml_artifacts.id
          }
        }
        Next = "CheckModelPerformance"
      }
      CheckModelPerformance = {
        Type = "Choice"
        Choices = [
          {
            Variable             = "$.Payload.body.test_r2"
            NumericGreaterThan   = var.model_performance_threshold
            Next                 = "CreateModel"
          }
        ]
        Default = "ModelPerformanceInsufficient"
      }
      CreateModel = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createModel"
        Parameters = {
          "ModelName.$"      = "$.ModelName"
          ExecutionRoleArn   = aws_iam_role.sagemaker_role.arn
          PrimaryContainer = {
            Image           = "683313688378.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
            "ModelDataUrl.$" = "$.ModelDataUrl"
            Environment = {
              SAGEMAKER_PROGRAM          = "inference.py"
              SAGEMAKER_SUBMIT_DIRECTORY = "/opt/ml/code"
            }
          }
        }
        Next = "CreateEndpointConfig"
      }
      CreateEndpointConfig = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createEndpointConfig"
        Parameters = {
          "EndpointConfigName.$" = "$.EndpointConfigName"
          ProductionVariants = [
            {
              VariantName         = "primary"
              "ModelName.$"       = "$.ModelName"
              InitialInstanceCount = 1
              InstanceType        = var.sagemaker_endpoint_instance_type
              InitialVariantWeight = 1
            }
          ]
        }
        Next = "CreateEndpoint"
      }
      CreateEndpoint = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createEndpoint"
        Parameters = {
          "EndpointName.$"       = "$.EndpointName"
          "EndpointConfigName.$" = "$.EndpointConfigName"
        }
        Next = "MLPipelineComplete"
      }
      MLPipelineComplete = {
        Type   = "Succeed"
        Result = "ML Pipeline completed successfully"
      }
      ProcessingJobFailed = {
        Type  = "Fail"
        Error = "ProcessingJobFailed"
        Cause = "The data preprocessing job failed"
      }
      TrainingJobFailed = {
        Type  = "Fail"
        Error = "TrainingJobFailed"
        Cause = "The model training job failed"
      }
      ModelPerformanceInsufficient = {
        Type  = "Fail"
        Error = "ModelPerformanceInsufficient"
        Cause = "Model performance does not meet the required threshold"
      }
    }
  })
}

# ==========================================
# CLOUDWATCH LOG GROUPS
# ==========================================

# CloudWatch log group for Step Functions
resource "aws_cloudwatch_log_group" "stepfunctions_logs" {
  name              = "/aws/stepfunctions/${aws_sfn_state_machine.ml_pipeline.name}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

# ==========================================
# SAMPLE DATA CREATION (OPTIONAL)
# ==========================================

# Lambda function for creating sample data
resource "aws_lambda_function" "create_sample_data" {
  count           = var.create_sample_data ? 1 : 0
  filename        = data.archive_file.sample_data_zip[0].output_path
  function_name   = "CreateSampleData-${local.unique_suffix}"
  role           = aws_iam_role.lambda_role.arn
  handler        = "create_sample_data.lambda_handler"
  runtime        = var.lambda_runtime
  timeout        = 300
  memory_size    = 512
  source_code_hash = data.archive_file.sample_data_zip[0].output_base64sha256
  
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.ml_artifacts.id
      TRAIN_TEST_SPLIT = var.train_test_split_ratio
    }
  }
  
  tags = local.common_tags
}

# Lambda function code for sample data creation
data "archive_file" "sample_data_zip" {
  count       = var.create_sample_data ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/create_sample_data.zip"

  source {
    content = <<EOF
import json
import boto3
import pandas as pd
import numpy as np
from sklearn.datasets import load_boston
from sklearn.model_selection import train_test_split
import io
import os

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = os.environ['S3_BUCKET']
    split_ratio = float(os.environ.get('TRAIN_TEST_SPLIT', '0.8'))
    
    try:
        # Load Boston Housing dataset
        boston = load_boston()
        X, y = boston.data, boston.target
        
        # Create DataFrame
        df = pd.DataFrame(X, columns=boston.feature_names)
        df['target'] = y
        
        # Split into train and test sets
        train_df, test_df = train_test_split(df, test_size=1-split_ratio, random_state=42)
        
        # Convert to CSV
        train_csv = train_df.to_csv(index=False)
        test_csv = test_df.to_csv(index=False)
        
        # Upload to S3
        s3.put_object(Bucket=bucket, Key='raw-data/train.csv', Body=train_csv)
        s3.put_object(Bucket=bucket, Key='raw-data/test.csv', Body=test_csv)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sample data created successfully',
                'train_shape': train_df.shape,
                'test_shape': test_df.shape
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "create_sample_data.py"
  }
}

# Lambda invocation to create sample data
resource "aws_lambda_invocation" "create_sample_data" {
  count         = var.create_sample_data ? 1 : 0
  function_name = aws_lambda_function.create_sample_data[0].function_name
  input         = jsonencode({})
  
  depends_on = [
    aws_s3_bucket.ml_artifacts,
    aws_s3_object.raw_data_folder
  ]
}

# ==========================================
# SAMPLE CODE UPLOADS
# ==========================================

# Preprocessing script
resource "aws_s3_object" "preprocessing_script" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "code/preprocessing.py"
  content = <<EOF
import pandas as pd
import numpy as np
import argparse
import os
from sklearn.preprocessing import StandardScaler
import joblib

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input-data', type=str, required=True)
    parser.add_argument('--output-data', type=str, required=True)
    
    args = parser.parse_args()
    
    # Read data
    df = pd.read_csv(args.input_data)
    
    # Separate features and target
    X = df.drop('target', axis=1)
    y = df['target']
    
    # Apply preprocessing
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # Create processed DataFrame
    processed_df = pd.DataFrame(X_scaled, columns=X.columns)
    processed_df['target'] = y.values
    
    # Save processed data
    processed_df.to_csv(args.output_data, index=False)
    
    # Save scaler for inference
    scaler_path = os.path.join(os.path.dirname(args.output_data), 'scaler.pkl')
    joblib.dump(scaler, scaler_path)
    
    print(f"Processed data saved to: {args.output_data}")
    print(f"Scaler saved to: {scaler_path}")

if __name__ == '__main__':
    main()
EOF
  tags = local.common_tags
}

# Training script
resource "aws_s3_object" "training_script" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "code/training.py"
  content = <<EOF
import pandas as pd
import numpy as np
import argparse
import os
import joblib
import json
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error, r2_score

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAIN'))
    parser.add_argument('--test', type=str, default=os.environ.get('SM_CHANNEL_TEST'))
    parser.add_argument('--output-data-dir', type=str, default=os.environ.get('SM_OUTPUT_DATA_DIR'))
    
    args = parser.parse_args()
    
    # Read training data
    train_df = pd.read_csv(os.path.join(args.train, 'train_processed.csv'))
    test_df = pd.read_csv(os.path.join(args.test, 'test.csv'))
    
    # Prepare features and targets
    X_train = train_df.drop('target', axis=1)
    y_train = train_df['target']
    X_test = test_df.drop('target', axis=1)
    y_test = test_df['target']
    
    # Train Random Forest model
    rf_model = RandomForestRegressor(n_estimators=100, random_state=42)
    rf_model.fit(X_train, y_train)
    
    # Make predictions
    y_pred_train = rf_model.predict(X_train)
    y_pred_test = rf_model.predict(X_test)
    
    # Calculate metrics
    train_rmse = np.sqrt(mean_squared_error(y_train, y_pred_train))
    test_rmse = np.sqrt(mean_squared_error(y_test, y_pred_test))
    train_r2 = r2_score(y_train, y_pred_train)
    test_r2 = r2_score(y_test, y_pred_test)
    
    # Save model
    model_path = os.path.join(args.model_dir, 'model.pkl')
    joblib.dump(rf_model, model_path)
    
    # Save evaluation metrics
    metrics = {
        'train_rmse': float(train_rmse),
        'test_rmse': float(test_rmse),
        'train_r2': float(train_r2),
        'test_r2': float(test_r2)
    }
    
    metrics_path = os.path.join(args.output_data_dir, 'evaluation.json')
    with open(metrics_path, 'w') as f:
        json.dump(metrics, f, indent=2)
    
    print(f"Model saved to: {model_path}")
    print(f"Evaluation metrics: {metrics}")

if __name__ == '__main__':
    main()
EOF
  tags = local.common_tags
}

# Inference script
resource "aws_s3_object" "inference_script" {
  bucket = aws_s3_bucket.ml_artifacts.id
  key    = "code/inference.py"
  content = <<EOF
import joblib
import json
import numpy as np
import pandas as pd

def model_fn(model_dir):
    """Load model for inference"""
    model = joblib.load(f"{model_dir}/model.pkl")
    return model

def input_fn(request_body, request_content_type):
    """Parse input data for inference"""
    if request_content_type == 'application/json':
        input_data = json.loads(request_body)
        return np.array(input_data['instances'])
    elif request_content_type == 'text/csv':
        return pd.read_csv(io.StringIO(request_body)).values
    else:
        raise ValueError(f"Unsupported content type: {request_content_type}")

def predict_fn(input_data, model):
    """Make prediction"""
    predictions = model.predict(input_data)
    return predictions

def output_fn(predictions, accept):
    """Format output"""
    if accept == 'application/json':
        return json.dumps({'predictions': predictions.tolist()})
    else:
        return str(predictions)
EOF
  tags = local.common_tags
}