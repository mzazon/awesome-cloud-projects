#!/bin/bash

# AWS AutoML Solutions with SageMaker Autopilot - Deployment Script
# This script deploys the complete AutoML solution including S3 bucket, IAM roles, 
# SageMaker Autopilot job, and real-time inference endpoint

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    error "Deployment failed. Cleaning up partially created resources..."
    
    # Stop monitoring if running
    if [[ -n "${MONITOR_PID:-}" ]]; then
        kill "${MONITOR_PID}" 2>/dev/null || true
    fi
    
    # Clean up resources in reverse order
    if [[ -n "${ENDPOINT_NAME:-}" ]]; then
        aws sagemaker delete-endpoint --endpoint-name "${ENDPOINT_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${ENDPOINT_CONFIG_NAME:-}" ]]; then
        aws sagemaker delete-endpoint-config --endpoint-config-name "${ENDPOINT_CONFIG_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${MODEL_NAME:-}" ]]; then
        aws sagemaker delete-model --model-name "${MODEL_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${S3_BUCKET_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess 2>/dev/null || true
        aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" 2>/dev/null || true
    fi
    
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "${account_id}" ]]; then
        error "Unable to get AWS account ID. Check your credentials."
        exit 1
    fi
    
    # Check jq installation
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some output formatting may be limited."
    fi
    
    log "Prerequisites check completed successfully"
}

# Generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix
    if ! RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null); then
        # Fallback to date-based suffix if secrets manager fails
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AUTOPILOT_JOB_NAME="autopilot-ml-job-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="sagemaker-autopilot-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="SageMakerAutopilotRole-${RANDOM_SUFFIX}"
    export MODEL_NAME="autopilot-model-${RANDOM_SUFFIX}"
    export ENDPOINT_CONFIG_NAME="autopilot-endpoint-config-${RANDOM_SUFFIX}"
    export ENDPOINT_NAME="autopilot-endpoint-${RANDOM_SUFFIX}"
    export TRANSFORM_JOB_NAME="autopilot-batch-transform-${RANDOM_SUFFIX}"
    
    log "Resource names generated with suffix: ${RANDOM_SUFFIX}"
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket: ${S3_BUCKET_NAME}"
    
    # Create bucket with appropriate region settings
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    log "S3 bucket created successfully: ${S3_BUCKET_NAME}"
}

# Create IAM role
create_iam_role() {
    log "Creating IAM role: ${IAM_ROLE_NAME}"
    
    # Create role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
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
        }' \
        --tags Key=Purpose,Value=AutoML-Demo Key=Environment,Value=Development
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 10
    
    log "IAM role created successfully: ${ROLE_ARN}"
}

# Prepare sample dataset
prepare_dataset() {
    log "Preparing sample dataset..."
    
    # Create sample customer churn dataset
    cat > churn_dataset.csv << 'EOF'
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
11,26,2,35.40,70.80,Month-to-month,Electronic check,Yes
12,47,24,89.50,2148.00,One year,Credit card,No
13,39,36,105.20,3787.20,Two year,Bank transfer,No
14,32,8,52.75,422.00,Month-to-month,Electronic check,Yes
15,44,60,118.90,7134.00,Two year,Credit card,No
16,28,4,41.85,167.40,Month-to-month,Electronic check,Yes
17,51,48,92.35,4432.80,Two year,Bank transfer,No
18,36,12,68.40,820.80,One year,Credit card,No
19,43,6,48.25,289.50,Month-to-month,Electronic check,Yes
20,30,72,132.45,9536.40,Two year,Credit card,No
EOF
    
    # Upload dataset to S3
    aws s3 cp churn_dataset.csv \
        "s3://${S3_BUCKET_NAME}/input/churn_dataset.csv"
    
    log "Sample dataset uploaded to S3"
}

# Create AutoML job
create_autopilot_job() {
    log "Creating AutoML job configuration..."
    
    # Create job configuration
    cat > autopilot_job_config.json << EOF
{
    "AutoMLJobName": "${AUTOPILOT_JOB_NAME}",
    "AutoMLJobInputDataConfig": [
        {
            "ChannelType": "training",
            "ContentType": "text/csv;header=present",
            "CompressionType": "None",
            "DataSource": {
                "S3DataSource": {
                    "S3DataType": "S3Prefix",
                    "S3Uri": "s3://${S3_BUCKET_NAME}/input/"
                }
            }
        }
    ],
    "OutputDataConfig": {
        "S3OutputPath": "s3://${S3_BUCKET_NAME}/output/"
    },
    "AutoMLProblemTypeConfig": {
        "TabularJobConfig": {
            "TargetAttributeName": "churn",
            "ProblemType": "BinaryClassification",
            "CompletionCriteria": {
                "MaxCandidates": 10,
                "MaxRuntimePerTrainingJobInSeconds": 3600,
                "MaxAutoMLJobRuntimeInSeconds": 14400
            }
        }
    },
    "RoleArn": "${ROLE_ARN}",
    "Tags": [
        {
            "Key": "Purpose",
            "Value": "AutoML-Demo"
        },
        {
            "Key": "Environment",
            "Value": "Development"
        }
    ]
}
EOF
    
    # Launch AutoML job
    log "Launching SageMaker Autopilot job: ${AUTOPILOT_JOB_NAME}"
    aws sagemaker create-auto-ml-job-v2 \
        --cli-input-json file://autopilot_job_config.json
    
    log "AutoML job launched successfully"
}

