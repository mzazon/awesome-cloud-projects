#!/bin/bash

#########################################################################
# AWS Simple App Configuration with AppConfig and Lambda - Deploy Script
# 
# This script deploys the complete infrastructure for the Simple
# Application Configuration recipe using AWS AppConfig and Lambda.
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate AWS permissions for AppConfig, Lambda, and IAM
# - jq installed for JSON processing
#
# Usage: ./deploy.sh [--dry-run] [--debug]
#########################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DRY_RUN=false
DEBUG=false
CLEANUP_ON_ERROR=true

#########################################################################
# Helper Functions
#########################################################################

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        log "${BLUE}[DEBUG]${NC} ${1}"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Simple App Configuration with AppConfig and Lambda

OPTIONS:
    --dry-run       Show what would be deployed without making changes
    --debug         Enable debug logging
    --no-cleanup    Don't cleanup resources on deployment failure
    -h, --help      Show this help message

EXAMPLES:
    $0                      # Deploy normally
    $0 --dry-run            # Preview deployment
    $0 --debug              # Deploy with debug logging
EOF
}

cleanup_on_failure() {
    if [[ "${CLEANUP_ON_ERROR}" == "true" ]]; then
        log_warning "Deployment failed. Cleaning up resources..."
        if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
            "${SCRIPT_DIR}/destroy.sh" --force
        fi
    fi
}

#########################################################################
# Validation Functions
#########################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "${account_id}" ]]; then
        log_error "Unable to retrieve AWS account information. Check your credentials."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
    debug "AWS Account ID: ${account_id}"
}

validate_aws_region() {
    local region
    region=$(aws configure get region 2>/dev/null || echo "")
    
    if [[ -z "${region}" ]]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    # Verify region exists and is accessible
    if ! aws ec2 describe-regions --region-names "${region}" &> /dev/null; then
        log_error "Invalid or inaccessible AWS region: ${region}"
        exit 1
    fi
    
    log_success "AWS region validated: ${region}"
    export AWS_REGION="${region}"
}

#########################################################################
# Resource Creation Functions
#########################################################################

setup_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export APP_NAME="simple-config-app-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="config-demo-${random_suffix}"
    export LAMBDA_ROLE_NAME="lambda-appconfig-role-${random_suffix}"
    export DEPLOYMENT_STRATEGY_NAME="immediate-deployment-${random_suffix}"
    export APPCONFIG_POLICY_NAME="AppConfigLambdaPolicy-${random_suffix}"
    
    # Store variables for cleanup
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
APP_NAME=${APP_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
DEPLOYMENT_STRATEGY_NAME=${DEPLOYMENT_STRATEGY_NAME}
APPCONFIG_POLICY_NAME=${APPCONFIG_POLICY_NAME}
EOF
    
    log_success "Environment variables configured"
    debug "Application Name: ${APP_NAME}"
    debug "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
}

create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: ${LAMBDA_ROLE_NAME}"
        return 0
    fi
    
    # Create trust policy
    local trust_policy=$(cat << 'EOF'
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
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document "${trust_policy}" \
        --description "IAM role for AppConfig Lambda demo" \
        --tags Key=Project,Value=SimpleAppConfig Key=Environment,Value=Demo \
        > /dev/null
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create custom policy for AppConfig access
    local appconfig_policy=$(cat << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "appconfig:StartConfigurationSession",
        "appconfig:GetLatestConfiguration"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)
    
    # Create and attach AppConfig policy
    aws iam create-policy \
        --policy-name "${APPCONFIG_POLICY_NAME}" \
        --policy-document "${appconfig_policy}" \
        --description "Policy for Lambda to access AppConfig" \
        > /dev/null
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${APPCONFIG_POLICY_NAME}"
    
    # Get the role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Update .env file with role ARN
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "IAM role created: ${LAMBDA_ROLE_ARN}"
}

create_appconfig_application() {
    log_info "Creating AppConfig application..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create AppConfig application: ${APP_NAME}"
        return 0
    fi
    
    # Create AppConfig application
    aws appconfig create-application \
        --name "${APP_NAME}" \
        --description "Simple configuration management demo" \
        --tags Project=SimpleAppConfig,Environment=Demo \
        > /dev/null
    
    # Get the application ID
    export APP_ID=$(aws appconfig list-applications \
        --query "Items[?Name=='${APP_NAME}'].Id" \
        --output text)
    
    echo "APP_ID=${APP_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "AppConfig application created with ID: ${APP_ID}"
}

create_appconfig_environment() {
    log_info "Creating AppConfig environment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create AppConfig environment: development"
        return 0
    fi
    
    # Create development environment
    aws appconfig create-environment \
        --application-id "${APP_ID}" \
        --name "development" \
        --description "Development environment for configuration testing" \
        --tags Project=SimpleAppConfig,Environment=Demo \
        > /dev/null
    
    # Get the environment ID
    export ENV_ID=$(aws appconfig list-environments \
        --application-id "${APP_ID}" \
        --query "Items[?Name=='development'].Id" \
        --output text)
    
    echo "ENV_ID=${ENV_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Development environment created with ID: ${ENV_ID}"
}

