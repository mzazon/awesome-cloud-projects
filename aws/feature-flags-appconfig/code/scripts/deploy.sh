#!/bin/bash

# AWS AppConfig Feature Flags Deployment Script
# Based on the "Feature Flags with AWS AppConfig" recipe
# Version: 1.0
# Description: Deploys a complete feature flag solution using AWS AppConfig, Lambda, and CloudWatch

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/feature-flags-appconfig-deploy-$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check log file: ${LOG_FILE}"
    exit 1
}

# Cleanup function for unexpected exits
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        log_error "Script interrupted. Cleaning up temporary files..."
        rm -f trust-policy.json appconfig-policy.json feature-flags.json lambda_function.py lambda-function.zip
        log_info "Temporary files cleaned up. Check log for details: ${LOG_FILE}"
    fi
}
trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d'/' -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    # Check required permissions (basic test)
    local caller_info=$(aws sts get-caller-identity)
    local account_id=$(echo "$caller_info" | jq -r '.Account' 2>/dev/null || echo "$caller_info" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    log_info "Deploying to AWS Account: ${account_id}"
    
    # Check if jq is available (helpful but not required)
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed. Some output formatting will be limited."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error_exit "zip utility is not installed. Required for Lambda deployment package."
    fi
    
    log_success "Prerequisites check completed."
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "${AWS_REGION}" ]; then
        export AWS_REGION="us-east-1"
        log_warn "No region configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export APP_NAME="feature-demo-app-${RANDOM_SUFFIX}"
    export ENVIRONMENT_NAME="production"
    export PROFILE_NAME="feature-flags"
    export FUNCTION_NAME="feature-flag-demo-${RANDOM_SUFFIX}"
    export ROLE_NAME="lambda-appconfig-role-${RANDOM_SUFFIX}"
    export ALARM_NAME="lambda-error-rate-${RANDOM_SUFFIX}"
    export STRATEGY_NAME="gradual-rollout-${RANDOM_SUFFIX}"
    export POLICY_NAME="appconfig-access-policy-${RANDOM_SUFFIX}"
    
    # Save deployment state
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
APP_NAME=${APP_NAME}
ENVIRONMENT_NAME=${ENVIRONMENT_NAME}
PROFILE_NAME=${PROFILE_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
ALARM_NAME=${ALARM_NAME}
STRATEGY_NAME=${STRATEGY_NAME}
POLICY_NAME=${POLICY_NAME}
EOF
    
    log_success "Environment configured:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "  Application: ${APP_NAME}"
    log_info "  Function: ${FUNCTION_NAME}"
    log_info "  Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
}

# Create IAM role for Lambda with AppConfig access
create_iam_role() {
    log_info "Creating IAM role for Lambda with AppConfig access..."
    
    # Create trust policy
    cat > trust-policy.json << 'EOF'
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
    
    # Create IAM role
    if aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --output text &>> "${LOG_FILE}"; then
        log_success "IAM role created: ${ROLE_NAME}"
    else
        error_exit "Failed to create IAM role"
    fi
    
    # Attach basic Lambda execution policy
    if aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        &>> "${LOG_FILE}"; then
        log_success "Attached Lambda basic execution policy"
    else
        error_exit "Failed to attach Lambda basic execution policy"
    fi
    
    # Create AppConfig access policy
    cat > appconfig-policy.json << 'EOF'
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
    
    # Create and attach AppConfig policy
    if aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file://appconfig-policy.json \
        --output text &>> "${LOG_FILE}"; then
        log_success "AppConfig access policy created: ${POLICY_NAME}"
    else
        error_exit "Failed to create AppConfig access policy"
    fi
    
    if aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" \
        &>> "${LOG_FILE}"; then
        log_success "Attached AppConfig access policy"
    else
        error_exit "Failed to attach AppConfig access policy"
    fi
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query Role.Arn --output text)
    
    if [ -n "${ROLE_ARN}" ]; then
        log_success "IAM role ready: ${ROLE_ARN}"
        echo "ROLE_ARN=${ROLE_ARN}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve IAM role ARN"
    fi
}

# Create AWS AppConfig application
create_appconfig_application() {
    log_info "Creating AWS AppConfig application..."
    
    if aws appconfig create-application \
        --name "${APP_NAME}" \
        --description "Feature flag demo application for safe deployments" \
        --output text &>> "${LOG_FILE}"; then
        log_success "AppConfig application created: ${APP_NAME}"
    else
        error_exit "Failed to create AppConfig application"
    fi
    
    # Get application ID
    APP_ID=$(aws appconfig list-applications \
        --query "Items[?Name=='${APP_NAME}'].Id | [0]" \
        --output text)
    
    if [ -n "${APP_ID}" ] && [ "${APP_ID}" != "None" ]; then
        log_success "AppConfig application ID: ${APP_ID}"
        echo "APP_ID=${APP_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve AppConfig application ID"
    fi
}

# Create CloudWatch alarm for monitoring
create_cloudwatch_alarm() {
    log_info "Creating CloudWatch alarm for monitoring..."
    
    if aws cloudwatch put-metric-alarm \
        --alarm-name "${ALARM_NAME}" \
        --alarm-description "Monitor Lambda function error rate for AppConfig rollback" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
        --output text &>> "${LOG_FILE}"; then
        log_success "CloudWatch alarm created: ${ALARM_NAME}"
    else
        error_exit "Failed to create CloudWatch alarm"
    fi
    
    # Get alarm ARN
    ALARM_ARN=$(aws cloudwatch describe-alarms \
        --alarm-names "${ALARM_NAME}" \
        --query "MetricAlarms[0].AlarmArn" --output text)
    
    if [ -n "${ALARM_ARN}" ] && [ "${ALARM_ARN}" != "None" ]; then
        log_success "CloudWatch alarm ARN: ${ALARM_ARN}"
        echo "ALARM_ARN=${ALARM_ARN}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve CloudWatch alarm ARN"
    fi
}

# Create service-linked role for AppConfig monitoring
create_service_linked_role() {
    log_info "Creating service-linked role for AppConfig monitoring..."
    
    # Create service-linked role (ignore if already exists)
    if aws iam create-service-linked-role \
        --aws-service-name appconfig.amazonaws.com \
        --description "Service-linked role for AppConfig monitoring" \
        &>> "${LOG_FILE}"; then
        log_success "Service-linked role created"
    else
        log_info "Service-linked role already exists or creation failed (this is normal)"
    fi
    
    # Get service-linked role ARN
    SERVICE_ROLE_ARN=$(aws iam get-role \
        --role-name AWSServiceRoleForAppConfig \
        --query Role.Arn --output text 2>/dev/null || echo "")
    
    if [ -n "${SERVICE_ROLE_ARN}" ]; then
        log_success "Service-linked role ARN: ${SERVICE_ROLE_ARN}"
        echo "SERVICE_ROLE_ARN=${SERVICE_ROLE_ARN}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        log_warn "Could not retrieve service-linked role ARN. AppConfig monitoring may be limited."
        SERVICE_ROLE_ARN=""
    fi
}

# Create AppConfig environment with monitoring
create_appconfig_environment() {
    log_info "Creating AppConfig environment with monitoring..."
    
    if [ -n "${SERVICE_ROLE_ARN}" ]; then
        # Create environment with monitoring
        aws appconfig create-environment \
            --application-id "${APP_ID}" \
            --name "${ENVIRONMENT_NAME}" \
            --description "Production environment with automated rollback" \
            --monitors "AlarmArn=${ALARM_ARN},AlarmRoleArn=${SERVICE_ROLE_ARN}" \
            --output text &>> "${LOG_FILE}"
    else
        # Create environment without monitoring
        aws appconfig create-environment \
            --application-id "${APP_ID}" \
            --name "${ENVIRONMENT_NAME}" \
            --description "Production environment" \
            --output text &>> "${LOG_FILE}"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "AppConfig environment created: ${ENVIRONMENT_NAME}"
    else
        error_exit "Failed to create AppConfig environment"
    fi
    
    # Get environment ID
    ENV_ID=$(aws appconfig list-environments \
        --application-id "${APP_ID}" \
        --query "Items[?Name=='${ENVIRONMENT_NAME}'].Id | [0]" \
        --output text)
    
    if [ -n "${ENV_ID}" ] && [ "${ENV_ID}" != "None" ]; then
        log_success "AppConfig environment ID: ${ENV_ID}"
        echo "ENV_ID=${ENV_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve AppConfig environment ID"
    fi
}

