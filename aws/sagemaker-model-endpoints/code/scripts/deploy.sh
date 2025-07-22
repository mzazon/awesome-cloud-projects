#!/bin/bash

# Deploy script for ML Models with Amazon SageMaker Endpoints
# This script deploys the complete infrastructure for serving ML models via SageMaker endpoints

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_FILE="${SCRIPT_DIR}/deploy_errors.log"

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$ERROR_FILE" >&2
}

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Deployment failed with exit code $exit_code"
        log "Check $ERROR_FILE for detailed error information"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python3 not found. Please install Python 3.8+"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon not running. Please start Docker"
        exit 1
    fi
    
    log "All prerequisites satisfied"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export REGION=${AWS_REGION:-us-east-1}
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export MODEL_NAME="sklearn-iris-classifier-$(date +%s)"
    export ENDPOINT_NAME="iris-prediction-endpoint-$(date +%s)"
    export ECR_REPOSITORY_NAME="sagemaker-sklearn-inference-$(date +%s)"
    
    # Save variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
REGION=$REGION
ACCOUNT_ID=$ACCOUNT_ID
MODEL_NAME=$MODEL_NAME
ENDPOINT_NAME=$ENDPOINT_NAME
ECR_REPOSITORY_NAME=$ECR_REPOSITORY_NAME
EOF
    
    log "Environment configured for region: $REGION"
    log "Using account ID: $ACCOUNT_ID"
}

# Create ECR repository
create_ecr_repository() {
    log "Creating ECR repository: $ECR_REPOSITORY_NAME"
    
    if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$REGION" &> /dev/null; then
        log "ECR repository already exists"
    else
        aws ecr create-repository \
            --repository-name "$ECR_REPOSITORY_NAME" \
            --image-scanning-configuration scanOnPush=true \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "ECR repository created successfully"
    fi
    
    # Get ECR login
    aws ecr get-login-password --region "$REGION" | \
        docker login --username AWS --password-stdin \
        "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    log "ECR login successful"
}

# Create S3 bucket for model artifacts
create_s3_bucket() {
    log "Creating S3 bucket for model artifacts..."
    
    export BUCKET_NAME="sagemaker-models-$(aws secretsmanager \
        get-random-password --exclude-punctuation \
        --exclude-uppercase --password-length 8 \
        --query 'RandomPassword' --output text)"
    
    # Add bucket name to env file
    echo "BUCKET_NAME=$BUCKET_NAME" >> "${SCRIPT_DIR}/.env"
    
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log "S3 bucket already exists"
    else
        if [ "$REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$BUCKET_NAME" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        else
            aws s3 mb "s3://$BUCKET_NAME" --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        fi
        
        log "S3 bucket created: $BUCKET_NAME"
    fi
}

# Create SageMaker execution role
create_sagemaker_role() {
    log "Creating SageMaker execution role..."
    
    export ROLE_NAME="SageMakerExecutionRole-$(date +%s)"
    echo "ROLE_NAME=$ROLE_NAME" >> "${SCRIPT_DIR}/.env"
    
    # Create trust policy
    cat > /tmp/sagemaker-trust-policy.json << 'EOF'
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
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log "IAM role already exists"
    else
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/sagemaker-trust-policy.json \
            >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        # Attach policies
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess \
            >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
            >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        # Wait for role to be available
        sleep 10
        
        log "SageMaker execution role created"
    fi
    
    export ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" \
        --query 'Role.Arn' --output text)
    echo "ROLE_ARN=$ROLE_ARN" >> "${SCRIPT_DIR}/.env"
    
    log "Role ARN: $ROLE_ARN"
}

# Train and prepare model
prepare_model() {
    log "Training and preparing ML model..."
    
    # Create model training directory
    mkdir -p "${SCRIPT_DIR}/../model-training"
    
    # Create training script
    cat > "${SCRIPT_DIR}/../model-training/train_model.py" << 'EOF'
import pickle
import numpy as np
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

# Load and prepare data
iris = load_iris()
X_train, X_test, y_train, y_test = train_test_split(
    iris.data, iris.target, test_size=0.2, random_state=42
)

# Train model
model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train, y_train)

# Validate model
predictions = model.predict(X_test)
accuracy = accuracy_score(y_test, predictions)
print(f"Model accuracy: {accuracy:.3f}")

# Save model
with open('model.pkl', 'wb') as f:
    pickle.dump(model, f)

print("Model saved as model.pkl")
EOF
    
    # Train model
    cd "${SCRIPT_DIR}/../model-training"
    python3 train_model.py >> "$LOG_FILE" 2>> "$ERROR_FILE"
    cd "$SCRIPT_DIR"
    
    log "Model training completed"
}

# Create inference container
create_inference_container() {
    log "Creating inference container..."
    
    # Create container directory structure
    mkdir -p "${SCRIPT_DIR}/../container/code"
    
    # Create inference script
    cat > "${SCRIPT_DIR}/../container/code/predictor.py" << 'EOF'
import pickle
import json
import numpy as np
import os
from flask import Flask, request, jsonify
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

class ModelHandler:
    def __init__(self):
        self.model = None
        self.class_names = ['setosa', 'versicolor', 'virginica']
    
    def load_model(self):
        """Load the model from the model directory"""
        model_path = '/opt/ml/model/model.pkl'
        if os.path.exists(model_path):
            with open(model_path, 'rb') as f:
                self.model = pickle.load(f)
            logger.info("Model loaded successfully")
        else:
            raise Exception(f"Model file not found at {model_path}")
    
    def predict(self, data):
        """Make predictions on input data"""
        if self.model is None:
            raise Exception("Model not loaded")
        
        # Convert input to numpy array
        input_data = np.array(data).reshape(-1, 4)
        
        # Make predictions
        predictions = self.model.predict(input_data)
        probabilities = self.model.predict_proba(input_data)
        
        # Format results
        results = []
        for i, pred in enumerate(predictions):
            results.append({
                'predicted_class': self.class_names[pred],
                'predicted_class_index': int(pred),
                'probabilities': {
                    self.class_names[j]: float(prob) 
                    for j, prob in enumerate(probabilities[i])
                }
            })
        
        return results

# Initialize model handler
model_handler = ModelHandler()

@app.route('/ping', methods=['GET'])
def ping():
    """Health check endpoint"""
    status = 200 if model_handler.model is not None else 404
    return '', status

@app.route('/invocations', methods=['POST'])
def invocations():
    """Prediction endpoint"""
    try:
        # Parse input data
        input_data = request.get_json()
        
        if 'instances' not in input_data:
            return jsonify({'error': 'Input must contain "instances" key'}), 400
        
        # Make predictions
        predictions = model_handler.predict(input_data['instances'])
        
        return jsonify({'predictions': predictions})
    
    except Exception as e:
        logger.error(f"Prediction error: {str(e)}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # Load model at startup
    model_handler.load_model()
    
    # Start Flask server
    app.run(host='0.0.0.0', port=8080)
EOF
    
    # Create Dockerfile
    cat > "${SCRIPT_DIR}/../container/Dockerfile" << 'EOF'
FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    flask==2.3.3 \
    scikit-learn==1.3.0 \
    numpy==1.24.3 \
    gunicorn==21.2.0

# Copy prediction code
COPY code /opt/ml/code
WORKDIR /opt/ml/code

# Set environment variables
ENV PYTHONUNBUFFERED=TRUE
ENV PYTHONDONTWRITEBYTECODE=TRUE
ENV PATH="/opt/ml/code:${PATH}"

# Expose port
EXPOSE 8080

# Define entrypoint
ENTRYPOINT ["python", "predictor.py"]
EOF
    
    log "Inference container files created"
}

# Build and push container
build_and_push_container() {
    log "Building and pushing container to ECR..."
    
    # Build container
    cd "${SCRIPT_DIR}/../"
    docker build -t "$ECR_REPOSITORY_NAME" container/ >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    # Tag for ECR
    export ECR_IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPOSITORY_NAME:latest"
    echo "ECR_IMAGE_URI=$ECR_IMAGE_URI" >> "${SCRIPT_DIR}/.env"
    
    docker tag "$ECR_REPOSITORY_NAME:latest" "$ECR_IMAGE_URI" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    # Push to ECR
    docker push "$ECR_IMAGE_URI" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    cd "$SCRIPT_DIR"
    log "Container pushed to: $ECR_IMAGE_URI"
}

# Upload model to S3
upload_model() {
    log "Uploading model artifacts to S3..."
    
    cd "${SCRIPT_DIR}/../model-training"
    tar -czf model.tar.gz model.pkl
    aws s3 cp model.tar.gz "s3://$BUCKET_NAME/model.tar.gz" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    cd "$SCRIPT_DIR"
    
    export MODEL_DATA_URL="s3://$BUCKET_NAME/model.tar.gz"
    echo "MODEL_DATA_URL=$MODEL_DATA_URL" >> "${SCRIPT_DIR}/.env"
    
    log "Model uploaded to: $MODEL_DATA_URL"
}

# Create SageMaker model
create_sagemaker_model() {
    log "Creating SageMaker model..."
    
    if aws sagemaker describe-model --model-name "$MODEL_NAME" --region "$REGION" &> /dev/null; then
        log "SageMaker model already exists"
    else
        aws sagemaker create-model \
            --model-name "$MODEL_NAME" \
            --primary-container Image="$ECR_IMAGE_URI",ModelDataUrl="$MODEL_DATA_URL" \
            --execution-role-arn "$ROLE_ARN" \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "SageMaker model created: $MODEL_NAME"
    fi
}

# Create endpoint configuration
create_endpoint_config() {
    log "Creating endpoint configuration..."
    
    export ENDPOINT_CONFIG_NAME="${MODEL_NAME}-config"
    echo "ENDPOINT_CONFIG_NAME=$ENDPOINT_CONFIG_NAME" >> "${SCRIPT_DIR}/.env"
    
    if aws sagemaker describe-endpoint-config --endpoint-config-name "$ENDPOINT_CONFIG_NAME" --region "$REGION" &> /dev/null; then
        log "Endpoint configuration already exists"
    else
        aws sagemaker create-endpoint-config \
            --endpoint-config-name "$ENDPOINT_CONFIG_NAME" \
            --production-variants \
            VariantName=primary,ModelName="$MODEL_NAME",InitialInstanceCount=1,InstanceType=ml.t2.medium,InitialVariantWeight=1.0 \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "Endpoint configuration created: $ENDPOINT_CONFIG_NAME"
    fi
}

# Deploy endpoint
deploy_endpoint() {
    log "Deploying SageMaker endpoint..."
    
    if aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION" &> /dev/null; then
        local status=$(aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION" --query 'EndpointStatus' --output text)
        if [ "$status" = "InService" ]; then
            log "Endpoint already exists and is in service"
            return
        fi
    fi
    
    aws sagemaker create-endpoint \
        --endpoint-name "$ENDPOINT_NAME" \
        --endpoint-config-name "$ENDPOINT_CONFIG_NAME" \
        --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    log "Creating endpoint: $ENDPOINT_NAME"
    log "This will take 5-10 minutes..."
    
    # Wait for endpoint to be in service
    aws sagemaker wait endpoint-in-service \
        --endpoint-name "$ENDPOINT_NAME" \
        --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    log "Endpoint is now in service!"
}

# Configure auto-scaling
configure_autoscaling() {
    log "Configuring auto-scaling for endpoint..."
    
    # Register scalable target
    aws application-autoscaling register-scalable-target \
        --service-namespace sagemaker \
        --resource-id "endpoint/$ENDPOINT_NAME/variant/primary" \
        --scalable-dimension sagemaker:variant:DesiredInstanceCount \
        --min-capacity 1 \
        --max-capacity 5 \
        --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    # Create scaling policy
    aws application-autoscaling put-scaling-policy \
        --service-namespace sagemaker \
        --resource-id "endpoint/$ENDPOINT_NAME/variant/primary" \
        --scalable-dimension sagemaker:variant:DesiredInstanceCount \
        --policy-name iris-endpoint-scaling-policy \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration \
        '{"TargetValue":70.0,"PredefinedMetricSpecification":{"PredefinedMetricType":"SageMakerVariantInvocationsPerInstance"}}' \
        --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    log "Auto-scaling configured for endpoint"
}

# Test endpoint
test_endpoint() {
    log "Testing endpoint with sample data..."
    
    # Create test payload
    cat > /tmp/test_payload.json << 'EOF'
{
  "instances": [
    [5.1, 3.5, 1.4, 0.2],
    [6.7, 3.1, 4.4, 1.4],
    [6.3, 3.3, 6.0, 2.5]
  ]
}
EOF
    
    # Test prediction
    aws sagemaker-runtime invoke-endpoint \
        --endpoint-name "$ENDPOINT_NAME" \
        --content-type application/json \
        --body fileb:///tmp/test_payload.json \
        --region "$REGION" \
        /tmp/prediction_output.json >> "$LOG_FILE" 2>> "$ERROR_FILE"
    
    log "Endpoint test completed successfully"
    log "Test results:"
    cat /tmp/prediction_output.json | python3 -m json.tool | tee -a "$LOG_FILE"
    
    # Cleanup test files
    rm -f /tmp/test_payload.json /tmp/prediction_output.json
}

# Main execution
main() {
    log "Starting SageMaker ML model deployment..."
    log "Deployment logs: $LOG_FILE"
    log "Error logs: $ERROR_FILE"
    
    check_prerequisites
    setup_environment
    create_ecr_repository
    create_s3_bucket
    create_sagemaker_role
    prepare_model
    create_inference_container
    build_and_push_container
    upload_model
    create_sagemaker_model
    create_endpoint_config
    deploy_endpoint
    configure_autoscaling
    test_endpoint
    
    log "===========================================" 
    log "Deployment completed successfully!"
    log "==========================================="
    log "Endpoint Name: $ENDPOINT_NAME"
    log "Model Name: $MODEL_NAME"
    log "ECR Repository: $ECR_REPOSITORY_NAME"
    log "S3 Bucket: $BUCKET_NAME"
    log "IAM Role: $ROLE_NAME"
    log "==========================================="
    log "To test the endpoint:"
    log "aws sagemaker-runtime invoke-endpoint \\"
    log "  --endpoint-name $ENDPOINT_NAME \\"
    log "  --content-type application/json \\"
    log "  --body '{\"instances\":[[5.1,3.5,1.4,0.2]]}' \\"
    log "  --region $REGION output.json"
    log "==========================================="
    log "Run ./destroy.sh to clean up resources"
}

# Execute main function
main "$@"