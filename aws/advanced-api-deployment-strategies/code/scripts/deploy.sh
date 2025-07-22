#!/bin/bash

# Deploy script for Advanced API Gateway Deployment Strategies with Blue-Green and Canary Patterns
# This script implements enterprise-grade API deployment with automated traffic shifting and monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default values
DEFAULT_CANARY_PERCENTAGE=10
DEFAULT_TRAFFIC_STEPS="10,25,50,100"
DEFAULT_MONITORING_INTERVAL=120

# Functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Advanced API Gateway with Blue-Green and Canary deployment patterns.

OPTIONS:
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose logging
    -d, --dry-run              Show what would be deployed without executing
    -c, --canary-percentage    Initial canary traffic percentage (default: ${DEFAULT_CANARY_PERCENTAGE})
    -s, --traffic-steps        Comma-separated traffic percentages (default: ${DEFAULT_TRAFFIC_STEPS})
    -i, --monitoring-interval  Monitoring interval in seconds (default: ${DEFAULT_MONITORING_INTERVAL})
    -r, --region               AWS region (default: current configured region)
    -p, --profile              AWS profile to use
    --skip-tests               Skip validation tests
    --auto-approve             Skip confirmation prompts

EXAMPLES:
    $0                          # Deploy with default settings
    $0 --canary-percentage 5    # Start with 5% canary traffic
    $0 --traffic-steps 5,15,50  # Custom traffic progression
    $0 --dry-run                # Preview deployment without executing
    $0 --verbose --auto-approve # Verbose output with no prompts

EOF
}

# Parse command line arguments
parse_args() {
    VERBOSE=false
    DRY_RUN=false
    SKIP_TESTS=false
    AUTO_APPROVE=false
    CANARY_PERCENTAGE=${DEFAULT_CANARY_PERCENTAGE}
    TRAFFIC_STEPS=${DEFAULT_TRAFFIC_STEPS}
    MONITORING_INTERVAL=${DEFAULT_MONITORING_INTERVAL}
    AWS_REGION=""
    AWS_PROFILE=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -c|--canary-percentage)
                CANARY_PERCENTAGE="$2"
                shift 2
                ;;
            -s|--traffic-steps)
                TRAFFIC_STEPS="$2"
                shift 2
                ;;
            -i|--monitoring-interval)
                MONITORING_INTERVAL="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        error "jq is not installed or not in PATH"
        exit 1
    fi

    # Check bc for arithmetic operations
    if ! command -v bc &> /dev/null; then
        error "bc is not installed or not in PATH"
        exit 1
    fi

    # Set AWS profile if specified
    if [[ -n "${AWS_PROFILE}" ]]; then
        export AWS_PROFILE="${AWS_PROFILE}"
        info "Using AWS profile: ${AWS_PROFILE}"
    fi

    # Set AWS region
    if [[ -n "${AWS_REGION}" ]]; then
        export AWS_DEFAULT_REGION="${AWS_REGION}"
        info "Using AWS region: ${AWS_REGION}"
    else
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_DEFAULT_REGION="${AWS_REGION}"
        info "Using default AWS region: ${AWS_REGION}"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi

    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"

    success "Prerequisites check completed"
}

# Generate unique identifiers
generate_identifiers() {
    info "Generating unique identifiers..."

    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")

    export API_NAME="advanced-deployment-api-${RANDOM_SUFFIX}"
    export BLUE_FUNCTION_NAME="blue-api-function-${RANDOM_SUFFIX}"
    export GREEN_FUNCTION_NAME="green-api-function-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="api-deployment-lambda-role-${RANDOM_SUFFIX}"

    info "Generated identifiers with suffix: ${RANDOM_SUFFIX}"
    
    # Save state
    cat > "${STATE_FILE}" << EOF
RANDOM_SUFFIX=${RANDOM_SUFFIX}
API_NAME=${API_NAME}
BLUE_FUNCTION_NAME=${BLUE_FUNCTION_NAME}
GREEN_FUNCTION_NAME=${GREEN_FUNCTION_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DEPLOYMENT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    success "Identifiers generated and saved to state file"
}

# Create IAM role for Lambda functions
create_iam_role() {
    info "Creating IAM role for Lambda functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create IAM role: ${LAMBDA_ROLE_NAME}"
        return 0
    fi

    # Create IAM role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
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
        --tags '[
            {
                "Key": "Purpose",
                "Value": "API-Gateway-Deployment-Demo"
            },
            {
                "Key": "Environment",
                "Value": "Development"
            }
        ]' > /dev/null

    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 15

    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    success "IAM role created: ${LAMBDA_ROLE_ARN}"
}

# Create Lambda functions
create_lambda_functions() {
    info "Creating Lambda functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create Lambda functions: ${BLUE_FUNCTION_NAME}, ${GREEN_FUNCTION_NAME}"
        return 0
    fi

    # Create Blue function code
    cat > "${SCRIPT_DIR}/blue-function.py" << 'EOF'
import json
import os

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from Blue environment!',
            'version': 'v1.0.0',
            'environment': 'blue',
            'timestamp': context.aws_request_id
        })
    }
EOF

    # Create Green function code
    cat > "${SCRIPT_DIR}/green-function.py" << 'EOF'
import json
import os

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from Green environment!',
            'version': 'v2.0.0',
            'environment': 'green',
            'timestamp': context.aws_request_id,
            'new_feature': 'Enhanced response format'
        })
    }
EOF

    # Package functions
    cd "${SCRIPT_DIR}"
    zip -q blue-function.zip blue-function.py
    zip -q green-function.zip green-function.py

    # Create Blue Lambda function
    aws lambda create-function \
        --function-name "${BLUE_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler blue-function.lambda_handler \
        --zip-file fileb://blue-function.zip \
        --description "Blue environment API function" \
        --timeout 30 \
        --memory-size 128 \
        --tags Purpose=API-Gateway-Deployment-Demo,Environment=Blue > /dev/null

    # Create Green Lambda function
    aws lambda create-function \
        --function-name "${GREEN_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler green-function.lambda_handler \
        --zip-file fileb://green-function.zip \
        --description "Green environment API function" \
        --timeout 30 \
        --memory-size 128 \
        --tags Purpose=API-Gateway-Deployment-Demo,Environment=Green > /dev/null

    # Get function ARNs
    export BLUE_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${BLUE_FUNCTION_NAME}" \
        --query Configuration.FunctionArn --output text)

    export GREEN_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${GREEN_FUNCTION_NAME}" \
        --query Configuration.FunctionArn --output text)

    # Update state file
    echo "BLUE_FUNCTION_ARN=${BLUE_FUNCTION_ARN}" >> "${STATE_FILE}"
    echo "GREEN_FUNCTION_ARN=${GREEN_FUNCTION_ARN}" >> "${STATE_FILE}"

    success "Lambda functions created successfully"
}

# Create API Gateway
create_api_gateway() {
    info "Creating API Gateway..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create API Gateway: ${API_NAME}"
        return 0
    fi

    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "Advanced deployment patterns demo API" \
        --query id --output text)

    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[?path==`/`].id' --output text)

    # Create /hello resource
    export HELLO_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part hello \
        --query id --output text)

    # Create GET method for Blue environment
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${HELLO_RESOURCE_ID}" \
        --http-method GET \
        --authorization-type NONE > /dev/null

    # Create Lambda integration for Blue environment
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${HELLO_RESOURCE_ID}" \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${BLUE_FUNCTION_ARN}/invocations" > /dev/null

    # Grant API Gateway permission to invoke Blue Lambda
    aws lambda add-permission \
        --function-name "${BLUE_FUNCTION_NAME}" \
        --statement-id "api-gateway-blue-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" > /dev/null

    # Grant API Gateway permission to invoke Green Lambda
    aws lambda add-permission \
        --function-name "${GREEN_FUNCTION_NAME}" \
        --statement-id "api-gateway-green-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" > /dev/null

    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com"

    # Update state file
    echo "API_ID=${API_ID}" >> "${STATE_FILE}"
    echo "API_ENDPOINT=${API_ENDPOINT}" >> "${STATE_FILE}"
    echo "ROOT_RESOURCE_ID=${ROOT_RESOURCE_ID}" >> "${STATE_FILE}"
    echo "HELLO_RESOURCE_ID=${HELLO_RESOURCE_ID}" >> "${STATE_FILE}"

    success "API Gateway created: ${API_ENDPOINT}"
}

