#!/bin/bash

# Feature Flags with CloudWatch Evidently - Deployment Script
# This script deploys the complete feature flag infrastructure using AWS CLI

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    echo -e "${TIMESTAMP} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: In production, you might want to run the destroy script here
    # But for safety, we'll just log the error and let users decide
    exit 1
}

trap cleanup_on_error ERR

# Print banner
print_banner() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  AWS CloudWatch Evidently Feature Flags Setup"
    echo "=================================================="
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    # Check required permissions (basic test)
    local account_id region
    account_id=$(aws sts get-caller-identity --query Account --output text)
    region=$(aws configure get region)
    
    if [[ -z "${region}" ]]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
    log_info "Account ID: ${account_id}"
    log_info "Region: ${region}"
    
    # Check if CloudWatch Evidently is available in the region
    if ! aws evidently list-projects --region "${region}" &> /dev/null; then
        log_warning "CloudWatch Evidently may not be available in region ${region}"
        log_warning "Please verify service availability and permissions"
    fi
}

# Generate unique identifiers
generate_identifiers() {
    log_info "Generating unique resource identifiers..."
    
    # Generate random suffix for resource naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set environment variables for resource names
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export PROJECT_NAME="feature-demo-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="evidently-demo-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="evidently-lambda-role-${RANDOM_SUFFIX}"
    
    log_success "Resource identifiers generated:"
    log_info "  Project name: ${PROJECT_NAME}"
    log_info "  Lambda function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  IAM role: ${IAM_ROLE_NAME}"
    log_info "  Random suffix: ${RANDOM_SUFFIX}"
}

# Create IAM role for Lambda
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Create trust policy document
    local trust_policy
    trust_policy=$(cat <<EOF
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
)
    
    # Create IAM role
    if aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document "${trust_policy}" \
        --description "IAM role for CloudWatch Evidently demo Lambda function" \
        --output table > /dev/null; then
        log_success "IAM role created: ${IAM_ROLE_NAME}"
    else
        log_error "Failed to create IAM role"
        return 1
    fi
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    aws iam wait role-exists --role-name "${IAM_ROLE_NAME}"
    
    # Attach basic Lambda execution policy
    if aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        --output table > /dev/null; then
        log_success "Attached AWSLambdaBasicExecutionRole policy"
    else
        log_error "Failed to attach basic execution policy"
        return 1
    fi
    
    # Attach CloudWatch Evidently policy
    if aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchEvidentlyFullAccess" \
        --output table > /dev/null; then
        log_success "Attached CloudWatchEvidentlyFullAccess policy"
    else
        log_error "Failed to attach Evidently policy"
        return 1
    fi
    
    # Wait for policy attachments to propagate
    log_info "Waiting for policy attachments to propagate..."
    sleep 10
}

# Create CloudWatch Evidently project
create_evidently_project() {
    log_info "Creating CloudWatch Evidently project..."
    
    # Create the project with log group configuration
    if aws evidently create-project \
        --name "${PROJECT_NAME}" \
        --description "Feature flag demonstration project for recipe tutorial" \
        --data-delivery '{
            "cloudWatchLogs": {
                "logGroup": "/aws/evidently/evaluations"
            }
        }' \
        --output table > /dev/null; then
        log_success "Evidently project created: ${PROJECT_NAME}"
    else
        log_error "Failed to create Evidently project"
        return 1
    fi
    
    # Wait for project to be available
    log_info "Waiting for project to be fully available..."
    sleep 5
    
    # Verify project creation
    if aws evidently get-project --project "${PROJECT_NAME}" --query 'name' --output text &> /dev/null; then
        log_success "Project verification successful"
    else
        log_error "Project verification failed"
        return 1
    fi
}

# Create feature flag
create_feature_flag() {
    log_info "Creating feature flag with variations..."
    
    # Create feature flag with boolean variations
    if aws evidently create-feature \
        --project "${PROJECT_NAME}" \
        --name "new-checkout-flow" \
        --description "Controls visibility of the new checkout experience for gradual rollout testing" \
        --variations '{
            "enabled": {
                "name": "enabled",
                "value": {
                    "boolValue": true
                }
            },
            "disabled": {
                "name": "disabled",
                "value": {
                    "boolValue": false
                }
            }
        }' \
        --default-variation "disabled" \
        --output table > /dev/null; then
        log_success "Feature flag 'new-checkout-flow' created with enabled/disabled variations"
    else
        log_error "Failed to create feature flag"
        return 1
    fi
    
    # Wait for feature to be available
    log_info "Waiting for feature flag to be available..."
    sleep 3
}

# Create launch configuration
create_launch_configuration() {
    log_info "Creating launch configuration for gradual rollout..."
    
    # Get current timestamp for launch start time
    local start_time
    start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create launch with traffic split configuration
    if aws evidently create-launch \
        --project "${PROJECT_NAME}" \
        --name "checkout-gradual-rollout" \
        --description "Gradual rollout of new checkout flow to 10% of users with monitoring" \
        --groups '[
            {
                "name": "control-group",
                "description": "Users with existing checkout flow (90%)",
                "feature": "new-checkout-flow",
                "variation": "disabled"
            },
            {
                "name": "treatment-group",
                "description": "Users with new checkout flow (10%)",
                "feature": "new-checkout-flow",
                "variation": "enabled"
            }
        ]' \
        --scheduled-splits-config "{
            \"steps\": [
                {
                    \"startTime\": \"${start_time}\",
                    \"groupWeights\": {
                        \"control-group\": 90,
                        \"treatment-group\": 10
                    }
                }
            ]
        }" \
        --output table > /dev/null; then
        log_success "Launch configuration created with 10% traffic to new checkout flow"
    else
        log_error "Failed to create launch configuration"
        return 1
    fi
    
    # Wait for launch to be available
    log_info "Waiting for launch configuration to be available..."
    sleep 3
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for feature evaluation..."
    
    # Create Lambda function code
    local lambda_code
    lambda_code=$(cat <<'EOF'
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to demonstrate CloudWatch Evidently feature flag evaluation.
    
    This function evaluates a feature flag and returns the result along with
    relevant metadata for debugging and monitoring purposes.
    """
    
    # Initialize Evidently client
    evidently = boto3.client('evidently')
    
    # Extract user information from event (with defaults)
    user_id = event.get('userId', f'anonymous-user-{context.aws_request_id[:8]}')
    project_name = os.environ.get('PROJECT_NAME')
    
    if not project_name:
        logger.error("PROJECT_NAME environment variable not set")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Configuration error: PROJECT_NAME not configured',
                'userId': user_id,
                'featureEnabled': False  # Safe default
            })
        }
    
    try:
        # Evaluate feature flag for user
        logger.info(f"Evaluating feature flag for user: {user_id}")
        
        response = evidently.evaluate_feature(
            project=project_name,
            feature='new-checkout-flow',
            entityId=user_id
        )
        
        # Determine if feature is enabled
        feature_enabled = response['variation'] == 'enabled'
        
        # Log evaluation result for monitoring
        logger.info(f"Feature evaluation result - User: {user_id}, "
                   f"Variation: {response['variation']}, "
                   f"Enabled: {feature_enabled}")
        
        # Return success response with detailed information
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'userId': user_id,
                'featureEnabled': feature_enabled,
                'variation': response['variation'],
                'reason': response.get('reason', 'evaluation'),
                'timestamp': context.aws_request_id,
                'project': project_name
            })
        }
        
    except Exception as e:
        # Log error for debugging
        logger.error(f"Error evaluating feature flag: {str(e)}")
        
        # Return error response with safe defaults
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f'Feature evaluation failed: {str(e)}',
                'userId': user_id,
                'featureEnabled': False,  # Safe default when evaluation fails
                'variation': 'disabled',  # Safe default variation
                'fallback': True
            })
        }
EOF
)
    
    # Write Lambda function code to file
    echo "${lambda_code}" > "${SCRIPT_DIR}/lambda_function.py"
    
    # Create deployment package
    log_info "Creating Lambda deployment package..."
    cd "${SCRIPT_DIR}"
    if [[ -f lambda-package.zip ]]; then
        rm lambda-package.zip
    fi
    zip lambda-package.zip lambda_function.py > /dev/null
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-package.zip \
        --environment "Variables={PROJECT_NAME=${PROJECT_NAME}}" \
        --timeout 30 \
        --description "CloudWatch Evidently feature flag evaluation demo function" \
        --output table > /dev/null; then
        log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
    else
        log_error "Failed to create Lambda function"
        return 1
    fi
    
    # Wait for function to be available
    log_info "Waiting for Lambda function to be available..."
    aws lambda wait function-active --function-name "${LAMBDA_FUNCTION_NAME}"
    
    # Clean up temporary files
    rm -f lambda_function.py lambda-package.zip
}

# Start the launch
start_launch() {
    log_info "Starting the launch to begin traffic splitting..."
    
    if aws evidently start-launch \
        --project "${PROJECT_NAME}" \
        --launch "checkout-gradual-rollout" \
        --output table > /dev/null; then
        log_success "Launch started - 10% of traffic now receiving new checkout flow"
    else
        log_error "Failed to start launch"
        return 1
    fi
    
    # Wait for launch to be running
    log_info "Waiting for launch to be fully active..."
    sleep 5
    
    # Verify launch status
    local launch_status
    launch_status=$(aws evidently get-launch \
        --project "${PROJECT_NAME}" \
        --launch "checkout-gradual-rollout" \
        --query 'status' --output text)
    
    if [[ "${launch_status}" == "RUNNING" ]]; then
        log_success "Launch is now running and actively splitting traffic"
    else
        log_warning "Launch status: ${launch_status} (may take a few moments to become active)"
    fi
}

# Test the deployment
test_deployment() {
    log_info "Testing the feature flag deployment..."
    
    # Test Lambda function with sample data
    log_info "Testing Lambda function with sample user data..."
    
    local test_payload='{"userId": "test-user-123"}'
    local test_result
    
    if test_result=$(aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload "${test_payload}" \
        --output json \
        response.json 2>/dev/null); then
        
        # Check if response file was created and contains data
        if [[ -f response.json ]]; then
            local response_content
            response_content=$(cat response.json)
            log_success "Lambda function test successful"
            log_info "Sample response: ${response_content}"
            rm -f response.json
        else
            log_warning "Lambda function executed but no response file generated"
        fi
    else
        log_warning "Lambda function test failed - this may be normal for new deployments"
    fi
    
    # Verify Evidently project status
    log_info "Verifying Evidently project status..."
    local project_status
    project_status=$(aws evidently get-project \
        --project "${PROJECT_NAME}" \
        --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
    
    log_info "Project status: ${project_status}"
    
    # Verify feature flag status
    log_info "Verifying feature flag configuration..."
    local feature_name
    feature_name=$(aws evidently get-feature \
        --project "${PROJECT_NAME}" \
        --feature "new-checkout-flow" \
        --query 'name' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${feature_name}" == "new-checkout-flow" ]]; then
        log_success "Feature flag verified: ${feature_name}"
    else
        log_warning "Feature flag verification failed"
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment-info.txt"
    
    cat > "${info_file}" <<EOF
# CloudWatch Evidently Feature Flags Deployment Information
# Generated on: ${TIMESTAMP}

# Resource Names
PROJECT_NAME="${PROJECT_NAME}"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME}"
IAM_ROLE_NAME="${IAM_ROLE_NAME}"
AWS_REGION="${AWS_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"

# Feature Flag Details
FEATURE_NAME="new-checkout-flow"
LAUNCH_NAME="checkout-gradual-rollout"

# Useful Commands
# Test Lambda function:
aws lambda invoke --function-name "${LAMBDA_FUNCTION_NAME}" --payload '{"userId": "test-user-456"}' response.json

# Check launch status:
aws evidently get-launch --project "${PROJECT_NAME}" --launch "checkout-gradual-rollout" --query 'status'

# View evaluation logs:
aws logs describe-log-streams --log-group-name "/aws/evidently/evaluations" --order-by LastEventTime --descending

# Stop launch (when ready):
aws evidently stop-launch --project "${PROJECT_NAME}" --launch "checkout-gradual-rollout"

# Clean up resources:
${SCRIPT_DIR}/destroy.sh
EOF
    
    log_success "Deployment information saved to: ${info_file}"
}

# Print deployment summary
print_summary() {
    echo
    echo -e "${GREEN}=================================================="
    echo "         DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo -e "==================================================${NC}"
    echo
    echo -e "${BLUE}Deployed Resources:${NC}"
    echo "  • Evidently Project: ${PROJECT_NAME}"
    echo "  • Feature Flag: new-checkout-flow"
    echo "  • Launch Config: checkout-gradual-rollout (10% traffic split)"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Test the Lambda function with different user IDs"
    echo "  2. Monitor CloudWatch Logs for evaluation events"
    echo "  3. View Evidently metrics in the AWS Console"
    echo "  4. When ready, run ./destroy.sh to clean up resources"
    echo
    echo -e "${BLUE}Quick Test:${NC}"
    echo "  aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} \\"
    echo "    --payload '{\"userId\": \"test-user-789\"}' response.json && cat response.json"
    echo
    echo -e "${BLUE}Monitoring:${NC}"
    echo "  • CloudWatch Logs: /aws/evidently/evaluations"
    echo "  • AWS Console: CloudWatch > Evidently > Projects > ${PROJECT_NAME}"
    echo
    echo -e "${YELLOW}Important:${NC} Remember to run the destroy script when finished to avoid ongoing costs."
    echo
}

# Main deployment function
main() {
    print_banner
    
    log_info "Starting CloudWatch Evidently feature flags deployment..."
    log_info "Deployment log: ${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    generate_identifiers
    create_iam_role
    create_evidently_project
    create_feature_flag
    create_launch_configuration
    create_lambda_function
    start_launch
    test_deployment
    save_deployment_info
    
    print_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi