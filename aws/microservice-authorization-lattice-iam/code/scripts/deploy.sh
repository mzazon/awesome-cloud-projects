#!/bin/bash

# Microservice Authorization with VPC Lattice and IAM - Deployment Script
# This script deploys the complete infrastructure for the microservice authorization recipe

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
}

# Help function
show_help() {
    cat << EOF
Microservice Authorization with VPC Lattice and IAM - Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -r, --region        AWS region (defaults to current CLI region)
    -p, --prefix        Resource name prefix (defaults to 'microservice-auth')
    -d, --dry-run       Show what would be done without executing
    -v, --verbose       Enable verbose output
    --skip-cleanup      Skip cleanup on failure

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --region us-west-2                # Deploy in specific region
    $0 --prefix my-demo                   # Deploy with custom prefix
    $0 --dry-run                         # Preview deployment

PREREQUISITES:
    - AWS CLI v2.0 or later installed and configured
    - VPC Lattice service available in target region
    - Appropriate IAM permissions for all services
    - jq command-line JSON processor

EOF
}

# Default values
DRY_RUN=false
VERBOSE=false
SKIP_CLEANUP=false
RESOURCE_PREFIX="microservice-auth"
CLEANUP_ON_FAILURE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            RESOURCE_PREFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-cleanup)
            SKIP_CLEANUP=true
            CLEANUP_ON_FAILURE=false
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | grep -oE 'aws-cli/[0-9]+' | cut -d'/' -f2)
    if [[ "$AWS_CLI_VERSION" -lt 2 ]]; then
        error "AWS CLI version 2.0 or later is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set. Use --region parameter or configure AWS CLI."
            exit 1
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Failed to get AWS account ID"
        exit 1
    fi
    export AWS_ACCOUNT_ID
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export NETWORK_NAME="${RESOURCE_PREFIX}-network-${RANDOM_SUFFIX}"
    export SERVICE_NAME="${RESOURCE_PREFIX}-order-service-${RANDOM_SUFFIX}"
    export CLIENT_FUNCTION="${RESOURCE_PREFIX}-product-service-${RANDOM_SUFFIX}"
    export PROVIDER_FUNCTION="${RESOURCE_PREFIX}-order-service-${RANDOM_SUFFIX}"
    export LOG_GROUP="/aws/vpclattice/${NETWORK_NAME}"
    export PRODUCT_ROLE_NAME="ProductServiceRole-${RANDOM_SUFFIX}"
    export ORDER_ROLE_NAME="OrderServiceRole-${RANDOM_SUFFIX}"
    
    # Check VPC Lattice availability
    if ! aws vpc-lattice list-service-networks --region "$AWS_REGION" &> /dev/null; then
        error "VPC Lattice is not available in region: $AWS_REGION"
        exit 1
    fi
    
    log "Environment configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account: $AWS_ACCOUNT_ID"
    log "  Resource Suffix: $RANDOM_SUFFIX"
    log "  Network Name: $NETWORK_NAME"
    log "  Service Name: $SERVICE_NAME"
    
    success "Environment setup completed"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description"
        echo "  Command: $cmd"
        return 0
    fi
    
    log "$description"
    if eval "$cmd"; then
        success "$description completed"
        return 0
    else
        error "$description failed"
        return 1
    fi
}

# Create IAM roles function
create_iam_roles() {
    log "Creating IAM roles for microservices..."
    
    # Create trust policy for Lambda execution
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
    
    # Create IAM role for product service (client)
    execute_command \
        "aws iam create-role \
            --role-name $PRODUCT_ROLE_NAME \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
            --tags Key=Environment,Value=Demo Key=Purpose,Value=MicroserviceAuth" \
        "Creating product service IAM role"
    
    # Create IAM role for order service (provider)
    execute_command \
        "aws iam create-role \
            --role-name $ORDER_ROLE_NAME \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
            --tags Key=Environment,Value=Demo Key=Purpose,Value=MicroserviceAuth" \
        "Creating order service IAM role"
    
    # Attach basic Lambda execution policy to both roles
    execute_command \
        "aws iam attach-role-policy \
            --role-name $PRODUCT_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching Lambda execution policy to product service role"
    
    execute_command \
        "aws iam attach-role-policy \
            --role-name $ORDER_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching Lambda execution policy to order service role"
    
    success "IAM roles created successfully"
}

