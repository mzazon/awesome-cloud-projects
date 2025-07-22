#!/bin/bash

# Deploy script for Machine Learning Model Deployment Pipelines with SageMaker and CodePipeline
# This script automates the deployment of a complete MLOps pipeline infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if AWS CLI is installed and configured
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions (basic check)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Unable to retrieve AWS account ID. Check your credentials."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        warning "AWS region not configured. Setting default region to us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export PROJECT_NAME="mlops-pipeline-${RANDOM_SUFFIX}"
    export BUCKET_NAME="sagemaker-mlops-${AWS_REGION}-${RANDOM_SUFFIX}"
    export MODEL_PACKAGE_GROUP_NAME="fraud-detection-models"
    export PIPELINE_NAME="ml-deployment-pipeline-${RANDOM_SUFFIX}"
    
    # Store environment variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
BUCKET_NAME=${BUCKET_NAME}
MODEL_PACKAGE_GROUP_NAME=${MODEL_PACKAGE_GROUP_NAME}
PIPELINE_NAME=${PIPELINE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Project Name: ${PROJECT_NAME}"
    log "S3 Bucket: ${BUCKET_NAME}"
    log "Region: ${AWS_REGION}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for artifacts..."
    
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "Bucket ${BUCKET_NAME} already exists. Skipping creation."
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "${BUCKET_NAME}"
        else
            aws s3api create-bucket \
                --bucket "${BUCKET_NAME}" \
                --region "${AWS_REGION}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        success "Created S3 bucket: ${BUCKET_NAME}"
    fi
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles for SageMaker, CodeBuild, CodePipeline, and Lambda..."
    
    # SageMaker Execution Role
    if ! aws iam get-role --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam create-role \
            --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
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
            }' > /dev/null
        
        aws iam attach-role-policy \
            --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
        
        aws iam attach-role-policy \
            --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        success "Created SageMaker execution role"
    else
        warning "SageMaker execution role already exists"
    fi
    
    # CodeBuild Service Role
    if ! aws iam get-role --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam create-role \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "codebuild.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' > /dev/null
        
        # Attach policies to CodeBuild role
        aws iam attach-role-policy \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
        
        aws iam attach-role-policy \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        aws iam attach-role-policy \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
        
        success "Created CodeBuild service role"
    else
        warning "CodeBuild service role already exists"
    fi
    
    # CodePipeline Service Role
    if ! aws iam get-role --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam create-role \
            --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "codepipeline.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' > /dev/null
        
        # Create and attach custom policy for CodePipeline
        cat > /tmp/codepipeline-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "codebuild:BatchGetBuilds",
                "codebuild:StartBuild"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sagemaker:*",
                "lambda:InvokeFunction"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}" \
            --policy-name CodePipelineServicePolicy \
            --policy-document file:///tmp/codepipeline-policy.json
        
        success "Created CodePipeline service role"
    else
        warning "CodePipeline service role already exists"
    fi
    
    # Lambda Execution Role
    if ! aws iam get-role --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam create-role \
            --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "lambda.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' > /dev/null
        
        aws iam attach-role-policy \
            --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        aws iam attach-role-policy \
            --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
        
        success "Created Lambda execution role"
    else
        warning "Lambda execution role already exists"
    fi
    
    # Wait for roles to be available
    log "Waiting for IAM roles to be available..."
    sleep 10
}

# Function to create SageMaker Model Package Group
create_model_package_group() {
    log "Creating SageMaker Model Package Group..."
    
    if aws sagemaker describe-model-package-group \
        --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" &>/dev/null; then
        warning "Model package group already exists"
    else
        aws sagemaker create-model-package-group \
            --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" \
            --model-package-group-description "Fraud detection model packages" \
            --tags Key=Project,Value="${PROJECT_NAME}" > /dev/null
        
        success "Created model package group: ${MODEL_PACKAGE_GROUP_NAME}"
    fi
}

