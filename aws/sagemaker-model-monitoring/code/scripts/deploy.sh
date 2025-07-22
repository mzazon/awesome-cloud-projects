#!/bin/bash

# Deploy script for Model Monitoring and Drift Detection with SageMaker Model Monitor
# This script automates the deployment of the complete monitoring infrastructure

set -euo pipefail

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
    if [[ "$AWS_CLI_VERSION" -lt 2 ]]; then
        error "AWS CLI v2 is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions (basic check)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export MODEL_MONITOR_ROLE_NAME="ModelMonitorRole-${RANDOM_SUFFIX}"
    export MODEL_MONITOR_BUCKET="model-monitor-${RANDOM_SUFFIX}"
    export MONITORING_SCHEDULE_NAME="model-monitor-schedule-${RANDOM_SUFFIX}"
    export BASELINE_JOB_NAME="model-monitor-baseline-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="model-monitor-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="model-monitor-handler-${RANDOM_SUFFIX}"
    export MODEL_NAME="demo-model-${RANDOM_SUFFIX}"
    export ENDPOINT_CONFIG_NAME="demo-endpoint-config-${RANDOM_SUFFIX}"
    export ENDPOINT_NAME="demo-endpoint-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="ModelMonitorLambdaRole-${RANDOM_SUFFIX}"
    export MODEL_QUALITY_SCHEDULE_NAME="model-quality-schedule-${RANDOM_SUFFIX}"
    
    success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
}

# Create S3 bucket and directory structure
create_s3_resources() {
    log "Creating S3 bucket and directory structure..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$MODEL_MONITOR_BUCKET" 2>/dev/null; then
        warning "Bucket $MODEL_MONITOR_BUCKET already exists, skipping creation"
    else
        # Create bucket with appropriate configuration
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://${MODEL_MONITOR_BUCKET}"
        else
            aws s3 mb "s3://${MODEL_MONITOR_BUCKET}" --region "$AWS_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$MODEL_MONITOR_BUCKET" \
            --versioning-configuration Status=Enabled
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$MODEL_MONITOR_BUCKET" \
            --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    fi
    
    # Create directory structure
    aws s3api put-object --bucket "$MODEL_MONITOR_BUCKET" --key baseline-data/ || true
    aws s3api put-object --bucket "$MODEL_MONITOR_BUCKET" --key captured-data/ || true
    aws s3api put-object --bucket "$MODEL_MONITOR_BUCKET" --key monitoring-results/ || true
    
    success "S3 resources created"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Model Monitor role
    if aws iam get-role --role-name "$MODEL_MONITOR_ROLE_NAME" &>/dev/null; then
        warning "IAM role $MODEL_MONITOR_ROLE_NAME already exists, skipping creation"
    else
        cat > /tmp/model-monitor-trust-policy.json << 'EOF'
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
        
        aws iam create-role \
            --role-name "$MODEL_MONITOR_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/model-monitor-trust-policy.json
        
        # Attach managed policy
        aws iam attach-role-policy \
            --role-name "$MODEL_MONITOR_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
        
        # Create custom policy
        cat > /tmp/model-monitor-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${MODEL_MONITOR_BUCKET}",
        "arn:aws:s3:::${MODEL_MONITOR_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "$MODEL_MONITOR_ROLE_NAME" \
            --policy-name ModelMonitorCustomPolicy \
            --policy-document file:///tmp/model-monitor-policy.json
        
        # Wait for role to be ready
        sleep 10
    fi
    
    export MODEL_MONITOR_ROLE_ARN=$(aws iam get-role \
        --role-name "$MODEL_MONITOR_ROLE_NAME" \
        --query Role.Arn --output text)
    
    success "Model Monitor IAM role created: $MODEL_MONITOR_ROLE_ARN"
}

