#!/bin/bash

# AWS URL Shortener Service Deployment Script
# This script deploys a serverless URL shortener using Lambda, DynamoDB, and API Gateway
# Based on the recipe: URL Shortener Service with Lambda

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_NAME="AWS URL Shortener Deploy"
LOG_FILE="/tmp/url-shortener-deploy-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="/tmp/url-shortener-deployment"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Progress indicator
progress() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Success indicator
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Warning indicator
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Error indicator
error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Deployment failed with exit code $exit_code"
        error "Check log file: $LOG_FILE"
        error "Run destroy.sh to clean up any partially created resources"
    fi
    # Clean up temporary files
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    exit $exit_code
}

trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
$SCRIPT_NAME

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without creating resources
    -v, --verbose       Enable verbose logging
    -r, --region        AWS region (default: from AWS CLI config)
    --suffix            Custom suffix for resource names (default: auto-generated)
    --skip-monitoring   Skip CloudWatch dashboard creation

EXAMPLES:
    $0                              # Deploy with default settings
    $0 --dry-run                    # Show deployment plan
    $0 --region us-west-2           # Deploy to specific region
    $0 --suffix mycompany           # Use custom resource suffix

PREREQUISITES:
    - AWS CLI installed and configured
    - Appropriate AWS permissions for Lambda, DynamoDB, API Gateway, CloudWatch, IAM
    - Python 3.9+ (for Lambda function)

EOF
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
CUSTOM_REGION=""
CUSTOM_SUFFIX=""
SKIP_MONITORING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -r|--region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        --suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        --skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

log "Starting $SCRIPT_NAME"
log "Log file: $LOG_FILE"

# Prerequisites check
check_prerequisites() {
    progress "Checking prerequisites..."
    
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
    
    # Check Python version
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
        PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d'.' -f1)
        PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d'.' -f2)
        if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 9 ]); then
            error "Python 3.9+ is required. Found: $PYTHON_VERSION"
            exit 1
        fi
    else
        error "Python 3 is not installed."
        exit 1
    fi
    
    # Check required AWS permissions (basic check)
    progress "Verifying AWS permissions..."
    
    local test_errors=0
    
    # Test Lambda permissions
    aws lambda list-functions --max-items 1 &>/dev/null || {
        error "Missing Lambda permissions"
        test_errors=$((test_errors + 1))
    }
    
    # Test DynamoDB permissions
    aws dynamodb list-tables --max-items 1 &>/dev/null || {
        error "Missing DynamoDB permissions"
        test_errors=$((test_errors + 1))
    }
    
    # Test API Gateway permissions
    aws apigatewayv2 get-apis --max-results 1 &>/dev/null || {
        error "Missing API Gateway permissions"
        test_errors=$((test_errors + 1))
    }
    
    # Test IAM permissions
    aws iam list-roles --max-items 1 &>/dev/null || {
        error "Missing IAM permissions"
        test_errors=$((test_errors + 1))
    }
    
    if [ $test_errors -gt 0 ]; then
        error "Missing required AWS permissions. Please check your IAM policy."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    progress "Setting up environment variables..."
    
    # Set AWS region
    if [ -n "$CUSTOM_REGION" ]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, using default: $AWS_REGION"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate or use custom suffix
    if [ -n "$CUSTOM_SUFFIX" ]; then
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export TABLE_NAME="url-shortener-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="url-shortener-${RANDOM_SUFFIX}"
    export API_NAME="url-shortener-api-${RANDOM_SUFFIX}"
    export ROLE_NAME="${FUNCTION_NAME}-role"
    export POLICY_NAME="${FUNCTION_NAME}-dynamodb-policy"
    export DASHBOARD_NAME="URLShortener-${RANDOM_SUFFIX}"
    
    log "Environment configuration:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Resource Suffix: $RANDOM_SUFFIX"
    log "  Table Name: $TABLE_NAME"
    log "  Function Name: $FUNCTION_NAME"
    log "  API Name: $API_NAME"
    
    # Save environment for cleanup script
    cat > "$TEMP_DIR/deployment-env.sh" << EOF
#!/bin/bash
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export TABLE_NAME="$TABLE_NAME"
export FUNCTION_NAME="$FUNCTION_NAME"
export API_NAME="$API_NAME"
export ROLE_NAME="$ROLE_NAME"
export POLICY_NAME="$POLICY_NAME"
export DASHBOARD_NAME="$DASHBOARD_NAME"
EOF
    
    success "Environment setup complete"
}

# Create IAM resources
create_iam_resources() {
    progress "Creating IAM role and policies..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would create IAM role: $ROLE_NAME"
        log "DRY RUN: Would create IAM policy: $POLICY_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        warning "IAM role $ROLE_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create IAM role for Lambda execution
    aws iam create-role \
        --role-name "$ROLE_NAME" \
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
        }' \
        --tags Key=Project,Value=URLShortener Key=DeployedBy,Value=DeployScript
    
    # Wait for role to be created
    progress "Waiting for IAM role to be available..."
    sleep 10
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for DynamoDB access
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query",
                        "dynamodb:Scan"
                    ],
                    "Resource": "arn:aws:dynamodb:'$AWS_REGION':'$AWS_ACCOUNT_ID':table/url-shortener-*"
                }
            ]
        }' \
        --tags Key=Project,Value=URLShortener Key=DeployedBy,Value=DeployScript
    
    # Wait for policy to be created
    sleep 5
    
    # Attach DynamoDB policy to Lambda role
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
    
    success "IAM resources created successfully"
}

# Create DynamoDB table
create_dynamodb_table() {
    progress "Creating DynamoDB table..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would create DynamoDB table: $TABLE_NAME"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
        warning "DynamoDB table $TABLE_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create DynamoDB table with on-demand billing
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=short_id,AttributeType=S \
        --key-schema \
            AttributeName=short_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=URLShortener Key=DeployedBy,Value=DeployScript
    
    # Wait for table to become active
    progress "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME"
    
    success "DynamoDB table created: $TABLE_NAME"
}

# Create Lambda function
create_lambda_function() {
    progress "Creating Lambda function..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would create Lambda function: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        warning "Lambda function $FUNCTION_NAME already exists, updating code..."
        
        # Update function code
        cd "$TEMP_DIR/lambda-function"
        zip -r ../lambda-function.zip . >/dev/null
        cd - >/dev/null
        
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file "fileb://$TEMP_DIR/lambda-function.zip"
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --environment Variables="{TABLE_NAME=$TABLE_NAME}"
        
        return 0
    fi
    
    # Create function directory and implementation
    mkdir -p "$TEMP_DIR/lambda-function"
    
    # Create the main Lambda function code
    cat > "$TEMP_DIR/lambda-function/lambda_function.py" << 'EOF'
import json
import boto3
import base64
import hashlib
import uuid
import logging
import os
from datetime import datetime, timedelta
from urllib.parse import urlparse

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Main Lambda handler for URL shortener operations"""
    
    try:
        # Extract HTTP method and path
        http_method = event['httpMethod']
        path = event['path']
        
        # Route requests based on method and path
        if http_method == 'POST' and path == '/shorten':
            return create_short_url(event)
        elif http_method == 'GET' and path.startswith('/'):
            return redirect_to_long_url(event)
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Endpoint not found'})
            }
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def create_short_url(event):
    """Create a new short URL mapping"""
    
    try:
        # Parse request body
        if event.get('isBase64Encoded', False):
            body = base64.b64decode(event['body']).decode('utf-8')
        else:
            body = event['body']
        
        request_data = json.loads(body)
        original_url = request_data.get('url')
        
        if not original_url:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'URL is required'})
            }
        
        # Validate URL format
        parsed_url = urlparse(original_url)
        if not parsed_url.scheme or not parsed_url.netloc:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Invalid URL format'})
            }
        
        # Generate short ID
        short_id = generate_short_id(original_url)
        
        # Create expiration time (30 days from now)
        expiration_time = datetime.utcnow() + timedelta(days=30)
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'short_id': short_id,
                'original_url': original_url,
                'created_at': datetime.utcnow().isoformat(),
                'expires_at': expiration_time.isoformat(),
                'click_count': 0,
                'is_active': True
            }
        )
        
        # Return success response
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'short_id': short_id,
                'short_url': f"https://your-domain.com/{short_id}",
                'original_url': original_url,
                'expires_at': expiration_time.isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating short URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Could not create short URL'})
        }

def redirect_to_long_url(event):
    """Redirect to original URL using short ID"""
    
    try:
        # Extract short ID from path
        short_id = event['path'][1:]  # Remove leading slash
        
        if not short_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short ID is required'})
            }
        
        # Retrieve from DynamoDB
        response = table.get_item(Key={'short_id': short_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL not found'})
            }
        
        item = response['Item']
        
        # Check if URL is still active
        if not item.get('is_active', True):
            return {
                'statusCode': 410,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL has been disabled'})
            }
        
        # Check expiration
        expires_at = datetime.fromisoformat(item['expires_at'])
        if datetime.utcnow() > expires_at:
            return {
                'statusCode': 410,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL has expired'})
            }
        
        # Increment click count
        table.update_item(
            Key={'short_id': short_id},
            UpdateExpression='SET click_count = click_count + :inc',
            ExpressionAttributeValues={':inc': 1}
        )
        
        # Return redirect response
        return {
            'statusCode': 302,
            'headers': {
                'Location': item['original_url'],
                'Access-Control-Allow-Origin': '*'
            },
            'body': ''
        }
        
    except Exception as e:
        logger.error(f"Error redirecting URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Could not redirect to URL'})
        }

def generate_short_id(url):
    """Generate a short ID from URL using hash"""
    
    # Create a hash of the URL with timestamp for uniqueness
    hash_input = f"{url}{datetime.utcnow().isoformat()}{uuid.uuid4().hex[:8]}"
    hash_object = hashlib.sha256(hash_input.encode())
    hash_hex = hash_object.hexdigest()
    
    # Convert to base62 for URL-safe short ID
    short_id = base62_encode(int(hash_hex[:16], 16))[:8]
    
    return short_id

def base62_encode(num):
    """Encode number to base62 string"""
    
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if num == 0:
        return alphabet[0]
    
    result = []
    while num:
        result.append(alphabet[num % 62])
        num //= 62
    
    return ''.join(reversed(result))
EOF
    
    # Create deployment package
    cd "$TEMP_DIR/lambda-function"
    zip -r ../lambda-function.zip . >/dev/null
    cd - >/dev/null
    
    # Get Lambda role ARN
    local lambda_role_arn=$(aws iam get-role \
        --role-name "$ROLE_NAME" \
        --query Role.Arn --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$lambda_role_arn" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://$TEMP_DIR/lambda-function.zip" \
        --timeout 30 \
        --memory-size 256 \
        --description "URL Shortener Service Function" \
        --environment Variables="{TABLE_NAME=$TABLE_NAME}" \
        --tags Key=Project,Value=URLShortener,Key=DeployedBy,Value=DeployScript
    
    # Wait for function to be active
    progress "Waiting for Lambda function to become active..."
    aws lambda wait function-active --function-name "$FUNCTION_NAME"
    
    success "Lambda function created: $FUNCTION_NAME"
}

# Create API Gateway
create_api_gateway() {
    progress "Creating API Gateway HTTP API..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would create API Gateway: $API_NAME"
        return 0
    fi
    
    # Check if API already exists
    local existing_api_id=$(aws apigatewayv2 get-apis \
        --query "Items[?Name=='$API_NAME'].ApiId" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_api_id" ] && [ "$existing_api_id" != "None" ]; then
        warning "API Gateway $API_NAME already exists: $existing_api_id"
        export API_ID="$existing_api_id"
    else
        # Create HTTP API
        export API_ID=$(aws apigatewayv2 create-api \
            --name "$API_NAME" \
            --protocol-type HTTP \
            --description "URL Shortener API" \
            --cors-configuration AllowCredentials=false,AllowMethods=GET,POST,OPTIONS,AllowOrigins=*,AllowHeaders=Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token \
            --tags Project=URLShortener,DeployedBy=DeployScript \
            --query ApiId --output text)
    fi
    
    # Get Lambda function ARN
    local lambda_arn=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    # Create integration
    local integration_id=$(aws apigatewayv2 create-integration \
        --api-id "$API_ID" \
        --integration-type AWS_PROXY \
        --integration-uri "$lambda_arn" \
        --payload-format-version 1.0 \
        --query IntegrationId --output text)
    
    # Create routes
    aws apigatewayv2 create-route \
        --api-id "$API_ID" \
        --route-key "POST /shorten" \
        --target "integrations/$integration_id" >/dev/null
    
    aws apigatewayv2 create-route \
        --api-id "$API_ID" \
        --route-key "GET /{proxy+}" \
        --target "integrations/$integration_id" >/dev/null
    
    # Create stage
    aws apigatewayv2 create-stage \
        --api-id "$API_ID" \
        --stage-name prod \
        --description "Production stage" \
        --auto-deploy >/dev/null
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$AWS_REGION:$AWS_ACCOUNT_ID:$API_ID/*/*/*" >/dev/null
    
    # Save API ID to environment file
    echo "export API_ID=\"$API_ID\"" >> "$TEMP_DIR/deployment-env.sh"
    
    success "API Gateway created: $API_ID"
}

# Create CloudWatch monitoring
create_monitoring() {
    if [ "$SKIP_MONITORING" = true ]; then
        progress "Skipping CloudWatch monitoring setup"
        return 0
    fi
    
    progress "Creating CloudWatch monitoring dashboard..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would create CloudWatch dashboard: $DASHBOARD_NAME"
        return 0
    fi
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            [ "AWS/Lambda", "Invocations", "FunctionName", "'$FUNCTION_NAME'" ],
                            [ ".", "Errors", ".", "." ],
                            [ ".", "Duration", ".", "." ]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "Lambda Function Metrics"
                    }
                },
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            [ "AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "'$TABLE_NAME'" ],
                            [ ".", "ConsumedWriteCapacityUnits", ".", "." ]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'$AWS_REGION'",
                        "title": "DynamoDB Table Metrics"
                    }
                }
            ]
        }' >/dev/null
    
    success "CloudWatch monitoring dashboard created: $DASHBOARD_NAME"
}

# Display deployment summary
show_deployment_summary() {
    progress "Deployment Summary"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN - No resources were actually created"
        return 0
    fi
    
    # Get API URL
    local api_url=$(aws apigatewayv2 get-api \
        --api-id "$API_ID" \
        --query ApiEndpoint --output text)
    
    log "=====================================  "
    success "URL Shortener Service Deployed Successfully!"
    log "====================================="
    log ""
    log "Resource Details:"
    log "  DynamoDB Table: $TABLE_NAME"
    log "  Lambda Function: $FUNCTION_NAME"
    log "  API Gateway: $API_NAME ($API_ID)"
    log "  IAM Role: $ROLE_NAME"
    log "  CloudWatch Dashboard: $DASHBOARD_NAME"
    log ""
    log "API Endpoints:"
    log "  Base URL: $api_url"
    log "  Create Short URL: POST $api_url/shorten"
    log "  Redirect: GET $api_url/{short_id}"
    log ""
    log "Quick Test Commands:"
    log "  # Create a short URL"
    log "  curl -X POST $api_url/shorten \\"
    log "    -H 'Content-Type: application/json' \\"
    log "    -d '{\"url\": \"https://aws.amazon.com\"}'"
    log ""
    log "Environment file saved to: $TEMP_DIR/deployment-env.sh"
    log "Log file: $LOG_FILE"
    log ""
    warning "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_resources
    create_dynamodb_table
    create_lambda_function
    create_api_gateway
    create_monitoring
    show_deployment_summary
    
    # Copy environment file to scripts directory for cleanup
    if [ ! "$DRY_RUN" = true ]; then
        cp "$TEMP_DIR/deployment-env.sh" "$(dirname "$0")/deployment-env.sh" 2>/dev/null || true
    fi
}

# Run main function
main "$@"