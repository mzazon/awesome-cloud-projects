# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique names for resources
  bucket_name     = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  repo_name       = var.codecommit_repo_name != "" ? var.codecommit_repo_name : "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  pipeline_name   = var.pipeline_name != "" ? var.pipeline_name : "${var.project_name}-pipeline-${var.environment}-${random_id.suffix.hex}"
  role_name       = var.sagemaker_execution_role_name != "" ? var.sagemaker_execution_role_name : "SageMakerExecutionRole-${var.environment}-${random_id.suffix.hex}"
  model_name      = var.model_name != "" ? var.model_name : "${var.project_name}-model-${var.environment}"
  
  # Common tags
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Recipe      = "end-to-end-mlops-sagemaker-pipelines"
  }, var.additional_tags)
}

# ================================
# S3 Bucket for MLOps Artifacts
# ================================

# S3 bucket for storing training data, model artifacts, and pipeline outputs
resource "aws_s3_bucket" "mlops_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "MLOps Data and Artifacts Bucket"
    Purpose = "Store training data, model artifacts, and pipeline outputs"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "mlops_bucket_versioning" {
  bucket = aws_s3_bucket.mlops_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "mlops_bucket_encryption" {
  bucket = aws_s3_bucket.mlops_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.enable_encryption
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "mlops_bucket_pab" {
  bucket = aws_s3_bucket.mlops_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket notification configuration for pipeline triggers (optional)
resource "aws_s3_bucket_notification" "mlops_bucket_notification" {
  bucket = aws_s3_bucket.mlops_bucket.id
  
  # Can be extended to trigger Lambda functions or SQS queues for automated pipeline execution
  depends_on = [aws_s3_bucket.mlops_bucket]
}

# ================================
# IAM Role for SageMaker Execution
# ================================

# Trust policy for SageMaker service
data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

# Custom IAM policy for SageMaker execution with S3 and CodeCommit access
data "aws_iam_policy_document" "sagemaker_execution_policy" {
  # S3 access for the MLOps bucket
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      aws_s3_bucket.mlops_bucket.arn,
      "${aws_s3_bucket.mlops_bucket.arn}/*"
    ]
  }

  # CodeCommit access for source code management
  statement {
    sid    = "CodeCommitAccess"
    effect = "Allow"
    actions = [
      "codecommit:BatchGet*",
      "codecommit:BatchDescribe*",
      "codecommit:Describe*",
      "codecommit:EvaluatePullRequestApprovalRules",
      "codecommit:Get*",
      "codecommit:List*",
      "codecommit:GitPull"
    ]
    resources = [aws_codecommit_repository.mlops_repo.arn]
  }

  # CloudWatch Logs access for monitoring and debugging
  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:GetLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }

  # ECR access for custom container images (if needed)
  statement {
    sid    = "ECRAccess"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = ["*"]
  }

  # SageMaker Model Registry access
  statement {
    sid    = "ModelRegistryAccess"
    effect = "Allow"
    actions = [
      "sagemaker:CreateModelPackage",
      "sagemaker:CreateModelPackageGroup",
      "sagemaker:DescribeModelPackage",
      "sagemaker:DescribeModelPackageGroup",
      "sagemaker:ListModelPackages",
      "sagemaker:ListModelPackageGroups",
      "sagemaker:UpdateModelPackage"
    ]
    resources = ["*"]
  }
}

# SageMaker execution role
resource "aws_iam_role" "sagemaker_execution_role" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json

  tags = merge(local.common_tags, {
    Name = "SageMaker Execution Role"
    Purpose = "Execution role for SageMaker pipelines and training jobs"
  })
}

# Attach AWS managed SageMaker execution policy
resource "aws_iam_role_policy_attachment" "sagemaker_execution_role_policy" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Attach custom execution policy
resource "aws_iam_policy" "sagemaker_custom_policy" {
  name        = "${local.role_name}-custom-policy"
  description = "Custom policy for SageMaker execution with S3 and CodeCommit access"
  policy      = data.aws_iam_policy_document.sagemaker_execution_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_custom_policy_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_custom_policy.arn
}

# ================================
# CodeCommit Repository
# ================================

# CodeCommit repository for ML code versioning
resource "aws_codecommit_repository" "mlops_repo" {
  repository_name   = local.repo_name
  repository_description = var.codecommit_repo_description

  tags = merge(local.common_tags, {
    Name = "MLOps Code Repository"
    Purpose = "Version control for ML pipeline code and training scripts"
  })
}

# ================================
# CloudWatch Log Groups
# ================================

# CloudWatch log group for SageMaker pipeline logs
resource "aws_cloudwatch_log_group" "sagemaker_pipeline_logs" {
  name              = "/aws/sagemaker/pipelines/${local.pipeline_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "SageMaker Pipeline Logs"
    Purpose = "Centralized logging for SageMaker pipeline executions"
  })
}

