#!/bin/bash

# ML Pipeline Deployment Script
# This script deploys the complete machine learning pipeline using SageMaker and Step Functions

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI v2"
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
    error "AWS CLI version 2.0.0 or higher required. Current version: $AWS_CLI_VERSION"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'"
    exit 1
fi

# Check Python
if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    error "Python not found. Please install Python 3.x"
    exit 1
fi

# Check required permissions
log "Validating AWS permissions..."
CALLER_IDENTITY=$(aws sts get-caller-identity)
AWS_ACCOUNT_ID=$(echo $CALLER_IDENTITY | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
AWS_USER_ARN=$(echo $CALLER_IDENTITY | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
info "Deploying as: $AWS_USER_ARN"
info "AWS Account ID: $AWS_ACCOUNT_ID"

log "Prerequisites check completed successfully"

# Set environment variables
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    warn "AWS region not configured. Using us-east-1 as default"
    export AWS_REGION="us-east-1"
fi

export AWS_ACCOUNT_ID

# Generate unique identifiers for resources
log "Generating unique resource identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))

export ML_PIPELINE_NAME="ml-pipeline-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="ml-pipeline-bucket-${RANDOM_SUFFIX}"
export SAGEMAKER_ROLE_NAME="SageMakerMLPipelineRole-${RANDOM_SUFFIX}"
export STEP_FUNCTIONS_ROLE_NAME="StepFunctionsMLRole-${RANDOM_SUFFIX}"

info "Using suffix: $RANDOM_SUFFIX"
info "S3 Bucket: $S3_BUCKET_NAME"
info "SageMaker Role: $SAGEMAKER_ROLE_NAME"
info "Step Functions Role: $STEP_FUNCTIONS_ROLE_NAME"

# Create temporary directory for files
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

log "Working in temporary directory: $TEMP_DIR"

# Function to cleanup temp directory
cleanup_temp() {
    log "Cleaning up temporary directory..."
    rm -rf "$TEMP_DIR"
}
trap cleanup_temp EXIT

if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: Would create the following resources:"
    info "- S3 Bucket: $S3_BUCKET_NAME"
    info "- SageMaker Role: $SAGEMAKER_ROLE_NAME"
    info "- Step Functions Role: $STEP_FUNCTIONS_ROLE_NAME"
    info "- Lambda Function: EvaluateModel"
    info "- Step Functions State Machine: $ML_PIPELINE_NAME"
    exit 0
fi

# Create S3 bucket for ML artifacts
log "Creating S3 bucket for ML artifacts..."
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
    warn "S3 bucket $S3_BUCKET_NAME already exists"
else
    aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
    log "S3 bucket created: $S3_BUCKET_NAME"
fi

# Create folder structure in S3
log "Creating S3 folder structure..."
aws s3api put-object --bucket "$S3_BUCKET_NAME" --key raw-data/
aws s3api put-object --bucket "$S3_BUCKET_NAME" --key processed-data/
aws s3api put-object --bucket "$S3_BUCKET_NAME" --key model-artifacts/
aws s3api put-object --bucket "$S3_BUCKET_NAME" --key code/

# Create IAM roles
log "Creating IAM roles..."

# Create SageMaker execution role
log "Creating SageMaker execution role..."
cat > sagemaker-trust-policy.json << EOF
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

if aws iam get-role --role-name "$SAGEMAKER_ROLE_NAME" &>/dev/null; then
    warn "SageMaker role $SAGEMAKER_ROLE_NAME already exists"
else
    aws iam create-role --role-name "$SAGEMAKER_ROLE_NAME" \
        --assume-role-policy-document file://sagemaker-trust-policy.json
    log "SageMaker role created: $SAGEMAKER_ROLE_NAME"
fi

# Attach managed policies to SageMaker role
log "Attaching policies to SageMaker role..."
aws iam attach-role-policy --role-name "$SAGEMAKER_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess || true

aws iam attach-role-policy --role-name "$SAGEMAKER_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess || true

export SAGEMAKER_ROLE_ARN=$(aws iam get-role \
    --role-name "$SAGEMAKER_ROLE_NAME" \
    --query Role.Arn --output text)

log "SageMaker role ARN: $SAGEMAKER_ROLE_ARN"

# Create Step Functions execution role
log "Creating Step Functions execution role..."
cat > step-functions-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "states.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

if aws iam get-role --role-name "$STEP_FUNCTIONS_ROLE_NAME" &>/dev/null; then
    warn "Step Functions role $STEP_FUNCTIONS_ROLE_NAME already exists"
else
    aws iam create-role --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
        --assume-role-policy-document file://step-functions-trust-policy.json
    log "Step Functions role created: $STEP_FUNCTIONS_ROLE_NAME"
fi

# Create custom policy for Step Functions SageMaker integration
log "Creating Step Functions custom policy..."
cat > step-functions-sagemaker-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
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
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "${SAGEMAKER_ROLE_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "*"
    }
  ]
}
EOF

STEP_FUNCTIONS_POLICY_NAME="StepFunctionsSageMakerPolicy-${RANDOM_SUFFIX}"
if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${STEP_FUNCTIONS_POLICY_NAME}" &>/dev/null; then
    warn "Step Functions policy $STEP_FUNCTIONS_POLICY_NAME already exists"
else
    aws iam create-policy --policy-name "$STEP_FUNCTIONS_POLICY_NAME" \
        --policy-document file://step-functions-sagemaker-policy.json
    log "Step Functions policy created: $STEP_FUNCTIONS_POLICY_NAME"
fi

aws iam attach-role-policy --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${STEP_FUNCTIONS_POLICY_NAME}" || true

export STEP_FUNCTIONS_ROLE_ARN=$(aws iam get-role \
    --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
    --query Role.Arn --output text)

log "Step Functions role ARN: $STEP_FUNCTIONS_ROLE_ARN"

# Wait for roles to propagate
log "Waiting for IAM roles to propagate..."
sleep 30

# Create sample training data
log "Creating sample training data..."
cat > generate_sample_data.py << 'EOF'
import pandas as pd
import numpy as np
try:
    from sklearn.datasets import load_boston
    from sklearn.model_selection import train_test_split
    
    # Load Boston Housing dataset
    boston = load_boston()
    X, y = boston.data, boston.target
    
    # Create DataFrame
    df = pd.DataFrame(X, columns=boston.feature_names)
    df['target'] = y
    
    # Split into train and test sets
    train_df, test_df = train_test_split(df, test_size=0.2, random_state=42)
    
    # Save to CSV files
    train_df.to_csv('train.csv', index=False)
    test_df.to_csv('test.csv', index=False)
    
    print(f"Training data shape: {train_df.shape}")
    print(f"Test data shape: {test_df.shape}")
    
except ImportError:
    print("Sklearn not available, creating synthetic data...")
    # Create synthetic data if sklearn is not available
    np.random.seed(42)
    n_samples = 506
    n_features = 13
    
    # Generate random features
    X = np.random.randn(n_samples, n_features)
    # Generate target with some correlation to features
    y = np.sum(X[:, :5], axis=1) + np.random.randn(n_samples) * 0.1
    
    # Create DataFrame
    feature_names = [f'feature_{i}' for i in range(n_features)]
    df = pd.DataFrame(X, columns=feature_names)
    df['target'] = y
    
    # Split into train and test sets
    train_size = int(0.8 * n_samples)
    train_df = df[:train_size]
    test_df = df[train_size:]
    
    # Save to CSV files
    train_df.to_csv('train.csv', index=False)
    test_df.to_csv('test.csv', index=False)
    
    print(f"Training data shape: {train_df.shape}")
    print(f"Test data shape: {test_df.shape}")
EOF

python3 generate_sample_data.py

# Upload data to S3
log "Uploading training data to S3..."
aws s3 cp train.csv "s3://${S3_BUCKET_NAME}/raw-data/"
aws s3 cp test.csv "s3://${S3_BUCKET_NAME}/raw-data/"