# Create and deploy sample model
deploy_sample_model() {
    log "Creating and deploying sample model..."
    
    # Create model artifacts directory
    mkdir -p /tmp/model-artifacts
    
    # Create inference script
    cat > /tmp/model-artifacts/inference.py << 'EOF'
import joblib
import json
import numpy as np

def model_fn(model_dir):
    # Load a simple model (for demo purposes)
    return {"type": "demo_model"}

def input_fn(request_body, request_content_type):
    if request_content_type == 'application/json':
        data = json.loads(request_body)
        return np.array(data['instances'])
    else:
        raise ValueError(f"Unsupported content type: {request_content_type}")

def predict_fn(input_data, model):
    # Simple prediction logic for demo
    predictions = np.random.random(len(input_data))
    return predictions

def output_fn(prediction, content_type):
    if content_type == 'application/json':
        return json.dumps({"predictions": prediction.tolist()})
    else:
        raise ValueError(f"Unsupported content type: {content_type}")
EOF
    
    # Create model tarball
    cd /tmp/model-artifacts
    tar -czf model.tar.gz inference.py
    cd - > /dev/null
    
    # Upload model to S3
    aws s3 cp /tmp/model-artifacts/model.tar.gz \
        "s3://${MODEL_MONITOR_BUCKET}/model-artifacts/model.tar.gz"
    
    # Check if model already exists
    if aws sagemaker describe-model --model-name "$MODEL_NAME" &>/dev/null; then
        warning "Model $MODEL_NAME already exists, skipping creation"
    else
        # Create SageMaker model
        aws sagemaker create-model \
            --model-name "$MODEL_NAME" \
            --primary-container "Image=763104351884.dkr.ecr.${AWS_REGION}.amazonaws.com/sklearn-inference:0.23-1-cpu-py3,ModelDataUrl=s3://${MODEL_MONITOR_BUCKET}/model-artifacts/model.tar.gz" \
            --execution-role-arn "$MODEL_MONITOR_ROLE_ARN"
    fi
    
    # Check if endpoint config already exists
    if aws sagemaker describe-endpoint-config --endpoint-config-name "$ENDPOINT_CONFIG_NAME" &>/dev/null; then
        warning "Endpoint config $ENDPOINT_CONFIG_NAME already exists, skipping creation"
    else
        # Create endpoint configuration with data capture
        aws sagemaker create-endpoint-config \
            --endpoint-config-name "$ENDPOINT_CONFIG_NAME" \
            --production-variants "VariantName=Primary,ModelName=${MODEL_NAME},InitialInstanceCount=1,InstanceType=ml.t2.medium,InitialVariantWeight=1.0" \
            --data-capture-config "EnableCapture=true,InitialSamplingPercentage=100,DestinationS3Uri=s3://${MODEL_MONITOR_BUCKET}/captured-data,KmsKeyId=,CaptureOptions=[{CaptureMode=Input},{CaptureMode=Output}],CaptureContentTypeHeader={}"
    fi
    
    # Check if endpoint already exists
    if aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" &>/dev/null; then
        warning "Endpoint $ENDPOINT_NAME already exists, checking status"
        ENDPOINT_STATUS=$(aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --query EndpointStatus --output text)
        if [[ "$ENDPOINT_STATUS" != "InService" ]]; then
            log "Waiting for existing endpoint to be in service..."
            aws sagemaker wait endpoint-in-service --endpoint-name "$ENDPOINT_NAME"
        fi
    else
        # Create endpoint
        aws sagemaker create-endpoint \
            --endpoint-name "$ENDPOINT_NAME" \
            --endpoint-config-name "$ENDPOINT_CONFIG_NAME"
        
        log "Waiting for endpoint to be in service (this may take 5-10 minutes)..."
        aws sagemaker wait endpoint-in-service --endpoint-name "$ENDPOINT_NAME"
    fi
    
    success "Sample model deployed: $ENDPOINT_NAME"
}