# CloudWatch log group for SageMaker training jobs
resource "aws_cloudwatch_log_group" "sagemaker_training_logs" {
  name              = "/aws/sagemaker/training-jobs/${local.model_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "SageMaker Training Job Logs"
    Purpose = "Centralized logging for SageMaker training job executions"
  })
}

# ================================
# SageMaker Model Package Group
# ================================

# SageMaker Model Package Group for model versioning and registry
resource "aws_sagemaker_model_package_group" "mlops_model_group" {
  model_package_group_name        = var.model_package_group_name != "" ? var.model_package_group_name : "${local.model_name}-package-group"
  model_package_group_description = "Model package group for ${var.project_name} ML models"

  tags = merge(local.common_tags, {
    Name = "MLOps Model Package Group"
    Purpose = "Version control and governance for ML models"
  })
}

# ================================
# SageMaker Domain (Optional)
# ================================

# SageMaker Domain for SageMaker Studio (commented out as it requires VPC configuration)
# Uncomment and configure if you want to use SageMaker Studio
/*
resource "aws_sagemaker_domain" "mlops_domain" {
  domain_name = "${var.project_name}-${var.environment}-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn

    # Security group configuration
    security_groups = var.security_group_ids

    # Sharing settings
    sharing_settings {
      notebook_output_option = "Allowed"
      s3_output_path         = "s3://${aws_s3_bucket.mlops_bucket.bucket}/studio-notebooks/"
    }
  }

  tags = merge(local.common_tags, {
    Name = "MLOps SageMaker Domain"
    Purpose = "SageMaker Studio domain for collaborative ML development"
  })
}
*/

# ================================
# Sample Data Upload (Optional)
# ================================

# Upload sample training data to S3 bucket
resource "aws_s3_object" "sample_train_data" {
  bucket = aws_s3_bucket.mlops_bucket.id
  key    = var.pipeline_parameters.training_data_path
  
  # Sample CSV content for demonstration
  content = <<EOF
crim,zn,indus,chas,nox,rm,age,dis,rad,tax,ptratio,b,lstat,medv
0.00632,18.0,2.31,0,0.538,6.575,65.2,4.0900,1,296,15.3,396.90,4.98,24.0
0.02731,0.0,7.07,0,0.469,6.421,78.9,4.9671,2,242,17.8,396.90,9.14,21.6
0.02729,0.0,7.07,0,0.469,7.185,61.1,4.9671,2,242,17.8,392.83,4.03,34.7
0.03237,0.0,2.18,0,0.458,6.998,45.8,6.0622,3,222,18.7,394.63,2.94,33.4
0.06905,0.0,2.18,0,0.458,7.147,54.2,6.0622,3,222,18.7,396.90,5.33,36.2
EOF

  content_type = "text/csv"

  tags = merge(local.common_tags, {
    Name = "Sample Training Data"
    Purpose = "Sample dataset for ML pipeline testing"
  })
}

# Upload sample validation data to S3 bucket
resource "aws_s3_object" "sample_validation_data" {
  bucket = aws_s3_bucket.mlops_bucket.id
  key    = var.pipeline_parameters.validation_data_path
  
  # Sample validation CSV content
  content = <<EOF
crim,zn,indus,chas,nox,rm,age,dis,rad,tax,ptratio,b,lstat,medv
0.09178,0.0,4.05,0,0.510,6.416,84.1,2.6463,5,296,16.6,395.50,9.04,23.6
0.06129,20.0,3.33,1,0.4429,6.769,87.3,2.5395,5,216,14.9,385.16,6.51,22.0
EOF

  content_type = "text/csv"

  tags = merge(local.common_tags, {
    Name = "Sample Validation Data"
    Purpose = "Sample validation dataset for ML pipeline testing"
  })
}

# ================================
# Training Script Upload
# ================================

# Upload sample training script to S3 bucket
resource "aws_s3_object" "training_script" {
  bucket = aws_s3_bucket.mlops_bucket.id
  key    = "code/train.py"
  
  # Sample training script content
  content = <<EOF
import argparse
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, r2_score
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    """Main training function for SageMaker training job."""
    parser = argparse.ArgumentParser()
    
    # SageMaker specific arguments
    parser.add_argument("--model-dir", type=str, default=os.environ.get("SM_MODEL_DIR"))
    parser.add_argument("--training", type=str, default=os.environ.get("SM_CHANNEL_TRAINING"))
    
    # Hyperparameters
    parser.add_argument("--n-estimators", type=int, default=100)
    parser.add_argument("--max-depth", type=int, default=None)
    parser.add_argument("--min-samples-split", type=int, default=2)
    parser.add_argument("--min-samples-leaf", type=int, default=1)
    parser.add_argument("--random-state", type=int, default=42)
    
    args = parser.parse_args()
    
    logger.info("Starting training job...")
    logger.info(f"Model directory: {args.model_dir}")
    logger.info(f"Training data directory: {args.training}")
    
    # Load training data
    try:
        train_file = os.path.join(args.training, "train.csv")
        logger.info(f"Loading training data from: {train_file}")
        training_data = pd.read_csv(train_file)
        logger.info(f"Training data shape: {training_data.shape}")
    except Exception as e:
        logger.error(f"Error loading training data: {e}")
        raise
    
    # Prepare features and target
    # Assuming 'medv' is the target column (Boston Housing dataset)
    target_column = 'medv'
    if target_column not in training_data.columns:
        logger.error(f"Target column '{target_column}' not found in training data")
        raise ValueError(f"Target column '{target_column}' not found")
    
    X = training_data.drop([target_column], axis=1)
    y = training_data[target_column]
    
    logger.info(f"Features shape: {X.shape}")
    logger.info(f"Target shape: {y.shape}")
    
    # Split data for validation
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.2, random_state=args.random_state
    )
    
    # Initialize and train model
    model = RandomForestRegressor(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        min_samples_split=args.min_samples_split,
        min_samples_leaf=args.min_samples_leaf,
        random_state=args.random_state,
        n_jobs=-1
    )
    
    logger.info("Training Random Forest model...")
    model.fit(X_train, y_train)
    
    # Evaluate model
    train_pred = model.predict(X_train)
    val_pred = model.predict(X_val)
    
    train_mse = mean_squared_error(y_train, train_pred)
    val_mse = mean_squared_error(y_val, val_pred)
    train_r2 = r2_score(y_train, train_pred)
    val_r2 = r2_score(y_val, val_pred)
    
    logger.info(f"Training MSE: {train_mse:.4f}")
    logger.info(f"Validation MSE: {val_mse:.4f}")
    logger.info(f"Training R2: {train_r2:.4f}")
    logger.info(f"Validation R2: {val_r2:.4f}")
    
    # Feature importance
    feature_importance = pd.DataFrame({
        'feature': X.columns,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)
    
    logger.info("Top 5 most important features:")
    logger.info(feature_importance.head().to_string(index=False))
    
    # Save model
    model_path = os.path.join(args.model_dir, "model.joblib")
    logger.info(f"Saving model to: {model_path}")
    joblib.dump(model, model_path)
    
    # Save feature names for inference
    feature_names_path = os.path.join(args.model_dir, "feature_names.joblib")
    joblib.dump(list(X.columns), feature_names_path)
    
    # Save metrics
    metrics = {
        'train_mse': train_mse,
        'val_mse': val_mse,
        'train_r2': train_r2,
        'val_r2': val_r2,
        'n_features': len(X.columns),
        'n_samples': len(training_data)
    }
    
    metrics_path = os.path.join(args.model_dir, "metrics.joblib")
    joblib.dump(metrics, metrics_path)
    
    logger.info("Training completed successfully!")

if __name__ == "__main__":
    main()
EOF

  content_type = "text/x-python"

  tags = merge(local.common_tags, {
    Name = "Training Script"
    Purpose = "Python script for ML model training in SageMaker"
  })
}

# ================================
# Pipeline Configuration File
# ================================

# Upload pipeline configuration to S3
resource "aws_s3_object" "pipeline_config" {
  bucket = aws_s3_bucket.mlops_bucket.id
  key    = "config/pipeline_config.json"
  
  content = jsonencode({
    pipeline_name = local.pipeline_name
    role_arn      = aws_iam_role.sagemaker_execution_role.arn
    
    training_config = {
      instance_type        = var.training_instance_type
      framework_version    = var.sklearn_framework_version
      python_version       = "py3"
      entry_point         = "train.py"
      source_dir          = "s3://${aws_s3_bucket.mlops_bucket.bucket}/code/"
    }
    
    data_config = {
      training_data_path   = "s3://${aws_s3_bucket.mlops_bucket.bucket}/${var.pipeline_parameters.training_data_path}"
      validation_data_path = "s3://${aws_s3_bucket.mlops_bucket.bucket}/${var.pipeline_parameters.validation_data_path}"
      output_path         = "s3://${aws_s3_bucket.mlops_bucket.bucket}/${var.pipeline_parameters.output_model_path}"
    }
    
    model_config = {
      model_package_group_name = aws_sagemaker_model_package_group.mlops_model_group.model_package_group_name
      approval_status         = "PendingManualApproval"
    }
  })

  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name = "Pipeline Configuration"
    Purpose = "Configuration file for SageMaker pipeline execution"
  })
}