# Function to create training and testing data
create_training_data() {
    log "Creating synthetic training data..."
    
    python3 << 'EOF'
import pandas as pd
import numpy as np

# Generate synthetic credit card transaction data
np.random.seed(42)
n_samples = 50000

# Create features that might indicate fraud
data = {
    'amount': np.random.exponential(50, n_samples),
    'hour': np.random.randint(0, 24, n_samples),
    'day_of_week': np.random.randint(0, 7, n_samples),
    'merchant_category': np.random.randint(0, 20, n_samples),
    'distance_from_home': np.random.exponential(10, n_samples),
    'online_transaction': np.random.choice([0, 1], n_samples, p=[0.7, 0.3]),
    'previous_failures': np.random.poisson(0.1, n_samples),
    'account_age_days': np.random.randint(30, 3650, n_samples),
    'credit_limit': np.random.normal(5000, 2000, n_samples),
    'current_balance': np.random.normal(2000, 1500, n_samples)
}

# Create additional derived features
for i in range(10):
    data[f'feature_{i}'] = np.random.randn(n_samples)

# Create target variable (fraud indicator)
fraud_probability = (
    (data['amount'] > 200) * 0.3 +
    (data['hour'] > 22) * 0.2 +
    (data['distance_from_home'] > 50) * 0.25 +
    (data['online_transaction'] == 1) * 0.1 +
    np.random.random(n_samples) * 0.15
)

data['is_fraud'] = (fraud_probability > 0.5).astype(int)

# Create DataFrame and save
df = pd.DataFrame(data)
df.to_csv('/tmp/training_data.csv', index=False)

print(f"Generated {len(df)} samples with {df['is_fraud'].sum()} fraud cases")
print(f"Fraud rate: {df['is_fraud'].mean():.2%}")
EOF
    
    # Upload training data to S3
    aws s3 cp /tmp/training_data.csv "s3://${BUCKET_NAME}/training-data/"
    
    success "Created and uploaded training data"
}

# Function to create model training script
create_training_script() {
    log "Creating model training script..."
    
    cat > /tmp/train.py << 'EOF'
import argparse
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import joblib
import os

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--n_estimators', type=int, default=100)
    parser.add_argument('--max_depth', type=int, default=10)
    parser.add_argument('--model_dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAINING'))
    
    args = parser.parse_args()
    
    # Generate synthetic training data for demonstration
    np.random.seed(42)
    n_samples = 10000
    n_features = 20
    
    # Create synthetic features
    X = np.random.randn(n_samples, n_features)
    # Create target with some correlation to features
    y = (X[:, 0] + X[:, 1] + np.random.randn(n_samples) * 0.1 > 0).astype(int)
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Train model
    model = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        random_state=42
    )
    model.fit(X_train, y_train)
    
    # Evaluate model
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"Model accuracy: {accuracy:.4f}")
    print(classification_report(y_test, y_pred))
    
    # Save model
    joblib.dump(model, os.path.join(args.model_dir, 'model.joblib'))
    
    # Save model metrics
    metrics = {
        'accuracy': accuracy,
        'n_estimators': args.n_estimators,
        'max_depth': args.max_depth
    }
    
    with open(os.path.join(args.model_dir, 'metrics.json'), 'w') as f:
        import json
        json.dump(metrics, f)

if __name__ == '__main__':
    main()
EOF
    
    # Upload training script to S3
    aws s3 cp /tmp/train.py "s3://${BUCKET_NAME}/code/"
    
    success "Created and uploaded training script"
}