# Create baseline statistics
create_baseline() {
    log "Creating baseline statistics and constraints..."
    
    # Create sample baseline data
    cat > /tmp/baseline-data.csv << 'EOF'
feature_1,feature_2,feature_3,target
0.1,0.2,0.3,0.15
0.2,0.3,0.4,0.25
0.3,0.4,0.5,0.35
0.4,0.5,0.6,0.45
0.5,0.6,0.7,0.55
0.6,0.7,0.8,0.65
0.7,0.8,0.9,0.75
0.8,0.9,1.0,0.85
0.9,1.0,1.1,0.95
1.0,1.1,1.2,1.05
EOF
    
    # Upload baseline data to S3
    aws s3 cp /tmp/baseline-data.csv \
        "s3://${MODEL_MONITOR_BUCKET}/baseline-data/baseline-data.csv"
    
    # Check if baseline job already exists
    if aws sagemaker describe-processing-job --processing-job-name "$BASELINE_JOB_NAME" &>/dev/null; then
        warning "Baseline job $BASELINE_JOB_NAME already exists, skipping creation"
    else
        # Create baseline job
        aws sagemaker create-processing-job \
            --processing-job-name "$BASELINE_JOB_NAME" \
            --processing-inputs "Source=s3://${MODEL_MONITOR_BUCKET}/baseline-data,Destination=/opt/ml/processing/input,S3DataType=S3Prefix,S3InputMode=File,S3DataDistributionType=FullyReplicated,S3CompressionType=None" \
            --processing-output-config "Outputs=[{OutputName=statistics,S3Output={S3Uri=s3://${MODEL_MONITOR_BUCKET}/monitoring-results/statistics,LocalPath=/opt/ml/processing/output/statistics,S3UploadMode=EndOfJob}},{OutputName=constraints,S3Output={S3Uri=s3://${MODEL_MONITOR_BUCKET}/monitoring-results/constraints,LocalPath=/opt/ml/processing/output/constraints,S3UploadMode=EndOfJob}}]" \
            --app-specification "ImageUri=159807026194.dkr.ecr.${AWS_REGION}.amazonaws.com/sagemaker-model-monitor-analyzer:latest" \
            --role-arn "$MODEL_MONITOR_ROLE_ARN" \
            --processing-resources "ClusterConfig={InstanceType=ml.m5.xlarge,InstanceCount=1,VolumeSizeInGB=20}"
        
        log "Waiting for baseline job to complete (this may take 10-15 minutes)..."
        aws sagemaker wait processing-job-completed-or-stopped \
            --processing-job-name "$BASELINE_JOB_NAME"
    fi
    
    # Check job status
    JOB_STATUS=$(aws sagemaker describe-processing-job \
        --processing-job-name "$BASELINE_JOB_NAME" \
        --query 'ProcessingJobStatus' --output text)
    
    if [[ "$JOB_STATUS" == "Completed" ]]; then
        success "Baseline statistics and constraints created"
    else
        error "Baseline job failed with status: $JOB_STATUS"
        exit 1
    fi
}

# Generate sample traffic
generate_sample_traffic() {
    log "Generating sample traffic..."
    
    # Create sample inference data
    cat > /tmp/sample-requests.json << 'EOF'
{"instances": [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], [0.7, 0.8, 0.9]]}
EOF
    
    # Send several requests to generate captured data
    for i in {1..10}; do
        aws sagemaker-runtime invoke-endpoint \
            --endpoint-name "$ENDPOINT_NAME" \
            --content-type application/json \
            --body "fileb:///tmp/sample-requests.json" \
            "/tmp/response-${i}.json" >/dev/null
        
        # Add some variation to the data
        python3 -c "
import json
import random
data = {'instances': [[random.uniform(0, 1), random.uniform(0, 1), random.uniform(0, 1)] for _ in range(3)]}
with open('/tmp/sample-requests.json', 'w') as f:
    json.dump(data, f)
"
        sleep 2
    done
    
    # Wait for data capture to process
    log "Waiting for data capture to process..."
    sleep 30
    
    success "Sample traffic generated and captured"
}

# Create SNS topic and Lambda function
create_alerting() {
    log "Creating SNS topic and Lambda function..."
    
    # Create SNS topic
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &>/dev/null; then
        warning "SNS topic $SNS_TOPIC_NAME already exists"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    else
        export SNS_TOPIC_ARN=$(aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --query TopicArn --output text)
    fi
    
    # Prompt for email subscription
    if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
        read -p "Enter your email address for alerts (or press Enter to skip): " EMAIL_ADDRESS
    fi
    
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS" >/dev/null || true
        log "Email subscription created. Check your email and confirm the subscription."
    fi
    
    # Create Lambda role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        warning "Lambda role $LAMBDA_ROLE_NAME already exists"
    else
        cat > /tmp/lambda-trust-policy.json << 'EOF'
{
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
}
EOF
        
        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        cat > /tmp/lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${SNS_TOPIC_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeMonitoringSchedule",
        "sagemaker:DescribeProcessingJob"
      ],
      "Resource": "*"
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name ModelMonitorLambdaPolicy \
            --policy-document file:///tmp/lambda-policy.json
        
        sleep 10
    fi
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query Role.Arn --output text)
    
    # Create Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        warning "Lambda function $LAMBDA_FUNCTION_NAME already exists"
    else
        cat > /tmp/lambda-function.py << 'EOF'
import json
import boto3
import os

def lambda_handler(event, context):
    """
    Lambda function to handle Model Monitor alerts
    """
    sns = boto3.client('sns')
    sagemaker = boto3.client('sagemaker')
    
    # Parse the CloudWatch alarm from SNS
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    alarm_name = message['AlarmName']
    alarm_description = message['AlarmDescription']
    new_state = message['NewStateValue']
    
    print(f"Received alarm: {alarm_name} - {new_state}")
    
    # Check if this is a model drift alarm
    if new_state == 'ALARM' and 'ModelMonitor' in alarm_name:
        # Log the drift detection
        print(f"Model drift detected: {alarm_description}")
        
        # Send notification
        notification_message = f"""
Model Monitor Alert:

Alarm: {alarm_name}
Status: {new_state}
Description: {alarm_description}

Action Required: Review monitoring results and consider retraining the model.
"""
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Model Monitor Alert - Action Required',
            Message=notification_message
        )
        
        # Additional automated actions could be added here:
        # - Trigger model retraining pipeline
        # - Update model endpoint configuration
        # - Send alerts to monitoring systems
        
    return {
        'statusCode': 200,
        'body': json.dumps('Alert processed successfully')
    }
EOF
        
        cd /tmp
        zip lambda-function.zip lambda-function.py
        cd - > /dev/null
        
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler lambda-function.lambda_handler \
            --zip-file "fileb:///tmp/lambda-function.zip" \
            --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
    fi
    
    success "SNS topic and Lambda function created"
}

