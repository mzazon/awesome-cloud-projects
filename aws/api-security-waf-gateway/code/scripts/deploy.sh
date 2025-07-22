#!/bin/bash

# Deploy script for API Access WAF Gateway Recipe
# This script deploys AWS WAF protection for API Gateway with comprehensive security rules

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Get caller identity
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    log "Authenticated as: $(echo $CALLER_IDENTITY | jq -r '.Arn')"
    
    # Check required permissions (basic check)
    log "Verifying required AWS permissions..."
    
    # Test WAF permissions
    if ! aws wafv2 list-web-acls --scope REGIONAL &> /dev/null; then
        error "Insufficient WAF permissions. Required: wafv2:* permissions"
        exit 1
    fi
    
    # Test API Gateway permissions
    if ! aws apigateway get-rest-apis &> /dev/null; then
        error "Insufficient API Gateway permissions. Required: apigateway:* permissions"
        exit 1
    fi
    
    # Test CloudWatch Logs permissions
    if ! aws logs describe-log-groups &> /dev/null; then
        error "Insufficient CloudWatch Logs permissions. Required: logs:* permissions"
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region set, using us-east-1"
    fi
    log "AWS Region: $AWS_REGION"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(openssl rand -hex 3))
    
    # Set resource names with unique suffix
    export WAF_WEB_ACL_NAME="api-security-acl-${RANDOM_SUFFIX}"
    export API_NAME="protected-api-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/waf/${WAF_WEB_ACL_NAME}"
    
    # Create temporary directory for storing resource IDs
    export TEMP_DIR="/tmp/waf-api-deployment-${RANDOM_SUFFIX}"
    mkdir -p "$TEMP_DIR"
    
    log "Environment setup completed with unique suffix: $RANDOM_SUFFIX"
    log "WAF Web ACL Name: $WAF_WEB_ACL_NAME"
    log "API Name: $API_NAME"
    log "Log Group Name: $LOG_GROUP_NAME"
    log "Temporary directory: $TEMP_DIR"
}

# Function to create CloudWatch log group
create_log_group() {
    log "Creating CloudWatch log group for WAF logging..."
    
    # Check if log group already exists
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
        --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
        warn "Log group $LOG_GROUP_NAME already exists"
    else
        aws logs create-log-group \
            --log-group-name "$LOG_GROUP_NAME" \
            --region "$AWS_REGION"
        success "CloudWatch log group created: $LOG_GROUP_NAME"
    fi
}

# Function to create WAF Web ACL
create_waf_web_acl() {
    log "Creating AWS WAF Web ACL with security rules..."
    
    # Check if Web ACL already exists
    if aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME']" --output text | grep -q "$WAF_WEB_ACL_NAME"; then
        warn "Web ACL $WAF_WEB_ACL_NAME already exists, retrieving ID..."
        WEB_ACL_ID=$(aws wafv2 list-web-acls --scope REGIONAL \
            --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME'].Id" --output text)
    else
        # Create the Web ACL with comprehensive rules
        WEB_ACL_ID=$(aws wafv2 create-web-acl \
            --name "$WAF_WEB_ACL_NAME" \
            --scope REGIONAL \
            --default-action Allow={} \
            --description "Web ACL for API Gateway protection with rate limiting and geo blocking" \
            --rules '[
              {
                "Name": "RateLimitRule",
                "Priority": 1,
                "Statement": {
                  "RateBasedStatement": {
                    "Limit": 1000,
                    "AggregateKeyType": "IP"
                  }
                },
                "Action": {
                  "Block": {}
                },
                "VisibilityConfig": {
                  "SampledRequestsEnabled": true,
                  "CloudWatchMetricsEnabled": true,
                  "MetricName": "RateLimitRule"
                }
              },
              {
                "Name": "GeoBlockRule",
                "Priority": 2,
                "Statement": {
                  "GeoMatchStatement": {
                    "CountryCodes": ["CN", "RU", "KP"]
                  }
                },
                "Action": {
                  "Block": {}
                },
                "VisibilityConfig": {
                  "SampledRequestsEnabled": true,
                  "CloudWatchMetricsEnabled": true,
                  "MetricName": "GeoBlockRule"
                }
              },
              {
                "Name": "AWSManagedRulesCommonRuleSet",
                "Priority": 3,
                "OverrideAction": {
                  "None": {}
                },
                "Statement": {
                  "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesCommonRuleSet"
                  }
                },
                "VisibilityConfig": {
                  "SampledRequestsEnabled": true,
                  "CloudWatchMetricsEnabled": true,
                  "MetricName": "CommonRuleSetMetric"
                }
              }
            ]' \
            --region "$AWS_REGION" \
            --query 'Summary.Id' --output text)
        
        success "WAF Web ACL created with ID: $WEB_ACL_ID"
    fi
    
    # Save Web ACL ID to file
    echo "$WEB_ACL_ID" > "$TEMP_DIR/web-acl-id.txt"
    export WEB_ACL_ID
}

# Function to create API Gateway REST API
create_api_gateway() {
    log "Creating API Gateway REST API..."
    
    # Check if API already exists
    if aws apigateway get-rest-apis --query "items[?name=='$API_NAME']" --output text | grep -q "$API_NAME"; then
        warn "API $API_NAME already exists, retrieving ID..."
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='$API_NAME'].id" --output text)
    else
        # Create a new REST API in API Gateway
        API_ID=$(aws apigateway create-rest-api \
            --name "$API_NAME" \
            --description "Test API protected by AWS WAF" \
            --endpoint-configuration types=REGIONAL \
            --query 'id' --output text)
        
        success "API Gateway REST API created with ID: $API_ID"
    fi
    
    # Save API ID to file
    echo "$API_ID" > "$TEMP_DIR/api-id.txt"
    export API_ID
    
    # Get the root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text)
    
    echo "$ROOT_RESOURCE_ID" > "$TEMP_DIR/root-resource-id.txt"
    export ROOT_RESOURCE_ID
    
    log "Root resource ID: $ROOT_RESOURCE_ID"
}

# Function to create API resources and methods
create_api_resources() {
    log "Creating API resources and methods..."
    
    # Check if test resource already exists
    EXISTING_RESOURCE=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query "items[?pathPart=='test'].id" --output text)
    
    if [ -n "$EXISTING_RESOURCE" ] && [ "$EXISTING_RESOURCE" != "None" ]; then
        warn "Test resource already exists"
        TEST_RESOURCE_ID="$EXISTING_RESOURCE"
    else
        # Create a test resource (/test)
        TEST_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "$API_ID" \
            --parent-id "$ROOT_RESOURCE_ID" \
            --path-part "test" \
            --query 'id' --output text)
        
        success "API resource created at /test with ID: $TEST_RESOURCE_ID"
    fi
    
    echo "$TEST_RESOURCE_ID" > "$TEMP_DIR/test-resource-id.txt"
    export TEST_RESOURCE_ID
    
    # Check if GET method already exists
    if aws apigateway get-method \
        --rest-api-id "$API_ID" \
        --resource-id "$TEST_RESOURCE_ID" \
        --http-method GET &> /dev/null; then
        warn "GET method already exists on /test resource"
    else
        # Create GET method on the test resource
        aws apigateway put-method \
            --rest-api-id "$API_ID" \
            --resource-id "$TEST_RESOURCE_ID" \
            --http-method GET \
            --authorization-type NONE \
            --no-api-key-required
        
        # Create mock integration for the GET method
        aws apigateway put-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$TEST_RESOURCE_ID" \
            --http-method GET \
            --type MOCK \
            --request-templates '{"application/json": "{\"statusCode\": 200}"}' \
            --integration-http-method GET
        
        # Create method response
        aws apigateway put-method-response \
            --rest-api-id "$API_ID" \
            --resource-id "$TEST_RESOURCE_ID" \
            --http-method GET \
            --status-code 200 \
            --response-models '{"application/json": "Empty"}'
        
        # Create integration response
        aws apigateway put-integration-response \
            --rest-api-id "$API_ID" \
            --resource-id "$TEST_RESOURCE_ID" \
            --http-method GET \
            --status-code 200 \
            --response-templates '{"application/json": "{\"message\": \"Hello from protected API!\", \"timestamp\": \"$context.requestTime\", \"sourceIp\": \"$context.identity.sourceIp\"}"}'
        
        success "API GET method created at /test with mock integration"
    fi
}

# Function to deploy API and associate with WAF
deploy_api_and_associate_waf() {
    log "Deploying API and associating with WAF..."
    
    # Check if prod stage already exists
    if aws apigateway get-stage \
        --rest-api-id "$API_ID" \
        --stage-name "prod" &> /dev/null; then
        warn "Production stage already exists, updating deployment..."
    fi
    
    # Deploy the API to prod stage
    aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name "prod" \
        --stage-description "Production stage with WAF protection" \
        --description "Deployment with WAF integration - $(date)"
    
    success "API deployed to prod stage"
    
    # Get the Web ACL ARN for association
    WEB_ACL_ARN=$(aws wafv2 get-web-acl \
        --id "$WEB_ACL_ID" \
        --name "$WAF_WEB_ACL_NAME" \
        --scope REGIONAL \
        --query 'WebACL.ARN' --output text)
    
    echo "$WEB_ACL_ARN" > "$TEMP_DIR/web-acl-arn.txt"
    export WEB_ACL_ARN
    
    # Associate the Web ACL with the API Gateway stage
    RESOURCE_ARN="arn:aws:apigateway:${AWS_REGION}::/restapis/${API_ID}/stages/prod"
    
    # Check if association already exists
    if aws wafv2 get-web-acl-for-resource --resource-arn "$RESOURCE_ARN" &> /dev/null; then
        warn "WAF already associated with API Gateway stage"
    else
        aws wafv2 associate-web-acl \
            --web-acl-arn "$WEB_ACL_ARN" \
            --resource-arn "$RESOURCE_ARN"
        
        success "WAF Web ACL associated with API Gateway"
    fi
    
    # Store the API endpoint URL
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/test"
    echo "$API_ENDPOINT" > "$TEMP_DIR/api-endpoint.txt"
    
    success "API Endpoint: $API_ENDPOINT"
}

# Function to enable WAF logging
enable_waf_logging() {
    log "Enabling WAF logging to CloudWatch..."
    
    # Check if logging is already configured
    if aws wafv2 get-logging-configuration \
        --resource-arn "$WEB_ACL_ARN" &> /dev/null; then
        warn "WAF logging already configured"
    else
        # Configure WAF logging to CloudWatch
        aws wafv2 put-logging-configuration \
            --resource-arn "$WEB_ACL_ARN" \
            --log-destination-configs "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}" \
            --region "$AWS_REGION"
        
        success "WAF logging enabled to CloudWatch log group"
    fi
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for security monitoring..."
    
    # Alarm for high number of blocked requests
    aws cloudwatch put-metric-alarm \
        --alarm-name "${WAF_WEB_ACL_NAME}-HighBlockedRequests" \
        --alarm-description "High number of requests blocked by WAF" \
        --metric-name BlockedRequests \
        --namespace AWS/WAFV2 \
        --statistic Sum \
        --period 300 \
        --threshold 100 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:waf-security-alerts" \
        --dimensions Name=WebACL,Value="$WAF_WEB_ACL_NAME" Name=Rule,Value=ALL Name=Region,Value="$AWS_REGION" \
        --treat-missing-data notBreaching 2>/dev/null || warn "Could not create CloudWatch alarm (SNS topic may not exist)"
    
    success "CloudWatch monitoring configured"
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Wait for deployment to be ready
    sleep 10
    
    # Test legitimate API access
    log "Testing legitimate API access..."
    API_ENDPOINT=$(cat "$TEMP_DIR/api-endpoint.txt")
    
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$API_ENDPOINT" || echo "000")
    if [ "$RESPONSE" = "200" ]; then
        success "API endpoint is accessible and returning 200 OK"
    else
        warn "API endpoint returned HTTP $RESPONSE (this may be expected during initial deployment)"
    fi
    
    # Check WAF metrics availability
    log "Checking WAF metrics availability..."
    sleep 5
    
    METRICS_CHECK=$(aws cloudwatch list-metrics \
        --namespace AWS/WAFV2 \
        --query "Metrics[?MetricName=='AllowedRequests']" \
        --output text)
    
    if [ -n "$METRICS_CHECK" ]; then
        success "WAF metrics are being published to CloudWatch"
    else
        warn "WAF metrics not yet available (may take a few minutes to appear)"
    fi
    
    success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "WAF Web ACL Name: $WAF_WEB_ACL_NAME"
    echo "WAF Web ACL ID: $WEB_ACL_ID"
    echo "API Gateway Name: $API_NAME"
    echo "API Gateway ID: $API_ID"
    echo "API Endpoint: $(cat $TEMP_DIR/api-endpoint.txt)"
    echo "CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "Deployment Files: $TEMP_DIR"
    echo ""
    echo "Security Features Enabled:"
    echo "- Rate limiting: 1000 requests per 5 minutes per IP"
    echo "- Geographic blocking: China, Russia, North Korea"
    echo "- AWS Managed Rules: Common Rule Set"
    echo "- CloudWatch logging and monitoring"
    echo ""
    echo "Next Steps:"
    echo "1. Test the API endpoint above"
    echo "2. Monitor CloudWatch logs and metrics"
    echo "3. Customize WAF rules as needed"
    echo "4. Set up SNS notifications for alerts"
    echo ""
    warn "Remember to run destroy.sh to clean up resources and avoid charges"
}

# Main execution
main() {
    log "Starting AWS WAF API Gateway deployment..."
    
    check_prerequisites
    setup_environment
    create_log_group
    create_waf_web_acl
    create_api_gateway
    create_api_resources
    deploy_api_and_associate_waf
    enable_waf_logging
    create_cloudwatch_alarms
    run_validation_tests
    display_summary
    
    success "Deployment completed successfully!"
    
    # Save deployment state for cleanup script
    cat > "$TEMP_DIR/deployment-state.txt" << EOF
WAF_WEB_ACL_NAME=$WAF_WEB_ACL_NAME
WEB_ACL_ID=$WEB_ACL_ID
API_NAME=$API_NAME
API_ID=$API_ID
LOG_GROUP_NAME=$LOG_GROUP_NAME
WEB_ACL_ARN=$WEB_ACL_ARN
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
TEMP_DIR=$TEMP_DIR
EOF
    
    log "Deployment state saved to $TEMP_DIR/deployment-state.txt"
}

# Trap cleanup on exit
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check the logs above for details."
        warn "You may need to manually clean up any partially created resources."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"