# Create VPC Lattice service network function
create_service_network() {
    log "Creating VPC Lattice service network..."
    
    local cmd="aws vpc-lattice create-service-network \
        --name $NETWORK_NAME \
        --auth-type AWS_IAM \
        --tags Key=Environment,Value=Demo Key=Purpose,Value=MicroserviceAuth"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Creating VPC Lattice service network"
        echo "  Command: $cmd"
        # Mock response for dry run
        export NETWORK_ID="sn-mock123456"
        export NETWORK_ARN="arn:aws:vpc-lattice:$AWS_REGION:$AWS_ACCOUNT_ID:servicenetwork/sn-mock123456"
        return 0
    fi
    
    log "Creating VPC Lattice service network"
    local response
    if response=$(eval "$cmd"); then
        export NETWORK_ID=$(echo "$response" | jq -r '.id')
        export NETWORK_ARN=$(echo "$response" | jq -r '.arn')
        log "Network ID: $NETWORK_ID"
        log "Network ARN: $NETWORK_ARN"
        success "VPC Lattice service network created"
    else
        error "Failed to create VPC Lattice service network"
        return 1
    fi
}

# Create Lambda functions function
create_lambda_functions() {
    log "Creating Lambda functions for microservices..."
    
    # Create product service (client) Lambda function code
    cat > /tmp/product-service.py << 'EOF'
import json
import boto3
import urllib3

def lambda_handler(event, context):
    # Simulate product service calling order service
    try:
        # In a real scenario, this would make HTTP requests to VPC Lattice service
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Product service authenticated and ready',
                'service': 'product-service',
                'role': context.invoked_function_arn.split(':')[4]
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create order service (provider) Lambda function code
    cat > /tmp/order-service.py << 'EOF'
import json

def lambda_handler(event, context):
    # Simulate order service processing requests
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Order service processing request',
            'service': 'order-service',
            'requestId': context.aws_request_id,
            'orders': [
                {'id': 1, 'product': 'Widget A', 'quantity': 5},
                {'id': 2, 'product': 'Widget B', 'quantity': 3}
            ]
        })
    }
EOF
    
    # Package Lambda functions
    if [[ "$DRY_RUN" == "false" ]]; then
        (cd /tmp && zip -q product-service.zip product-service.py)
        (cd /tmp && zip -q order-service.zip order-service.py)
    fi
    
    # Get role ARNs (wait for role creation to propagate)
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for IAM role propagation..."
        sleep 10
        
        PRODUCT_ROLE_ARN=$(aws iam get-role \
            --role-name "$PRODUCT_ROLE_NAME" \
            --query 'Role.Arn' --output text)
        
        ORDER_ROLE_ARN=$(aws iam get-role \
            --role-name "$ORDER_ROLE_NAME" \
            --query 'Role.Arn' --output text)
    else
        PRODUCT_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$PRODUCT_ROLE_NAME"
        ORDER_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$ORDER_ROLE_NAME"
    fi
    
    # Create product service Lambda
    execute_command \
        "aws lambda create-function \
            --function-name $CLIENT_FUNCTION \
            --runtime python3.12 \
            --role $PRODUCT_ROLE_ARN \
            --handler product-service.lambda_handler \
            --zip-file fileb:///tmp/product-service.zip \
            --timeout 30 \
            --tags Environment=Demo,Purpose=MicroserviceAuth" \
        "Creating product service Lambda function"
    
    # Create order service Lambda
    execute_command \
        "aws lambda create-function \
            --function-name $PROVIDER_FUNCTION \
            --runtime python3.12 \
            --role $ORDER_ROLE_ARN \
            --handler order-service.lambda_handler \
            --zip-file fileb:///tmp/order-service.zip \
            --timeout 30 \
            --tags Environment=Demo,Purpose=MicroserviceAuth" \
        "Creating order service Lambda function"
    
    success "Lambda functions created successfully"
}

# Create VPC Lattice service function
create_lattice_service() {
    log "Creating VPC Lattice service with Lambda target..."
    
    local cmd="aws vpc-lattice create-service \
        --name $SERVICE_NAME \
        --auth-type AWS_IAM"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Creating VPC Lattice service"
        echo "  Command: $cmd"
        export SERVICE_ID="svc-mock123456"
        export SERVICE_ARN="arn:aws:vpc-lattice:$AWS_REGION:$AWS_ACCOUNT_ID:service/svc-mock123456"
        export TARGET_GROUP_ID="tg-mock123456"
        return 0
    fi
    
    log "Creating VPC Lattice service"
    local response
    if response=$(eval "$cmd"); then
        export SERVICE_ID=$(echo "$response" | jq -r '.id')
        export SERVICE_ARN=$(echo "$response" | jq -r '.arn')
        log "Service ID: $SERVICE_ID"
        log "Service ARN: $SERVICE_ARN"
    else
        error "Failed to create VPC Lattice service"
        return 1
    fi
    
    # Create target group for Lambda function
    execute_command \
        "aws vpc-lattice create-target-group \
            --name order-targets-${RANDOM_SUFFIX} \
            --type LAMBDA" \
        "Creating target group for Lambda function"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local tg_response
        tg_response=$(aws vpc-lattice create-target-group \
            --name "order-targets-${RANDOM_SUFFIX}" \
            --type LAMBDA)
        export TARGET_GROUP_ID=$(echo "$tg_response" | jq -r '.id')
        log "Target Group ID: $TARGET_GROUP_ID"
    fi
    
    # Register Lambda function as target
    execute_command \
        "aws vpc-lattice register-targets \
            --target-group-identifier $TARGET_GROUP_ID \
            --targets id=$PROVIDER_FUNCTION" \
        "Registering Lambda function as target"
    
    # Create listener for the service
    execute_command \
        "aws vpc-lattice create-listener \
            --service-identifier $SERVICE_ID \
            --name order-listener \
            --protocol HTTP \
            --port 80 \
            --default-action forward='{\"targetGroups\":[{\"targetGroupIdentifier\":\"$TARGET_GROUP_ID\"}]}'" \
        "Creating listener for the service"
    
    success "VPC Lattice service created successfully"
}

# Associate service with network function
associate_service_network() {
    log "Associating service with service network..."
    
    execute_command \
        "aws vpc-lattice create-service-network-service-association \
            --service-network-identifier $NETWORK_ID \
            --service-identifier $SERVICE_ID" \
        "Creating service network association"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for service association to become active..."
        sleep 30
        
        local status
        status=$(aws vpc-lattice get-service-network-service-association \
            --service-network-service-association-identifier \
            "${NETWORK_ID}/${SERVICE_ID}" \
            --query 'status' --output text)
        
        log "Association status: $status"
    fi
    
    success "Service associated with network successfully"
}

# Create authorization policy function
create_auth_policy() {
    log "Creating fine-grained authorization policy..."
    
    # Create auth policy for fine-grained access control
    cat > /tmp/auth-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowProductServiceAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PRODUCT_ROLE_NAME}"
      },
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": "arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:service/${SERVICE_ID}/*",
      "Condition": {
        "StringEquals": {
          "vpc-lattice-svcs:RequestMethod": ["GET", "POST"]
        },
        "StringLike": {
          "vpc-lattice-svcs:RequestPath": "/orders*"
        }
      }
    },
    {
      "Sid": "DenyUnauthorizedAccess",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": "arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:service/${SERVICE_ID}/*",
      "Condition": {
        "StringNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PRODUCT_ROLE_NAME}"
        }
      }
    }
  ]
}
EOF
    
    # Apply auth policy to the service
    execute_command \
        "aws vpc-lattice put-auth-policy \
            --resource-identifier $SERVICE_ID \
            --policy file:///tmp/auth-policy.json" \
        "Applying authorization policy to service"
    
    success "Fine-grained authorization policy applied"
}

# Enable monitoring function
enable_monitoring() {
    log "Enabling CloudWatch monitoring and access logging..."
    
    # Create CloudWatch log group for VPC Lattice access logs
    execute_command \
        "aws logs create-log-group \
            --log-group-name $LOG_GROUP" \
        "Creating CloudWatch log group"
    
    # Enable access logging for the service network
    execute_command \
        "aws vpc-lattice create-access-log-subscription \
            --resource-identifier $NETWORK_ID \
            --destination-arn arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:$LOG_GROUP" \
        "Enabling access logging for service network"
    
    # Create CloudWatch alarm for authorization failures
    execute_command \
        "aws cloudwatch put-metric-alarm \
            --alarm-name VPC-Lattice-Auth-Failures-${RANDOM_SUFFIX} \
            --alarm-description 'Monitor VPC Lattice authorization failures' \
            --metric-name 4XXError \
            --namespace AWS/VpcLattice \
            --statistic Sum \
            --period 300 \
            --threshold 5 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --dimensions Name=ServiceNetwork,Value=$NETWORK_ID" \
        "Creating CloudWatch alarm for authorization failures"
    
    success "CloudWatch monitoring and access logging enabled"
}

# Configure Lambda permissions function
configure_lambda_permissions() {
    log "Configuring Lambda permissions for VPC Lattice integration..."
    
    # Grant VPC Lattice permission to invoke Lambda function
    execute_command \
        "aws lambda add-permission \
            --function-name $PROVIDER_FUNCTION \
            --statement-id vpc-lattice-invoke \
            --action lambda:InvokeFunction \
            --principal vpc-lattice.amazonaws.com" \
        "Granting VPC Lattice permission to invoke Lambda"
    
    # Create policy for product service to invoke VPC Lattice services
    cat > /tmp/vpc-lattice-invoke-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "vpc-lattice-svcs:Invoke"
      ],
      "Resource": "arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:service/${SERVICE_ID}/*"
    }
  ]
}
EOF
    
    execute_command \
        "aws iam put-role-policy \
            --role-name $PRODUCT_ROLE_NAME \
            --policy-name VPCLatticeInvokePolicy \
            --policy-document file:///tmp/vpc-lattice-invoke-policy.json" \
        "Adding VPC Lattice invoke policy to product service role"
    
    success "Lambda permissions configured for VPC Lattice integration"
}

# Save deployment state function
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > /tmp/deployment-state.json << EOF
{
  "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "awsRegion": "$AWS_REGION",
  "awsAccountId": "$AWS_ACCOUNT_ID",
  "resourcePrefix": "$RESOURCE_PREFIX",
  "randomSuffix": "$RANDOM_SUFFIX",
  "networkName": "$NETWORK_NAME",
  "networkId": "${NETWORK_ID:-}",
  "networkArn": "${NETWORK_ARN:-}",
  "serviceName": "$SERVICE_NAME",
  "serviceId": "${SERVICE_ID:-}",
  "serviceArn": "${SERVICE_ARN:-}",
  "targetGroupId": "${TARGET_GROUP_ID:-}",
  "clientFunction": "$CLIENT_FUNCTION",
  "providerFunction": "$PROVIDER_FUNCTION",
  "productRoleName": "$PRODUCT_ROLE_NAME",
  "orderRoleName": "$ORDER_ROLE_NAME",
  "logGroup": "$LOG_GROUP"
}
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp /tmp/deployment-state.json "./deployment-state-${RANDOM_SUFFIX}.json"
        success "Deployment state saved to deployment-state-${RANDOM_SUFFIX}.json"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would save deployment state to deployment-state-${RANDOM_SUFFIX}.json"
    fi
}

# Cleanup function for failed deployments
cleanup_on_failure() {
    if [[ "$CLEANUP_ON_FAILURE" == "true" && "$DRY_RUN" == "false" ]]; then
        warning "Deployment failed. Cleaning up resources..."
        
        # Call destroy script if it exists
        if [[ -f "./destroy.sh" ]]; then
            bash ./destroy.sh --auto-confirm --prefix "$RESOURCE_PREFIX" --suffix "$RANDOM_SUFFIX" || true
        fi
    fi
}

# Main deployment function
main() {
    log "Starting microservice authorization deployment..."
    log "Script version: 1.0"
    log "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Set trap for cleanup on failure
    if [[ "$CLEANUP_ON_FAILURE" == "true" ]]; then
        trap cleanup_on_failure ERR
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_roles
    create_service_network
    create_lambda_functions
    create_lattice_service
    associate_service_network
    create_auth_policy
    enable_monitoring
    configure_lambda_permissions
    save_deployment_state
    
    # Clean up temporary files
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f /tmp/lambda-trust-policy.json /tmp/auth-policy.json /tmp/vpc-lattice-invoke-policy.json
        rm -f /tmp/product-service.py /tmp/order-service.py /tmp/*.zip
        rm -f /tmp/deployment-state.json
    fi
    
    success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "=== Deployment Summary ==="
        echo "Network ID: ${NETWORK_ID:-N/A}"
        echo "Service ID: ${SERVICE_ID:-N/A}"
        echo "Product Service Function: $CLIENT_FUNCTION"
        echo "Order Service Function: $PROVIDER_FUNCTION"
        echo "Log Group: $LOG_GROUP"
        echo ""
        echo "To validate the deployment, run:"
        echo "aws lambda invoke --function-name $CLIENT_FUNCTION --payload '{}' response.json && cat response.json"
        echo ""
        echo "To clean up resources, run:"
        echo "./destroy.sh --prefix $RESOURCE_PREFIX --suffix $RANDOM_SUFFIX"
    fi
}

# Run main function
main "$@"