# Create preprocessing script
log "Creating preprocessing script..."
cat > preprocessing.py << 'EOF'
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

aws s3 cp preprocessing.py "s3://${S3_BUCKET_NAME}/code/"

# Create training script
log "Creating training script..."
cat > training.py << 'EOF'
import pandas as pd
import numpy as np
import argparse
import os
import joblib
import json
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score
import tarfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAIN'))
    parser.add_argument('--test', type=str, default=os.environ.get('SM_CHANNEL_TEST'))
    parser.add_argument('--output-data-dir', type=str, default=os.environ.get('SM_OUTPUT_DATA_DIR'))
    
    args = parser.parse_args()
    
    # Read training data
    train_df = pd.read_csv(os.path.join(args.train, 'train.csv'))
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

aws s3 cp training.py "s3://${S3_BUCKET_NAME}/code/"

# Create inference script
log "Creating inference script..."
cat > inference.py << 'EOF'
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
        return pd.read_csv(request_body).values
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

aws s3 cp inference.py "s3://${S3_BUCKET_NAME}/code/"

# Create Lambda function for model evaluation
log "Creating Lambda function for model evaluation..."
cat > evaluate_model.py << 'EOF'
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

# Create deployment package
zip -r evaluate_model.zip evaluate_model.py

# Create Lambda function role
LAMBDA_ROLE_NAME="LambdaEvaluateModelRole-${RANDOM_SUFFIX}"
log "Creating Lambda function role..."
if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
    warn "Lambda role $LAMBDA_ROLE_NAME already exists"
else
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
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
        }'
    log "Lambda role created: $LAMBDA_ROLE_NAME"
fi

# Attach policies to Lambda role
aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true

aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess || true

LAMBDA_ROLE_ARN=$(aws iam get-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --query Role.Arn --output text)

# Wait for Lambda role to propagate
log "Waiting for Lambda role to propagate..."
sleep 15

# Create Lambda function
LAMBDA_FUNCTION_NAME="EvaluateModel-${RANDOM_SUFFIX}"
log "Creating Lambda function..."
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
    warn "Lambda function $LAMBDA_FUNCTION_NAME already exists"
else
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler evaluate_model.lambda_handler \
        --zip-file fileb://evaluate_model.zip \
        --timeout 30
    log "Lambda function created: $LAMBDA_FUNCTION_NAME"
fi

# Create Step Functions state machine definition
log "Creating Step Functions state machine definition..."
cat > ml-pipeline-state-machine.json << EOF
{
  "Comment": "ML Pipeline with SageMaker and Step Functions",
  "StartAt": "DataPreprocessing",
  "States": {
    "DataPreprocessing": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sagemaker:createProcessingJob.sync",
      "Parameters": {
        "ProcessingJobName.$": "$.PreprocessingJobName",
        "RoleArn": "${SAGEMAKER_ROLE_ARN}",
        "AppSpecification": {
          "ImageUri": "683313688378.dkr.ecr.${AWS_REGION}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3",
          "ContainerEntrypoint": [
            "python3",
            "/opt/ml/processing/input/code/preprocessing.py"
          ],
          "ContainerArguments": [
            "--input-data",
            "/opt/ml/processing/input/data/train.csv",
            "--output-data",
            "/opt/ml/processing/output/train_processed.csv"
          ]
        },
        "ProcessingInputs": [
          {
            "InputName": "data",
            "S3Input": {
              "S3Uri": "s3://${S3_BUCKET_NAME}/raw-data",
              "LocalPath": "/opt/ml/processing/input/data",
              "S3DataType": "S3Prefix"
            }
          },
          {
            "InputName": "code",
            "S3Input": {
              "S3Uri": "s3://${S3_BUCKET_NAME}/code",
              "LocalPath": "/opt/ml/processing/input/code",
              "S3DataType": "S3Prefix"
            }
          }
        ],
        "ProcessingOutputs": [
          {
            "OutputName": "processed_data",
            "S3Output": {
              "S3Uri": "s3://${S3_BUCKET_NAME}/processed-data",
              "LocalPath": "/opt/ml/processing/output"
            }
          }
        ],
        "ProcessingResources": {
          "ClusterConfig": {
            "InstanceCount": 1,
            "InstanceType": "ml.m5.large",
            "VolumeSizeInGB": 30
          }
        }
      },
      "Next": "ModelTraining",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessingJobFailed"
        }
      ]
    },
    "ModelTraining": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sagemaker:createTrainingJob.sync",
      "Parameters": {
        "TrainingJobName.$": "$.TrainingJobName",
        "RoleArn": "${SAGEMAKER_ROLE_ARN}",
        "AlgorithmSpecification": {
          "TrainingImage": "683313688378.dkr.ecr.${AWS_REGION}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3",
          "TrainingInputMode": "File"
        },
        "InputDataConfig": [
          {
            "ChannelName": "train",
            "DataSource": {
              "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://${S3_BUCKET_NAME}/processed-data",
                "S3DataDistributionType": "FullyReplicated"
              }
            }
          },
          {
            "ChannelName": "test",
            "DataSource": {
              "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://${S3_BUCKET_NAME}/raw-data",
                "S3DataDistributionType": "FullyReplicated"
              }
            }
          },
          {
            "ChannelName": "code",
            "DataSource": {
              "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://${S3_BUCKET_NAME}/code",
                "S3DataDistributionType": "FullyReplicated"
              }
            }
          }
        ],
        "OutputDataConfig": {
          "S3OutputPath": "s3://${S3_BUCKET_NAME}/model-artifacts"
        },
        "ResourceConfig": {
          "InstanceType": "ml.m5.large",
          "InstanceCount": 1,
          "VolumeSizeInGB": 30
        },
        "StoppingCondition": {
          "MaxRuntimeInSeconds": 3600
        },
        "HyperParameters": {
          "sagemaker_program": "training.py",
          "sagemaker_submit_directory": "/opt/ml/input/data/code"
        }
      },
      "Next": "ModelEvaluation",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "TrainingJobFailed"
        }
      ]
    },
    "ModelEvaluation": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${LAMBDA_FUNCTION_NAME}",
        "Payload": {
          "TrainingJobName.$": "$.TrainingJobName",
          "S3Bucket": "${S3_BUCKET_NAME}"
        }
      },
      "Next": "CheckModelPerformance"
    },
    "CheckModelPerformance": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.Payload.body.test_r2",
          "NumericGreaterThan": 0.7,
          "Next": "CreateModel"
        }
      ],
      "Default": "ModelPerformanceInsufficient"
    },
    "CreateModel": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sagemaker:createModel",
      "Parameters": {
        "ModelName.$": "$.ModelName",
        "ExecutionRoleArn": "${SAGEMAKER_ROLE_ARN}",
        "PrimaryContainer": {
          "Image": "683313688378.dkr.ecr.${AWS_REGION}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3",
          "ModelDataUrl.$": "$.ModelDataUrl",
          "Environment": {
            "SAGEMAKER_PROGRAM": "inference.py",
            "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/code"
          }
        }
      },
      "Next": "CreateEndpointConfig"
    },
    "CreateEndpointConfig": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sagemaker:createEndpointConfig",
      "Parameters": {
        "EndpointConfigName.$": "$.EndpointConfigName",
        "ProductionVariants": [
          {
            "VariantName": "primary",
            "ModelName.$": "$.ModelName",
            "InitialInstanceCount": 1,
            "InstanceType": "ml.t2.medium",
            "InitialVariantWeight": 1
          }
        ]
      },
      "Next": "CreateEndpoint"
    },
    "CreateEndpoint": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sagemaker:createEndpoint",
      "Parameters": {
        "EndpointName.$": "$.EndpointName",
        "EndpointConfigName.$": "$.EndpointConfigName"
      },
      "Next": "MLPipelineComplete"
    },
    "MLPipelineComplete": {
      "Type": "Succeed",
      "Result": "ML Pipeline completed successfully"
    },
    "ProcessingJobFailed": {
      "Type": "Fail",
      "Error": "ProcessingJobFailed",
      "Cause": "The data preprocessing job failed"
    },
    "TrainingJobFailed": {
      "Type": "Fail",
      "Error": "TrainingJobFailed",
      "Cause": "The model training job failed"
    },
    "ModelPerformanceInsufficient": {
      "Type": "Fail",
      "Error": "ModelPerformanceInsufficient",
      "Cause": "Model performance does not meet the required threshold"
    }
  }
}
EOF

