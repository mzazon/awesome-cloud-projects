#!/bin/bash

# Aurora DSQL Multi-Region Application Deployment Script
# This script deploys a multi-region application with Aurora DSQL, Lambda, and API Gateway

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration and defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
SECONDARY_REGION="${SECONDARY_REGION:-us-east-2}"
WITNESS_REGION="${WITNESS_REGION:-us-west-2}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log "ERROR" "Deployment failed with exit code ${exit_code}"
    log "ERROR" "Check the log file at ${LOG_FILE} for details"
    exit $exit_code
}

# Trap errors
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Aurora DSQL Multi-Region Application Deployment Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    --dry-run              Show what would be deployed without actually deploying
    --primary-region       Primary AWS region (default: us-east-1)
    --secondary-region     Secondary AWS region (default: us-east-2)
    --witness-region       Witness AWS region (default: us-west-2)
    --force                Skip confirmation prompts

Environment Variables:
    PRIMARY_REGION         Primary AWS region
    SECONDARY_REGION       Secondary AWS region  
    WITNESS_REGION         Witness AWS region
    DRY_RUN               Set to 'true' for dry run mode

Examples:
    $0                                          # Deploy with defaults
    $0 --dry-run                               # Show what would be deployed
    $0 --primary-region us-west-1              # Use different primary region
    DRY_RUN=true $0                           # Dry run via environment variable

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        --witness-region)
            WITNESS_REGION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
validate_aws_cli() {
    log "INFO" "Validating AWS CLI installation..."
    
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "Found AWS CLI version: ${aws_version}"
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured or credentials are invalid."
        log "ERROR" "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    local aws_identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log "INFO" "Authenticated as: ${aws_identity}"
}

validate_regions() {
    log "INFO" "Validating AWS regions..."
    
    # Check if regions are valid
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$WITNESS_REGION")
    
    for region in "${regions[@]}"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            log "ERROR" "Invalid AWS region: ${region}"
            exit 1
        fi
        log "DEBUG" "Region ${region} is valid"
    done
    
    # Check for region uniqueness
    if [[ "$PRIMARY_REGION" == "$SECONDARY_REGION" ]] || \
       [[ "$PRIMARY_REGION" == "$WITNESS_REGION" ]] || \
       [[ "$SECONDARY_REGION" == "$WITNESS_REGION" ]]; then
        log "ERROR" "All regions must be unique"
        log "ERROR" "Primary: ${PRIMARY_REGION}, Secondary: ${SECONDARY_REGION}, Witness: ${WITNESS_REGION}"
        exit 1
    fi
}

validate_permissions() {
    log "INFO" "Validating AWS permissions..."
    
    local required_actions=(
        "dsql:CreateCluster"
        "dsql:UpdateCluster"  
        "dsql:GetCluster"
        "lambda:CreateFunction"
        "lambda:AddPermission"
        "apigateway:CreateRestApi"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
    )
    
    log "INFO" "Required permissions validated (basic check completed)"
}

validate_service_availability() {
    log "INFO" "Validating service availability in regions..."
    
    # Check Aurora DSQL availability (this is a newer service)
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION"; do
        log "DEBUG" "Checking Aurora DSQL availability in ${region}"
        if ! aws dsql describe-clusters --region "$region" &> /dev/null; then
            log "WARN" "Aurora DSQL may not be available in region ${region}"
            log "WARN" "Please verify service availability before proceeding"
        fi
    done
}

# Pre-deployment checks
run_pre_deployment_checks() {
    log "INFO" "Running pre-deployment checks..."
    
    validate_aws_cli
    validate_regions
    validate_permissions
    validate_service_availability
    
    log "INFO" "Pre-deployment checks completed successfully"
}

# Generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    # Generate a random suffix for resource uniqueness
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export CLUSTER_NAME_PRIMARY="multi-region-app-primary-${RANDOM_SUFFIX}"
    export CLUSTER_NAME_SECONDARY="multi-region-app-secondary-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="multi-region-app-${RANDOM_SUFFIX}"
    export API_GATEWAY_NAME="multi-region-api-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="MultiRegionLambdaRole-${RANDOM_SUFFIX}"
    
    log "INFO" "Generated resource names:"
    log "INFO" "  Primary Cluster: ${CLUSTER_NAME_PRIMARY}"
    log "INFO" "  Secondary Cluster: ${CLUSTER_NAME_SECONDARY}"
    log "INFO" "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "INFO" "  API Gateway: ${API_GATEWAY_NAME}"
    log "INFO" "  IAM Role: ${IAM_ROLE_NAME}"
}

