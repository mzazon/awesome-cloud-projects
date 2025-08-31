#!/bin/bash

# Blue-Green Deployments with VPC Lattice and Lambda - Deployment Script
# This script automates the deployment of a blue-green deployment infrastructure
# using AWS VPC Lattice, Lambda functions, and CloudWatch monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI version
check_aws_cli_version() {
    local version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $version | cut -d. -f1)
    
    if [ "$major_version" -lt 2 ]; then
        error "AWS CLI version 2 or higher is required. Current version: $version"
        exit 1
    fi
    
    log "AWS CLI version check passed: $version"
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log "AWS credentials validated for account: $account_id"
    info "Using identity: $user_arn"
}

# Function to check required permissions
check_permissions() {
    local required_services=(
        "lambda"
        "vpc-lattice" 
        "iam"
        "cloudwatch"
        "sts"
    )
    
    info "Checking AWS service permissions..."
    
    for service in "${required_services[@]}"; do
        case $service in
            "lambda")
                if ! aws lambda list-functions --max-items 1 >/dev/null 2>&1; then
                    error "Missing Lambda permissions"
                    exit 1
                fi
                ;;
            "vpc-lattice")
                if ! aws vpc-lattice list-services --max-results 1 >/dev/null 2>&1; then
                    error "Missing VPC Lattice permissions"
                    exit 1
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 >/dev/null 2>&1; then
                    error "Missing IAM permissions"
                    exit 1
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-metrics --max-records 1 >/dev/null 2>&1; then
                    error "Missing CloudWatch permissions"
                    exit 1
                fi
                ;;
            "sts")
                if ! aws sts get-caller-identity >/dev/null 2>&1; then
                    error "Missing STS permissions"
                    exit 1
                fi
                ;;
        esac
    done
    
    log "All required permissions verified"
}

# Function to generate random suffix
generate_random_suffix() {
    if ! aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword >/dev/null 2>&1; then
        
        warn "Unable to use AWS Secrets Manager for random generation, using date-based suffix"
        echo "$(date +%s | tail -c 7)"
    else
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword
    fi
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(generate_random_suffix)
    
    # Set resource names
    export SERVICE_NAME="ecommerce-api-${RANDOM_SUFFIX}"
    export BLUE_FUNCTION_NAME="ecommerce-blue-${RANDOM_SUFFIX}"
    export GREEN_FUNCTION_NAME="ecommerce-green-${RANDOM_SUFFIX}"
    export BLUE_TG_NAME="blue-tg-${RANDOM_SUFFIX}"
    export GREEN_TG_NAME="green-tg-${RANDOM_SUFFIX}"
    export LATTICE_SERVICE_NAME="lattice-service-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="LambdaVPCLatticeRole-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="ecommerce-network-${RANDOM_SUFFIX}"
    
    log "Environment configured with suffix: ${RANDOM_SUFFIX}"
    info "Region: $AWS_REGION"
    info "Account ID: $AWS_ACCOUNT_ID"
    
    # Save environment variables to file for cleanup script
    cat > .deployment-env << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export SERVICE_NAME="$SERVICE_NAME"
export BLUE_FUNCTION_NAME="$BLUE_FUNCTION_NAME"
export GREEN_FUNCTION_NAME="$GREEN_FUNCTION_NAME"
export BLUE_TG_NAME="$BLUE_TG_NAME"
export GREEN_TG_NAME="$GREEN_TG_NAME"
export LATTICE_SERVICE_NAME="$LATTICE_SERVICE_NAME"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export SERVICE_NETWORK_NAME="$SERVICE_NETWORK_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "lambda.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags Key=Purpose,Value=blue-green-deployment \
               Key=Environment,Value=demo \
        >/dev/null 2>&1
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 15
    
    # Get the role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query Role.Arn --output text)
    
    log "IAM role created: $LAMBDA_ROLE_ARN"
}