# Create feature flag configuration profile
create_configuration_profile() {
    log_info "Creating feature flag configuration profile..."
    
    if aws appconfig create-configuration-profile \
        --application-id "${APP_ID}" \
        --name "${PROFILE_NAME}" \
        --location-uri hosted \
        --type AWS.AppConfig.FeatureFlags \
        --description "Feature flags for gradual rollout and A/B testing" \
        --output text &>> "${LOG_FILE}"; then
        log_success "Configuration profile created: ${PROFILE_NAME}"
    else
        error_exit "Failed to create configuration profile"
    fi
    
    # Get configuration profile ID
    PROFILE_ID=$(aws appconfig list-configuration-profiles \
        --application-id "${APP_ID}" \
        --query "Items[?Name=='${PROFILE_NAME}'].Id | [0]" \
        --output text)
    
    if [ -n "${PROFILE_ID}" ] && [ "${PROFILE_ID}" != "None" ]; then
        log_success "Configuration profile ID: ${PROFILE_ID}"
        echo "PROFILE_ID=${PROFILE_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve configuration profile ID"
    fi
}

# Create feature flag configuration data
create_feature_flag_configuration() {
    log_info "Creating feature flag configuration data..."
    
    # Create feature flag configuration
    cat > feature-flags.json << 'EOF'
{
    "flags": {
        "new-checkout-flow": {
            "name": "new-checkout-flow",
            "enabled": false,
            "attributes": {
                "rollout-percentage": {
                    "constraints": {
                        "type": "number",
                        "required": true
                    }
                },
                "target-audience": {
                    "constraints": {
                        "type": "string",
                        "required": false
                    }
                }
            }
        },
        "enhanced-search": {
            "name": "enhanced-search",
            "enabled": true,
            "attributes": {
                "search-algorithm": {
                    "constraints": {
                        "type": "string",
                        "required": true
                    }
                },
                "cache-ttl": {
                    "constraints": {
                        "type": "number",
                        "required": false
                    }
                }
            }
        },
        "premium-features": {
            "name": "premium-features",
            "enabled": false,
            "attributes": {
                "feature-list": {
                    "constraints": {
                        "type": "string",
                        "required": false
                    }
                }
            }
        }
    },
    "attributes": {
        "rollout-percentage": {
            "number": 0
        },
        "target-audience": {
            "string": "beta-users"
        },
        "search-algorithm": {
            "string": "elasticsearch"
        },
        "cache-ttl": {
            "number": 300
        },
        "feature-list": {
            "string": "advanced-analytics,priority-support"
        }
    }
}
EOF
    
    # Create configuration version
    if aws appconfig create-hosted-configuration-version \
        --application-id "${APP_ID}" \
        --configuration-profile-id "${PROFILE_ID}" \
        --content-type "application/json" \
        --content file://feature-flags.json \
        --output text &>> "${LOG_FILE}"; then
        log_success "Feature flag configuration created"
    else
        error_exit "Failed to create feature flag configuration"
    fi
    
    # Get configuration version
    CONFIG_VERSION=$(aws appconfig list-hosted-configuration-versions \
        --application-id "${APP_ID}" \
        --configuration-profile-id "${PROFILE_ID}" \
        --query "Items[0].VersionNumber" --output text)
    
    if [ -n "${CONFIG_VERSION}" ] && [ "${CONFIG_VERSION}" != "None" ]; then
        log_success "Configuration version: ${CONFIG_VERSION}"
        echo "CONFIG_VERSION=${CONFIG_VERSION}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve configuration version"
    fi
}

# Create deployment strategy
create_deployment_strategy() {
    log_info "Creating deployment strategy for gradual rollout..."
    
    if aws appconfig create-deployment-strategy \
        --name "${STRATEGY_NAME}" \
        --description "Gradual rollout over 20 minutes with monitoring" \
        --deployment-duration-in-minutes 20 \
        --final-bake-time-in-minutes 10 \
        --growth-factor 25 \
        --growth-type LINEAR \
        --replicate-to NONE \
        --output text &>> "${LOG_FILE}"; then
        log_success "Deployment strategy created: ${STRATEGY_NAME}"
    else
        error_exit "Failed to create deployment strategy"
    fi
    
    # Get deployment strategy ID
    STRATEGY_ID=$(aws appconfig list-deployment-strategies \
        --query "Items[?Name=='${STRATEGY_NAME}'].Id | [0]" \
        --output text)
    
    if [ -n "${STRATEGY_ID}" ] && [ "${STRATEGY_ID}" != "None" ]; then
        log_success "Deployment strategy ID: ${STRATEGY_ID}"
        echo "STRATEGY_ID=${STRATEGY_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        error_exit "Failed to retrieve deployment strategy ID"
    fi
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function with AppConfig integration..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import urllib.request
import urllib.error
import os

def lambda_handler(event, context):
    # AppConfig Lambda extension endpoint
    appconfig_url = f"http://localhost:2772/applications/{os.environ['APP_ID']}/environments/{os.environ['ENV_ID']}/configurations/{os.environ['PROFILE_ID']}"
    
    try:
        # Retrieve feature flags from AppConfig
        request = urllib.request.Request(appconfig_url)
        with urllib.request.urlopen(request, timeout=10) as response:
            config_data = json.loads(response.read().decode())
        
        # Extract feature flags
        flags = config_data.get('flags', {})
        attributes = config_data.get('attributes', {})
        
        # Business logic using feature flags
        result = {
            'message': 'Feature flag demo response',
            'features': {}
        }
        
        # Check new checkout flow
        if flags.get('new-checkout-flow', {}).get('enabled', False):
            rollout_percentage = attributes.get('rollout-percentage', {}).get('number', 0)
            result['features']['checkout'] = {
                'enabled': True,
                'type': 'new-flow',
                'rollout_percentage': rollout_percentage
            }
        else:
            result['features']['checkout'] = {
                'enabled': False,
                'type': 'legacy-flow'
            }
        
        # Check enhanced search
        if flags.get('enhanced-search', {}).get('enabled', False):
            search_algorithm = attributes.get('search-algorithm', {}).get('string', 'basic')
            cache_ttl = attributes.get('cache-ttl', {}).get('number', 300)
            result['features']['search'] = {
                'enabled': True,
                'algorithm': search_algorithm,
                'cache_ttl': cache_ttl
            }
        else:
            result['features']['search'] = {
                'enabled': False,
                'algorithm': 'basic'
            }
        
        # Check premium features
        if flags.get('premium-features', {}).get('enabled', False):
            feature_list = attributes.get('feature-list', {}).get('string', '')
            result['features']['premium'] = {
                'enabled': True,
                'features': feature_list.split(',') if feature_list else []
            }
        else:
            result['features']['premium'] = {
                'enabled': False,
                'features': []
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, indent=2)
        }
        
    except urllib.error.HTTPError as e:
        print(f"HTTP Error retrieving feature flags: {e.code} - {e.reason}")
        return create_fallback_response(str(e))
    except urllib.error.URLError as e:
        print(f"URL Error retrieving feature flags: {str(e)}")
        return create_fallback_response(str(e))
    except json.JSONDecodeError as e:
        print(f"JSON decode error: {str(e)}")
        return create_fallback_response(str(e))
    except Exception as e:
        print(f"Unexpected error retrieving feature flags: {str(e)}")
        return create_fallback_response(str(e))

def create_fallback_response(error_msg):
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Using default configuration due to error',
            'error': error_msg,
            'features': {
                'checkout': {'enabled': False, 'type': 'legacy-flow'},
                'search': {'enabled': False, 'algorithm': 'basic'},
                'premium': {'enabled': False, 'features': []}
            }
        }, indent=2)
    }
EOF
    
    # Create deployment package
    if zip lambda-function.zip lambda_function.py &>> "${LOG_FILE}"; then
        log_success "Lambda deployment package created"
    else
        error_exit "Failed to create Lambda deployment package"
    fi
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{APP_ID=${APP_ID},ENV_ID=${ENV_ID},PROFILE_ID=${PROFILE_ID}}" \
        --output text &>> "${LOG_FILE}"; then
        log_success "Lambda function created: ${FUNCTION_NAME}"
    else
        error_exit "Failed to create Lambda function"
    fi
    
    # Add AppConfig Lambda extension layer
    log_info "Adding AppConfig Lambda extension layer..."
    if aws lambda update-function-configuration \
        --function-name "${FUNCTION_NAME}" \
        --layers "arn:aws:lambda:${AWS_REGION}:027255383542:layer:AWS-AppConfig-Extension:82" \
        --output text &>> "${LOG_FILE}"; then
        log_success "AppConfig Lambda extension layer added"
    else
        log_warn "Failed to add AppConfig Lambda extension layer, but continuing..."
    fi
}

# Deploy feature flag configuration
deploy_configuration() {
    log_info "Deploying feature flag configuration..."
    
    if aws appconfig start-deployment \
        --application-id "${APP_ID}" \
        --environment-id "${ENV_ID}" \
        --deployment-strategy-id "${STRATEGY_ID}" \
        --configuration-profile-id "${PROFILE_ID}" \
        --configuration-version "${CONFIG_VERSION}" \
        --description "Initial deployment of feature flags" \
        --output text &>> "${LOG_FILE}"; then
        log_success "Feature flag deployment started"
    else
        error_exit "Failed to start feature flag deployment"
    fi
    
    # Get deployment ID
    DEPLOYMENT_ID=$(aws appconfig list-deployments \
        --application-id "${APP_ID}" \
        --environment-id "${ENV_ID}" \
        --query "Items[0].DeploymentNumber" --output text)
    
    if [ -n "${DEPLOYMENT_ID}" ] && [ "${DEPLOYMENT_ID}" != "None" ]; then
        log_success "Deployment ID: ${DEPLOYMENT_ID}"
        echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    else
        log_warn "Could not retrieve deployment ID"
    fi
}

# Test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    # Wait a moment for the deployment to start
    sleep 10
    
    # Test Lambda function
    log_info "Testing Lambda function..."
    if aws lambda invoke \
        --function-name "${FUNCTION_NAME}" \
        --payload '{}' \
        response.json &>> "${LOG_FILE}"; then
        log_success "Lambda function test successful"
        if command -v jq &> /dev/null; then
            log_info "Lambda response:"
            cat response.json | jq . | tee -a "${LOG_FILE}"
        else
            log_info "Lambda response: $(cat response.json)"
        fi
    else
        log_warn "Lambda function test failed, but deployment continues"
    fi
    
    # Check deployment status
    if [ -n "${DEPLOYMENT_ID}" ]; then
        log_info "Checking deployment status..."
        DEPLOYMENT_STATE=$(aws appconfig get-deployment \
            --application-id "${APP_ID}" \
            --environment-id "${ENV_ID}" \
            --deployment-number "${DEPLOYMENT_ID}" \
            --query "State" --output text 2>/dev/null || echo "UNKNOWN")
        log_info "Deployment state: ${DEPLOYMENT_STATE}"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f trust-policy.json appconfig-policy.json feature-flags.json
    rm -f lambda_function.py lambda-function.zip response.json
    log_success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log_info "Resources created:"
    log_info "  • IAM Role: ${ROLE_NAME}"
    log_info "  • AppConfig Application: ${APP_NAME} (${APP_ID})"
    log_info "  • AppConfig Environment: ${ENVIRONMENT_NAME} (${ENV_ID})"
    log_info "  • Configuration Profile: ${PROFILE_NAME} (${PROFILE_ID})"
    log_info "  • Deployment Strategy: ${STRATEGY_NAME} (${STRATEGY_ID})"
    log_info "  • Lambda Function: ${FUNCTION_NAME}"
    log_info "  • CloudWatch Alarm: ${ALARM_NAME}"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Monitor the deployment in AWS Console"
    log_info "  2. Test the Lambda function: aws lambda invoke --function-name ${FUNCTION_NAME} --payload '{}' response.json"
    log_info "  3. Update feature flags as needed using the AWS Console or CLI"
    log_info "  4. To clean up resources, run: ./destroy.sh"
    log_info ""
    log_info "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
    log_info "Deployment log saved to: ${LOG_FILE}"
    log_info ""
    log_success "Feature flags with AWS AppConfig deployment completed successfully!"
}

# Main deployment function
main() {
    echo -e "${BLUE}Starting AWS AppConfig Feature Flags Deployment${NC}"
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_appconfig_application
    create_cloudwatch_alarm
    create_service_linked_role
    create_appconfig_environment
    create_configuration_profile
    create_feature_flag_configuration
    create_deployment_strategy
    create_lambda_function
    deploy_configuration
    test_deployment
    cleanup_temp_files
    display_summary
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi