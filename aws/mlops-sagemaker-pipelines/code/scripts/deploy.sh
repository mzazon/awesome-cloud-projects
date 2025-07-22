#!/bin/bash

# Deploy script for End-to-End MLOps with SageMaker Pipelines
# This script automates the deployment of a complete MLOps pipeline including
# IAM roles, S3 storage, CodeCommit repository, and SageMaker Pipeline

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is installed and configured
check_aws_prerequisites() {
    log_info "Checking AWS CLI prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        echo "Installation guide: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        echo "Run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    log_success "AWS CLI is properly configured"
}

# Function to check required permissions
check_permissions() {
    log_info "Checking required AWS permissions..."
    
    local required_actions=(
        "iam:CreateRole"
        "iam:AttachRolePolicy" 
        "s3:CreateBucket"
        "codecommit:CreateRepository"
        "sagemaker:CreatePipeline"
    )
    
    # Test basic permissions by trying to list resources
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log_warning "Cannot verify IAM permissions. Continuing with deployment..."
    fi
    
    if ! aws s3 ls &> /dev/null; then
        log_error "Insufficient S3 permissions. Please ensure you have S3 access."
        exit 1
    fi
    
    log_success "Basic permissions validated"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please run 'aws configure set region <your-region>'"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export BUCKET_NAME="sagemaker-mlops-${RANDOM_SUFFIX}"
    export PIPELINE_NAME="mlops-pipeline-${RANDOM_SUFFIX}"
    export ROLE_NAME="SageMakerExecutionRole-${RANDOM_SUFFIX}"
    export CODECOMMIT_REPO="mlops-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for later use
    cat > .env << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export BUCKET_NAME=${BUCKET_NAME}
export PIPELINE_NAME=${PIPELINE_NAME}
export ROLE_NAME=${ROLE_NAME}
export CODECOMMIT_REPO=${CODECOMMIT_REPO}
export RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured:"
    log_info "  Region: ${AWS_REGION}"
    log_info "  Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Bucket: ${BUCKET_NAME}"
    log_info "  Pipeline: ${PIPELINE_NAME}"
    log_info "  Role: ${ROLE_NAME}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for data and artifacts..."
    
    if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists"
        return 0
    fi
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning for model artifacts
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Block public access for security
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log_success "S3 bucket ${BUCKET_NAME} created successfully"
}

# Function to create IAM execution role
create_iam_role() {
    log_info "Creating IAM execution role for SageMaker..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${ROLE_NAME} already exists"
        export ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)
        return 0
    fi
    
    # Create trust policy for SageMaker service
    cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create the execution role
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --description "SageMaker execution role for MLOps pipeline"
    
    # Attach managed policies for SageMaker full access
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
    
    # Store role ARN for later use
    export ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    # Clean up temporary files
    rm -f trust-policy.json
    
    log_success "IAM role created: ${ROLE_ARN}"
}

# Function to create CodeCommit repository
create_codecommit_repo() {
    log_info "Creating CodeCommit repository for ML code..."
    
    # Check if repository already exists
    if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO}" &>/dev/null; then
        log_warning "CodeCommit repository ${CODECOMMIT_REPO} already exists"
        return 0
    fi
    
    # Create CodeCommit repository
    aws codecommit create-repository \
        --repository-name "${CODECOMMIT_REPO}" \
        --repository-description "MLOps pipeline code repository for ${PIPELINE_NAME}"
    
    # Get repository clone URL
    export REPO_URL=$(aws codecommit get-repository \
        --repository-name "${CODECOMMIT_REPO}" \
        --query 'repositoryMetadata.cloneUrlHttp' --output text)
    
    log_success "CodeCommit repository created: ${REPO_URL}"
}

