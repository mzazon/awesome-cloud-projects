#!/bin/bash

# Deploy script for Basic Secret Management with Secrets Manager and Lambda
# This script deploys the complete infrastructure needed for the recipe
set -e

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    # Check if zip is available for Lambda packaging
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install it for Lambda packaging."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources to avoid conflicts
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Set resource names with unique suffix
    export SECRET_NAME="my-app-secrets-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="secret-demo-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="lambda-secrets-role-${RANDOM_SUFFIX}"
    export POLICY_NAME="SecretsAccess-${RANDOM_SUFFIX}"
    
    # Create state file to track deployed resources
    cat > .deployment-state << EOF
SECRET_NAME=${SECRET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
POLICY_NAME=${POLICY_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Environment initialized with region: ${AWS_REGION}, suffix: ${RANDOM_SUFFIX}"
}

# Create IAM role for Lambda
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda service
    cat > trust-policy.json << EOF
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
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create IAM role
        aws iam create-role \
            --role-name ${IAM_ROLE_NAME} \
            --assume-role-policy-document file://trust-policy.json \
            --description "IAM role for Lambda function to access Secrets Manager"
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name ${IAM_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Store role ARN for later use
        export LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name ${IAM_ROLE_NAME} \
            --query 'Role.Arn' --output text)
        
        # Add role ARN to state file
        echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .deployment-state
        
        success "IAM role created: ${LAMBDA_ROLE_ARN}"
    else
        log "[DRY-RUN] Would create IAM role: ${IAM_ROLE_NAME}"
    fi
}

# Create secret in AWS Secrets Manager
create_secret() {
    log "Creating sample secret in Secrets Manager..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create a sample database secret
        aws secretsmanager create-secret \
            --name ${SECRET_NAME} \
            --description "Sample application secrets for Lambda demo - deployed via script" \
            --secret-string '{
              "database_host": "mydb.cluster-xyz.'${AWS_REGION}'.rds.amazonaws.com",
              "database_port": "5432",
              "database_name": "production",
              "username": "appuser",
              "password": "secure-random-password-123"
            }' \
            --tags '[
              {"Key": "Environment", "Value": "demo"},
              {"Key": "Application", "Value": "secrets-management-demo"},
              {"Key": "DeployedBy", "Value": "deployment-script"}
            ]'
        
        # Get the secret ARN for IAM policy
        export SECRET_ARN=$(aws secretsmanager describe-secret \
            --secret-id ${SECRET_NAME} \
            --query 'ARN' --output text)
        
        # Add secret ARN to state file
        echo "SECRET_ARN=${SECRET_ARN}" >> .deployment-state
        
        success "Secret created: ${SECRET_NAME}"
        log "Secret ARN: ${SECRET_ARN}"
    else
        log "[DRY-RUN] Would create secret: ${SECRET_NAME}"
    fi
}

# Create IAM policy for secret access
create_secret_policy() {
    log "Creating IAM policy for secret access..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create custom policy for secret access
        cat > secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "${SECRET_ARN}"
    }
  ]
}
EOF
        
        # Create and attach the policy
        aws iam create-policy \
            --policy-name ${POLICY_NAME} \
            --policy-document file://secrets-policy.json \
            --description "Policy allowing access to specific secret in Secrets Manager"
        
        aws iam attach-role-policy \
            --role-name ${IAM_ROLE_NAME} \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
        
        success "Secrets access policy attached to Lambda role"
    else
        log "[DRY-RUN] Would create IAM policy: ${POLICY_NAME}"
    fi
}

# Create Lambda function package
create_lambda_package() {
    log "Creating Lambda function code and package..."
    
    # Create directory for Lambda package
    mkdir -p lambda-package
    
    # Create Python function code
    cat > lambda-package/lambda_function.py << 'EOF'
import json
import urllib.request
import urllib.error
import os

# AWS Parameters and Secrets Lambda Extension HTTP endpoint
SECRETS_EXTENSION_HTTP_PORT = "2773"
SECRETS_EXTENSION_SERVER_PORT = os.environ.get(
    'PARAMETERS_SECRETS_EXTENSION_HTTP_PORT', 
    SECRETS_EXTENSION_HTTP_PORT
)

def get_secret(secret_name):
    """Retrieve secret using AWS Parameters and Secrets Lambda Extension"""
    secrets_extension_endpoint = (
        f"http://localhost:{SECRETS_EXTENSION_SERVER_PORT}"
        f"/secretsmanager/get?secretId={secret_name}"
    )
    
    # Add authentication header for the extension
    headers = {
        'X-Aws-Parameters-Secrets-Token': os.environ.get('AWS_SESSION_TOKEN', '')
    }
    
    try:
        req = urllib.request.Request(
            secrets_extension_endpoint, 
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            secret_data = response.read().decode('utf-8')
            return json.loads(secret_data)
    except urllib.error.URLError as e:
        print(f"Error retrieving secret from extension: {e}")
        raise
    except json.JSONDecodeError as e:
        print(f"Error parsing secret JSON: {e}")
        raise
    except Exception as e:
        print(f"Unexpected error in get_secret: {e}")
        raise

def lambda_handler(event, context):
    """Main Lambda function handler"""
    secret_name = os.environ.get('SECRET_NAME')
    
    if not secret_name:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'SECRET_NAME environment variable not set'
            })
        }
    
    try:
        # Retrieve secret using the extension
        print(f"Attempting to retrieve secret: {secret_name}")
        secret_response = get_secret(secret_name)
        secret_value = json.loads(secret_response['SecretString'])
        
        # Use secret values (example: database connection info)
        db_host = secret_value.get('database_host', 'Not found')
        db_name = secret_value.get('database_name', 'Not found')
        username = secret_value.get('username', 'Not found')
        
        print(f"Successfully retrieved secret for database: {db_name}")
        
        # In a real application, you would use these values to connect
        # to your database or external service
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Secret retrieved successfully',
                'database_host': db_host,
                'database_name': db_name,
                'username': username,
                'extension_cache': 'Enabled with 300s TTL',
                'note': 'Password retrieved but not displayed for security',
                'deployment_info': {
                    'deployed_by': 'deployment-script',
                    'function_name': os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown')
                }
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }
EOF
    
    # Create deployment package
    cd lambda-package
    zip -r ../lambda-function.zip . > /dev/null
    cd ..
    
    success "Lambda function code created and packaged"
}

# Deploy Lambda function
deploy_lambda_function() {
    log "Deploying Lambda function with Secrets Extension..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for IAM role propagation
        log "Waiting for IAM role propagation (15 seconds)..."
        sleep 15
        
        # Create Lambda function
        aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --runtime python3.11 \
            --role ${LAMBDA_ROLE_ARN} \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 30 \
            --memory-size 256 \
            --description "Demo function for secret management with Secrets Manager" \
            --environment Variables="{SECRET_NAME=${SECRET_NAME}}" \
            --tags "Environment=demo,Application=secrets-management-demo,DeployedBy=deployment-script"
        
        # Add AWS Parameters and Secrets Lambda Extension layer
        # Using the latest extension layer ARN (version 18 as of 2024)
        EXTENSION_LAYER_ARN="arn:aws:lambda:${AWS_REGION}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:18"
        
        aws lambda update-function-configuration \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --layers ${EXTENSION_LAYER_ARN}
        
        # Configure extension environment variables
        aws lambda update-function-configuration \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --environment Variables="{
              SECRET_NAME=${SECRET_NAME},
              PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED=true,
              PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE=1000,
              PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS=3,
              PARAMETERS_SECRETS_EXTENSION_HTTP_PORT=2773
            }"
        
        # Wait for function update to complete
        log "Waiting for Lambda function to be ready..."
        aws lambda wait function-updated-v2 --function-name ${LAMBDA_FUNCTION_NAME}
        
        success "Lambda function deployed with Secrets Extension layer"
    else
        log "[DRY-RUN] Would deploy Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
}

# Test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Test Lambda function
        log "Invoking Lambda function for testing..."
        aws lambda invoke \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --payload '{}' \
            response.json > /dev/null
        
        # Check if response is successful
        if [[ -f response.json ]]; then
            STATUS_CODE=$(cat response.json | jq -r '.statusCode // 500')
            if [[ "$STATUS_CODE" == "200" ]]; then
                success "Lambda function test passed!"
                log "Response: $(cat response.json | jq -r '.body' | jq .)"
            else
                error "Lambda function test failed with status code: $STATUS_CODE"
                log "Response: $(cat response.json)"
            fi
        else
            error "No response file generated from Lambda invocation"
        fi
    else
        log "[DRY-RUN] Would test Lambda function deployment"
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files but keep deployment state
    rm -f trust-policy.json secrets-policy.json lambda-function.zip response.json
    rm -rf lambda-package
    
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Basic Secret Management solution..."
    
    # Run all deployment steps
    check_prerequisites
    initialize_environment
    create_iam_role
    create_secret
    create_secret_policy
    create_lambda_package
    deploy_lambda_function
    test_deployment
    cleanup_temp_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Deployment completed successfully!"
        echo ""
        log "=== DEPLOYMENT SUMMARY ==="
        log "Secret Name: ${SECRET_NAME}"
        log "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        log "IAM Role: ${IAM_ROLE_NAME}"
        log "AWS Region: ${AWS_REGION}"
        echo ""
        log "To test your deployment:"
        log "aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{}' response.json && cat response.json"
        echo ""
        log "To clean up resources, run: ./destroy.sh"
        echo ""
        warning "Remember to run the destroy script to avoid ongoing charges!"
    else
        success "Dry-run completed successfully!"
        log "Run without --dry-run flag to deploy resources"
    fi
}

# Handle script interruption
trap 'error "Deployment interrupted! Check .deployment-state file for partial deployment details."; exit 1' INT TERM

# Run main function
main "$@"