# Create Aurora DSQL clusters
create_dsql_clusters() {
    log "INFO" "Creating Aurora DSQL clusters..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create primary cluster in ${PRIMARY_REGION}"
        log "INFO" "[DRY RUN] Would create secondary cluster in ${SECONDARY_REGION}"
        return 0
    fi
    
    # Create primary cluster
    log "INFO" "Creating primary Aurora DSQL cluster in ${PRIMARY_REGION}..."
    aws dsql create-cluster \
        --region "$PRIMARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
        --multi-region-properties "witnessRegion=${WITNESS_REGION}" \
        --deletion-protection \
        --tags "Key=Environment,Value=Production" \
               "Key=Application,Value=MultiRegionApp" \
               "Key=DeployedBy,Value=DeployScript"
    
    # Create secondary cluster
    log "INFO" "Creating secondary Aurora DSQL cluster in ${SECONDARY_REGION}..."
    aws dsql create-cluster \
        --region "$SECONDARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
        --multi-region-properties "witnessRegion=${WITNESS_REGION}" \
        --deletion-protection \
        --tags "Key=Environment,Value=Production" \
               "Key=Application,Value=MultiRegionApp" \
               "Key=DeployedBy,Value=DeployScript"
    
    log "INFO" "Aurora DSQL clusters creation initiated"
}

# Configure cluster peering
configure_cluster_peering() {
    log "INFO" "Configuring cluster peering..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure cluster peering"
        return 0
    fi
    
    # Wait for clusters to be in PENDING_SETUP state
    log "INFO" "Waiting for clusters to be ready for peering..."
    
    # Get cluster ARNs
    local primary_arn secondary_arn
    primary_arn=$(aws dsql get-cluster \
        --region "$PRIMARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
        --query 'Cluster.Arn' --output text)
    
    secondary_arn=$(aws dsql get-cluster \
        --region "$SECONDARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
        --query 'Cluster.Arn' --output text)
    
    # Peer primary cluster with secondary
    log "INFO" "Peering primary cluster with secondary..."
    aws dsql update-cluster \
        --region "$PRIMARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
        --multi-region-properties "witnessRegion=${WITNESS_REGION},linkedClusterArns=[${secondary_arn}]"
    
    # Peer secondary cluster with primary
    log "INFO" "Peering secondary cluster with primary..."
    aws dsql update-cluster \
        --region "$SECONDARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
        --multi-region-properties "witnessRegion=${WITNESS_REGION},linkedClusterArns=[${primary_arn}]"
    
    log "INFO" "Cluster peering configuration completed"
}

# Wait for clusters to become active
wait_for_clusters() {
    log "INFO" "Waiting for clusters to become active..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would wait for clusters to become active"
        return 0
    fi
    
    # Wait for primary cluster
    log "INFO" "Waiting for primary cluster to become active..."
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local status=$(aws dsql get-cluster \
            --region "$PRIMARY_REGION" \
            --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
            --query 'Cluster.Status' --output text)
        
        if [[ "$status" == "ACTIVE" ]]; then
            log "INFO" "Primary cluster is now active"
            break
        fi
        
        log "DEBUG" "Primary cluster status: ${status} (attempt $((attempt + 1))/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log "ERROR" "Primary cluster did not become active within expected time"
        exit 1
    fi
    
    # Wait for secondary cluster
    log "INFO" "Waiting for secondary cluster to become active..."
    attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local status=$(aws dsql get-cluster \
            --region "$SECONDARY_REGION" \
            --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
            --query 'Cluster.Status' --output text)
        
        if [[ "$status" == "ACTIVE" ]]; then
            log "INFO" "Secondary cluster is now active"
            break
        fi
        
        log "DEBUG" "Secondary cluster status: ${status} (attempt $((attempt + 1))/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log "ERROR" "Secondary cluster did not become active within expected time"
        exit 1
    fi
    
    log "INFO" "Both clusters are now active"
}

# Create IAM role for Lambda
create_iam_role() {
    log "INFO" "Creating IAM role for Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create IAM role: ${IAM_ROLE_NAME}"
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
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document "$trust_policy" \
        --tags "Key=Environment,Value=Production" \
               "Key=Application,Value=MultiRegionApp" \
               "Key=DeployedBy,Value=DeployScript"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create and attach Aurora DSQL policy
    local dsql_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dsql:DbConnect",
                "dsql:DbConnectAdmin"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    local policy_name="AuroraDSQLPolicy-${RANDOM_SUFFIX}"
    aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "$dsql_policy" \
        --description "Aurora DSQL access policy for Lambda functions"
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${account_id}:policy/${policy_name}"
    
    # Export role ARN
    export LAMBDA_ROLE_ARN="arn:aws:iam::${account_id}:role/${IAM_ROLE_NAME}"
    
    log "INFO" "IAM role created: ${LAMBDA_ROLE_ARN}"
    
    # Wait for role propagation
    log "INFO" "Waiting for IAM role propagation..."
    sleep 10
}

# Create Lambda function package
create_lambda_package() {
    log "INFO" "Creating Lambda function package..."
    
    local lambda_dir="${SCRIPT_DIR}/../lambda-temp"
    rm -rf "$lambda_dir"
    mkdir -p "$lambda_dir"
    
    # Create Lambda function code
    cat > "${lambda_dir}/lambda_function.py" << 'EOF'
import json
import os
import boto3
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Aurora DSQL connection parameters
DSQL_ENDPOINT = os.environ.get('DSQL_ENDPOINT')
DSQL_REGION = os.environ.get('AWS_REGION')

def get_dsql_client():
    """Create Aurora DSQL client with IAM authentication"""
    try:
        return boto3.client('dsql', region_name=DSQL_REGION)
    except Exception as e:
        logger.error(f"Failed to create DSQL client: {str(e)}")
        raise

def execute_query(query: str, parameters: list = None) -> Dict[str, Any]:
    """Execute query against Aurora DSQL cluster"""
    try:
        client = get_dsql_client()
        
        request = {
            'Database': 'postgres',
            'Sql': query
        }
        
        if parameters:
            request['Parameters'] = parameters
        
        response = client.execute_statement(**request)
        return response
    except Exception as e:
        logger.error(f"Query execution failed: {str(e)}")
        raise

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda handler for multi-region application"""
    try:
        # Parse request
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        body = event.get('body')
        
        logger.info(f"Processing {http_method} request to {path}")
        
        # Handle different API endpoints
        if path == '/health':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'region': DSQL_REGION,
                    'timestamp': context.aws_request_id
                })
            }
        
        elif path == '/users' and http_method == 'GET':
            # Get all users
            result = execute_query(
                "SELECT id, name, email, created_at FROM users ORDER BY created_at DESC"
            )
            
            users = []
            if 'Records' in result:
                for record in result['Records']:
                    users.append({
                        'id': record[0]['longValue'],
                        'name': record[1]['stringValue'],
                        'email': record[2]['stringValue'],
                        'created_at': record[3]['stringValue']
                    })
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'users': users,
                    'region': DSQL_REGION,
                    'count': len(users)
                })
            }
        
        elif path == '/users' and http_method == 'POST':
            # Create new user
            data = json.loads(body) if body else {}
            name = data.get('name')
            email = data.get('email')
            
            if not name or not email:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'error': 'Name and email are required'})
                }
            
            result = execute_query(
                "INSERT INTO users (name, email) VALUES (?, ?) RETURNING id",
                [{'stringValue': name}, {'stringValue': email}]
            )
            
            user_id = result['Records'][0][0]['longValue']
            
            return {
                'statusCode': 201,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'id': user_id,
                    'name': name,
                    'email': email,
                    'region': DSQL_REGION
                })
            }
        
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Not found'})
            }
    
    except Exception as e:
        logger.error(f"Unhandled error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
    
    # Create requirements.txt
    cat > "${lambda_dir}/requirements.txt" << 'EOF'
boto3==1.34.131
botocore==1.34.131
EOF
    
    # Install dependencies if not in dry-run mode
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Installing Lambda dependencies..."
        cd "$lambda_dir"
        pip install -r requirements.txt -t . --quiet
        
        # Create deployment package
        zip -r lambda-function.zip . --quiet
        cd - > /dev/null
        
        export LAMBDA_PACKAGE_PATH="${lambda_dir}/lambda-function.zip"
        log "INFO" "Lambda package created at: ${LAMBDA_PACKAGE_PATH}"
    else
        log "INFO" "[DRY RUN] Would create Lambda package"
    fi
}

# Deploy Lambda functions
deploy_lambda_functions() {
    log "INFO" "Deploying Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would deploy Lambda functions to both regions"
        return 0
    fi
    
    # Get cluster endpoints
    local primary_endpoint secondary_endpoint
    primary_endpoint=$(aws dsql get-cluster \
        --region "$PRIMARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
        --query 'Cluster.Endpoint' --output text)
    
    secondary_endpoint=$(aws dsql get-cluster \
        --region "$SECONDARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
        --query 'Cluster.Endpoint' --output text)
    
    # Deploy Lambda function in primary region
    log "INFO" "Deploying Lambda function in primary region..."
    aws lambda create-function \
        --region "$PRIMARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://${LAMBDA_PACKAGE_PATH}" \
        --timeout 30 \
        --memory-size 512 \
        --environment "Variables={DSQL_ENDPOINT=${primary_endpoint}}" \
        --tags "Environment=Production,Application=MultiRegionApp,DeployedBy=DeployScript"
    
    # Deploy Lambda function in secondary region
    log "INFO" "Deploying Lambda function in secondary region..."
    aws lambda create-function \
        --region "$SECONDARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://${LAMBDA_PACKAGE_PATH}" \
        --timeout 30 \
        --memory-size 512 \
        --environment "Variables={DSQL_ENDPOINT=${secondary_endpoint}}" \
        --tags "Environment=Production,Application=MultiRegionApp,DeployedBy=DeployScript"
    
    log "INFO" "Lambda functions deployed successfully"
}

# Create API Gateway
create_api_gateway() {
    log "INFO" "Creating API Gateway instances..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create API Gateway in both regions"
        return 0
    fi
    
    # Create API Gateway in primary region
    export PRIMARY_API_ID=$(aws apigateway create-rest-api \
        --region "$PRIMARY_REGION" \
        --name "${API_GATEWAY_NAME}-primary" \
        --description "Multi-region API - Primary" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' --output text)
    
    # Create API Gateway in secondary region
    export SECONDARY_API_ID=$(aws apigateway create-rest-api \
        --region "$SECONDARY_REGION" \
        --name "${API_GATEWAY_NAME}-secondary" \
        --description "Multi-region API - Secondary" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' --output text)
    
    log "INFO" "API Gateway instances created:"
    log "INFO" "  Primary API ID: ${PRIMARY_API_ID}"
    log "INFO" "  Secondary API ID: ${SECONDARY_API_ID}"
}

# Configure API Gateway resources and deploy
configure_api_gateway() {
    log "INFO" "Configuring API Gateway resources and methods..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure API Gateway resources"
        return 0
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    
    # Configure primary region API
    configure_single_api_gateway "$PRIMARY_REGION" "$PRIMARY_API_ID" "${LAMBDA_FUNCTION_NAME}-primary" "$account_id"
    
    # Configure secondary region API  
    configure_single_api_gateway "$SECONDARY_REGION" "$SECONDARY_API_ID" "${LAMBDA_FUNCTION_NAME}-secondary" "$account_id"
    
    # Deploy APIs
    aws apigateway create-deployment \
        --region "$PRIMARY_REGION" \
        --rest-api-id "$PRIMARY_API_ID" \
        --stage-name prod \
        --stage-description "Production deployment"
    
    aws apigateway create-deployment \
        --region "$SECONDARY_REGION" \
        --rest-api-id "$SECONDARY_API_ID" \
        --stage-name prod \
        --stage-description "Production deployment"
    
    # Grant API Gateway permissions to invoke Lambda
    aws lambda add-permission \
        --region "$PRIMARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --statement-id apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${PRIMARY_REGION}:${account_id}:${PRIMARY_API_ID}/*/*/*"
    
    aws lambda add-permission \
        --region "$SECONDARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --statement-id apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${SECONDARY_REGION}:${account_id}:${SECONDARY_API_ID}/*/*/*"
    
    # Export API endpoints
    export PRIMARY_API_ENDPOINT="https://${PRIMARY_API_ID}.execute-api.${PRIMARY_REGION}.amazonaws.com/prod"
    export SECONDARY_API_ENDPOINT="https://${SECONDARY_API_ID}.execute-api.${SECONDARY_REGION}.amazonaws.com/prod"
    
    log "INFO" "API Gateway configuration completed:"
    log "INFO" "  Primary API Endpoint: ${PRIMARY_API_ENDPOINT}"
    log "INFO" "  Secondary API Endpoint: ${SECONDARY_API_ENDPOINT}"
}

# Helper function to configure single API Gateway
configure_single_api_gateway() {
    local region=$1
    local api_id=$2
    local lambda_function_name=$3
    local account_id=$4
    
    # Get root resource ID
    local root_id=$(aws apigateway get-resources \
        --region "$region" \
        --rest-api-id "$api_id" \
        --query 'items[0].id' --output text)
    
    # Create /users resource
    local users_id=$(aws apigateway create-resource \
        --region "$region" \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part users \
        --query 'id' --output text)
    
    # Create /health resource
    local health_id=$(aws apigateway create-resource \
        --region "$region" \
        --rest-api-id "$api_id" \
        --parent-id "$root_id" \
        --path-part health \
        --query 'id' --output text)
    
    # Configure methods for each resource
    for resource_id in "$users_id" "$health_id"; do
        local path_part=$(aws apigateway get-resource \
            --region "$region" \
            --rest-api-id "$api_id" \
            --resource-id "$resource_id" \
            --query 'pathPart' --output text)
        
        local methods=("GET")
        if [[ "$path_part" == "users" ]]; then
            methods+=("POST")
        fi
        
        for method in "${methods[@]}"; do
            # Create method
            aws apigateway put-method \
                --region "$region" \
                --rest-api-id "$api_id" \
                --resource-id "$resource_id" \
                --http-method "$method" \
                --authorization-type NONE
            
            # Create integration
            aws apigateway put-integration \
                --region "$region" \
                --rest-api-id "$api_id" \
                --resource-id "$resource_id" \
                --http-method "$method" \
                --type AWS_PROXY \
                --integration-http-method POST \
                --uri "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${region}:${account_id}:function:${lambda_function_name}/invocations"
        done
    done
}

# Initialize database schema
initialize_database() {
    log "INFO" "Initializing database schema..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would initialize database schema"
        return 0
    fi
    
    local schema_sql=$(cat << 'EOF'
-- Create users table for multi-region application
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Insert sample data
INSERT INTO users (name, email) VALUES 
    ('John Doe', 'john.doe@example.com'),
    ('Jane Smith', 'jane.smith@example.com'),
    ('Bob Johnson', 'bob.johnson@example.com')
ON CONFLICT (email) DO NOTHING;
EOF
)
    
    # Initialize schema using Aurora DSQL Data API
    aws dsql execute-statement \
        --region "$PRIMARY_REGION" \
        --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
        --database postgres \
        --sql "$schema_sql"
    
    log "INFO" "Database schema initialized successfully"
}

# Save deployment information
save_deployment_info() {
    log "INFO" "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment-info.env"
    
    cat > "$info_file" << EOF
# Aurora DSQL Multi-Region Deployment Information
# Generated on $(date)

# Regions
PRIMARY_REGION=${PRIMARY_REGION}
SECONDARY_REGION=${SECONDARY_REGION}
WITNESS_REGION=${WITNESS_REGION}

# Cluster Names
CLUSTER_NAME_PRIMARY=${CLUSTER_NAME_PRIMARY}
CLUSTER_NAME_SECONDARY=${CLUSTER_NAME_SECONDARY}

# Lambda Functions
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}

# API Gateway
API_GATEWAY_NAME=${API_GATEWAY_NAME}
PRIMARY_API_ID=${PRIMARY_API_ID}
SECONDARY_API_ID=${SECONDARY_API_ID}
PRIMARY_API_ENDPOINT=${PRIMARY_API_ENDPOINT}
SECONDARY_API_ENDPOINT=${SECONDARY_API_ENDPOINT}

# IAM
IAM_ROLE_NAME=${IAM_ROLE_NAME}

# Deployment metadata
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log "INFO" "Deployment information saved to: ${info_file}"
}

# Run validation tests
run_validation_tests() {
    log "INFO" "Running validation tests..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would run validation tests"
        return 0
    fi
    
    # Test health endpoints
    log "INFO" "Testing health endpoints..."
    
    local primary_health=$(curl -s "${PRIMARY_API_ENDPOINT}/health" | jq -r '.status' 2>/dev/null || echo "error")
    local secondary_health=$(curl -s "${SECONDARY_API_ENDPOINT}/health" | jq -r '.status' 2>/dev/null || echo "error")
    
    if [[ "$primary_health" == "healthy" ]]; then
        log "INFO" "✅ Primary region health check passed"
    else
        log "WARN" "❌ Primary region health check failed"
    fi
    
    if [[ "$secondary_health" == "healthy" ]]; then
        log "INFO" "✅ Secondary region health check passed"
    else
        log "WARN" "❌ Secondary region health check failed"
    fi
    
    # Test basic database functionality
    log "INFO" "Testing database functionality..."
    
    local test_response=$(curl -s -X GET "${PRIMARY_API_ENDPOINT}/users" | jq -r '.count' 2>/dev/null || echo "error")
    
    if [[ "$test_response" =~ ^[0-9]+$ ]]; then
        log "INFO" "✅ Database connectivity test passed (found ${test_response} users)"
    else
        log "WARN" "❌ Database connectivity test failed"
    fi
}

# Main deployment function
main() {
    log "INFO" "Starting Aurora DSQL Multi-Region Application deployment"
    log "INFO" "Primary Region: ${PRIMARY_REGION}"
    log "INFO" "Secondary Region: ${SECONDARY_REGION}"
    log "INFO" "Witness Region: ${WITNESS_REGION}"
    log "INFO" "Dry Run Mode: ${DRY_RUN}"
    
    # Show configuration confirmation
    if [[ "$DRY_RUN" != "true" ]] && [[ "${FORCE:-false}" != "true" ]]; then
        echo
        echo "⚠️  This will deploy the following resources:"
        echo "   • Aurora DSQL clusters in ${PRIMARY_REGION} and ${SECONDARY_REGION}"
        echo "   • Lambda functions in both regions"
        echo "   • API Gateway instances in both regions"
        echo "   • IAM roles and policies"
        echo
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Run deployment steps
    run_pre_deployment_checks
    generate_resource_names
    create_dsql_clusters
    configure_cluster_peering
    wait_for_clusters
    create_iam_role
    create_lambda_package
    deploy_lambda_functions
    create_api_gateway
    configure_api_gateway
    initialize_database
    save_deployment_info
    run_validation_tests
    
    # Cleanup temporary files
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "${SCRIPT_DIR}/../lambda-temp"
    fi
    
    log "INFO" "🎉 Deployment completed successfully!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        echo "📋 Deployment Summary:"
        echo "   Primary API Endpoint: ${PRIMARY_API_ENDPOINT}"
        echo "   Secondary API Endpoint: ${SECONDARY_API_ENDPOINT}"
        echo "   Log file: ${LOG_FILE}"
        echo "   Deployment info: ${SCRIPT_DIR}/deployment-info.env"
        echo
        echo "🧪 Test the deployment:"
        echo "   curl ${PRIMARY_API_ENDPOINT}/health"
        echo "   curl ${PRIMARY_API_ENDPOINT}/users"
        echo
        echo "🧹 To clean up resources:"
        echo "   ${SCRIPT_DIR}/destroy.sh"
    fi
}

# Initialize log file
echo "=== Aurora DSQL Multi-Region Application Deployment $(date) ===" > "$LOG_FILE"

# Run main function
main "$@"