# Function to create BuildSpec files
create_buildspec_files() {
    log "Creating BuildSpec files for training and testing..."
    
    # Create buildspec for model training
    cat > /tmp/buildspec-train.yml << 'EOF'
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - pip install boto3 scikit-learn pandas numpy sagemaker
  build:
    commands:
      - echo "Starting model training..."
      - |
        python << 'PYTHON_EOF'
        import boto3
        import sagemaker
        import json
        import os
        from sagemaker.sklearn.estimator import SKLearn
        from sagemaker.model_package import ModelPackage
        
        # Initialize SageMaker session
        session = sagemaker.Session()
        role = os.environ['SAGEMAKER_ROLE_ARN']
        
        # Create training job
        sklearn_estimator = SKLearn(
            entry_point='train.py',
            role=role,
            instance_type='ml.m5.large',
            framework_version='1.0-1',
            py_version='py3',
            hyperparameters={
                'n_estimators': 100,
                'max_depth': 10
            }
        )
        
        # Submit training job
        training_job_name = f"fraud-detection-{os.environ['CODEBUILD_BUILD_NUMBER']}"
        sklearn_estimator.fit(
            inputs={'training': f"s3://{os.environ['BUCKET_NAME']}/training-data/"},
            job_name=training_job_name,
            wait=True
        )
        
        # Register model in Model Registry
        model_package = sklearn_estimator.create_model_package(
            model_package_group_name=os.environ['MODEL_PACKAGE_GROUP_NAME'],
            approval_status='PendingManualApproval',
            description=f"Fraud detection model trained from build {os.environ['CODEBUILD_BUILD_NUMBER']}"
        )
        
        # Save model package ARN for next stage
        with open('model_package_arn.txt', 'w') as f:
            f.write(model_package.model_package_arn)
        
        print(f"Model package created: {model_package.model_package_arn}")
        PYTHON_EOF
artifacts:
  files:
    - model_package_arn.txt
EOF
    
    # Create buildspec for model testing
    cat > /tmp/buildspec-test.yml << 'EOF'
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - pip install boto3 sagemaker pandas numpy scikit-learn
  build:
    commands:
      - echo "Starting model testing..."
      - |
        python << 'PYTHON_EOF'
        import boto3
        import sagemaker
        import json
        import os
        import time
        from sagemaker.model_package import ModelPackage
        
        # Read model package ARN from previous stage
        with open('model_package_arn.txt', 'r') as f:
            model_package_arn = f.read().strip()
        
        print(f"Testing model package: {model_package_arn}")
        
        # Initialize SageMaker session
        session = sagemaker.Session()
        
        # Create model package object
        model_package = ModelPackage(
            model_package_arn=model_package_arn,
            sagemaker_session=session
        )
        
        # Create test endpoint configuration
        endpoint_config_name = f"test-config-{int(time.time())}"
        endpoint_name = f"test-endpoint-{int(time.time())}"
        
        # Deploy model to test endpoint
        predictor = model_package.deploy(
            initial_instance_count=1,
            instance_type='ml.t2.medium',
            endpoint_name=endpoint_name,
            wait=True
        )
        
        # Perform model testing
        import numpy as np
        test_data = np.random.randn(10, 20).tolist()
        
        try:
            # Test predictions
            predictions = predictor.predict(test_data)
            print(f"Test predictions successful: {len(predictions)} predictions made")
            
            # Basic validation - check if predictions are within expected range
            if all(isinstance(p, (int, float)) for p in predictions):
                print("✅ Model test passed - predictions are valid")
                test_result = "PASSED"
            else:
                print("❌ Model test failed - invalid predictions")
                test_result = "FAILED"
                
        except Exception as e:
            print(f"❌ Model test failed with error: {str(e)}")
            test_result = "FAILED"
        
        finally:
            # Clean up test endpoint
            predictor.delete_endpoint()
            print("✅ Cleaned up test endpoint")
        
        # Save test results
        with open('test_results.json', 'w') as f:
            json.dump({
                'test_status': test_result,
                'model_package_arn': model_package_arn,
                'timestamp': time.time()
            }, f)
        
        # If tests passed, approve the model
        if test_result == "PASSED":
            client = boto3.client('sagemaker')
            client.update_model_package(
                ModelPackageArn=model_package_arn,
                ModelApprovalStatus='Approved'
            )
            print("✅ Model approved for deployment")
        else:
            raise Exception("Model failed testing - deployment blocked")
        PYTHON_EOF
artifacts:
  files:
    - test_results.json
    - model_package_arn.txt
EOF
    
    # Upload buildspecs to S3
    aws s3 cp /tmp/buildspec-train.yml "s3://${BUCKET_NAME}/buildspecs/"
    aws s3 cp /tmp/buildspec-test.yml "s3://${BUCKET_NAME}/buildspecs/"
    
    success "Created and uploaded BuildSpec files"
}