# Create monitoring schedules
create_monitoring_schedules() {
    log "Creating monitoring schedules..."
    
    # Create data quality monitoring schedule
    if aws sagemaker describe-monitoring-schedule --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" &>/dev/null; then
        warning "Monitoring schedule $MONITORING_SCHEDULE_NAME already exists"
    else
        cat > /tmp/monitoring-schedule-config.json << EOF
{
  "MonitoringScheduleName": "${MONITORING_SCHEDULE_NAME}",
  "MonitoringScheduleConfig": {
    "ScheduleConfig": {
      "ScheduleExpression": "cron(0 * * * ? *)"
    },
    "MonitoringJobDefinition": {
      "MonitoringInputs": [
        {
          "EndpointInput": {
            "EndpointName": "${ENDPOINT_NAME}",
            "LocalPath": "/opt/ml/processing/input/endpoint",
            "S3InputMode": "File",
            "S3DataDistributionType": "FullyReplicated"
          }
        }
      ],
      "MonitoringOutputConfig": {
        "MonitoringOutputs": [
          {
            "S3Output": {
              "S3Uri": "s3://${MODEL_MONITOR_BUCKET}/monitoring-results/data-quality",
              "LocalPath": "/opt/ml/processing/output",
              "S3UploadMode": "EndOfJob"
            }
          }
        ]
      },
      "MonitoringResources": {
        "ClusterConfig": {
          "InstanceType": "ml.m5.xlarge",
          "InstanceCount": 1,
          "VolumeSizeInGB": 20
        }
      },
      "MonitoringAppSpecification": {
        "ImageUri": "159807026194.dkr.ecr.${AWS_REGION}.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
      },
      "BaselineConfig": {
        "StatisticsResource": {
          "S3Uri": "s3://${MODEL_MONITOR_BUCKET}/monitoring-results/statistics"
        },
        "ConstraintsResource": {
          "S3Uri": "s3://${MODEL_MONITOR_BUCKET}/monitoring-results/constraints"
        }
      },
      "RoleArn": "${MODEL_MONITOR_ROLE_ARN}"
    }
  }
}
EOF
        
        aws sagemaker create-monitoring-schedule \
            --cli-input-json file:///tmp/monitoring-schedule-config.json
    fi
    
    # Create model quality monitoring schedule
    if aws sagemaker describe-monitoring-schedule --monitoring-schedule-name "$MODEL_QUALITY_SCHEDULE_NAME" &>/dev/null; then
        warning "Model quality schedule $MODEL_QUALITY_SCHEDULE_NAME already exists"
    else
        cat > /tmp/model-quality-schedule.json << EOF
{
  "MonitoringScheduleName": "${MODEL_QUALITY_SCHEDULE_NAME}",
  "MonitoringScheduleConfig": {
    "ScheduleConfig": {
      "ScheduleExpression": "cron(0 6 * * ? *)"
    },
    "MonitoringJobDefinition": {
      "MonitoringInputs": [
        {
          "EndpointInput": {
            "EndpointName": "${ENDPOINT_NAME}",
            "LocalPath": "/opt/ml/processing/input/endpoint",
            "S3InputMode": "File",
            "S3DataDistributionType": "FullyReplicated"
          }
        }
      ],
      "MonitoringOutputConfig": {
        "MonitoringOutputs": [
          {
            "S3Output": {
              "S3Uri": "s3://${MODEL_MONITOR_BUCKET}/monitoring-results/model-quality",
              "LocalPath": "/opt/ml/processing/output",
              "S3UploadMode": "EndOfJob"
            }
          }
        ]
      },
      "MonitoringResources": {
        "ClusterConfig": {
          "InstanceType": "ml.m5.xlarge",
          "InstanceCount": 1,
          "VolumeSizeInGB": 20
        }
      },
      "MonitoringAppSpecification": {
        "ImageUri": "159807026194.dkr.ecr.${AWS_REGION}.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
      },
      "RoleArn": "${MODEL_MONITOR_ROLE_ARN}"
    }
  }
}
EOF
        
        aws sagemaker create-monitoring-schedule \
            --cli-input-json file:///tmp/model-quality-schedule.json
    fi
    
    success "Monitoring schedules created"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create alarm for constraint violations
    aws cloudwatch put-metric-alarm \
        --alarm-name "ModelMonitor-ConstraintViolations-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when model monitor detects constraint violations" \
        --metric-name "constraint_violations" \
        --namespace "AWS/SageMaker/ModelMonitor" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions "Name=MonitoringSchedule,Value=${MONITORING_SCHEDULE_NAME}" || true
    
    # Create alarm for monitoring job failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "ModelMonitor-JobFailures-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when model monitor jobs fail" \
        --metric-name "monitoring_job_failures" \
        --namespace "AWS/SageMaker/ModelMonitor" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions "Name=MonitoringSchedule,Value=${MONITORING_SCHEDULE_NAME}" || true
    
    # Subscribe Lambda to SNS topic
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol lambda \
        --notification-endpoint "$LAMBDA_ARN" || true
    
    # Add permission for SNS to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id sns-invoke \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "$SNS_TOPIC_ARN" || true
    
    success "CloudWatch alarms created"
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    cat > /tmp/dashboard-config.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/SageMaker/ModelMonitor", "constraint_violations", "MonitoringSchedule", "${MONITORING_SCHEDULE_NAME}" ],
          [ ".", "monitoring_job_failures", ".", "." ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Model Monitor Metrics"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/sagemaker/ProcessingJobs' | fields @timestamp, @message | filter @message like /constraint/",
        "region": "${AWS_REGION}",
        "title": "Model Monitor Logs"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "ModelMonitor-Dashboard-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-config.json || true
    
    success "CloudWatch dashboard created"
}

# Test the monitoring system
test_monitoring() {
    log "Testing the monitoring system..."
    
    # Start monitoring schedule manually
    aws sagemaker start-monitoring-schedule \
        --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" || true
    
    # Generate anomalous data
    python3 -c "
import json
import random

# Create significantly different data patterns
anomalous_data = {
    'instances': [
        [random.uniform(10, 20), random.uniform(10, 20), random.uniform(10, 20)]
        for _ in range(5)
    ]
}

with open('/tmp/anomalous-requests.json', 'w') as f:
    json.dump(anomalous_data, f)
"
    
    # Send anomalous requests
    for i in {1..5}; do
        aws sagemaker-runtime invoke-endpoint \
            --endpoint-name "$ENDPOINT_NAME" \
            --content-type application/json \
            --body "fileb:///tmp/anomalous-requests.json" \
            "/tmp/anomalous-response-${i}.json" >/dev/null || true
        sleep 1
    done
    
    success "Monitoring system tested with anomalous data"
}

# Save environment variables for cleanup
save_environment() {
    log "Saving environment variables for cleanup..."
    
    cat > /tmp/model-monitor-env.sh << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export MODEL_MONITOR_ROLE_NAME="$MODEL_MONITOR_ROLE_NAME"
export MODEL_MONITOR_BUCKET="$MODEL_MONITOR_BUCKET"
export MONITORING_SCHEDULE_NAME="$MONITORING_SCHEDULE_NAME"
export BASELINE_JOB_NAME="$BASELINE_JOB_NAME"
export SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
export MODEL_NAME="$MODEL_NAME"
export ENDPOINT_CONFIG_NAME="$ENDPOINT_CONFIG_NAME"
export ENDPOINT_NAME="$ENDPOINT_NAME"
export LAMBDA_ROLE_NAME="$LAMBDA_ROLE_NAME"
export MODEL_QUALITY_SCHEDULE_NAME="$MODEL_QUALITY_SCHEDULE_NAME"
export SNS_TOPIC_ARN="$SNS_TOPIC_ARN"
export MODEL_MONITOR_ROLE_ARN="$MODEL_MONITOR_ROLE_ARN"
export LAMBDA_ROLE_ARN="$LAMBDA_ROLE_ARN"
export LAMBDA_ARN="$LAMBDA_ARN"
EOF
    
    success "Environment variables saved to /tmp/model-monitor-env.sh"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f /tmp/model-monitor-*.json /tmp/lambda-*.json /tmp/lambda-*.py /tmp/lambda-*.zip
    rm -f /tmp/baseline-data.csv /tmp/sample-requests.json /tmp/anomalous-requests.json
    rm -f /tmp/*response*.json /tmp/dashboard-config.json
    rm -rf /tmp/model-artifacts
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting Model Monitor deployment..."
    
    # Deployment steps
    check_prerequisites
    set_environment
    create_s3_resources
    create_iam_roles
    deploy_sample_model
    create_baseline
    generate_sample_traffic
    create_alerting
    create_monitoring_schedules
    create_cloudwatch_alarms
    create_dashboard
    test_monitoring
    save_environment
    cleanup_temp_files
    
    success "Model Monitor deployment completed successfully!"
    
    log "Deployment Summary:"
    log "- S3 Bucket: $MODEL_MONITOR_BUCKET"
    log "- SageMaker Endpoint: $ENDPOINT_NAME"
    log "- Monitoring Schedule: $MONITORING_SCHEDULE_NAME"
    log "- SNS Topic: $SNS_TOPIC_ARN"
    log "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "- CloudWatch Dashboard: ModelMonitor-Dashboard-${RANDOM_SUFFIX}"
    
    warning "Note: Monitoring jobs may take 20-30 minutes to complete."
    warning "Check your email for SNS subscription confirmation if you provided an email address."
    
    log "To clean up resources, run: ./destroy.sh"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi