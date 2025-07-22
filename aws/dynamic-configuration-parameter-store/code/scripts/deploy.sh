#!/bin/bash

# Deploy script for Dynamic Configuration with Parameter Store
# This script deploys the complete serverless configuration management solution

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partially created resources..."
    
    # Remove local files if they exist
    rm -f trust-policy.json parameter-store-policy.json dashboard.json
    rm -f function.zip lambda_function.py response*.json
    
    # Attempt to clean up AWS resources if variables are set
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log "Attempting to clean up AWS resources..."
        
        # Remove Lambda function
        aws lambda delete-function --function-name "${FUNCTION_NAME}" 2>/dev/null || true
        
        # Remove EventBridge rule
        if [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]]; then
            aws events remove-targets --rule "${EVENTBRIDGE_RULE_NAME}" --ids "1" 2>/dev/null || true
            aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}" 2>/dev/null || true
        fi
        
        # Remove CloudWatch alarms
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            aws cloudwatch delete-alarms \
                --alarm-names "ConfigManager-Errors-${RANDOM_SUFFIX}" \
                              "ConfigManager-Duration-${RANDOM_SUFFIX}" \
                              "ConfigManager-RetrievalFailures-${RANDOM_SUFFIX}" 2>/dev/null || true
            
            aws cloudwatch delete-dashboards \
                --dashboard-names "ConfigManager-${RANDOM_SUFFIX}" 2>/dev/null || true
        fi
        
        # Remove IAM resources
        if [[ -n "${ROLE_NAME:-}" && -n "${AWS_ACCOUNT_ID:-}" && -n "${RANDOM_SUFFIX:-}" ]]; then
            aws iam detach-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
            
            aws iam detach-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ParameterStoreAccessPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
            
            aws iam delete-policy \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ParameterStoreAccessPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
            
            aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
        fi
    fi
    
    error "Cleanup completed. Please check AWS console for any remaining resources."
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing jq for JSON processing..."
        # Try to install jq if not present (works on Amazon Linux/Ubuntu)
        if command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        else
            error "Please install jq manually for JSON processing"
            exit 1
        fi
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    success "All prerequisites check passed"
}

# Function to set up environment
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 3)
    
    # Set resource names
    export FUNCTION_NAME="config-manager-${RANDOM_SUFFIX}"
    export ROLE_NAME="config-manager-role-${RANDOM_SUFFIX}"
    export PARAMETER_PREFIX="/myapp/config"
    export EVENTBRIDGE_RULE_NAME="parameter-change-rule-${RANDOM_SUFFIX}"
    
    # Create deployment info file for cleanup script
    cat > .deployment_info << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
PARAMETER_PREFIX=${PARAMETER_PREFIX}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment configured - Region: ${AWS_REGION}, Account: ${AWS_ACCOUNT_ID}"
    success "Function name: ${FUNCTION_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda service
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
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    success "IAM role created: ${ROLE_NAME}"
}

# Function to create custom IAM policy
create_iam_policy() {
    log "Creating custom IAM policy for Parameter Store access..."
    
    # Create custom policy for Parameter Store and monitoring
    cat > parameter-store-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Resource": "arn:aws:ssm:*:*:parameter/myapp/config/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": "arn:aws:kms:*:*:key/*",
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": "ssm.*.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach the policy
    aws iam create-policy \
        --policy-name "ParameterStoreAccessPolicy-${RANDOM_SUFFIX}" \
        --policy-document file://parameter-store-policy.json \
        --description "Policy for accessing Parameter Store and CloudWatch metrics"
    
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ParameterStoreAccessPolicy-${RANDOM_SUFFIX}"
    
    success "Parameter Store access policy created and attached"
}

# Function to create sample parameters
create_sample_parameters() {
    log "Creating sample configuration parameters in Parameter Store..."
    
    # Create application configuration parameters
    aws ssm put-parameter \
        --name "${PARAMETER_PREFIX}/database/host" \
        --value "myapp-db.cluster-xyz.us-east-1.rds.amazonaws.com" \
        --type "String" \
        --description "Database host endpoint" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    aws ssm put-parameter \
        --name "${PARAMETER_PREFIX}/database/port" \
        --value "5432" \
        --type "String" \
        --description "Database port number" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    aws ssm put-parameter \
        --name "${PARAMETER_PREFIX}/api/timeout" \
        --value "30" \
        --type "String" \
        --description "API timeout in seconds" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    aws ssm put-parameter \
        --name "${PARAMETER_PREFIX}/features/new-ui" \
        --value "true" \
        --type "String" \
        --description "Feature flag for new UI" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    # Create a SecureString parameter for sensitive data
    aws ssm put-parameter \
        --name "${PARAMETER_PREFIX}/database/password" \
        --value "supersecretpassword123" \
        --type "SecureString" \
        --description "Database password (encrypted)" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    success "Configuration parameters created in Parameter Store"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function code..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import os
import urllib3
import boto3
from datetime import datetime

# Initialize HTTP client for extension
http = urllib3.PoolManager()

# Initialize CloudWatch client for custom metrics
cloudwatch = boto3.client('cloudwatch')

def get_parameter_from_extension(parameter_name):
    """Retrieve parameter using the Parameters and Secrets Extension"""
    try:
        # Use localhost endpoint provided by the extension
        port = os.environ.get('PARAMETERS_SECRETS_EXTENSION_HTTP_PORT', '2773')
        url = f'http://localhost:{port}/systemsmanager/parameters/get/?name={parameter_name}'
        
        response = http.request('GET', url)
        
        if response.status == 200:
            data = json.loads(response.data.decode('utf-8'))
            return data['Parameter']['Value']
        else:
            raise Exception(f"Failed to retrieve parameter: {response.status}")
            
    except Exception as e:
        print(f"Error retrieving parameter {parameter_name}: {str(e)}")
        # Fallback to direct SSM call if extension fails
        return get_parameter_direct(parameter_name)

def get_parameter_direct(parameter_name):
    """Fallback method using direct SSM API call"""
    try:
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error with direct SSM call: {str(e)}")
        return None

def send_custom_metric(metric_name, value, unit='Count'):
    """Send custom metric to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='ConfigManager',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        print(f"Error sending metric: {str(e)}")

def lambda_handler(event, context):
    """Main Lambda handler function"""
    try:
        # Define parameter prefix
        parameter_prefix = os.environ.get('PARAMETER_PREFIX', '/myapp/config')
        
        # Retrieve configuration parameters
        config = {}
        parameters = [
            f"{parameter_prefix}/database/host",
            f"{parameter_prefix}/database/port",
            f"{parameter_prefix}/api/timeout",
            f"{parameter_prefix}/features/new-ui"
        ]
        
        # Track configuration retrieval metrics
        successful_retrievals = 0
        failed_retrievals = 0
        
        for param in parameters:
            value = get_parameter_from_extension(param)
            if value is not None:
                config[param.split('/')[-1]] = value
                successful_retrievals += 1
            else:
                failed_retrievals += 1
        
        # Send custom metrics
        send_custom_metric('SuccessfulParameterRetrievals', successful_retrievals)
        send_custom_metric('FailedParameterRetrievals', failed_retrievals)
        
        # Log configuration status
        print(f"Configuration loaded: {len(config)} parameters")
        print(f"Configuration: {json.dumps(config, indent=2)}")
        
        # Return response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Configuration loaded successfully',
                'config': config,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        send_custom_metric('ConfigurationErrors', 1)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Configuration retrieval failed',
                'message': str(e)
            })
        }
EOF
    
    # Create deployment package
    zip -r function.zip lambda_function.py
    
    success "Lambda function code created and packaged"
}

# Function to deploy Lambda function
deploy_lambda_function() {
    log "Deploying Lambda function with Parameters Extension..."
    
    # Get the Parameters and Secrets Extension layer ARN for the region
    case ${AWS_REGION} in
        us-east-1)
            EXTENSION_ARN="arn:aws:lambda:us-east-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
            ;;
        us-west-2)
            EXTENSION_ARN="arn:aws:lambda:us-west-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
            ;;
        eu-west-1)
            EXTENSION_ARN="arn:aws:lambda:eu-west-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
            ;;
        ap-southeast-1)
            EXTENSION_ARN="arn:aws:lambda:ap-southeast-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
            ;;
        *)
            log "Using default Parameters and Secrets Extension ARN for ${AWS_REGION}"
            EXTENSION_ARN="arn:aws:lambda:${AWS_REGION}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
            ;;
    esac
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function with extension layer
    aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 256 \
        --layers "${EXTENSION_ARN}" \
        --environment Variables="{PARAMETER_PREFIX=${PARAMETER_PREFIX},SSM_PARAMETER_STORE_TTL=300}" \
        --tags Project=ConfigManager,Environment=demo
    
    success "Lambda function deployed with Parameters Extension"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for parameter change events..."
    
    # Create EventBridge rule for Parameter Store events
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --event-pattern "{
            \"source\": [\"aws.ssm\"],
            \"detail-type\": [\"Parameter Store Change\"],
            \"detail\": {
                \"name\": [{\"prefix\": \"${PARAMETER_PREFIX}\"}]
            }
        }" \
        --state ENABLED \
        --description "Trigger on Parameter Store changes" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "allow-eventbridge" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
    
    success "EventBridge rule configured for parameter change events"
}

# Function to create CloudWatch monitoring
create_monitoring() {
    log "Creating CloudWatch alarms and dashboard..."
    
    # Create alarm for Lambda function errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "ConfigManager-Errors-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    # Create alarm for function duration
    aws cloudwatch put-metric-alarm \
        --alarm-name "ConfigManager-Duration-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor Lambda function duration" \
        --metric-name Duration \
        --namespace AWS/Lambda \
        --statistic Average \
        --period 300 \
        --threshold 10000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    # Create alarm for configuration retrieval failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "ConfigManager-RetrievalFailures-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor configuration retrieval failures" \
        --metric-name FailedParameterRetrievals \
        --namespace ConfigManager \
        --statistic Sum \
        --period 300 \
        --threshold 3 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --tags Key=Project,Value=ConfigManager Key=Environment,Value=demo
    
    # Create CloudWatch dashboard
    cat > dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Lambda", "Invocations", "FunctionName", "${FUNCTION_NAME}" ],
                    [ ".", "Errors", ".", "." ],
                    [ ".", "Duration", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Lambda Function Metrics"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "ConfigManager", "SuccessfulParameterRetrievals" ],
                    [ ".", "FailedParameterRetrievals" ],
                    [ ".", "ConfigurationErrors" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Configuration Management Metrics"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "ConfigManager-${RANDOM_SUFFIX}" \
        --dashboard-body file://dashboard.json
    
    success "CloudWatch monitoring configured"
}

# Function to test deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test Lambda function invocation
    aws lambda invoke \
        --function-name "${FUNCTION_NAME}" \
        --payload '{}' \
        response.json > /dev/null
    
    # Check if response is successful
    if jq -e '.statusCode == 200' response.json > /dev/null; then
        success "Lambda function test successful"
        
        # Display configuration
        log "Retrieved configuration:"
        jq -r '.body | fromjson | .config' response.json | jq .
    else
        error "Lambda function test failed"
        cat response.json
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "==========================================";
    
    echo -e "${GREEN}✅ IAM Role: ${ROLE_NAME}${NC}"
    echo -e "${GREEN}✅ Lambda Function: ${FUNCTION_NAME}${NC}"
    echo -e "${GREEN}✅ Parameter Prefix: ${PARAMETER_PREFIX}${NC}"
    echo -e "${GREEN}✅ EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}${NC}"
    echo -e "${GREEN}✅ CloudWatch Dashboard: ConfigManager-${RANDOM_SUFFIX}${NC}"
    echo
    
    echo -e "${BLUE}🔗 Useful AWS Console Links:${NC}"
    echo "• Lambda Function: https://console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions/${FUNCTION_NAME}"
    echo "• Parameter Store: https://console.aws.amazon.com/systems-manager/parameters?region=${AWS_REGION}"
    echo "• CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=ConfigManager-${RANDOM_SUFFIX}"
    echo "• EventBridge Rules: https://console.aws.amazon.com/events/home?region=${AWS_REGION}#/rules"
    echo
    
    echo -e "${YELLOW}📝 Next Steps:${NC}"
    echo "1. Test parameter updates by modifying values in Parameter Store"
    echo "2. Monitor CloudWatch metrics and alarms"
    echo "3. Check Lambda function logs for configuration retrieval events"
    echo "4. Run './destroy.sh' to clean up resources when done"
    echo
    
    echo -e "${BLUE}💡 Quick Commands:${NC}"
    echo "• Test function: aws lambda invoke --function-name ${FUNCTION_NAME} --payload '{}' test-response.json"
    echo "• Update parameter: aws ssm put-parameter --name '${PARAMETER_PREFIX}/api/timeout' --value '45' --type 'String' --overwrite"
    echo "• View logs: aws logs tail /aws/lambda/${FUNCTION_NAME} --follow"
    echo
}

# Main execution
main() {
    log "Starting Dynamic Configuration Management deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_iam_policy
    create_sample_parameters
    create_lambda_function
    deploy_lambda_function
    create_eventbridge_rule
    create_monitoring
    
    # Clean up temporary files
    rm -f trust-policy.json parameter-store-policy.json dashboard.json
    rm -f function.zip lambda_function.py response.json
    
    test_deployment
    display_summary
    
    success "Deployment completed successfully! 🎉"
}

# Execute main function
main "$@"