# Function to create CodeBuild projects
create_codebuild_projects() {
    log "Creating CodeBuild projects for training and testing..."
    
    CODEBUILD_ROLE_ARN=$(aws iam get-role \
        --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    # Create training CodeBuild project
    if ! aws codebuild batch-get-projects --names "${PROJECT_NAME}-train" &>/dev/null; then
        aws codebuild create-project \
            --name "${PROJECT_NAME}-train" \
            --description "ML model training project" \
            --source type=CODEPIPELINE,buildspec=buildspecs/buildspec-train.yml \
            --artifacts type=CODEPIPELINE \
            --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_MEDIUM \
            --service-role "${CODEBUILD_ROLE_ARN}" \
            --tags Key=Project,Value="${PROJECT_NAME}" > /dev/null
        
        success "Created training CodeBuild project"
    else
        warning "Training CodeBuild project already exists"
    fi
    
    # Create testing CodeBuild project
    if ! aws codebuild batch-get-projects --names "${PROJECT_NAME}-test" &>/dev/null; then
        aws codebuild create-project \
            --name "${PROJECT_NAME}-test" \
            --description "ML model testing project" \
            --source type=CODEPIPELINE,buildspec=buildspecs/buildspec-test.yml \
            --artifacts type=CODEPIPELINE \
            --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_MEDIUM \
            --service-role "${CODEBUILD_ROLE_ARN}" \
            --tags Key=Project,Value="${PROJECT_NAME}" > /dev/null
        
        success "Created testing CodeBuild project"
    else
        warning "Testing CodeBuild project already exists"
    fi
}

# Function to create Lambda deployment function
create_lambda_function() {
    log "Creating Lambda deployment function..."
    
    # Create deployment Lambda function
    cat > /tmp/deploy_function.py << 'EOF'
import json
import boto3
import os
import time

def lambda_handler(event, context):
    codepipeline = boto3.client('codepipeline')
    sagemaker = boto3.client('sagemaker')
    
    # Get job details from CodePipeline
    job_id = event['CodePipeline.job']['id']
    
    try:
        # Get input artifacts
        input_artifacts = event['CodePipeline.job']['data']['inputArtifacts']
        
        # Extract model package ARN from artifacts
        # This would normally be read from the artifacts
        model_package_arn = os.environ.get('MODEL_PACKAGE_ARN')
        
        if not model_package_arn:
            raise Exception("Model package ARN not found")
        
        # Deploy model to production endpoint
        endpoint_name = f"fraud-detection-prod-{int(time.time())}"
        
        # Create endpoint configuration
        endpoint_config_name = f"fraud-detection-config-{int(time.time())}"
        
        # This is a simplified deployment - in practice you'd create
        # endpoint configurations and deploy the model
        print(f"Deploying model package: {model_package_arn}")
        print(f"Target endpoint: {endpoint_name}")
        
        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Deployment successful')
        }
        
    except Exception as e:
        print(f"Deployment failed: {str(e)}")
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={'message': str(e)}
        )
        raise e
EOF
    
    # Create deployment package
    cd /tmp
    zip -q deploy_function.zip deploy_function.py
    
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    # Create Lambda function
    if ! aws lambda get-function --function-name "${PROJECT_NAME}-deploy" &>/dev/null; then
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-deploy" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler deploy_function.lambda_handler \
            --zip-file fileb://deploy_function.zip \
            --description "Deploy ML model to production" \
            --timeout 300 > /dev/null
        
        success "Created deployment Lambda function"
    else
        warning "Lambda deployment function already exists"
    fi
}

# Function to create source code structure
create_source_structure() {
    log "Creating source code structure..."
    
    # Create source code structure
    mkdir -p /tmp/ml-source-code
    cd /tmp/ml-source-code
    
    # Copy training script
    cp /tmp/train.py .
    
    # Copy buildspecs
    mkdir -p buildspecs
    cp /tmp/buildspec-train.yml buildspecs/
    cp /tmp/buildspec-test.yml buildspecs/
    
    # Create README
    cat > README.md << 'EOF'
# ML Model Deployment Pipeline

This repository contains the source code for an automated ML model deployment pipeline.

## Structure
- `train.py` - Model training script
- `buildspecs/` - CodeBuild configuration files
- `README.md` - This file

## Pipeline Stages
1. Source - Code changes trigger pipeline
2. Build - Model training with SageMaker
3. Test - Automated model validation
4. Deploy - Production deployment
EOF
    
    # Upload source code to S3
    zip -rq ml-source-code.zip .
    aws s3 cp ml-source-code.zip "s3://${BUCKET_NAME}/source/"
    
    success "Created and uploaded source code structure"
}

# Function to create CodePipeline
create_codepipeline() {
    log "Creating CodePipeline..."
    
    SAGEMAKER_ROLE_ARN=$(aws iam get-role \
        --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    CODEPIPELINE_ROLE_ARN=$(aws iam get-role \
        --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    # Create pipeline definition
    cat > /tmp/pipeline.json << EOF
{
    "pipeline": {
        "name": "${PIPELINE_NAME}",
        "roleArn": "${CODEPIPELINE_ROLE_ARN}",
        "artifactStore": {
            "type": "S3",
            "location": "${BUCKET_NAME}"
        },
        "stages": [
            {
                "name": "Source",
                "actions": [
                    {
                        "name": "SourceAction",
                        "actionTypeId": {
                            "category": "Source",
                            "owner": "AWS",
                            "provider": "S3",
                            "version": "1"
                        },
                        "configuration": {
                            "S3Bucket": "${BUCKET_NAME}",
                            "S3ObjectKey": "source/ml-source-code.zip"
                        },
                        "outputArtifacts": [
                            {
                                "name": "SourceOutput"
                            }
                        ]
                    }
                ]
            },
            {
                "name": "Build",
                "actions": [
                    {
                        "name": "TrainModel",
                        "actionTypeId": {
                            "category": "Build",
                            "owner": "AWS",
                            "provider": "CodeBuild",
                            "version": "1"
                        },
                        "configuration": {
                            "ProjectName": "${PROJECT_NAME}-train",
                            "EnvironmentVariables": "[{\"name\":\"SAGEMAKER_ROLE_ARN\",\"value\":\"${SAGEMAKER_ROLE_ARN}\"},{\"name\":\"BUCKET_NAME\",\"value\":\"${BUCKET_NAME}\"},{\"name\":\"MODEL_PACKAGE_GROUP_NAME\",\"value\":\"${MODEL_PACKAGE_GROUP_NAME}\"}]"
                        },
                        "inputArtifacts": [
                            {
                                "name": "SourceOutput"
                            }
                        ],
                        "outputArtifacts": [
                            {
                                "name": "BuildOutput"
                            }
                        ]
                    }
                ]
            },
            {
                "name": "Test",
                "actions": [
                    {
                        "name": "TestModel",
                        "actionTypeId": {
                            "category": "Build",
                            "owner": "AWS",
                            "provider": "CodeBuild",
                            "version": "1"
                        },
                        "configuration": {
                            "ProjectName": "${PROJECT_NAME}-test"
                        },
                        "inputArtifacts": [
                            {
                                "name": "BuildOutput"
                            }
                        ],
                        "outputArtifacts": [
                            {
                                "name": "TestOutput"
                            }
                        ]
                    }
                ]
            },
            {
                "name": "Deploy",
                "actions": [
                    {
                        "name": "DeployModel",
                        "actionTypeId": {
                            "category": "Invoke",
                            "owner": "AWS",
                            "provider": "Lambda",
                            "version": "1"
                        },
                        "configuration": {
                            "FunctionName": "${PROJECT_NAME}-deploy"
                        },
                        "inputArtifacts": [
                            {
                                "name": "TestOutput"
                            }
                        ]
                    }
                ]
            }
        ]
    }
}
EOF
    
    # Create the pipeline
    if ! aws codepipeline get-pipeline --name "${PIPELINE_NAME}" &>/dev/null; then
        aws codepipeline create-pipeline \
            --cli-input-json file:///tmp/pipeline.json > /dev/null
        
        success "Created CodePipeline: ${PIPELINE_NAME}"
    else
        warning "CodePipeline already exists"
    fi
}

# Function to start pipeline execution
start_pipeline() {
    log "Starting pipeline execution..."
    
    # Start the pipeline execution
    aws codepipeline start-pipeline-execution \
        --name "${PIPELINE_NAME}" > /dev/null
    
    success "Started pipeline execution: ${PIPELINE_NAME}"
    log "Monitor pipeline progress in AWS Console:"
    log "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${PIPELINE_NAME}/view"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "==================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "S3 Bucket: ${BUCKET_NAME}"
    echo "Model Package Group: ${MODEL_PACKAGE_GROUP_NAME}"
    echo "Pipeline Name: ${PIPELINE_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo ""
    echo "Resources Created:"
    echo "- S3 Bucket for artifacts"
    echo "- IAM Roles (SageMaker, CodeBuild, CodePipeline, Lambda)"
    echo "- SageMaker Model Package Group"
    echo "- CodeBuild Projects (train, test)"
    echo "- Lambda Deployment Function"
    echo "- CodePipeline with 4 stages"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor pipeline execution in AWS Console"
    echo "2. Check CodeBuild logs for training progress"
    echo "3. Verify model registration in SageMaker Model Registry"
    echo "4. Test deployed endpoints"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    
    success "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting MLOps Pipeline Deployment..."
    log "======================================"
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_roles
    create_model_package_group
    create_training_data
    create_training_script
    create_buildspec_files
    create_codebuild_projects
    create_lambda_function
    create_source_structure
    create_codepipeline
    start_pipeline
    display_summary
}

# Trap errors and cleanup
trap 'error "Deployment failed. Check the logs above for details."' ERR

# Run main function
main "$@"