# Monitor job progress
monitor_autopilot_job() {
    log "Starting AutoML job monitoring..."
    
    local max_wait_time=14400  # 4 hours max wait time
    local wait_interval=300    # 5 minutes between checks
    local elapsed_time=0
    
    while [[ ${elapsed_time} -lt ${max_wait_time} ]]; do
        local status
        status=$(aws sagemaker describe-auto-ml-job-v2 \
            --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
            --query 'AutoMLJobStatus' \
            --output text 2>/dev/null || echo "Unknown")
        
        info "AutoML job status: ${status} (${elapsed_time}s elapsed)"
        
        case "${status}" in
            "Completed")
                log "AutoML job completed successfully"
                return 0
                ;;
            "Failed")
                error "AutoML job failed"
                return 1
                ;;
            "Stopped")
                error "AutoML job was stopped"
                return 1
                ;;
            "InProgress")
                info "Job is still running. Waiting ${wait_interval} seconds..."
                sleep ${wait_interval}
                elapsed_time=$((elapsed_time + wait_interval))
                ;;
            *)
                info "Job status: ${status}. Waiting ${wait_interval} seconds..."
                sleep ${wait_interval}
                elapsed_time=$((elapsed_time + wait_interval))
                ;;
        esac
    done
    
    error "AutoML job timed out after ${max_wait_time} seconds"
    return 1
}

# Get best model information
get_best_model() {
    log "Retrieving best model information..."
    
    # Get best candidate
    local best_candidate
    best_candidate=$(aws sagemaker describe-auto-ml-job-v2 \
        --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
        --query 'BestCandidate.CandidateName' \
        --output text)
    
    info "Best candidate: ${best_candidate}"
    
    # Get model performance metrics
    aws sagemaker describe-auto-ml-job-v2 \
        --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
        --query 'BestCandidate.FinalAutoMLJobObjectiveMetric' \
        --output table
    
    log "Best model information retrieved"
}

# Download generated artifacts
download_artifacts() {
    log "Downloading generated notebooks and reports..."
    
    # Create local directory
    mkdir -p ./autopilot_artifacts/
    
    # Download notebooks
    aws s3 sync "s3://${S3_BUCKET_NAME}/output/" ./autopilot_artifacts/ \
        --exclude "*" --include "*.ipynb"
    
    # Download explainability reports
    aws s3 sync "s3://${S3_BUCKET_NAME}/output/" ./autopilot_artifacts/ \
        --exclude "*" --include "*explainability*"
    
    log "Artifacts downloaded to ./autopilot_artifacts/"
}

# Create and deploy model
deploy_model() {
    log "Creating SageMaker model..."
    
    # Get model artifact URL
    local model_artifact_url
    model_artifact_url=$(aws sagemaker describe-auto-ml-job-v2 \
        --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
        --query 'BestCandidate.ModelInsights.ModelArtifactUrl' \
        --output text)
    
    # Get inference container image
    local inference_image
    inference_image=$(aws sagemaker describe-auto-ml-job-v2 \
        --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
        --query 'BestCandidate.InferenceContainers[0].Image' \
        --output text)
    
    # Create model
    aws sagemaker create-model \
        --model-name "${MODEL_NAME}" \
        --primary-container Image="${inference_image}",ModelDataUrl="${model_artifact_url}" \
        --execution-role-arn "${ROLE_ARN}" \
        --tags Key=Purpose,Value=AutoML-Demo Key=Environment,Value=Development
    
    log "Model created: ${MODEL_NAME}"
    
    # Create endpoint configuration
    log "Creating endpoint configuration..."
    aws sagemaker create-endpoint-config \
        --endpoint-config-name "${ENDPOINT_CONFIG_NAME}" \
        --production-variants \
        VariantName=primary,ModelName="${MODEL_NAME}",InitialInstanceCount=1,InstanceType=ml.m5.large \
        --tags Key=Purpose,Value=AutoML-Demo Key=Environment,Value=Development
    
    log "Endpoint configuration created: ${ENDPOINT_CONFIG_NAME}"
    
    # Create endpoint
    log "Creating endpoint (this may take 5-10 minutes)..."
    aws sagemaker create-endpoint \
        --endpoint-name "${ENDPOINT_NAME}" \
        --endpoint-config-name "${ENDPOINT_CONFIG_NAME}" \
        --tags Key=Purpose,Value=AutoML-Demo Key=Environment,Value=Development
    
    # Wait for endpoint to be in service
    info "Waiting for endpoint to be in service..."
    aws sagemaker wait endpoint-in-service \
        --endpoint-name "${ENDPOINT_NAME}"
    
    log "Endpoint is now in service: ${ENDPOINT_NAME}"
}

# Test model inference
test_inference() {
    log "Testing model inference..."
    
    # Create test data
    cat > test_data.csv << 'EOF'
25,6,45.20,271.20,Month-to-month,Electronic check
55,36,89.15,3209.40,Two year,Mailed check
EOF
    
    # Test inference
    aws sagemaker-runtime invoke-endpoint \
        --endpoint-name "${ENDPOINT_NAME}" \
        --content-type text/csv \
        --body fileb://test_data.csv \
        prediction_output.json
    
    # Display results
    info "Prediction results:"
    if command -v jq &> /dev/null; then
        cat prediction_output.json | jq '.'
    else
        cat prediction_output.json
    fi
    
    log "Model inference test completed successfully"
}

# Create batch transform job
create_batch_transform() {
    log "Creating batch transform job..."
    
    # Upload test data for batch processing
    aws s3 cp test_data.csv \
        "s3://${S3_BUCKET_NAME}/batch-input/test_data.csv"
    
    # Create batch transform job
    aws sagemaker create-transform-job \
        --transform-job-name "${TRANSFORM_JOB_NAME}" \
        --model-name "${MODEL_NAME}" \
        --transform-input DataSource='{
            "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://'${S3_BUCKET_NAME}'/batch-input/"
            }
        }',ContentType=text/csv,CompressionType=None,SplitType=Line \
        --transform-output S3OutputPath="s3://${S3_BUCKET_NAME}/batch-output/" \
        --transform-resources InstanceType=ml.m5.large,InstanceCount=1 \
        --tags Key=Purpose,Value=AutoML-Demo Key=Environment,Value=Development
    
    log "Batch transform job created: ${TRANSFORM_JOB_NAME}"
}

# Save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    # Create deployment config file
    cat > deployment_config.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "resources": {
        "autopilot_job_name": "${AUTOPILOT_JOB_NAME}",
        "s3_bucket_name": "${S3_BUCKET_NAME}",
        "iam_role_name": "${IAM_ROLE_NAME}",
        "iam_role_arn": "${ROLE_ARN}",
        "model_name": "${MODEL_NAME}",
        "endpoint_config_name": "${ENDPOINT_CONFIG_NAME}",
        "endpoint_name": "${ENDPOINT_NAME}",
        "transform_job_name": "${TRANSFORM_JOB_NAME}"
    },
    "deployment_status": "completed"
}
EOF
    
    log "Deployment configuration saved to deployment_config.json"
}

# Main deployment function
main() {
    log "Starting AWS AutoML Solutions deployment..."
    
    # Check if already deployed
    if [[ -f "deployment_config.json" ]]; then
        local existing_config
        existing_config=$(cat deployment_config.json)
        if echo "${existing_config}" | grep -q '"deployment_status": "completed"'; then
            warn "Deployment already exists. Use destroy.sh first to clean up."
            info "Existing deployment details:"
            if command -v jq &> /dev/null; then
                echo "${existing_config}" | jq '.'
            else
                echo "${existing_config}"
            fi
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    create_s3_bucket
    create_iam_role
    prepare_dataset
    create_autopilot_job
    monitor_autopilot_job
    get_best_model
    download_artifacts
    deploy_model
    test_inference
    create_batch_transform
    save_deployment_config
    
    log "Deployment completed successfully!"
    log "═══════════════════════════════════════════════════════════════════════════════"
    log "AWS AutoML Solutions with SageMaker Autopilot has been deployed successfully!"
    log ""
    log "Resources created:"
    log "  • S3 Bucket: ${S3_BUCKET_NAME}"
    log "  • IAM Role: ${IAM_ROLE_NAME}"
    log "  • AutoML Job: ${AUTOPILOT_JOB_NAME}"
    log "  • SageMaker Model: ${MODEL_NAME}"
    log "  • Endpoint: ${ENDPOINT_NAME}"
    log "  • Batch Transform Job: ${TRANSFORM_JOB_NAME}"
    log ""
    log "Next steps:"
    log "  • View generated notebooks in ./autopilot_artifacts/"
    log "  • Test the endpoint with your own data"
    log "  • Monitor costs in the AWS console"
    log "  • Run ./destroy.sh when done to clean up resources"
    log ""
    warn "Remember: The endpoint will incur hourly charges until destroyed!"
    log "═══════════════════════════════════════════════════════════════════════════════"
}

# Execute main function
main "$@"