# Create stages and deployments
create_stages() {
    info "Creating API Gateway stages..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create production and staging stages"
        return 0
    fi

    # Create initial deployment for production (Blue)
    export BLUE_DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name production \
        --stage-description "Production stage with Blue environment" \
        --description "Initial Blue deployment" \
        --query id --output text)

    # Configure production stage settings
    aws apigateway update-stage \
        --rest-api-id "${API_ID}" \
        --stage-name production \
        --patch-operations \
            'op=replace,path=/cacheClusterEnabled,value=false' \
            'op=replace,path=/tracingEnabled,value=true' \
            'op=replace,path=/*/*/throttling/rateLimit,value=1000' \
            'op=replace,path=/*/*/throttling/burstLimit,value=2000' \
            'op=replace,path=/*/*/logging/loglevel,value=INFO' \
            'op=replace,path=/*/*/logging/dataTrace,value=true' \
            'op=replace,path=/*/*/metricsEnabled,value=true' > /dev/null

    # Update integration to point to Green Lambda for staging
    aws apigateway update-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${HELLO_RESOURCE_ID}" \
        --http-method GET \
        --patch-operations "op=replace,path=/uri,value=arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${GREEN_FUNCTION_ARN}/invocations" > /dev/null

    # Create staging deployment (Green)
    export GREEN_DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name staging \
        --stage-description "Staging stage for Green environment testing" \
        --description "Green environment deployment" \
        --query id --output text)

    # Update state file
    echo "BLUE_DEPLOYMENT_ID=${BLUE_DEPLOYMENT_ID}" >> "${STATE_FILE}"
    echo "GREEN_DEPLOYMENT_ID=${GREEN_DEPLOYMENT_ID}" >> "${STATE_FILE}"

    success "API Gateway stages created successfully"
}

# Set up CloudWatch monitoring
setup_monitoring() {
    info "Setting up CloudWatch monitoring and alarms..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create CloudWatch alarms"
        return 0
    fi

    # Create CloudWatch alarm for 4XX errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${API_NAME}-4xx-errors" \
        --alarm-description "API Gateway 4XX errors" \
        --metric-name 4XXError \
        --namespace AWS/ApiGateway \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ApiName,Value="${API_NAME}" Name=Stage,Value=production \
        --tags '[
            {
                "Key": "Purpose",
                "Value": "API-Gateway-Deployment-Demo"
            }
        ]' > /dev/null

    # Create CloudWatch alarm for 5XX errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${API_NAME}-5xx-errors" \
        --alarm-description "API Gateway 5XX errors" \
        --metric-name 5XXError \
        --namespace AWS/ApiGateway \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=ApiName,Value="${API_NAME}" Name=Stage,Value=production \
        --tags '[
            {
                "Key": "Purpose",
                "Value": "API-Gateway-Deployment-Demo"
            }
        ]' > /dev/null

    # Create CloudWatch alarm for latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "${API_NAME}-high-latency" \
        --alarm-description "API Gateway high latency" \
        --metric-name Latency \
        --namespace AWS/ApiGateway \
        --statistic Average \
        --period 300 \
        --threshold 5000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ApiName,Value="${API_NAME}" Name=Stage,Value=production \
        --tags '[
            {
                "Key": "Purpose",
                "Value": "API-Gateway-Deployment-Demo"
            }
        ]' > /dev/null

    success "CloudWatch monitoring configured"
}

# Implement canary deployment
implement_canary_deployment() {
    info "Implementing canary deployment with ${CANARY_PERCENTAGE}% traffic..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create canary deployment with ${CANARY_PERCENTAGE}% traffic"
        return 0
    fi

    # Create canary deployment
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name production \
        --description "Canary deployment - ${CANARY_PERCENTAGE}% Green traffic" \
        --canary-settings "{
            \"percentTraffic\": ${CANARY_PERCENTAGE},
            \"deploymentId\": \"${GREEN_DEPLOYMENT_ID}\",
            \"stageVariableOverrides\": {
                \"environment\": \"canary\"
            },
            \"useStageCache\": false
        }" > /dev/null

    # Wait for deployment propagation
    sleep 5

    success "Canary deployment created with ${CANARY_PERCENTAGE}% traffic to Green environment"
}

# Monitor deployment health
monitor_deployment() {
    local duration=$1
    info "Monitoring deployment health for ${duration} seconds..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would monitor deployment for ${duration} seconds"
        return 0
    fi

    local end_time=$(($(date +%s) + duration))
    local error_count=0

    while [[ $(date +%s) -lt $end_time ]]; do
        # Check for 5XX errors
        error_count=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name 5XXError \
            --dimensions Name=ApiName,Value="${API_NAME}" Name=Stage,Value=production \
            --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 300 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "0")

        if [[ "${error_count}" != "null" ]] && [[ "${error_count}" != "None" ]] && [[ "${error_count}" != "0" ]]; then
            error "Error detected during monitoring! Error count: ${error_count}"
            return 1
        fi

        info "Health check passed - no errors detected"
        sleep 30
    done

    success "Monitoring completed successfully"
    return 0
}

# Automated traffic shifting
automated_traffic_shifting() {
    info "Starting automated traffic shifting..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would perform automated traffic shifting: ${TRAFFIC_STEPS}"
        return 0
    fi

    IFS=',' read -ra STEPS <<< "${TRAFFIC_STEPS}"
    
    for step in "${STEPS[@]}"; do
        info "Shifting traffic to ${step}%..."
        
        # Update canary traffic percentage
        aws apigateway update-stage \
            --rest-api-id "${API_ID}" \
            --stage-name production \
            --patch-operations "op=replace,path=/canarySettings/percentTraffic,value=${step}" > /dev/null

        # Monitor deployment health
        if ! monitor_deployment "${MONITORING_INTERVAL}"; then
            error "Health check failed at ${step}% traffic - initiating rollback"
            rollback_deployment
            return 1
        fi

        success "Traffic shift to ${step}% completed successfully"
    done

    success "Automated traffic shifting completed"
}

# Rollback deployment
rollback_deployment() {
    warning "Initiating rollback to Blue environment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would rollback to Blue environment"
        return 0
    fi

    # Remove canary settings (rollback to Blue)
    aws apigateway update-stage \
        --rest-api-id "${API_ID}" \
        --stage-name production \
        --patch-operations "op=remove,path=/canarySettings" > /dev/null

    success "Rollback to Blue environment completed"
}

# Promote to production
promote_to_production() {
    info "Promoting Green environment to full production..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would promote Green environment to production"
        return 0
    fi

    # Promote Green to production (remove canary, update deployment)
    aws apigateway update-stage \
        --rest-api-id "${API_ID}" \
        --stage-name production \
        --patch-operations \
            "op=replace,path=/deploymentId,value=${GREEN_DEPLOYMENT_ID}" \
            "op=remove,path=/canarySettings" > /dev/null

    success "Green environment promoted to full production"
}

# Run validation tests
run_validation_tests() {
    if [[ "${SKIP_TESTS}" == "true" ]]; then
        info "Skipping validation tests"
        return 0
    fi

    info "Running validation tests..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would run validation tests"
        return 0
    fi

    # Test Blue environment (production)
    info "Testing Blue environment..."
    blue_response=$(curl -s "${API_ENDPOINT}/production/hello" || echo "ERROR")
    if [[ "${blue_response}" == "ERROR" ]]; then
        error "Failed to test Blue environment"
        return 1
    fi

    # Test Green environment (staging)
    info "Testing Green environment..."
    green_response=$(curl -s "${API_ENDPOINT}/staging/hello" || echo "ERROR")
    if [[ "${green_response}" == "ERROR" ]]; then
        error "Failed to test Green environment"
        return 1
    fi

    success "Validation tests completed successfully"
}

# Main deployment process
main() {
    info "Starting Advanced API Gateway Deployment..."
    
    # Initialize logging
    echo "=== Deployment started at $(date) ===" > "${LOG_FILE}"
    
    # Parse arguments
    parse_args "$@"
    
    # Show deployment summary
    if [[ "${AUTO_APPROVE}" != "true" ]]; then
        echo
        echo "=== Deployment Summary ==="
        echo "Canary Percentage: ${CANARY_PERCENTAGE}%"
        echo "Traffic Steps: ${TRAFFIC_STEPS}"
        echo "Monitoring Interval: ${MONITORING_INTERVAL}s"
        echo "AWS Region: ${AWS_REGION}"
        echo "Dry Run: ${DRY_RUN}"
        echo "Skip Tests: ${SKIP_TESTS}"
        echo
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Deployment cancelled by user"
                exit 0
            fi
        fi
    fi

    # Execute deployment steps
    check_prerequisites
    generate_identifiers
    create_iam_role
    create_lambda_functions
    create_api_gateway
    create_stages
    setup_monitoring
    implement_canary_deployment
    run_validation_tests
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        automated_traffic_shifting
        promote_to_production
    fi

    # Final success message
    echo
    success "🎉 Advanced API Gateway deployment completed successfully!"
    echo
    echo "=== Deployment Results ==="
    echo "API Endpoint: ${API_ENDPOINT}"
    echo "Production URL: ${API_ENDPOINT}/production/hello"
    echo "Staging URL: ${API_ENDPOINT}/staging/hello"
    echo "State File: ${STATE_FILE}"
    echo "Log File: ${LOG_FILE}"
    echo
    echo "Next steps:"
    echo "1. Test your API endpoints"
    echo "2. Monitor CloudWatch metrics and alarms"
    echo "3. Review deployment logs"
    echo "4. Run ./destroy.sh when finished testing"
    echo
    
    log "Deployment completed successfully"
}

# Trap to handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"