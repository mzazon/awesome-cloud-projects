#!/bin/bash

#######################################################################
# Private API Integration with VPC Lattice and EventBridge - Deployment Script
# 
# This script deploys the complete infrastructure for private API integration
# using VPC Lattice, EventBridge, Step Functions, and API Gateway.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for VPC Lattice, EventBridge, Step Functions, API Gateway
# - jq installed for JSON processing
#
# Usage:
#   ./deploy.sh [--dry-run] [--region REGION] [--suffix SUFFIX]
#
# Options:
#   --dry-run    Show what would be deployed without making changes
#   --region     AWS region (default: from AWS CLI config)
#   --suffix     Custom suffix for resource names (default: random)
#   --help       Show this help message
#######################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
CUSTOM_SUFFIX=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
Private API Integration with VPC Lattice and EventBridge - Deployment Script

Usage: $0 [OPTIONS]

Options:
    --dry-run           Show what would be deployed without making changes
    --region REGION     AWS region (default: from AWS CLI config)
    --suffix SUFFIX     Custom suffix for resource names (default: random)
    --help              Show this help message

Examples:
    $0                              # Deploy with default settings
    $0 --dry-run                    # Preview deployment
    $0 --region us-west-2          # Deploy to specific region
    $0 --suffix demo               # Use custom suffix

Prerequisites:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions
    - jq installed for JSON processing

For more information, see the recipe documentation.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --region)
            export AWS_DEFAULT_REGION="$2"
            shift 2
            ;;
        --suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
echo "Deployment started at $(date)" > "$LOG_FILE"

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI version 2 is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions by attempting to list resources
    local permission_errors=0
    
    if ! aws vpc-lattice list-service-networks --max-results 1 &> /dev/null; then
        error "Missing VPC Lattice permissions"
        ((permission_errors++))
    fi
    
    if ! aws events list-event-buses --limit 1 &> /dev/null; then
        error "Missing EventBridge permissions"
        ((permission_errors++))
    fi
    
    if ! aws stepfunctions list-state-machines --max-items 1 &> /dev/null; then
        error "Missing Step Functions permissions"
        ((permission_errors++))
    fi
    
    if ! aws apigateway get-rest-apis --limit 1 &> /dev/null; then
        error "Missing API Gateway permissions"
        ((permission_errors++))
    fi
    
    if [[ $permission_errors -gt 0 ]]; then
        error "Missing required AWS permissions. Please check IAM policies."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would execute: $description"
        info "[DRY RUN] Command: $cmd"
        return 0
    fi
    
    info "Executing: $description"
    if eval "$cmd"; then
        log "✅ $description completed successfully"
        return 0
    else
        error "❌ Failed: $description"
        return 1
    fi
}

# Wait for resource to be active
wait_for_resource() {
    local check_cmd="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local sleep_interval="${4:-10}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would wait for $resource_name to become active"
        return 0
    fi
    
    info "Waiting for $resource_name to become active..."
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        if eval "$check_cmd" &> /dev/null; then
            log "✅ $resource_name is now active"
            return 0
        fi
        
        ((attempts++))
        info "Attempt $attempts/$max_attempts - waiting ${sleep_interval}s..."
        sleep "$sleep_interval"
    done
    
    error "❌ $resource_name did not become active within expected time"
    return 1
}

# Generate environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export VPC_LATTICE_SERVICE_NETWORK="private-api-network-${RANDOM_SUFFIX}"
    export RESOURCE_CONFIG_NAME="private-api-config-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_BUS_NAME="private-api-bus-${RANDOM_SUFFIX}"
    export STEP_FUNCTION_NAME="private-api-workflow-${RANDOM_SUFFIX}"
    export API_GATEWAY_NAME="private-demo-api-${RANDOM_SUFFIX}"
    
    # Get availability zones
    local az_list=($(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[].ZoneName' --output text))
    export AZ1="${az_list[0]}"
    export AZ2="${az_list[1]}"
    
    log "Environment setup completed"
    log "AWS Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export VPC_LATTICE_SERVICE_NETWORK="$VPC_LATTICE_SERVICE_NETWORK"
export RESOURCE_CONFIG_NAME="$RESOURCE_CONFIG_NAME"
export EVENTBRIDGE_BUS_NAME="$EVENTBRIDGE_BUS_NAME"
export STEP_FUNCTION_NAME="$STEP_FUNCTION_NAME"
export API_GATEWAY_NAME="$API_GATEWAY_NAME"
export AZ1="$AZ1"
export AZ2="$AZ2"
EOF
}

# Create VPC and networking resources
create_vpc_resources() {
    info "Creating VPC and networking resources..."
    
    # Create target VPC
    execute_command \
        "aws ec2 create-vpc \
            --cidr-block 10.1.0.0/16 \
            --tag-specifications \
            'ResourceType=vpc,Tags=[{Key=Name,Value=target-vpc-${RANDOM_SUFFIX}},{Key=Purpose,Value=private-api}]'" \
        "Create target VPC"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export TARGET_VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=target-vpc-${RANDOM_SUFFIX}" \
            --query 'Vpcs[0].VpcId' --output text)
        echo "export TARGET_VPC_ID=\"$TARGET_VPC_ID\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
    
    # Create subnets
    execute_command \
        "aws ec2 create-subnet \
            --vpc-id \${TARGET_VPC_ID} \
            --cidr-block 10.1.1.0/24 \
            --availability-zone \${AZ1} \
            --tag-specifications \
            'ResourceType=subnet,Tags=[{Key=Name,Value=target-subnet-1-${RANDOM_SUFFIX}}]'" \
        "Create subnet 1"
    
    execute_command \
        "aws ec2 create-subnet \
            --vpc-id \${TARGET_VPC_ID} \
            --cidr-block 10.1.2.0/24 \
            --availability-zone \${AZ2} \
            --tag-specifications \
            'ResourceType=subnet,Tags=[{Key=Name,Value=target-subnet-2-${RANDOM_SUFFIX}}]'" \
        "Create subnet 2"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export SUBNET_ID_1=$(aws ec2 describe-subnets \
            --filters "Name=tag:Name,Values=target-subnet-1-${RANDOM_SUFFIX}" \
            --query 'Subnets[0].SubnetId' --output text)
        export SUBNET_ID_2=$(aws ec2 describe-subnets \
            --filters "Name=tag:Name,Values=target-subnet-2-${RANDOM_SUFFIX}" \
            --query 'Subnets[0].SubnetId' --output text)
        
        echo "export SUBNET_ID_1=\"$SUBNET_ID_1\"" >> "${SCRIPT_DIR}/deployment_vars.env"
        echo "export SUBNET_ID_2=\"$SUBNET_ID_2\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Create VPC Lattice service network
create_vpc_lattice_network() {
    info "Creating VPC Lattice service network..."
    
    execute_command \
        "aws vpc-lattice create-service-network \
            --name \${VPC_LATTICE_SERVICE_NETWORK} \
            --auth-type AWS_IAM \
            --tags Key=Environment,Value=demo Key=Purpose,Value=private-api-integration" \
        "Create VPC Lattice service network"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${VPC_LATTICE_SERVICE_NETWORK}'].id" \
            --output text)
        echo "export SERVICE_NETWORK_ID=\"$SERVICE_NETWORK_ID\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Create API Gateway with VPC endpoint
create_api_gateway() {
    info "Creating API Gateway with VPC endpoint..."
    
    # Create VPC endpoint
    execute_command \
        "aws ec2 create-vpc-endpoint \
            --vpc-id \${TARGET_VPC_ID} \
            --service-name com.amazonaws.\${AWS_REGION}.execute-api \
            --vpc-endpoint-type Interface \
            --subnet-ids \${SUBNET_ID_1} \${SUBNET_ID_2} \
            --policy-document '{
                \"Version\": \"2012-10-17\",
                \"Statement\": [
                    {
                        \"Effect\": \"Allow\",
                        \"Principal\": \"*\",
                        \"Action\": \"execute-api:*\",
                        \"Resource\": \"*\"
                    }
                ]
            }' \
            --tag-specifications \
            'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=api-gateway-endpoint-${RANDOM_SUFFIX}}]'" \
        "Create VPC endpoint for API Gateway"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export VPC_ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=${TARGET_VPC_ID}" \
                     "Name=service-name,Values=com.amazonaws.${AWS_REGION}.execute-api" \
            --query 'VpcEndpoints[0].VpcEndpointId' --output text)
        echo "export VPC_ENDPOINT_ID=\"$VPC_ENDPOINT_ID\"" >> "${SCRIPT_DIR}/deployment_vars.env"
        
        # Wait for VPC endpoint to be available
        wait_for_resource \
            "aws ec2 describe-vpc-endpoints --vpc-endpoint-ids ${VPC_ENDPOINT_ID} --query 'VpcEndpoints[0].State' --output text | grep -q available" \
            "VPC endpoint"
    fi
    
    # Create private API Gateway
    execute_command \
        "aws apigateway create-rest-api \
            --name \${API_GATEWAY_NAME} \
            --endpoint-configuration types=PRIVATE \
            --policy '{
                \"Version\": \"2012-10-17\",
                \"Statement\": [
                    {
                        \"Effect\": \"Allow\",
                        \"Principal\": \"*\",
                        \"Action\": \"execute-api:Invoke\",
                        \"Resource\": \"*\",
                        \"Condition\": {
                            \"StringEquals\": {
                                \"aws:sourceVpce\": \"'\${VPC_ENDPOINT_ID}'\"
                            }
                        }
                    }
                ]
            }'" \
        "Create private API Gateway"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_GATEWAY_NAME}'].id" \
            --output text)
        echo "export API_ID=\"$API_ID\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Configure API Gateway resources and methods
configure_api_gateway() {
    info "Configuring API Gateway resources and methods..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get root resource ID
        ROOT_RESOURCE_ID=$(aws apigateway get-resources \
            --rest-api-id "${API_ID}" \
            --query 'items[?path==`/`].id' --output text)
        
        # Create /orders resource
        aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part orders
        
        ORDERS_RESOURCE_ID=$(aws apigateway get-resources \
            --rest-api-id "${API_ID}" \
            --query 'items[?pathPart==`orders`].id' --output text)
        
        # Create POST method
        aws apigateway put-method \
            --rest-api-id "${API_ID}" \
            --resource-id "${ORDERS_RESOURCE_ID}" \
            --http-method POST \
            --authorization-type AWS_IAM
        
        # Add mock integration
        aws apigateway put-integration \
            --rest-api-id "${API_ID}" \
            --resource-id "${ORDERS_RESOURCE_ID}" \
            --http-method POST \
            --type MOCK \
            --request-templates '{"application/json": "{\"statusCode\": 200}"}'
        
        # Configure responses
        aws apigateway put-method-response \
            --rest-api-id "${API_ID}" \
            --resource-id "${ORDERS_RESOURCE_ID}" \
            --http-method POST \
            --status-code 200
        
        aws apigateway put-integration-response \
            --rest-api-id "${API_ID}" \
            --resource-id "${ORDERS_RESOURCE_ID}" \
            --http-method POST \
            --status-code 200 \
            --response-templates \
            '{"application/json": "{\"orderId\": \"12345\", \"status\": \"created\", \"timestamp\": \"$(context.requestTime)\"}"}'
        
        # Deploy API
        aws apigateway create-deployment \
            --rest-api-id "${API_ID}" \
            --stage-name prod
        
        log "✅ API Gateway configured with /orders endpoint"
    else
        info "[DRY RUN] Would configure API Gateway resources and methods"
    fi
}

# Create resource gateway and configuration
create_resource_gateway() {
    info "Creating VPC Lattice resource gateway and configuration..."
    
    # Create resource gateway
    execute_command \
        "aws vpc-lattice create-resource-gateway \
            --name \"api-gateway-resource-gateway-\${RANDOM_SUFFIX}\" \
            --vpc-identifier \${TARGET_VPC_ID} \
            --subnet-ids \${SUBNET_ID_1} \${SUBNET_ID_2} \
            --tags Key=Purpose,Value=private-api-access Key=Environment,Value=demo" \
        "Create resource gateway"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export RESOURCE_GATEWAY_ID=$(aws vpc-lattice list-resource-gateways \
            --query "items[?name=='api-gateway-resource-gateway-${RANDOM_SUFFIX}'].id" \
            --output text)
        echo "export RESOURCE_GATEWAY_ID=\"$RESOURCE_GATEWAY_ID\"" >> "${SCRIPT_DIR}/deployment_vars.env"
        
        # Wait for resource gateway to be active
        wait_for_resource \
            "aws vpc-lattice get-resource-gateway --resource-gateway-identifier ${RESOURCE_GATEWAY_ID} --query 'status' --output text | grep -q ACTIVE" \
            "Resource gateway"
    fi
    
    # Create resource configuration
    execute_command \
        "aws vpc-lattice create-resource-configuration \
            --name \${RESOURCE_CONFIG_NAME} \
            --type SINGLE \
            --resource-gateway-identifier \${RESOURCE_GATEWAY_ID} \
            --resource-configuration-definition '{
                \"type\": \"RESOURCE\",
                \"resourceIdentifier\": \"'\${VPC_ENDPOINT_ID}'\",
                \"portRanges\": [{\"fromPort\": 443, \"toPort\": 443, \"protocol\": \"TCP\"}]
            }' \
            --allow-association-to-shareable-service-network \
            --tags Key=Purpose,Value=private-api-integration Key=Environment,Value=demo" \
        "Create resource configuration"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export RESOURCE_CONFIG_ARN=$(aws vpc-lattice list-resource-configurations \
            --query "items[?name=='${RESOURCE_CONFIG_NAME}'].arn" \
            --output text)
        echo "export RESOURCE_CONFIG_ARN=\"$RESOURCE_CONFIG_ARN\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Associate resource configuration with service network
create_resource_association() {
    info "Creating resource association..."
    
    execute_command \
        "aws vpc-lattice create-service-network-resource-association \
            --service-network-identifier \${SERVICE_NETWORK_ID} \
            --resource-configuration-identifier \${RESOURCE_CONFIG_ARN}" \
        "Create service network resource association"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 15  # Allow time for association to be created
        export ASSOCIATION_ID=$(aws vpc-lattice list-service-network-resource-associations \
            --service-network-identifier "${SERVICE_NETWORK_ID}" \
            --query "items[?resourceConfigurationArn=='${RESOURCE_CONFIG_ARN}'].id" \
            --output text)
        echo "export ASSOCIATION_ID=\"$ASSOCIATION_ID\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Create IAM role for EventBridge and Step Functions
create_iam_role() {
    info "Creating IAM role for EventBridge and Step Functions..."
    
    execute_command \
        "aws iam create-role \
            --role-name EventBridgeStepFunctionsVPCLatticeRole-\${RANDOM_SUFFIX} \
            --assume-role-policy-document '{
                \"Version\": \"2012-10-17\",
                \"Statement\": [
                    {
                        \"Effect\": \"Allow\",
                        \"Principal\": {
                            \"Service\": [\"events.amazonaws.com\", \"states.amazonaws.com\"]
                        },
                        \"Action\": \"sts:AssumeRole\"
                    }
                ]
            }'" \
        "Create IAM role"
    
    execute_command \
        "aws iam put-role-policy \
            --role-name EventBridgeStepFunctionsVPCLatticeRole-\${RANDOM_SUFFIX} \
            --policy-name VPCLatticeConnectionPolicy \
            --policy-document '{
                \"Version\": \"2012-10-17\",
                \"Statement\": [
                    {
                        \"Effect\": \"Allow\",
                        \"Action\": [
                            \"events:CreateConnection\",
                            \"events:UpdateConnection\",
                            \"events:InvokeApiDestination\",
                            \"execute-api:Invoke\",
                            \"vpc-lattice:GetResourceConfiguration\",
                            \"states:StartExecution\"
                        ],
                        \"Resource\": \"*\"
                    }
                ]
            }'" \
        "Attach policy to IAM role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export ROLE_ARN=$(aws iam get-role \
            --role-name "EventBridgeStepFunctionsVPCLatticeRole-${RANDOM_SUFFIX}" \
            --query 'Role.Arn' --output text)
        echo "export ROLE_ARN=\"$ROLE_ARN\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Create EventBridge resources
create_eventbridge_resources() {
    info "Creating EventBridge resources..."
    
    # Create custom event bus
    execute_command \
        "aws events create-event-bus --name \${EVENTBRIDGE_BUS_NAME}" \
        "Create EventBridge custom bus"
    
    # Create connection
    execute_command \
        "aws events create-connection \
            --name \"private-api-connection-\${RANDOM_SUFFIX}\" \
            --description \"Connection to private API Gateway via VPC Lattice\" \
            --authorization-type INVOCATION_HTTP_PARAMETERS \
            --invocation-http-parameters '{
                \"HeaderParameters\": {
                    \"Content-Type\": \"application/json\"
                }
            }' \
            --invocation-endpoint \
            \"https://\${API_ID}-\${VPC_ENDPOINT_ID}.execute-api.\${AWS_REGION}.amazonaws.com/prod/orders\" \
            --invocation-resource-configuration-arn \${RESOURCE_CONFIG_ARN}" \
        "Create EventBridge connection"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export CONNECTION_ARN=$(aws events describe-connection \
            --name "private-api-connection-${RANDOM_SUFFIX}" \
            --query 'ConnectionArn' --output text)
        echo "export CONNECTION_ARN=\"$CONNECTION_ARN\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    fi
}

# Create Step Functions state machine
create_step_functions() {
    info "Creating Step Functions state machine..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create state machine definition
        cat > "${SCRIPT_DIR}/step-function-definition.json" << EOF
{
    "Comment": "Workflow that invokes private API via VPC Lattice",
    "StartAt": "ProcessOrder",
    "States": {
        "ProcessOrder": {
            "Type": "Task",
            "Resource": "arn:aws:states:::http:invoke",
            "Parameters": {
                "ApiEndpoint": "${CONNECTION_ARN}",
                "Method": "POST",
                "RequestBody": {
                    "customerId": "12345",
                    "orderItems": ["item1", "item2"],
                    "timestamp.$": "$$.State.EnteredTime"
                },
                "Headers": {
                    "Content-Type": "application/json"
                }
            },
            "Retry": [
                {
                    "ErrorEquals": ["States.Http.StatusCodeFailure"],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 3,
                    "BackoffRate": 2.0
                }
            ],
            "Catch": [
                {
                    "ErrorEquals": ["States.TaskFailed"],
                    "Next": "HandleError"
                }
            ],
            "Next": "ProcessSuccess"
        },
        "ProcessSuccess": {
            "Type": "Pass",
            "Result": "Order processed successfully",
            "End": true
        },
        "HandleError": {
            "Type": "Pass",
            "Result": "Order processing failed",
            "End": true
        }
    }
}
EOF
        
        # Create state machine
        aws stepfunctions create-state-machine \
            --name "${STEP_FUNCTION_NAME}" \
            --definition "file://${SCRIPT_DIR}/step-function-definition.json" \
            --role-arn "${ROLE_ARN}"
        
        export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
            --query "stateMachines[?name=='${STEP_FUNCTION_NAME}'].stateMachineArn" \
            --output text)
        echo "export STATE_MACHINE_ARN=\"$STATE_MACHINE_ARN\"" >> "${SCRIPT_DIR}/deployment_vars.env"
        
        log "✅ Step Functions state machine created"
    else
        info "[DRY RUN] Would create Step Functions state machine"
    fi
}

# Create EventBridge rule
create_eventbridge_rule() {
    info "Creating EventBridge rule..."
    
    execute_command \
        "aws events put-rule \
            --event-bus-name \${EVENTBRIDGE_BUS_NAME} \
            --name \"trigger-private-api-workflow-\${RANDOM_SUFFIX}\" \
            --event-pattern '{
                \"source\": [\"demo.application\"],
                \"detail-type\": [\"Order Received\"]
            }' \
            --state ENABLED" \
        "Create EventBridge rule"
    
    execute_command \
        "aws events put-targets \
            --event-bus-name \${EVENTBRIDGE_BUS_NAME} \
            --rule \"trigger-private-api-workflow-\${RANDOM_SUFFIX}\" \
            --targets \"Id\"=\"1\",\"Arn\"=\"\${STATE_MACHINE_ARN}\",\"RoleArn\"=\"\${ROLE_ARN}\"" \
        "Add Step Functions as target"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Load environment variables
    source "${SCRIPT_DIR}/deployment_vars.env"
    
    # Check VPC Lattice resource configuration
    if aws vpc-lattice get-resource-configuration \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ARN}" \
        --query 'status' --output text | grep -q ACTIVE; then
        log "✅ VPC Lattice resource configuration is active"
    else
        warn "⚠️ VPC Lattice resource configuration may not be ready"
    fi
    
    # Check EventBridge connection
    if aws events describe-connection \
        --name "private-api-connection-${RANDOM_SUFFIX}" \
        --query 'ConnectionState' --output text | grep -q AUTHORIZED; then
        log "✅ EventBridge connection is authorized"
    else
        warn "⚠️ EventBridge connection may not be ready"
    fi
    
    # Test with a sample event
    info "Sending test event..."
    aws events put-events \
        --entries "[
            {
                \"Source\": \"demo.application\",
                \"DetailType\": \"Order Received\",
                \"Detail\": \"{\\\"orderId\\\": \\\"test-123\\\", \\\"customerId\\\": \\\"cust-456\\\"}\",
                \"EventBusName\": \"${EVENTBRIDGE_BUS_NAME}\"
            }
        ]"
    
    log "✅ Test event sent - check Step Functions execution"
}

# Print deployment summary
print_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "=== DRY RUN SUMMARY ==="
        info "This was a dry run. No resources were actually created."
        info "To deploy for real, run the script without --dry-run flag."
        return 0
    fi
    
    source "${SCRIPT_DIR}/deployment_vars.env"
    
    log "=== DEPLOYMENT SUMMARY ==="
    log "✅ Private API Integration with VPC Lattice deployed successfully!"
    log ""
    log "Resources created:"
    log "  • Target VPC: ${TARGET_VPC_ID}"
    log "  • VPC Lattice Service Network: ${SERVICE_NETWORK_ID}"
    log "  • API Gateway: ${API_ID}"
    log "  • VPC Endpoint: ${VPC_ENDPOINT_ID}"
    log "  • Resource Gateway: ${RESOURCE_GATEWAY_ID}"
    log "  • EventBridge Bus: ${EVENTBRIDGE_BUS_NAME}"
    log "  • Step Functions: ${STEP_FUNCTION_NAME}"
    log ""
    log "Next steps:"
    log "  1. Test the integration by sending events to the EventBridge bus"
    log "  2. Monitor Step Functions executions in the AWS console"
    log "  3. Check VPC Lattice metrics for connectivity insights"
    log ""
    log "To clean up resources, run: ./destroy.sh"
    log "Environment variables saved to: ${SCRIPT_DIR}/deployment_vars.env"
}

# Cleanup function for script failures
cleanup_on_failure() {
    error "Deployment failed. Cleaning up partial resources..."
    if [[ -f "${SCRIPT_DIR}/deployment_vars.env" ]]; then
        source "${SCRIPT_DIR}/deployment_vars.env"
        # Add basic cleanup commands here if needed
        warn "Please run ./destroy.sh to clean up any created resources"
    fi
}

# Trap for cleanup on failure
trap cleanup_on_failure ERR

# Main execution
main() {
    log "Starting Private API Integration with VPC Lattice deployment..."
    
    check_prerequisites
    setup_environment
    create_vpc_resources
    create_vpc_lattice_network
    create_api_gateway
    configure_api_gateway
    create_resource_gateway
    create_resource_association
    create_iam_role
    create_eventbridge_resources
    create_step_functions
    create_eventbridge_rule
    validate_deployment
    print_summary
    
    log "Deployment completed successfully!"
}

# Execute main function
main "$@"