# Create Step Functions state machine
log "Creating Step Functions state machine..."
if aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${ML_PIPELINE_NAME}" &>/dev/null; then
    warn "State machine $ML_PIPELINE_NAME already exists"
else
    aws stepfunctions create-state-machine \
        --name "$ML_PIPELINE_NAME" \
        --definition file://ml-pipeline-state-machine.json \
        --role-arn "$STEP_FUNCTIONS_ROLE_ARN"
    log "Step Functions state machine created: $ML_PIPELINE_NAME"
fi

# Get state machine ARN
export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --query "stateMachines[?name=='${ML_PIPELINE_NAME}'].stateMachineArn" \
    --output text)

log "Step Functions state machine ARN: $STATE_MACHINE_ARN"

# Save deployment information
log "Saving deployment information..."
cat > ml-pipeline-info.json << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "random_suffix": "${RANDOM_SUFFIX}",
  "s3_bucket_name": "${S3_BUCKET_NAME}",
  "sagemaker_role_name": "${SAGEMAKER_ROLE_NAME}",
  "sagemaker_role_arn": "${SAGEMAKER_ROLE_ARN}",
  "step_functions_role_name": "${STEP_FUNCTIONS_ROLE_NAME}",
  "step_functions_role_arn": "${STEP_FUNCTIONS_ROLE_ARN}",
  "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
  "lambda_role_name": "${LAMBDA_ROLE_NAME}",
  "ml_pipeline_name": "${ML_PIPELINE_NAME}",
  "state_machine_arn": "${STATE_MACHINE_ARN}",
  "step_functions_policy_name": "${STEP_FUNCTIONS_POLICY_NAME}"
}
EOF

# Upload deployment info to S3
aws s3 cp ml-pipeline-info.json "s3://${S3_BUCKET_NAME}/deployment-info/"

log "✅ ML Pipeline deployment completed successfully!"
info ""
info "Deployment Summary:"
info "===================="
info "Region: $AWS_REGION"
info "S3 Bucket: $S3_BUCKET_NAME"
info "State Machine: $ML_PIPELINE_NAME"
info "State Machine ARN: $STATE_MACHINE_ARN"
info "Lambda Function: $LAMBDA_FUNCTION_NAME"
info ""
info "Next Steps:"
info "1. Execute the pipeline using the Step Functions console or CLI"
info "2. Monitor pipeline execution in the Step Functions console"
info "3. View logs in CloudWatch Logs"
info "4. Test the deployed model endpoint when pipeline completes"
info ""
info "To execute the pipeline, use:"
info "aws stepfunctions start-execution --state-machine-arn $STATE_MACHINE_ARN --name execution-\$(date +%Y%m%d%H%M%S) --input '{\"PreprocessingJobName\":\"preprocessing-\$(date +%Y%m%d%H%M%S)\",\"TrainingJobName\":\"training-\$(date +%Y%m%d%H%M%S)\",\"ModelName\":\"model-\$(date +%Y%m%d%H%M%S)\",\"EndpointConfigName\":\"endpoint-config-\$(date +%Y%m%d%H%M%S)\",\"EndpointName\":\"endpoint-\$(date +%Y%m%d%H%M%S)\",\"ModelDataUrl\":\"s3://${S3_BUCKET_NAME}/model-artifacts/training-\$(date +%Y%m%d%H%M%S)/output/model.tar.gz\"}'"
info ""
warn "Remember to run ./destroy.sh when you're done to avoid ongoing charges!"