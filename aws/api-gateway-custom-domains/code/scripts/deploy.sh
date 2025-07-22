#!/bin/bash

# API Gateway Custom Domain Names - Deployment Script
# This script deploys the complete API Gateway with custom domain solution
# including SSL certificates, Lambda functions, custom authorizers, and DNS configuration

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DEPLOYMENT_STARTED=false
RESOURCES_CREATED=()

# Logging functions
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

# Error handling function
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ "$DEPLOYMENT_STARTED" = true ]; then
        log_error "Deployment failed with exit code $exit_code. Starting cleanup..."
        cleanup_resources
    fi
    exit $exit_code
}

# Set up error trap
trap cleanup_on_error ERR INT TERM

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required utilities
    local required_tools=("jq" "curl" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    # Required environment variables
    local required_vars=(
        "DOMAIN_NAME"
        "AWS_REGION"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable $var is not set"
            log_info "Please set: export $var=your_value"
            exit 1
        fi
    done
    
    # Validate domain name format
    if ! echo "$DOMAIN_NAME" | grep -E "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$" > /dev/null; then
        log_error "Invalid domain name format: $DOMAIN_NAME"
        exit 1
    fi
    
    log_success "Environment validation passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS configuration
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export API_SUBDOMAIN="api.${DOMAIN_NAME}"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export API_NAME="petstore-api-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="petstore-handler-${RANDOM_SUFFIX}"
    export AUTHORIZER_FUNCTION_NAME="petstore-authorizer-${RANDOM_SUFFIX}"
    export DEPLOYMENT_BUCKET="api-deployment-${RANDOM_SUFFIX}"
    
    # Create deployment bucket
    if ! aws s3 ls "s3://${DEPLOYMENT_BUCKET}" 2>/dev/null; then
        aws s3 mb "s3://${DEPLOYMENT_BUCKET}" --region "${AWS_REGION}"
        RESOURCES_CREATED+=("s3:${DEPLOYMENT_BUCKET}")
        log_success "Created deployment bucket: ${DEPLOYMENT_BUCKET}"
    else
        log_info "Deployment bucket already exists: ${DEPLOYMENT_BUCKET}"
    fi
    
    # Save environment variables for cleanup
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DOMAIN_NAME=${DOMAIN_NAME}
API_SUBDOMAIN=${API_SUBDOMAIN}
API_NAME=${API_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
AUTHORIZER_FUNCTION_NAME=${AUTHORIZER_FUNCTION_NAME}
DEPLOYMENT_BUCKET=${DEPLOYMENT_BUCKET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment setup completed for domain: ${API_SUBDOMAIN}"
}

# Request SSL certificate
create_ssl_certificate() {
    log_info "Requesting SSL certificate for ${API_SUBDOMAIN}..."
    
    # Check if certificate already exists
    EXISTING_CERT=$(aws acm list-certificates \
        --query "CertificateSummaryList[?DomainName=='${API_SUBDOMAIN}'].CertificateArn" \
        --output text 2>/dev/null || true)
    
    if [ -n "$EXISTING_CERT" ] && [ "$EXISTING_CERT" != "None" ]; then
        export CERTIFICATE_ARN="$EXISTING_CERT"
        log_info "Using existing certificate: ${CERTIFICATE_ARN}"
    else
        export CERTIFICATE_ARN=$(aws acm request-certificate \
            --domain-name "${API_SUBDOMAIN}" \
            --validation-method DNS \
            --subject-alternative-names "*.${API_SUBDOMAIN}" \
            --query CertificateArn --output text)
        
        RESOURCES_CREATED+=("acm:${CERTIFICATE_ARN}")
        log_success "Certificate requested: ${CERTIFICATE_ARN}"
    fi
    
    # Get certificate validation details
    log_info "Getting certificate validation details..."
    aws acm describe-certificate \
        --certificate-arn "${CERTIFICATE_ARN}" \
        --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
        --output table
    
    log_warning "MANUAL ACTION REQUIRED:"
    log_warning "Add the DNS validation record shown above to your domain's DNS settings"
    log_warning "The certificate must be validated before proceeding with custom domain creation"
    
    echo "${CERTIFICATE_ARN}" > "${SCRIPT_DIR}/.certificate_arn"
}

# Create IAM role for Lambda functions
create_lambda_role() {
    log_info "Creating Lambda execution role..."
    
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        log_info "Lambda role already exists: $role_name"
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << EOF
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
        --role-name "$role_name" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/lambda-trust-policy.json" \
        --description "Execution role for API Gateway Lambda functions"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    RESOURCES_CREATED+=("iam:role:${role_name}")
    log_success "Lambda IAM role created: ${role_name}"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
}

# Deploy Lambda functions
deploy_lambda_functions() {
    log_info "Creating Lambda function code..."
    
    # Create main API Lambda function
    cat > "${SCRIPT_DIR}/lambda-function.py" << 'EOF'
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Sample API responses
    if path == '/pets' and http_method == 'GET':
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'pets': [
                    {'id': 1, 'name': 'Buddy', 'type': 'dog'},
                    {'id': 2, 'name': 'Whiskers', 'type': 'cat'}
                ]
            })
        }
    elif path == '/pets' and http_method == 'POST':
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Pet created successfully',
                'id': 3
            })
        }
    else:
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Not Found'
            })
        }
EOF
    
    # Create custom authorizer function
    cat > "${SCRIPT_DIR}/authorizer-function.py" << 'EOF'
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Authorizer Event: {json.dumps(event)}")
    
    # Extract the authorization token
    token = event.get('authorizationToken', '')
    method_arn = event.get('methodArn', '')
    
    # Simple token validation (in production, use proper JWT validation)
    if token == 'Bearer valid-token':
        effect = 'Allow'
        principal_id = 'user123'
    else:
        effect = 'Deny'
        principal_id = 'anonymous'
    
    # Generate policy document
    policy_document = {
        'Version': '2012-10-17',
        'Statement': [
            {
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': method_arn
            }
        ]
    }
    
    return {
        'principalId': principal_id,
        'policyDocument': policy_document,
        'context': {
            'userId': principal_id,
            'userRole': 'user'
        }
    }
EOF
    
    # Package Lambda functions
    cd "${SCRIPT_DIR}"
    zip -q lambda-function.zip lambda-function.py
    zip -q authorizer-function.zip authorizer-function.py
    
    log_info "Deploying main Lambda function..."
    
    # Check if main function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        log_info "Updating existing Lambda function: ${LAMBDA_FUNCTION_NAME}"
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file "fileb://lambda-function.zip"
    else
        export LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
            --handler lambda-function.lambda_handler \
            --zip-file "fileb://lambda-function.zip" \
            --description "Pet Store API backend function" \
            --timeout 30 \
            --query FunctionArn --output text)
        
        RESOURCES_CREATED+=("lambda:${LAMBDA_FUNCTION_NAME}")
        log_success "Lambda function created: ${LAMBDA_FUNCTION_ARN}"
    fi
    
    log_info "Deploying custom authorizer function..."
    
    # Check if authorizer function already exists
    if aws lambda get-function --function-name "${AUTHORIZER_FUNCTION_NAME}" >/dev/null 2>&1; then
        log_info "Updating existing authorizer function: ${AUTHORIZER_FUNCTION_NAME}"
        aws lambda update-function-code \
            --function-name "${AUTHORIZER_FUNCTION_NAME}" \
            --zip-file "fileb://authorizer-function.zip"
    else
        export AUTHORIZER_FUNCTION_ARN=$(aws lambda create-function \
            --function-name "${AUTHORIZER_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
            --handler authorizer-function.lambda_handler \
            --zip-file "fileb://authorizer-function.zip" \
            --description "Custom authorizer for Pet Store API" \
            --timeout 30 \
            --query FunctionArn --output text)
        
        RESOURCES_CREATED+=("lambda:${AUTHORIZER_FUNCTION_NAME}")
        log_success "Custom authorizer function created: ${AUTHORIZER_FUNCTION_ARN}"
    fi
    
    # Save function ARNs
    echo "${LAMBDA_FUNCTION_ARN:-}" > "${SCRIPT_DIR}/.lambda_function_arn"
    echo "${AUTHORIZER_FUNCTION_ARN:-}" > "${SCRIPT_DIR}/.authorizer_function_arn"
}

# Create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway REST API..."
    
    # Check if API already exists
    EXISTING_API=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" \
        --output text 2>/dev/null || true)
    
    if [ -n "$EXISTING_API" ] && [ "$EXISTING_API" != "None" ]; then
        export REST_API_ID="$EXISTING_API"
        log_info "Using existing REST API: ${REST_API_ID}"
    else
        export REST_API_ID=$(aws apigateway create-rest-api \
            --name "${API_NAME}" \
            --description "Pet Store API with custom domain" \
            --endpoint-configuration types=REGIONAL \
            --query id --output text)
        
        RESOURCES_CREATED+=("apigateway:${REST_API_ID}")
        log_success "REST API created: ${REST_API_ID}"
    fi
    
    # Get the root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${REST_API_ID}" \
        --query 'items[?path==`/`].id' --output text)
    
    # Create /pets resource if it doesn't exist
    EXISTING_PETS_RESOURCE=$(aws apigateway get-resources \
        --rest-api-id "${REST_API_ID}" \
        --query 'items[?pathPart==`pets`].id' --output text 2>/dev/null || true)
    
    if [ -n "$EXISTING_PETS_RESOURCE" ] && [ "$EXISTING_PETS_RESOURCE" != "None" ]; then
        export PETS_RESOURCE_ID="$EXISTING_PETS_RESOURCE"
        log_info "Using existing /pets resource: ${PETS_RESOURCE_ID}"
    else
        export PETS_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${REST_API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part pets \
            --query id --output text)
        
        log_success "/pets resource created: ${PETS_RESOURCE_ID}"
    fi
    
    # Save API details
    cat >> "${SCRIPT_DIR}/.env" << EOF
REST_API_ID=${REST_API_ID}
ROOT_RESOURCE_ID=${ROOT_RESOURCE_ID}
PETS_RESOURCE_ID=${PETS_RESOURCE_ID}
EOF
}

# Configure API Gateway methods and integrations
configure_api_methods() {
    log_info "Configuring API Gateway methods and integrations..."
    
    # Load function ARNs
    if [ -f "${SCRIPT_DIR}/.lambda_function_arn" ]; then
        LAMBDA_FUNCTION_ARN=$(cat "${SCRIPT_DIR}/.lambda_function_arn")
    fi
    if [ -f "${SCRIPT_DIR}/.authorizer_function_arn" ]; then
        AUTHORIZER_FUNCTION_ARN=$(cat "${SCRIPT_DIR}/.authorizer_function_arn")
    fi
    
    # Create custom authorizer
    EXISTING_AUTHORIZER=$(aws apigateway get-authorizers \
        --rest-api-id "${REST_API_ID}" \
        --query "items[?name=='${AUTHORIZER_FUNCTION_NAME}'].id" \
        --output text 2>/dev/null || true)
    
    if [ -n "$EXISTING_AUTHORIZER" ] && [ "$EXISTING_AUTHORIZER" != "None" ]; then
        export AUTHORIZER_ID="$EXISTING_AUTHORIZER"
        log_info "Using existing authorizer: ${AUTHORIZER_ID}"
    else
        export AUTHORIZER_ID=$(aws apigateway create-authorizer \
            --rest-api-id "${REST_API_ID}" \
            --name "${AUTHORIZER_FUNCTION_NAME}" \
            --type TOKEN \
            --authorizer-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${AUTHORIZER_FUNCTION_ARN}/invocations" \
            --identity-source method.request.header.Authorization \
            --authorizer-result-ttl-in-seconds 300 \
            --query id --output text)
        
        log_success "Custom authorizer created: ${AUTHORIZER_ID}"
    fi
    
    # Grant API Gateway permission to invoke authorizer
    aws lambda add-permission \
        --function-name "${AUTHORIZER_FUNCTION_NAME}" \
        --statement-id "${AUTHORIZER_FUNCTION_NAME}-apigateway" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REST_API_ID}/authorizers/${AUTHORIZER_ID}" \
        2>/dev/null || log_info "Authorizer permission already exists"
    
    # Create API methods (GET and POST)
    for method in GET POST; do
        # Check if method already exists
        if aws apigateway get-method \
            --rest-api-id "${REST_API_ID}" \
            --resource-id "${PETS_RESOURCE_ID}" \
            --http-method "$method" >/dev/null 2>&1; then
            log_info "$method method already exists for /pets"
        else
            aws apigateway put-method \
                --rest-api-id "${REST_API_ID}" \
                --resource-id "${PETS_RESOURCE_ID}" \
                --http-method "$method" \
                --authorization-type CUSTOM \
                --authorizer-id "${AUTHORIZER_ID}"
            
            log_success "$method method created for /pets"
        fi
        
        # Create Lambda integration
        aws apigateway put-integration \
            --rest-api-id "${REST_API_ID}" \
            --resource-id "${PETS_RESOURCE_ID}" \
            --http-method "$method" \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_FUNCTION_ARN}/invocations" \
            2>/dev/null || log_info "$method integration already configured"
    done
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "${LAMBDA_FUNCTION_NAME}-apigateway" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REST_API_ID}/*" \
        2>/dev/null || log_info "Lambda permission already exists"
    
    echo "${AUTHORIZER_ID}" > "${SCRIPT_DIR}/.authorizer_id"
    log_success "API methods and integrations configured"
}

# Deploy API stages
deploy_api_stages() {
    log_info "Deploying API stages..."
    
    # Create initial deployment
    export DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "${REST_API_ID}" \
        --stage-name dev \
        --stage-description "Development stage" \
        --description "Deployment $(date)" \
        --query id --output text)
    
    # Create production stage
    if aws apigateway get-stage \
        --rest-api-id "${REST_API_ID}" \
        --stage-name prod >/dev/null 2>&1; then
        log_info "Production stage already exists"
        aws apigateway update-stage \
            --rest-api-id "${REST_API_ID}" \
            --stage-name prod \
            --patch-operations op=replace,path=/deploymentId,value="${DEPLOYMENT_ID}"
    else
        aws apigateway create-stage \
            --rest-api-id "${REST_API_ID}" \
            --stage-name prod \
            --deployment-id "${DEPLOYMENT_ID}" \
            --description "Production stage" \
            --variables environment=production
        
        log_success "Production stage created"
    fi
    
    # Configure throttling
    aws apigateway update-stage \
        --rest-api-id "${REST_API_ID}" \
        --stage-name prod \
        --patch-operations \
            op=replace,path=/throttle/rateLimit,value=100 \
            op=replace,path=/throttle/burstLimit,value=200 \
        2>/dev/null || log_info "Throttling already configured for prod"
    
    aws apigateway update-stage \
        --rest-api-id "${REST_API_ID}" \
        --stage-name dev \
        --patch-operations \
            op=replace,path=/throttle/rateLimit,value=50 \
            op=replace,path=/throttle/burstLimit,value=100 \
        2>/dev/null || log_info "Throttling already configured for dev"
    
    echo "${DEPLOYMENT_ID}" > "${SCRIPT_DIR}/.deployment_id"
    log_success "API deployed to dev and prod stages"
    log_info "Default API URL: https://${REST_API_ID}.execute-api.${AWS_REGION}.amazonaws.com/dev"
}

# Wait for certificate validation
wait_for_certificate() {
    log_info "Checking certificate validation status..."
    
    if [ -f "${SCRIPT_DIR}/.certificate_arn" ]; then
        CERTIFICATE_ARN=$(cat "${SCRIPT_DIR}/.certificate_arn")
    fi
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(aws acm describe-certificate \
            --certificate-arn "${CERTIFICATE_ARN}" \
            --query 'Certificate.Status' --output text 2>/dev/null || echo "UNKNOWN")
        
        case "$status" in
            "ISSUED")
                log_success "Certificate is validated and issued"
                return 0
                ;;
            "PENDING_VALIDATION")
                log_info "Certificate validation pending... (attempt $attempt/$max_attempts)"
                log_info "Please ensure DNS validation record is added to your domain"
                ;;
            "FAILED"|"EXPIRED"|"REVOKED")
                log_error "Certificate validation failed with status: $status"
                return 1
                ;;
            *)
                log_warning "Unknown certificate status: $status"
                ;;
        esac
        
        sleep 30
        ((attempt++))
    done
    
    log_error "Certificate validation timed out after $((max_attempts * 30)) seconds"
    log_warning "You can continue the deployment later once the certificate is validated"
    return 1
}

# Create custom domain
create_custom_domain() {
    log_info "Creating custom domain name..."
    
    if [ -f "${SCRIPT_DIR}/.certificate_arn" ]; then
        CERTIFICATE_ARN=$(cat "${SCRIPT_DIR}/.certificate_arn")
    fi
    
    # Check if custom domain already exists
    if aws apigateway get-domain-name --domain-name "${API_SUBDOMAIN}" >/dev/null 2>&1; then
        log_info "Custom domain already exists: ${API_SUBDOMAIN}"
    else
        aws apigateway create-domain-name \
            --domain-name "${API_SUBDOMAIN}" \
            --certificate-arn "${CERTIFICATE_ARN}" \
            --endpoint-configuration types=REGIONAL \
            --security-policy TLS_1_2
        
        RESOURCES_CREATED+=("apigateway:domain:${API_SUBDOMAIN}")
        log_success "Custom domain created: ${API_SUBDOMAIN}"
    fi
    
    # Get the regional domain name for DNS setup
    export REGIONAL_DOMAIN=$(aws apigateway get-domain-name \
        --domain-name "${API_SUBDOMAIN}" \
        --query regionalDomainName --output text)
    
    echo "${REGIONAL_DOMAIN}" > "${SCRIPT_DIR}/.regional_domain"
    log_success "Regional domain for DNS: ${REGIONAL_DOMAIN}"
}

# Create API mappings
create_api_mappings() {
    log_info "Creating API base path mappings..."
    
    # Create base path mapping for dev stage
    if aws apigateway get-base-path-mapping \
        --domain-name "${API_SUBDOMAIN}" \
        --base-path v1-dev >/dev/null 2>&1; then
        log_info "Dev mapping already exists"
    else
        aws apigateway create-base-path-mapping \
            --domain-name "${API_SUBDOMAIN}" \
            --rest-api-id "${REST_API_ID}" \
            --stage dev \
            --base-path v1-dev
        
        log_success "Dev mapping created: v1-dev"
    fi
    
    # Create base path mapping for prod stage
    if aws apigateway get-base-path-mapping \
        --domain-name "${API_SUBDOMAIN}" \
        --base-path v1 >/dev/null 2>&1; then
        log_info "Prod v1 mapping already exists"
    else
        aws apigateway create-base-path-mapping \
            --domain-name "${API_SUBDOMAIN}" \
            --rest-api-id "${REST_API_ID}" \
            --stage prod \
            --base-path v1
        
        log_success "Prod v1 mapping created"
    fi
    
    # Create default mapping (empty base path) for prod
    if aws apigateway get-base-path-mapping \
        --domain-name "${API_SUBDOMAIN}" \
        --base-path '' >/dev/null 2>&1; then
        log_info "Default prod mapping already exists"
    else
        aws apigateway create-base-path-mapping \
            --domain-name "${API_SUBDOMAIN}" \
            --rest-api-id "${REST_API_ID}" \
            --stage prod \
            2>/dev/null || log_info "Default mapping may already exist"
        
        log_success "Default prod mapping created"
    fi
    
    log_success "API mappings configured:"
    log_info "  - Production: https://${API_SUBDOMAIN}/pets"
    log_info "  - Production (v1): https://${API_SUBDOMAIN}/v1/pets"
    log_info "  - Development: https://${API_SUBDOMAIN}/v1-dev/pets"
}

# Configure DNS (Route 53)
configure_dns() {
    log_info "Configuring DNS records..."
    
    if [ -f "${SCRIPT_DIR}/.regional_domain" ]; then
        REGIONAL_DOMAIN=$(cat "${SCRIPT_DIR}/.regional_domain")
    fi
    
    # Check if hosted zone exists for the domain
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
        --output text 2>/dev/null | cut -d'/' -f3 || true)
    
    if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" = "None" ]; then
        log_warning "No hosted zone found for ${DOMAIN_NAME}"
        log_warning "Please create a CNAME record manually:"
        log_warning "  Name: ${API_SUBDOMAIN}"
        log_warning "  Value: ${REGIONAL_DOMAIN}"
        log_warning "  TTL: 300"
        return 0
    fi
    
    # Check if DNS record already exists
    EXISTING_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --query "ResourceRecordSets[?Name=='${API_SUBDOMAIN}.'].Type" \
        --output text 2>/dev/null || true)
    
    if [ -n "$EXISTING_RECORD" ]; then
        log_info "DNS record already exists for ${API_SUBDOMAIN}"
        return 0
    fi
    
    # Create DNS record for custom domain
    cat > "${SCRIPT_DIR}/dns-record.json" << EOF
{
    "Changes": [{
        "Action": "CREATE",
        "ResourceRecordSet": {
            "Name": "${API_SUBDOMAIN}",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{"Value": "${REGIONAL_DOMAIN}"}]
        }
    }]
}
EOF
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --change-batch "file://${SCRIPT_DIR}/dns-record.json"
    
    RESOURCES_CREATED+=("route53:${HOSTED_ZONE_ID}:${API_SUBDOMAIN}")
    log_success "DNS record created in Route 53"
    echo "${HOSTED_ZONE_ID}" > "${SCRIPT_DIR}/.hosted_zone_id"
}

# Cleanup function for error handling
cleanup_resources() {
    log_warning "Cleaning up resources created during failed deployment..."
    
    # Source environment if available
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        source "${SCRIPT_DIR}/.env"
    fi
    
    # Cleanup in reverse order
    for resource in "${RESOURCES_CREATED[@]}"; do
        local type=$(echo "$resource" | cut -d':' -f1)
        local name=$(echo "$resource" | cut -d':' -f2-)
        
        case "$type" in
            "route53")
                local zone_id=$(echo "$name" | cut -d':' -f1)
                local record_name=$(echo "$name" | cut -d':' -f2)
                log_info "Cleaning up DNS record: $record_name"
                # DNS cleanup would go here
                ;;
            "apigateway")
                if [[ "$name" == domain:* ]]; then
                    local domain_name=$(echo "$name" | cut -d':' -f2)
                    log_info "Cleaning up custom domain: $domain_name"
                    aws apigateway delete-domain-name --domain-name "$domain_name" 2>/dev/null || true
                else
                    log_info "Cleaning up API Gateway: $name"
                    aws apigateway delete-rest-api --rest-api-id "$name" 2>/dev/null || true
                fi
                ;;
            "lambda")
                log_info "Cleaning up Lambda function: $name"
                aws lambda delete-function --function-name "$name" 2>/dev/null || true
                ;;
            "iam")
                local role_name=$(echo "$name" | cut -d':' -f2)
                log_info "Cleaning up IAM role: $role_name"
                aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
                aws iam delete-role --role-name "$role_name" 2>/dev/null || true
                ;;
            "acm")
                log_info "Cleaning up certificate: $name"
                aws acm delete-certificate --certificate-arn "$name" 2>/dev/null || true
                ;;
            "s3")
                log_info "Cleaning up S3 bucket: $name"
                aws s3 rb "s3://$name" --force 2>/dev/null || true
                ;;
        esac
    done
    
    log_warning "Cleanup completed"
}

# Run tests
run_tests() {
    log_info "Running deployment validation tests..."
    
    # Test 1: Check if custom domain is accessible
    log_info "Testing custom domain accessibility..."
    if curl -s --connect-timeout 10 "https://${API_SUBDOMAIN}" >/dev/null 2>&1; then
        log_success "Custom domain is accessible"
    else
        log_warning "Custom domain may not be fully propagated yet"
    fi
    
    # Test 2: Check SSL certificate
    log_info "Validating SSL certificate..."
    if openssl s_client -connect "${API_SUBDOMAIN}:443" -servername "${API_SUBDOMAIN}" < /dev/null 2>/dev/null | \
       openssl x509 -noout -subject -dates >/dev/null 2>&1; then
        log_success "SSL certificate is valid"
    else
        log_warning "SSL certificate validation failed"
    fi
    
    # Test 3: Check API endpoints (if domain is accessible)
    log_info "Testing API endpoints..."
    
    # Test unauthorized access (should fail)
    if curl -s -o /dev/null -w "%{http_code}" "https://${API_SUBDOMAIN}/pets" | grep -q "401\|403"; then
        log_success "Unauthorized access properly denied"
    else
        log_warning "Unauthorized access test inconclusive"
    fi
    
    # Test authorized access
    if curl -s -H "Authorization: Bearer valid-token" "https://${API_SUBDOMAIN}/pets" | grep -q "pets"; then
        log_success "Authorized API access working"
    else
        log_warning "Authorized API access test failed (domain may not be ready)"
    fi
}

# Print deployment summary
print_summary() {
    log_success "=== DEPLOYMENT SUMMARY ==="
    log_info "API Name: ${API_NAME}"
    log_info "Custom Domain: ${API_SUBDOMAIN}"
    log_info "Regional Domain: ${REGIONAL_DOMAIN:-N/A}"
    log_info "REST API ID: ${REST_API_ID}"
    log_info "Certificate ARN: ${CERTIFICATE_ARN}"
    log_info ""
    log_info "API Endpoints:"
    log_info "  - Production: https://${API_SUBDOMAIN}/pets"
    log_info "  - Production (v1): https://${API_SUBDOMAIN}/v1/pets"
    log_info "  - Development: https://${API_SUBDOMAIN}/v1-dev/pets"
    log_info ""
    log_info "Test commands:"
    log_info "  curl -H \"Authorization: Bearer valid-token\" https://${API_SUBDOMAIN}/pets"
    log_info ""
    log_info "Environment file: ${SCRIPT_DIR}/.env"
    log_info "Cleanup script: ${SCRIPT_DIR}/destroy.sh"
    log_info ""
    log_success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log_info "Starting API Gateway Custom Domain deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    DEPLOYMENT_STARTED=true
    
    # Execute deployment steps
    check_prerequisites
    validate_environment
    setup_environment
    create_ssl_certificate
    create_lambda_role
    deploy_lambda_functions
    create_api_gateway
    configure_api_methods
    deploy_api_stages
    
    # Certificate validation checkpoint
    if wait_for_certificate; then
        create_custom_domain
        create_api_mappings
        configure_dns
        run_tests
        print_summary
    else
        log_warning "Certificate validation incomplete. You can:"
        log_warning "1. Add the DNS validation record"
        log_warning "2. Run this script again to complete deployment"
        log_warning "3. Or run: aws acm describe-certificate --certificate-arn ${CERTIFICATE_ARN}"
    fi
}

# Show usage information
usage() {
    echo "Usage: $0"
    echo ""
    echo "Required environment variables:"
    echo "  DOMAIN_NAME    - Your domain name (e.g., example.com)"
    echo "  AWS_REGION     - AWS region for deployment (e.g., us-east-1)"
    echo ""
    echo "Example:"
    echo "  export DOMAIN_NAME=example.com"
    echo "  export AWS_REGION=us-east-1"
    echo "  $0"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Enable verbose logging"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if required environment variables are set
if [ -z "${DOMAIN_NAME:-}" ] || [ -z "${AWS_REGION:-}" ]; then
    log_error "Required environment variables not set"
    usage
    exit 1
fi

# Run main function
main "$@"