# Function to upload sample training data
upload_sample_data() {
    log_info "Creating and uploading sample training data..."
    
    # Create sample data directory
    mkdir -p sample-data
    
    # Create sample CSV data for demonstration (Boston Housing dataset structure)
    cat > sample-data/train.csv << 'EOF'
crim,zn,indus,chas,nox,rm,age,dis,rad,tax,ptratio,b,lstat,medv
0.00632,18.0,2.31,0,0.538,6.575,65.2,4.0900,1,296,15.3,396.90,4.98,24.0
0.02731,0.0,7.07,0,0.469,6.421,78.9,4.9671,2,242,17.8,396.90,9.14,21.6
0.02729,0.0,7.07,0,0.469,7.185,61.1,4.9671,2,242,17.8,392.83,4.03,34.7
0.03237,0.0,2.18,0,0.458,6.998,45.8,6.0622,3,222,18.7,394.63,2.94,33.4
0.06905,0.0,2.18,0,0.458,7.147,54.2,6.0622,3,222,18.7,396.90,5.33,36.2
0.02985,0.0,2.18,0,0.458,6.430,58.7,6.0622,3,222,18.7,394.12,5.21,28.7
0.08829,12.5,7.87,0,0.524,6.012,66.6,5.5605,5,311,15.2,395.60,12.43,22.9
0.14455,12.5,7.87,0,0.524,6.172,96.1,5.9505,5,311,15.2,396.90,19.15,27.1
0.21124,12.5,7.87,0,0.524,5.631,100.0,6.0821,5,311,15.2,386.63,29.93,16.5
0.17004,12.5,7.87,0,0.524,6.004,85.9,6.5921,5,311,15.2,386.71,17.10,18.9
EOF
    
    cat > sample-data/validation.csv << 'EOF'
crim,zn,indus,chas,nox,rm,age,dis,rad,tax,ptratio,b,lstat,medv
0.22489,12.5,7.87,0,0.524,6.377,94.3,6.3467,5,311,15.2,392.52,20.45,15.0
0.11747,12.5,7.87,0,0.524,6.009,82.9,6.2267,5,311,15.2,396.90,13.27,18.9
0.09378,12.5,7.87,0,0.524,5.889,39.0,5.4509,5,311,15.2,390.50,15.71,21.7
0.62976,0.0,8.14,0,0.538,5.949,61.8,4.7075,4,307,21.0,396.90,8.26,20.4
0.63796,0.0,8.14,0,0.538,6.096,84.5,4.4619,4,307,21.0,380.02,10.26,18.2
0.62739,0.0,8.14,0,0.538,5.834,56.5,4.4986,4,307,21.0,395.62,8.47,19.9
1.05393,0.0,8.14,0,0.538,5.935,29.3,4.4986,4,307,21.0,386.85,6.58,23.1
0.78420,0.0,8.14,0,0.538,5.990,81.7,4.2579,4,307,21.0,386.75,14.67,17.5
0.80271,0.0,8.14,0,0.538,5.456,36.6,3.7965,4,307,21.0,288.99,11.69,20.2
0.72580,0.0,8.14,0,0.538,5.727,69.5,3.7965,4,307,21.0,390.95,11.28,18.2
EOF
    
    # Upload data to S3
    aws s3 cp sample-data/ "s3://${BUCKET_NAME}/data/" --recursive
    
    # Clean up local files
    rm -rf sample-data/
    
    log_success "Training data uploaded to s3://${BUCKET_NAME}/data/"
}

# Function to create training script
create_training_script() {
    log_info "Creating training script for the pipeline..."
    
    cat > train.py << 'EOF'
import argparse
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
import os
import json
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=str, default=os.environ.get("SM_MODEL_DIR"))
    parser.add_argument("--training", type=str, default=os.environ.get("SM_CHANNEL_TRAINING"))
    parser.add_argument("--output-data-dir", type=str, default=os.environ.get("SM_OUTPUT_DATA_DIR"))
    
    args = parser.parse_args()
    
    logger.info("Starting model training...")
    logger.info(f"Model directory: {args.model_dir}")
    logger.info(f"Training data directory: {args.training}")
    
    try:
        # Load training data
        train_file = os.path.join(args.training, "train.csv")
        if not os.path.exists(train_file):
            raise FileNotFoundError(f"Training file not found: {train_file}")
        
        training_data = pd.read_csv(train_file)
        logger.info(f"Loaded training data with shape: {training_data.shape}")
        
        # Prepare features and target
        if 'medv' not in training_data.columns:
            raise ValueError("Target column 'medv' not found in training data")
        
        X = training_data.drop(['medv'], axis=1)
        y = training_data['medv']
        
        logger.info(f"Features shape: {X.shape}, Target shape: {y.shape}")
        
        # Split data for validation
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        # Train model
        logger.info("Training Random Forest model...")
        model = RandomForestRegressor(
            n_estimators=100, 
            random_state=42,
            max_depth=10,
            min_samples_split=5
        )
        model.fit(X_train, y_train)
        
        # Evaluate model
        y_pred = model.predict(X_test)
        mse = mean_squared_error(y_test, y_pred)
        mae = mean_absolute_error(y_test, y_pred)
        r2 = r2_score(y_test, y_pred)
        
        logger.info(f"Model evaluation results:")
        logger.info(f"  Mean Squared Error: {mse:.4f}")
        logger.info(f"  Mean Absolute Error: {mae:.4f}")
        logger.info(f"  R² Score: {r2:.4f}")
        
        # Save model
        model_path = os.path.join(args.model_dir, "model.joblib")
        joblib.dump(model, model_path)
        logger.info(f"Model saved to: {model_path}")
        
        # Save model metadata
        metadata = {
            "model_type": "RandomForestRegressor",
            "n_estimators": 100,
            "training_samples": len(X_train),
            "test_samples": len(X_test),
            "features": list(X.columns),
            "metrics": {
                "mse": float(mse),
                "mae": float(mae),
                "r2_score": float(r2)
            }
        }
        
        metadata_path = os.path.join(args.model_dir, "model_metadata.json")
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        logger.info("Training completed successfully!")
        
    except Exception as e:
        logger.error(f"Training failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()
EOF
    
    # Upload training script to S3
    aws s3 cp train.py "s3://${BUCKET_NAME}/code/"
    
    # Clean up local file
    rm -f train.py
    
    log_success "Training script created and uploaded"
}

# Function to create pipeline definition
create_pipeline_definition() {
    log_info "Creating SageMaker pipeline definition..."
    
    cat > pipeline_definition.py << EOF
import boto3
import sagemaker
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.steps import TrainingStep, ProcessingStep
from sagemaker.sklearn.estimator import SKLearn
from sagemaker.workflow.parameters import ParameterString, ParameterInteger
from sagemaker.workflow.pipeline_context import PipelineSession
from sagemaker.inputs import TrainingInput

def create_pipeline():
    """Create SageMaker Pipeline for MLOps workflow"""
    
    # Initialize SageMaker session
    pipeline_session = PipelineSession()
    role = "${ROLE_ARN}"
    bucket = "${BUCKET_NAME}"
    
    # Define parameters
    input_data = ParameterString(
        name="InputData",
        default_value=f"s3://{bucket}/data/"
    )
    
    model_approval_status = ParameterString(
        name="ModelApprovalStatus",
        default_value="PendingManualApproval"
    )
    
    # Create SKLearn estimator for training
    sklearn_estimator = SKLearn(
        entry_point="train.py",
        source_dir=f"s3://{bucket}/code/",
        framework_version="1.0-1",
        py_version="py3",
        instance_type="ml.m5.large",
        instance_count=1,
        role=role,
        sagemaker_session=pipeline_session,
        hyperparameters={
            'n_estimators': 100,
            'max_depth': 10
        }
    )
    
    # Create training step
    training_step = TrainingStep(
        name="ModelTraining",
        estimator=sklearn_estimator,
        inputs={
            "training": TrainingInput(
                s3_data=input_data,
                content_type="text/csv"
            )
        }
    )
    
    # Create pipeline
    pipeline = Pipeline(
        name="${PIPELINE_NAME}",
        parameters=[input_data, model_approval_status],
        steps=[training_step],
        sagemaker_session=pipeline_session
    )
    
    return pipeline

if __name__ == "__main__":
    pipeline = create_pipeline()
    
    # Create or update pipeline
    pipeline.upsert(role_arn="${ROLE_ARN}")
    
    print(f"Pipeline '{pipeline.name}' created/updated successfully")
    print(f"Pipeline ARN: {pipeline.describe()['PipelineArn']}")
    
    # Start pipeline execution
    execution = pipeline.start()
    print(f"Pipeline execution started: {execution.arn}")
    print("Monitor execution in SageMaker Studio or AWS Console")
EOF
    
    log_success "Pipeline definition created"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log_success "✓ S3 bucket is accessible"
    else
        log_error "✗ S3 bucket validation failed"
        return 1
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        log_success "✓ IAM role exists"
    else
        log_error "✗ IAM role validation failed"
        return 1
    fi
    
    # Check CodeCommit repository
    if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO}" &>/dev/null; then
        log_success "✓ CodeCommit repository exists"
    else
        log_error "✗ CodeCommit repository validation failed"
        return 1
    fi
    
    # Check training data
    if aws s3 ls "s3://${BUCKET_NAME}/data/" &>/dev/null; then
        log_success "✓ Training data is uploaded"
    else
        log_error "✗ Training data validation failed"
        return 1
    fi
    
    log_success "All validation checks passed!"
}

# Function to display next steps
display_next_steps() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "=== Next Steps ==="
    echo ""
    echo "1. Execute the pipeline:"
    echo "   python pipeline_definition.py"
    echo ""
    echo "2. Monitor pipeline execution:"
    echo "   aws sagemaker list-pipeline-executions --pipeline-name ${PIPELINE_NAME}"
    echo ""
    echo "3. View pipeline in AWS Console:"
    echo "   https://console.aws.amazon.com/sagemaker/home?region=${AWS_REGION}#/pipelines"
    echo ""
    echo "4. Access your resources:"
    echo "   - S3 Bucket: ${BUCKET_NAME}"
    echo "   - IAM Role: ${ROLE_NAME}"
    echo "   - CodeCommit Repo: ${CODECOMMIT_REPO}"
    echo "   - Pipeline: ${PIPELINE_NAME}"
    echo ""
    echo "5. Clean up resources when done:"
    echo "   ./destroy.sh"
    echo ""
    echo "Environment variables saved in .env file for future use."
}

# Main deployment function
main() {
    echo "=================================================="
    echo "SageMaker MLOps Pipeline Deployment Script"
    echo "=================================================="
    echo ""
    
    # Check prerequisites
    check_aws_prerequisites
    check_permissions
    
    # Setup environment
    setup_environment
    
    # Deploy infrastructure
    create_s3_bucket
    create_iam_role
    create_codecommit_repo
    upload_sample_data
    create_training_script
    create_pipeline_definition
    
    # Validate deployment
    validate_deployment
    
    # Display next steps
    display_next_steps
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Check the error above."' ERR

# Run main function
main "$@"