# Function to create Lambda function code
create_lambda_code() {
    local environment=$1
    local version=$2
    local filename="${environment}_function.py"
    
    info "Creating Lambda function code for $environment environment..."
    
    if [ "$environment" = "blue" ]; then
        cat > "$filename" << 'EOF'
import json
import time

def lambda_handler(event, context):
    # Blue environment - stable production version
    response_data = {
        'environment': 'blue',
        'version': '1.0.0',
        'message': 'Hello from Blue Environment!',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Environment': 'blue'
        },
        'body': json.dumps(response_data)
    }
EOF
    else
        cat > "$filename" << 'EOF'
import json
import time

def lambda_handler(event, context):
    # Green environment - new version being deployed
    response_data = {
        'environment': 'green',
        'version': '2.0.0',
        'message': 'Hello from Green Environment!',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id,
        'new_feature': 'Enhanced response with additional metadata'
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Environment': 'green'
        },
        'body': json.dumps(response_data)
    }
EOF
    fi
    
    # Package the function
    zip "${environment}_function.zip" "$filename" >/dev/null 2>&1
    
    log "Lambda code created and packaged for $environment environment"
}

# Function to create Lambda function
create_lambda_function() {
    local environment=$1
    local function_name=$2
    
    log "Creating Lambda function: $function_name..."
    
    aws lambda create-function \
        --function-name "$function_name" \
        --runtime python3.12 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler "${environment}_function.lambda_handler" \
        --zip-file "fileb://${environment}_function.zip" \
        --timeout 30 \
        --memory-size 256 \
        --environment "Variables={ENVIRONMENT=$environment}" \
        --tags Environment="$environment",Deployment=blue-green \
        >/dev/null 2>&1
    
    log "Lambda function created: $function_name"
}

# Function to create VPC Lattice service network
create_service_network() {
    log "Creating VPC Lattice service network..."
    
    aws vpc-lattice create-service-network \
        --name "$SERVICE_NETWORK_NAME" \
        --auth-type AWS_IAM \
        --tags Environment=production,Purpose=blue-green-deployment \
        >/dev/null 2>&1
    
    # Wait for service network to be created
    info "Waiting for service network to be created..."
    sleep 15
    
    # Get service network ID
    export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='$SERVICE_NETWORK_NAME'].id" \
        --output text)
    
    if [ -z "$SERVICE_NETWORK_ID" ]; then
        error "Failed to create or retrieve service network ID"
        exit 1
    fi
    
    log "VPC Lattice service network created: $SERVICE_NETWORK_ID"
}

# Function to create target group
create_target_group() {
    local environment=$1
    local tg_name=$2
    local function_name=$3
    
    log "Creating target group for $environment environment..."
    
    aws vpc-lattice create-target-group \
        --name "$tg_name" \
        --type LAMBDA \
        --tags Environment="$environment",Purpose=target-group \
        >/dev/null 2>&1
    
    # Get target group ARN
    local tg_arn=$(aws vpc-lattice list-target-groups \
        --query "items[?name=='$tg_name'].arn" \
        --output text)
    
    if [ -z "$tg_arn" ]; then
        error "Failed to create or retrieve target group ARN for $environment"
        exit 1
    fi
    
    # Add permission for VPC Lattice to invoke Lambda
    aws lambda add-permission \
        --function-name "$function_name" \
        --statement-id "vpc-lattice-$environment" \
        --principal vpc-lattice.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "$tg_arn" \
        >/dev/null 2>&1
    
    # Register Lambda function as target
    aws vpc-lattice register-targets \
        --target-group-identifier "$tg_arn" \
        --targets Id="$function_name" \
        >/dev/null 2>&1
    
    log "Target group created and Lambda function registered: $tg_name"
    
    # Save ARN for later use
    if [ "$environment" = "blue" ]; then
        export BLUE_TG_ARN="$tg_arn"
    else
        export GREEN_TG_ARN="$tg_arn"
    fi
}

