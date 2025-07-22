#!/bin/bash

# Deploy script for AWS Secrets Manager Recipe
# This script deploys the complete secrets management solution with automatic rotation

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or you don't have access. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command_exists jq; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if zip is installed
    if ! command_exists zip; then
        error "zip is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [ "$(printf '%s\n' "2.0.0" "$AWS_CLI_VERSION" | sort -V | head -n1)" != "2.0.0" ]; then
        warn "AWS CLI version is older than 2.0.0. Some features may not work correctly."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to cleanup on script exit
cleanup() {
    if [ -f "/tmp/kms-key-id.txt" ]; then
        rm -f /tmp/kms-key-id.txt
    fi
    if [ -f "/tmp/lambda-trust-policy.json" ]; then
        rm -f /tmp/lambda-trust-policy.json
    fi
    if [ -f "/tmp/secrets-manager-policy.json" ]; then
        rm -f /tmp/secrets-manager-policy.json
    fi
    if [ -f "/tmp/db-credentials.json" ]; then
        rm -f /tmp/db-credentials.json
    fi
    if [ -f "/tmp/rotation_lambda.py" ]; then
        rm -f /tmp/rotation_lambda.py
    fi
    if [ -f "/tmp/rotation_lambda.zip" ]; then
        rm -f /tmp/rotation_lambda.zip
    fi
    if [ -f "/tmp/cross-account-policy.json" ]; then
        rm -f /tmp/cross-account-policy.json
    fi
    if [ -f "/tmp/app_integration.py" ]; then
        rm -f /tmp/app_integration.py
    fi
    if [ -f "/tmp/dashboard.json" ]; then
        rm -f /tmp/dashboard.json
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Function to wait for IAM role propagation
wait_for_iam_propagation() {
    local role_name=$1
    local max_attempts=30
    local attempt=1
    
    info "Waiting for IAM role propagation..."
    
    while [ $attempt -le $max_attempts ]; do
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            log "IAM role is ready"
            return 0
        fi
        
        info "Attempt $attempt/$max_attempts: IAM role not yet available, waiting..."
        sleep 10
        ((attempt++))
    done
    
    error "IAM role did not become available within expected time"
    return 1
}

# Function to validate resource creation
validate_resource() {
    local resource_type=$1
    local resource_name=$2
    local validation_command=$3
    
    info "Validating $resource_type: $resource_name"
    if eval "$validation_command" >/dev/null 2>&1; then
        log "$resource_type validation successful"
        return 0
    else
        error "$resource_type validation failed"
        return 1
    fi
}

# Main deployment function
deploy() {
    info "Starting AWS Secrets Manager deployment..."
    
    # Check if already deployed
    if [ -f ".deployment_state" ]; then
        info "Deployment state file found. Checking existing resources..."
        source .deployment_state
        
        # Check if secret exists
        if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
            warn "Secret $SECRET_NAME already exists. Skipping deployment."
            info "To redeploy, run ./destroy.sh first, then ./deploy.sh"
            exit 0
        fi
    fi
    
    # Step 1: Set environment variables
    info "Setting up environment variables..."
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export SECRET_NAME="demo-db-credentials-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="secret-rotation-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="SecretsManagerRotationRole-${RANDOM_SUFFIX}"
    export KMS_KEY_ALIAS="alias/secrets-manager-key-${RANDOM_SUFFIX}"
    
    log "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Secret Name: $SECRET_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "IAM Role: $IAM_ROLE_NAME"
    log "KMS Key Alias: $KMS_KEY_ALIAS"
    
    # Step 2: Create KMS key for encryption
    info "Creating KMS key for encryption..."
    aws kms create-key \
        --description "KMS key for Secrets Manager encryption" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --output text --query KeyMetadata.KeyId > /tmp/kms-key-id.txt
    
    export KMS_KEY_ID=$(cat /tmp/kms-key-id.txt)
    
    # Create KMS key alias
    aws kms create-alias \
        --alias-name "${KMS_KEY_ALIAS}" \
        --target-key-id "${KMS_KEY_ID}"
    
    log "KMS key created: $KMS_KEY_ID"
    log "KMS key alias created: $KMS_KEY_ALIAS"
    
    # Step 3: Create IAM role for Lambda rotation function
    info "Creating IAM role for Lambda rotation function..."
    
    cat > /tmp/lambda-trust-policy.json << EOF
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
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    log "IAM role created: $IAM_ROLE_NAME"
    
    # Step 4: Create custom IAM policy for Secrets Manager access
    info "Creating custom IAM policy for Secrets Manager access..."
    
    cat > /tmp/secrets-manager-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:PutSecretValue",
                "secretsmanager:UpdateSecretVersionStage"
            ],
            "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:Encrypt",
                "kms:GenerateDataKey*",
                "kms:ReEncrypt*"
            ],
            "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "SecretsManagerRotationPolicy-${RANDOM_SUFFIX}" \
        --policy-document file:///tmp/secrets-manager-policy.json
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerRotationPolicy-${RANDOM_SUFFIX}"
    
    log "Secrets Manager policy created and attached"
    
    # Wait for IAM role propagation
    wait_for_iam_propagation "${IAM_ROLE_NAME}"
    
    # Step 5: Create database secret with structured data
    info "Creating database secret with structured data..."
    
    DB_PASSWORD=$(aws secretsmanager get-random-password \
        --password-length 20 \
        --exclude-characters '"@/\' \
        --require-each-included-type \
        --output text --query RandomPassword)
    
    cat > /tmp/db-credentials.json << EOF
{
    "engine": "mysql",
    "host": "demo-database.cluster-abc123.us-east-1.rds.amazonaws.com",
    "username": "admin",
    "password": "$DB_PASSWORD",
    "dbname": "myapp",
    "port": 3306
}
EOF
    
    aws secretsmanager create-secret \
        --name "${SECRET_NAME}" \
        --description "Database credentials for demo application" \
        --secret-string file:///tmp/db-credentials.json \
        --kms-key-id "${KMS_KEY_ID}" \
        --tags Key=Environment,Value=Demo Key=Application,Value=MyApp
    
    log "Database secret created: $SECRET_NAME"
    
    # Step 6: Create Lambda rotation function
    info "Creating Lambda rotation function..."
    
    cat > /tmp/rotation_lambda.py << 'EOF'
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to handle secret rotation
    """
    secretsmanager = boto3.client('secretsmanager')
    
    secret_arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    
    logger.info(f"Rotation step: {step} for secret: {secret_arn}")
    
    if step == "createSecret":
        create_secret(secretsmanager, secret_arn, token)
    elif step == "setSecret":
        set_secret(secretsmanager, secret_arn, token)
    elif step == "testSecret":
        test_secret(secretsmanager, secret_arn, token)
    elif step == "finishSecret":
        finish_secret(secretsmanager, secret_arn, token)
    else:
        logger.error(f"Invalid step parameter: {step}")
        raise ValueError(f"Invalid step parameter: {step}")
    
    return {"statusCode": 200, "body": "Rotation completed successfully"}

def create_secret(secretsmanager, secret_arn, token):
    """Create a new secret version"""
    try:
        current_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT"
        )
        
        # Parse current secret
        current_data = json.loads(current_secret['SecretString'])
        
        # Generate new password
        new_password = secretsmanager.get_random_password(
            PasswordLength=20,
            ExcludeCharacters='"@/\\',
            RequireEachIncludedType=True
        )['RandomPassword']
        
        # Update password in secret data
        current_data['password'] = new_password
        
        # Create new secret version
        secretsmanager.put_secret_value(
            SecretId=secret_arn,
            ClientRequestToken=token,
            SecretString=json.dumps(current_data),
            VersionStages=['AWSPENDING']
        )
        
        logger.info("createSecret: Successfully created new secret version")
        
    except Exception as e:
        logger.error(f"createSecret: Error creating secret: {str(e)}")
        raise

def set_secret(secretsmanager, secret_arn, token):
    """Set the secret in the service"""
    logger.info("setSecret: In a real implementation, this would update the database user password")
    # In a real implementation, you would connect to the database
    # and update the user's password here

def test_secret(secretsmanager, secret_arn, token):
    """Test the secret"""
    logger.info("testSecret: In a real implementation, this would test database connectivity")
    # In a real implementation, you would test the database connection
    # with the new credentials here

def finish_secret(secretsmanager, secret_arn, token):
    """Finish the rotation"""
    try:
        # Move AWSCURRENT to AWSPREVIOUS
        secretsmanager.update_secret_version_stage(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT",
            MoveToVersionId=token,
            RemoveFromVersionId=get_current_version_id(secretsmanager, secret_arn)
        )
        
        logger.info("finishSecret: Successfully completed rotation")
        
    except Exception as e:
        logger.error(f"finishSecret: Error finishing rotation: {str(e)}")
        raise

def get_current_version_id(secretsmanager, secret_arn):
    """Get the current version ID"""
    versions = secretsmanager.list_secret_version_ids(SecretId=secret_arn)
    
    for version in versions['Versions']:
        if 'AWSCURRENT' in version['VersionStages']:
            return version['VersionId']
    
    return None
EOF
    
    # Create deployment package
    zip /tmp/rotation_lambda.zip /tmp/rotation_lambda.py >/dev/null 2>&1
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler rotation_lambda.lambda_handler \
        --zip-file fileb:///tmp/rotation_lambda.zip \
        --timeout 60 \
        --description "Lambda function for rotating Secrets Manager secrets"
    
    log "Lambda rotation function created: $LAMBDA_FUNCTION_NAME"
    
    # Step 7: Configure automatic rotation
    info "Configuring automatic rotation..."
    
    # Get Lambda function ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query Configuration.FunctionArn \
        --output text)
    
    # Grant Secrets Manager permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id SecretsManagerInvoke \
        --action lambda:InvokeFunction \
        --principal secretsmanager.amazonaws.com
    
    # Configure automatic rotation (every 7 days)
    aws secretsmanager rotate-secret \
        --secret-id "${SECRET_NAME}" \
        --rotation-lambda-arn "${LAMBDA_ARN}" \
        --rotation-rules '{"ScheduleExpression": "rate(7 days)"}'
    
    log "Automatic rotation configured for $SECRET_NAME"
    
    # Step 8: Create cross-account access policy
    info "Creating cross-account access policy..."
    
    cat > /tmp/cross-account-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCrossAccountAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
            },
            "Action": "secretsmanager:GetSecretValue",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "secretsmanager:ResourceTag/Environment": "Demo"
                }
            }
        }
    ]
}
EOF
    
    aws secretsmanager put-resource-policy \
        --secret-id "${SECRET_NAME}" \
        --resource-policy file:///tmp/cross-account-policy.json \
        --block-public-policy
    
    log "Cross-account access policy configured"
    
    # Step 9: Create application integration example
    info "Creating application integration example..."
    
    cat > /tmp/app_integration.py << 'EOF'
import boto3
import json
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_secret(secret_name, region_name="us-east-1"):
    """
    Retrieve a secret from AWS Secrets Manager
    """
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        
        # Parse the secret value
        secret_data = json.loads(response['SecretString'])
        
        logger.info(f"Successfully retrieved secret: {secret_name}")
        return secret_data
        
    except ClientError as e:
        logger.error(f"Error retrieving secret {secret_name}: {e}")
        raise
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing secret JSON: {e}")
        raise

def connect_to_database(secret_name):
    """
    Example database connection using secrets
    """
    try:
        # Get database credentials from Secrets Manager
        credentials = get_secret(secret_name)
        
        # Extract connection parameters
        host = credentials['host']
        port = credentials['port']
        username = credentials['username']
        password = credentials['password']
        database = credentials['dbname']
        
        # In a real application, you would use these credentials
        # to connect to your database
        print(f"Connecting to database: {host}:{port}/{database}")
        print(f"Username: {username}")
        print("Password: [REDACTED]")
        
        return True
        
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return False

if __name__ == "__main__":
    # Example usage
    SECRET_NAME = "demo-db-credentials-123456"
    
    if connect_to_database(SECRET_NAME):
        print("✅ Database connection successful")
    else:
        print("❌ Database connection failed")
EOF
    
    log "Application integration example created"
    
    # Step 10: Set up CloudWatch monitoring
    info "Setting up CloudWatch monitoring..."
    
    cat > /tmp/dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/SecretsManager", "RotationSucceeded", "SecretName", "${SECRET_NAME}"],
                    ["AWS/SecretsManager", "RotationFailed", "SecretName", "${SECRET_NAME}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Secret Rotation Status"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "SecretsManager-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard.json
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "SecretsManager-RotationFailure-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when secret rotation fails" \
        --metric-name RotationFailed \
        --namespace AWS/SecretsManager \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=SecretName,Value="${SECRET_NAME}"
    
    log "CloudWatch monitoring configured"
    
    # Save deployment state
    cat > .deployment_state << EOF
# Deployment state file - DO NOT EDIT MANUALLY
AWS_REGION="$AWS_REGION"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
SECRET_NAME="$SECRET_NAME"
LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
IAM_ROLE_NAME="$IAM_ROLE_NAME"
KMS_KEY_ALIAS="$KMS_KEY_ALIAS"
KMS_KEY_ID="$KMS_KEY_ID"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
DEPLOYMENT_DATE="$(date)"
EOF
    
    # Final validation
    info "Running final validation..."
    
    # Validate secret creation
    if validate_resource "Secret" "$SECRET_NAME" "aws secretsmanager describe-secret --secret-id $SECRET_NAME"; then
        log "✅ Secret validation passed"
    else
        error "❌ Secret validation failed"
        exit 1
    fi
    
    # Validate Lambda function
    if validate_resource "Lambda Function" "$LAMBDA_FUNCTION_NAME" "aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME"; then
        log "✅ Lambda function validation passed"
    else
        error "❌ Lambda function validation failed"
        exit 1
    fi
    
    # Validate IAM role
    if validate_resource "IAM Role" "$IAM_ROLE_NAME" "aws iam get-role --role-name $IAM_ROLE_NAME"; then
        log "✅ IAM role validation passed"
    else
        error "❌ IAM role validation failed"
        exit 1
    fi
    
    # Display deployment summary
    echo
    log "🎉 Deployment completed successfully!"
    echo
    info "Deployment Summary:"
    info "=================="
    info "Region: $AWS_REGION"
    info "Account ID: $AWS_ACCOUNT_ID"
    info "Secret Name: $SECRET_NAME"
    info "Lambda Function: $LAMBDA_FUNCTION_NAME"
    info "IAM Role: $IAM_ROLE_NAME"
    info "KMS Key: $KMS_KEY_ID"
    info "KMS Alias: $KMS_KEY_ALIAS"
    echo
    info "Next Steps:"
    info "- Test secret retrieval: aws secretsmanager get-secret-value --secret-id $SECRET_NAME"
    info "- View CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=SecretsManager-$RANDOM_SUFFIX"
    info "- Monitor rotation status: aws secretsmanager describe-secret --secret-id $SECRET_NAME --query 'RotationEnabled'"
    echo
    warn "Remember: This deployment creates billable resources. Run ./destroy.sh to clean up when done."
    echo
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -v, --verbose        Enable verbose logging"
    echo "  --dry-run           Show what would be deployed without actually deploying"
    echo "  --region REGION     Override AWS region (default: from AWS config)"
    echo ""
    echo "Examples:"
    echo "  $0                   Deploy with default settings"
    echo "  $0 --verbose         Deploy with verbose logging"
    echo "  $0 --dry-run         Show deployment plan without executing"
    echo "  $0 --region us-west-2 Deploy to us-west-2 region"
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Override region if specified
if [ -n "$CUSTOM_REGION" ]; then
    export AWS_DEFAULT_REGION="$CUSTOM_REGION"
fi

# Main execution
main() {
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN MODE - No resources will be created"
        info "This would deploy the AWS Secrets Manager solution with:"
        info "- KMS key for encryption"
        info "- IAM role and policies for Lambda function"
        info "- Database secret with structured data"
        info "- Lambda function for automatic rotation"
        info "- CloudWatch monitoring and alarms"
        info "- Cross-account access policies"
        exit 0
    fi
    
    log "Starting AWS Secrets Manager deployment script"
    check_prerequisites
    deploy
    log "Deployment script completed successfully"
}

# Run main function
main "$@"