create_configuration_profile() {
    log_info "Creating configuration profile..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create configuration profile: app-settings"
        return 0
    fi
    
    # Create configuration profile for freeform data
    aws appconfig create-configuration-profile \
        --application-id "${APP_ID}" \
        --name "app-settings" \
        --description "Application settings configuration" \
        --location-uri "hosted" \
        --tags Project=SimpleAppConfig,Environment=Demo \
        > /dev/null
    
    # Get the configuration profile ID
    export CONFIG_PROFILE_ID=$(aws appconfig list-configuration-profiles \
        --application-id "${APP_ID}" \
        --query "Items[?Name=='app-settings'].Id" \
        --output text)
    
    echo "CONFIG_PROFILE_ID=${CONFIG_PROFILE_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Configuration profile created with ID: ${CONFIG_PROFILE_ID}"
}

create_initial_configuration() {
    log_info "Creating initial configuration data..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create initial configuration data"
        return 0
    fi
    
    # Create configuration data as JSON
    local config_data=$(cat << 'EOF'
{
  "database": {
    "max_connections": 100,
    "timeout_seconds": 30,
    "retry_attempts": 3
  },
  "features": {
    "enable_logging": true,
    "enable_metrics": true,
    "debug_mode": false
  },
  "api": {
    "rate_limit": 1000,
    "cache_ttl": 300
  }
}
EOF
)
    
    # Create hosted configuration version
    echo "${config_data}" | aws appconfig create-hosted-configuration-version \
        --application-id "${APP_ID}" \
        --configuration-profile-id "${CONFIG_PROFILE_ID}" \
        --content-type "application/json" \
        --content fileb:///dev/stdin \
        > /dev/null
    
    # Get the version number
    export CONFIG_VERSION=$(aws appconfig list-hosted-configuration-versions \
        --application-id "${APP_ID}" \
        --configuration-profile-id "${CONFIG_PROFILE_ID}" \
        --query "Items[0].VersionNumber" --output text)
    
    echo "CONFIG_VERSION=${CONFIG_VERSION}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Configuration data created with version: ${CONFIG_VERSION}"
}

create_lambda_function() {
    log_info "Creating Lambda function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Create temporary directory for Lambda code
    local temp_dir=$(mktemp -d)
    local lambda_code_file="${temp_dir}/lambda_function.py"
    
    # Copy Lambda function code
    if [[ -f "${PROJECT_ROOT}/code/lambda/lambda_function.py" ]]; then
        cp "${PROJECT_ROOT}/code/lambda/lambda_function.py" "${lambda_code_file}"
    else
        # Create Lambda function code if it doesn't exist
        cat > "${lambda_code_file}" << 'EOF'
import json
import urllib3
import os

def lambda_handler(event, context):
    # AppConfig extension endpoint (local to Lambda execution environment)
    appconfig_endpoint = 'http://localhost:2772'
    
    # AppConfig parameters from environment variables
    application_id = os.environ.get('APPCONFIG_APPLICATION_ID')
    environment_id = os.environ.get('APPCONFIG_ENVIRONMENT_ID')
    configuration_profile_id = os.environ.get('APPCONFIG_CONFIGURATION_PROFILE_ID')
    
    try:
        # Create HTTP connection to AppConfig extension
        http = urllib3.PoolManager()
        
        # Retrieve configuration from AppConfig
        config_url = f"{appconfig_endpoint}/applications/{application_id}/environments/{environment_id}/configurations/{configuration_profile_id}"
        response = http.request('GET', config_url)
        
        if response.status == 200:
            config_data = json.loads(response.data.decode('utf-8'))
            
            # Use configuration in application logic
            max_connections = config_data.get('database', {}).get('max_connections', 50)
            enable_logging = config_data.get('features', {}).get('enable_logging', False)
            rate_limit = config_data.get('api', {}).get('rate_limit', 500)
            
            # Log configuration usage if logging is enabled
            if enable_logging:
                print(f"Configuration loaded - Max connections: {max_connections}, Rate limit: {rate_limit}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Configuration loaded successfully',
                    'config_summary': {
                        'database_max_connections': max_connections,
                        'logging_enabled': enable_logging,
                        'api_rate_limit': rate_limit
                    }
                })
            }
        else:
            print(f"Failed to retrieve configuration: {response.status}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Configuration retrieval failed'})
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
    fi
    
    # Create deployment package
    local zip_file="${temp_dir}/lambda-function.zip"
    (cd "${temp_dir}" && zip -q "${zip_file}" lambda_function.py)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.12 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://${zip_file}" \
        --timeout 30 \
        --description "Demo function for AppConfig integration" \
        --environment Variables="{
            APPCONFIG_APPLICATION_ID=${APP_ID},
            APPCONFIG_ENVIRONMENT_ID=${ENV_ID},
            APPCONFIG_CONFIGURATION_PROFILE_ID=${CONFIG_PROFILE_ID}
        }" \
        --tags Project=SimpleAppConfig,Environment=Demo \
        > /dev/null
    
    # Cleanup temporary files
    rm -rf "${temp_dir}"
    
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