# Function to create VPC Lattice service
create_lattice_service() {
    log "Creating VPC Lattice service with weighted routing..."
    
    aws vpc-lattice create-service \
        --name "$LATTICE_SERVICE_NAME" \
        --auth-type AWS_IAM \
        --tags Environment=production,Purpose=blue-green-service \
        >/dev/null 2>&1
    
    # Wait for service to be created
    info "Waiting for VPC Lattice service to be created..."
    sleep 15
    
    # Get service ARN and ID
    export SERVICE_ARN=$(aws vpc-lattice list-services \
        --query "items[?name=='$LATTICE_SERVICE_NAME'].arn" \
        --output text)
    
    export SERVICE_ID=$(aws vpc-lattice list-services \
        --query "items[?name=='$LATTICE_SERVICE_NAME'].id" \
        --output text)
    
    if [ -z "$SERVICE_ID" ]; then
        error "Failed to create or retrieve VPC Lattice service"
        exit 1
    fi
    
    # Associate service with service network
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --service-identifier "$SERVICE_ID" \
        >/dev/null 2>&1
    
    # Wait for association to complete
    info "Waiting for service network association..."
    sleep 20
    
    # Create HTTP listener with weighted routing
    aws vpc-lattice create-listener \
        --service-identifier "$SERVICE_ID" \
        --name http-listener \
        --protocol HTTP \
        --port 80 \
        --default-action "{
            \"forward\": {
                \"targetGroups\": [
                    {
                        \"targetGroupIdentifier\": \"$BLUE_TG_ARN\",
                        \"weight\": 90
                    },
                    {
                        \"targetGroupIdentifier\": \"$GREEN_TG_ARN\",
                        \"weight\": 10
                    }
                ]
            }
        }" \
        >/dev/null 2>&1
    
    log "VPC Lattice service created with weighted routing (90% blue, 10% green)"
}

# Function to configure CloudWatch monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarm for green environment error rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "${GREEN_FUNCTION_NAME}-ErrorRate" \
        --alarm-description "Monitor error rate for green environment" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="$GREEN_FUNCTION_NAME" \
        --treat-missing-data notBreaching \
        >/dev/null 2>&1
    
    # Create CloudWatch alarm for green environment duration
    aws cloudwatch put-metric-alarm \
        --alarm-name "${GREEN_FUNCTION_NAME}-Duration" \
        --alarm-description "Monitor duration for green environment" \
        --metric-name Duration \
        --namespace AWS/Lambda \
        --statistic Average \
        --period 300 \
        --threshold 10000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="$GREEN_FUNCTION_NAME" \
        --treat-missing-data notBreaching \
        >/dev/null 2>&1
    
    log "CloudWatch alarms configured for monitoring"
}

# Function to implement gradual traffic shifting
implement_traffic_shifting() {
    log "Implementing gradual traffic shifting..."
    
    # Get listener ARN for traffic shifting
    local listener_arn=$(aws vpc-lattice list-listeners \
        --service-identifier "$SERVICE_ID" \
        --query "items[0].arn" --output text)
    
    if [ -z "$listener_arn" ]; then
        error "Failed to retrieve listener ARN"
        exit 1
    fi
    
    info "Initial deployment: 90% blue, 10% green traffic"
    
    # Wait and monitor (simulated monitoring period)
    info "Monitoring green environment performance for 30 seconds..."
    sleep 30
    
    # Increase green traffic to 50%
    info "Increasing green traffic to 50%..."
    aws vpc-lattice update-listener \
        --service-identifier "$SERVICE_ID" \
        --listener-identifier "$listener_arn" \
        --default-action "{
            \"forward\": {
                \"targetGroups\": [
                    {
                        \"targetGroupIdentifier\": \"$BLUE_TG_ARN\",
                        \"weight\": 50
                    },
                    {
                        \"targetGroupIdentifier\": \"$GREEN_TG_ARN\",
                        \"weight\": 50
                    }
                ]
            }
        }" \
        >/dev/null 2>&1
    
    log "Traffic shifted to 50% blue, 50% green"
}

# Function to get service endpoint
get_service_endpoint() {
    log "Retrieving service endpoint..."
    
    SERVICE_ENDPOINT=$(aws vpc-lattice get-service \
        --service-identifier "$SERVICE_ID" \
        --query 'dnsEntry.domainName' --output text)
    
    if [ -z "$SERVICE_ENDPOINT" ]; then
        warn "Service endpoint not available yet, you can retrieve it later with:"
        warn "aws vpc-lattice get-service --service-identifier $SERVICE_ID --query 'dnsEntry.domainName' --output text"
    else
        log "Service endpoint: https://$SERVICE_ENDPOINT"
    fi
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "========================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "========================================="
    echo "Blue-Green Deployment Successfully Created!"
    echo ""
    echo "Resources Created:"
    echo "  • IAM Role: $IAM_ROLE_NAME"
    echo "  • Blue Lambda: $BLUE_FUNCTION_NAME"
    echo "  • Green Lambda: $GREEN_FUNCTION_NAME"
    echo "  • Service Network: $SERVICE_NETWORK_NAME"
    echo "  • VPC Lattice Service: $LATTICE_SERVICE_NAME"
    echo "  • Target Groups: $BLUE_TG_NAME, $GREEN_TG_NAME"
    echo ""
    echo "Traffic Distribution:"
    echo "  • Blue Environment: 50%"
    echo "  • Green Environment: 50%"
    echo ""
    if [ ! -z "$SERVICE_ENDPOINT" ]; then
        echo "Service Endpoint: https://$SERVICE_ENDPOINT"
        echo ""
    fi
    echo "Configuration saved to: .deployment-env"
    echo ""
    echo "To test the deployment:"
    echo "  curl -s https://$SERVICE_ENDPOINT | jq"
    echo ""
    echo "To clean up resources:"
    echo "  ./destroy.sh"
    echo "========================================="
}

# Function to clean up temporary files
cleanup_temp_files() {
    rm -f blue_function.py green_function.py
    rm -f blue_function.zip green_function.zip
}

# Main deployment function
main() {
    echo "================================================"
    echo "Blue-Green Deployments with VPC Lattice and Lambda"
    echo "Deployment Script v1.0"
    echo "================================================"
    echo ""
    
    # Prerequisites check
    log "Starting deployment prerequisites check..."
    
    # Check if required commands exist
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command_exists zip; then
        error "zip command is not available"
        exit 1
    fi
    
    if ! command_exists jq; then
        warn "jq is not installed - JSON parsing may be limited"
    fi
    
    # Check AWS CLI version and credentials
    check_aws_cli_version
    check_aws_credentials
    check_permissions
    
    log "Prerequisites check completed successfully"
    echo ""
    
    # Start deployment
    log "Starting blue-green deployment infrastructure creation..."
    
    # Setup environment
    setup_environment
    
    # Create IAM role
    create_iam_role
    
    # Create Lambda function code and functions
    create_lambda_code "blue" "1.0.0"
    create_lambda_code "green" "2.0.0"
    
    create_lambda_function "blue" "$BLUE_FUNCTION_NAME"
    create_lambda_function "green" "$GREEN_FUNCTION_NAME"
    
    # Create VPC Lattice infrastructure
    create_service_network
    
    create_target_group "blue" "$BLUE_TG_NAME" "$BLUE_FUNCTION_NAME"
    create_target_group "green" "$GREEN_TG_NAME" "$GREEN_FUNCTION_NAME"
    
    create_lattice_service
    
    # Configure monitoring
    configure_monitoring
    
    # Implement traffic shifting
    implement_traffic_shifting
    
    # Get service endpoint
    get_service_endpoint
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Display summary
    display_summary
    
    log "Deployment completed successfully!"
}

# Trap to clean up on exit
trap cleanup_temp_files EXIT

# Run main function
main "$@"