add_appconfig_extension() {
    log_info "Adding AppConfig extension layer..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would add AppConfig extension layer"
        return 0
    fi
    
    # Add AppConfig extension layer (region-specific ARN)
    aws lambda update-function-configuration \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --layers "arn:aws:lambda:${AWS_REGION}:027255383542:layer:AWS-AppConfig-Extension:207" \
        > /dev/null
    
    log_success "AppConfig extension layer added to Lambda function"
}

create_deployment_strategy() {
    log_info "Creating deployment strategy..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create deployment strategy: ${DEPLOYMENT_STRATEGY_NAME}"
        return 0
    fi
    
    # Create deployment strategy for immediate deployment
    aws appconfig create-deployment-strategy \
        --name "${DEPLOYMENT_STRATEGY_NAME}" \
        --description "Immediate deployment for testing" \
        --deployment-duration-in-minutes 0 \
        --final-bake-time-in-minutes 0 \
        --growth-factor 100 \
        --growth-type LINEAR \
        --replicate-to NONE \
        --tags Project=SimpleAppConfig,Environment=Demo \
        > /dev/null
    
    # Get deployment strategy ID
    export DEPLOYMENT_STRATEGY_ID=$(aws appconfig list-deployment-strategies \
        --query "Items[?Name=='${DEPLOYMENT_STRATEGY_NAME}'].Id" \
        --output text)
    
    echo "DEPLOYMENT_STRATEGY_ID=${DEPLOYMENT_STRATEGY_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Deployment strategy created with ID: ${DEPLOYMENT_STRATEGY_ID}"
}

deploy_configuration() {
    log_info "Deploying configuration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy configuration"
        return 0
    fi
    
    # Start configuration deployment
    aws appconfig start-deployment \
        --application-id "${APP_ID}" \
        --environment-id "${ENV_ID}" \
        --deployment-strategy-id "${DEPLOYMENT_STRATEGY_ID}" \
        --configuration-profile-id "${CONFIG_PROFILE_ID}" \
        --configuration-version "${CONFIG_VERSION}" \
        --description "Initial configuration deployment" \
        --tags Project=SimpleAppConfig,Environment=Demo \
        > /dev/null
    
    # Wait for deployment to complete
    log_info "Waiting for configuration deployment to complete..."
    sleep 10
    
    log_success "Configuration deployed successfully"
}

#########################################################################
# Validation Functions
#########################################################################

validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Test Lambda function
    local response_file=$(mktemp)
    
    if aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload '{}' \
        "${response_file}" > /dev/null 2>&1; then
        
        local response_content
        response_content=$(cat "${response_file}")
        
        if echo "${response_content}" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
            log_success "Lambda function test passed"
            debug "Response: ${response_content}"
        else
            log_warning "Lambda function test returned non-200 status"
            debug "Response: ${response_content}"
        fi
    else
        log_warning "Lambda function invocation failed"
    fi
    
    rm -f "${response_file}"
    
    # Verify resources exist
    local resources_ok=true
    
    if ! aws appconfig get-application --application-id "${APP_ID}" > /dev/null 2>&1; then
        log_error "AppConfig application not found"
        resources_ok=false
    fi
    
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" > /dev/null 2>&1; then
        log_error "Lambda function not found"
        resources_ok=false
    fi
    
    if [[ "${resources_ok}" == "true" ]]; then
        log_success "Resource validation passed"
    else
        log_error "Resource validation failed"
        return 1
    fi
}

#########################################################################
# Main Deployment Function
#########################################################################

deploy() {
    local start_time=$(date +%s)
    
    log_info "Starting deployment of Simple App Configuration..."
    log_info "Timestamp: $(date)"
    log_info "Log file: ${LOG_FILE}"
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Run deployment steps
    check_prerequisites
    validate_aws_region
    setup_environment_variables
    create_iam_role
    create_appconfig_application
    create_appconfig_environment
    create_configuration_profile
    create_initial_configuration
    create_lambda_function
    add_appconfig_extension
    create_deployment_strategy
    deploy_configuration
    validate_deployment
    
    # Calculate deployment time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: ${duration} seconds"
    log_info "Resources created:"
    log_info "  - AppConfig Application: ${APP_NAME} (${APP_ID})"
    log_info "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  - IAM Role: ${LAMBDA_ROLE_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        cat << EOF

┌─────────────────────────────────────────────────────────────────┐
│                    🎉 Deployment Successful! 🎉                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Your Simple App Configuration is now ready to use!             │
│                                                                 │
│ Next Steps:                                                     │
│ 1. Test your Lambda function in the AWS Console                │
│ 2. Modify configuration values in AppConfig                    │
│ 3. Try the configuration update example in the recipe          │
│                                                                 │
│ To clean up resources: ./destroy.sh                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

EOF
    fi
}

#########################################################################
# Script Entry Point
#########################################################################

main() {
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log_info "Dry run mode enabled"
                shift
                ;;
            --debug)
                DEBUG=true
                log_info "Debug mode enabled"
                shift
                ;;
            --no-cleanup)
                CLEANUP_ON_ERROR=false
                log_info "Cleanup on error disabled"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Start deployment
    deploy
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi