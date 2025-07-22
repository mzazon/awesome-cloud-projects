#!/bin/bash

# Real-time Recommendation Systems with Amazon Personalize and API Gateway
# Deployment Script
# 
# This script automates the deployment of a complete recommendation system
# using Amazon Personalize, Lambda, and API Gateway for real-time inference.

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some JSON parsing may not work optimally."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Required for Lambda deployment."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured. Using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    # Export resource names
    export BUCKET_NAME="personalize-demo-${RANDOM_SUFFIX}"
    export DATASET_GROUP_NAME="ecommerce-recommendations-${RANDOM_SUFFIX}"
    export SOLUTION_NAME="user-personalization-${RANDOM_SUFFIX}"
    export CAMPAIGN_NAME="real-time-recommendations-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="recommendation-api-${RANDOM_SUFFIX}"
    export API_NAME="recommendation-api-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export BUCKET_NAME=${BUCKET_NAME}
export DATASET_GROUP_NAME=${DATASET_GROUP_NAME}
export SOLUTION_NAME=${SOLUTION_NAME}
export CAMPAIGN_NAME=${CAMPAIGN_NAME}
export LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
export API_NAME=${API_NAME}
export RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables set successfully"
    info "Using suffix: ${RANDOM_SUFFIX}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for training data..."
    
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warn "S3 bucket ${BUCKET_NAME} already exists"
    else
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "${BUCKET_NAME}"
        else
            aws s3api create-bucket --bucket "${BUCKET_NAME}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        log "S3 bucket created: ${BUCKET_NAME}"
    fi
}

# Function to create IAM role for Personalize
create_personalize_iam_role() {
    log "Creating IAM role for Amazon Personalize..."
    
    # Create trust policy
    cat > personalize-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "personalize.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    if aws iam get-role --role-name "PersonalizeExecutionRole-${RANDOM_SUFFIX}" &>/dev/null; then
        warn "IAM role PersonalizeExecutionRole-${RANDOM_SUFFIX} already exists"
    else
        aws iam create-role \
            --role-name "PersonalizeExecutionRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file://personalize-trust-policy.json
        
        # Attach required policy
        aws iam attach-role-policy \
            --role-name "PersonalizeExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonPersonalizeFullAccess
        
        log "IAM role created: PersonalizeExecutionRole-${RANDOM_SUFFIX}"
    fi
    
    # Store role ARN
    export PERSONALIZE_ROLE_ARN=$(aws iam get-role \
        --role-name "PersonalizeExecutionRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    echo "export PERSONALIZE_ROLE_ARN=${PERSONALIZE_ROLE_ARN}" >> .env
}

# Function to upload sample training data
upload_training_data() {
    log "Creating and uploading sample training data..."
    
    # Create sample interaction data
    cat > sample-interactions.csv << EOF
USER_ID,ITEM_ID,TIMESTAMP,EVENT_TYPE
user1,item101,1640995200,purchase
user1,item102,1640995260,view
user1,item103,1640995320,purchase
user2,item101,1640995380,view
user2,item104,1640995440,purchase
user2,item105,1640995500,view
user3,item102,1640995560,purchase
user3,item103,1640995620,view
user3,item106,1640995680,purchase
user4,item101,1640995740,view
user4,item107,1640995800,purchase
user5,item108,1640995860,view
user5,item109,1640995920,purchase
user6,item110,1640995980,view
user6,item111,1641000040,purchase
user7,item112,1641000100,view
user7,item113,1641000160,purchase
user8,item114,1641000220,view
user8,item115,1641000280,purchase
user9,item116,1641000340,view
user9,item117,1641000400,purchase
user10,item118,1641000460,view
user10,item119,1641000520,purchase
user11,item120,1641000580,view
user11,item121,1641000640,purchase
user12,item122,1641000700,view
user12,item123,1641000760,purchase
user13,item124,1641000820,view
user13,item125,1641000880,purchase
user14,item126,1641000940,view
user14,item127,1641001000,purchase
user15,item128,1641001060,view
user15,item129,1641001120,purchase
user16,item130,1641001180,view
user16,item131,1641001240,purchase
user17,item132,1641001300,view
user17,item133,1641001360,purchase
user18,item134,1641001420,view
user18,item135,1641001480,purchase
user19,item136,1641001540,view
user19,item137,1641001600,purchase
user20,item138,1641001660,view
user20,item139,1641001720,purchase
user21,item140,1641001780,view
user21,item141,1641001840,purchase
user22,item142,1641001900,view
user22,item143,1641001960,purchase
user23,item144,1641002020,view
user23,item145,1641002080,purchase
user24,item146,1641002140,view
user24,item147,1641002200,purchase
user25,item148,1641002260,view
user25,item149,1641002320,purchase
EOF
    
    # Upload to S3
    aws s3 cp sample-interactions.csv s3://${BUCKET_NAME}/training-data/interactions.csv
    
    log "Training data uploaded to S3"
}

# Function to create Personalize dataset group and schema
create_personalize_resources() {
    log "Creating Personalize dataset group and schema..."
    
    # Create dataset group
    if aws personalize describe-dataset-group \
        --dataset-group-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}" &>/dev/null; then
        warn "Dataset group ${DATASET_GROUP_NAME} already exists"
    else
        aws personalize create-dataset-group \
            --name "${DATASET_GROUP_NAME}" \
            --region "${AWS_REGION}"
        
        log "Dataset group created: ${DATASET_GROUP_NAME}"
    fi
    
    # Wait for dataset group to be active
    info "Waiting for dataset group to become active..."
    aws personalize wait dataset-group-active \
        --dataset-group-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}"
    
    export DATASET_GROUP_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}"
    
    # Create schema
    cat > interactions-schema.json << EOF
{
    "type": "record",
    "name": "Interactions",
    "namespace": "com.amazonaws.personalize.schema",
    "fields": [
        {
            "name": "USER_ID",
            "type": "string"
        },
        {
            "name": "ITEM_ID",
            "type": "string"
        },
        {
            "name": "TIMESTAMP",
            "type": "long"
        },
        {
            "name": "EVENT_TYPE",
            "type": "string"
        }
    ],
    "version": "1.0"
}
EOF
    
    if aws personalize describe-schema \
        --schema-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/interaction-schema-${RANDOM_SUFFIX}" &>/dev/null; then
        warn "Schema interaction-schema-${RANDOM_SUFFIX} already exists"
    else
        aws personalize create-schema \
            --name "interaction-schema-${RANDOM_SUFFIX}" \
            --schema file://interactions-schema.json
        
        log "Schema created: interaction-schema-${RANDOM_SUFFIX}"
    fi
    
    export SCHEMA_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/interaction-schema-${RANDOM_SUFFIX}"
    
    # Add to env file
    cat >> .env << EOF
export DATASET_GROUP_ARN=${DATASET_GROUP_ARN}
export SCHEMA_ARN=${SCHEMA_ARN}
EOF
}

# Function to create dataset and import data
create_dataset_and_import() {
    log "Creating dataset and importing training data..."
    
    # Create dataset
    if aws personalize describe-dataset \
        --dataset-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/INTERACTIONS" &>/dev/null; then
        warn "Dataset already exists"
    else
        aws personalize create-dataset \
            --name "interactions-dataset-${RANDOM_SUFFIX}" \
            --dataset-group-arn "${DATASET_GROUP_ARN}" \
            --dataset-type Interactions \
            --schema-arn "${SCHEMA_ARN}"
        
        log "Dataset created"
    fi
    
    export DATASET_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/INTERACTIONS"
    
    # Create import job
    IMPORT_JOB_NAME="import-interactions-${RANDOM_SUFFIX}"
    if aws personalize describe-dataset-import-job \
        --dataset-import-job-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-import-job/${IMPORT_JOB_NAME}" &>/dev/null; then
        warn "Import job already exists"
    else
        aws personalize create-dataset-import-job \
            --job-name "${IMPORT_JOB_NAME}" \
            --dataset-arn "${DATASET_ARN}" \
            --data-source dataLocation=s3://${BUCKET_NAME}/training-data/interactions.csv \
            --role-arn "${PERSONALIZE_ROLE_ARN}"
        
        log "Import job created"
    fi
    
    export IMPORT_JOB_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-import-job/${IMPORT_JOB_NAME}"
    
    # Wait for import job to complete
    info "Waiting for data import to complete (this may take 10-15 minutes)..."
    while true; do
        STATUS=$(aws personalize describe-dataset-import-job \
            --dataset-import-job-arn "${IMPORT_JOB_ARN}" \
            --query DatasetImportJob.Status --output text)
        
        if [[ "$STATUS" == "ACTIVE" ]]; then
            log "Data import completed successfully"
            break
        elif [[ "$STATUS" == "CREATE_FAILED" ]]; then
            error "Data import failed"
        else
            info "Import status: $STATUS - waiting..."
            sleep 30
        fi
    done
    
    # Add to env file
    cat >> .env << EOF
export DATASET_ARN=${DATASET_ARN}
export IMPORT_JOB_ARN=${IMPORT_JOB_ARN}
EOF
}

# Function to create solution and train model
create_solution_and_train() {
    log "Creating solution and training model..."
    
    # Create solution
    if aws personalize describe-solution \
        --solution-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${SOLUTION_NAME}" &>/dev/null; then
        warn "Solution ${SOLUTION_NAME} already exists"
    else
        aws personalize create-solution \
            --name "${SOLUTION_NAME}" \
            --dataset-group-arn "${DATASET_GROUP_ARN}" \
            --recipe-arn arn:aws:personalize:::recipe/aws-user-personalization
        
        log "Solution created: ${SOLUTION_NAME}"
    fi
    
    export SOLUTION_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${SOLUTION_NAME}"
    
    # Create solution version
    SOLUTION_VERSION_NAME="solution-version-$(date +%s)"
    aws personalize create-solution-version \
        --solution-arn "${SOLUTION_ARN}" \
        --name "${SOLUTION_VERSION_NAME}"
    
    # Get the solution version ARN
    export SOLUTION_VERSION_ARN=$(aws personalize list-solution-versions \
        --solution-arn "${SOLUTION_ARN}" \
        --query 'solutionVersions[0].solutionVersionArn' --output text)
    
    log "Model training started (this will take 60-90 minutes)"
    info "Solution Version ARN: ${SOLUTION_VERSION_ARN}"
    
    # Add to env file
    cat >> .env << EOF
export SOLUTION_ARN=${SOLUTION_ARN}
export SOLUTION_VERSION_ARN=${SOLUTION_VERSION_ARN}
EOF
}

# Function to wait for solution version
wait_for_solution_version() {
    log "Waiting for solution version to become active..."
    
    while true; do
        STATUS=$(aws personalize describe-solution-version \
            --solution-version-arn "${SOLUTION_VERSION_ARN}" \
            --query SolutionVersion.Status --output text)
        
        if [[ "$STATUS" == "ACTIVE" ]]; then
            log "Solution version is now active"
            break
        elif [[ "$STATUS" == "CREATE_FAILED" ]]; then
            error "Solution version creation failed"
        else
            info "Solution version status: $STATUS - waiting..."
            sleep 300  # Wait 5 minutes between checks
        fi
    done
}

# Function to create campaign
create_campaign() {
    log "Creating campaign for real-time inference..."
    
    if aws personalize describe-campaign \
        --campaign-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:campaign/${CAMPAIGN_NAME}" &>/dev/null; then
        warn "Campaign ${CAMPAIGN_NAME} already exists"
    else
        aws personalize create-campaign \
            --name "${CAMPAIGN_NAME}" \
            --solution-version-arn "${SOLUTION_VERSION_ARN}" \
            --min-provisioned-tps 1
        
        log "Campaign created: ${CAMPAIGN_NAME}"
    fi
    
    export CAMPAIGN_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:campaign/${CAMPAIGN_NAME}"
    
    # Wait for campaign to be active
    info "Waiting for campaign to become active..."
    while true; do
        STATUS=$(aws personalize describe-campaign \
            --campaign-arn "${CAMPAIGN_ARN}" \
            --query Campaign.Status --output text)
        
        if [[ "$STATUS" == "ACTIVE" ]]; then
            log "Campaign is now active"
            break
        elif [[ "$STATUS" == "CREATE_FAILED" ]]; then
            error "Campaign creation failed"
        else
            info "Campaign status: $STATUS - waiting..."
            sleep 60
        fi
    done
    
    # Add to env file
    echo "export CAMPAIGN_ARN=${CAMPAIGN_ARN}" >> .env
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for API logic..."
    
    # Create Lambda function code
    cat > recommendation-handler.py << 'EOF'
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

personalize = boto3.client('personalize-runtime')

def lambda_handler(event, context):
    try:
        # Extract user ID from path parameters
        user_id = event['pathParameters']['userId']
        
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        num_results = int(query_params.get('numResults', 10))
        
        # Get recommendations from Personalize
        response = personalize.get_recommendations(
            campaignArn=os.environ['CAMPAIGN_ARN'],
            userId=user_id,
            numResults=num_results
        )
        
        # Format response
        recommendations = []
        for item in response['itemList']:
            recommendations.append({
                'itemId': item['itemId'],
                'score': item['score']
            })
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'userId': user_id,
                'recommendations': recommendations,
                'requestId': response['ResponseMetadata']['RequestId']
            })
        }
        
    except Exception as e:
        logger.error(f"Error getting recommendations: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
EOF
    
    # Create deployment package
    zip -r recommendation-handler.zip recommendation-handler.py
    
    # Create Lambda execution role
    cat > lambda-trust-policy.json << EOF
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
    
    # Create IAM role for Lambda
    if aws iam get-role --role-name "LambdaPersonalizeRole-${RANDOM_SUFFIX}" &>/dev/null; then
        warn "Lambda IAM role already exists"
    else
        aws iam create-role \
            --role-name "LambdaPersonalizeRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file://lambda-trust-policy.json
        
        # Attach policies
        aws iam attach-role-policy \
            --role-name "LambdaPersonalizeRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        aws iam attach-role-policy \
            --role-name "LambdaPersonalizeRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonPersonalizeFullAccess
        
        log "Lambda IAM role created"
        
        # Wait for role to be available
        sleep 10
    fi
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "LambdaPersonalizeRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    # Create Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        warn "Lambda function already exists"
    else
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler recommendation-handler.lambda_handler \
            --zip-file fileb://recommendation-handler.zip \
            --environment Variables="{CAMPAIGN_ARN=${CAMPAIGN_ARN}}" \
            --timeout 30 \
            --memory-size 256
        
        log "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Add to env file
    echo "export LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .env
}

# Function to create API Gateway
create_api_gateway() {
    log "Creating API Gateway REST API..."
    
    # Create REST API
    if aws apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id" --output text | grep -q .; then
        warn "API Gateway with name ${API_NAME} already exists"
        export API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_NAME}'].id" --output text)
    else
        export API_ID=$(aws apigateway create-rest-api \
            --name "${API_NAME}" \
            --description "Real-time recommendation API" \
            --query id --output text)
        
        log "API Gateway created: ${API_NAME}"
    fi
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text)
    
    # Create resource for recommendations
    RECOMMENDATIONS_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query "items[?pathPart=='recommendations'].id" --output text)
    
    if [[ -z "$RECOMMENDATIONS_RESOURCE_ID" ]]; then
        export RECOMMENDATIONS_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part recommendations \
            --query id --output text)
        
        log "Created recommendations resource"
    else
        export RECOMMENDATIONS_RESOURCE_ID="$RECOMMENDATIONS_RESOURCE_ID"
        warn "Recommendations resource already exists"
    fi
    
    # Create resource for user ID parameter
    USER_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query "items[?pathPart=='{userId}'].id" --output text)
    
    if [[ -z "$USER_RESOURCE_ID" ]]; then
        export USER_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${RECOMMENDATIONS_RESOURCE_ID}" \
            --path-part '{userId}' \
            --query id --output text)
        
        log "Created user resource"
    else
        export USER_RESOURCE_ID="$USER_RESOURCE_ID"
        warn "User resource already exists"
    fi
    
    # Add to env file
    cat >> .env << EOF
export API_ID=${API_ID}
export ROOT_RESOURCE_ID=${ROOT_RESOURCE_ID}
export RECOMMENDATIONS_RESOURCE_ID=${RECOMMENDATIONS_RESOURCE_ID}
export USER_RESOURCE_ID=${USER_RESOURCE_ID}
EOF
}

# Function to configure API Gateway method and integration
configure_api_gateway() {
    log "Configuring API Gateway method and integration..."
    
    # Check if GET method exists
    if aws apigateway get-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${USER_RESOURCE_ID}" \
        --http-method GET &>/dev/null; then
        warn "GET method already exists"
    else
        # Create GET method
        aws apigateway put-method \
            --rest-api-id "${API_ID}" \
            --resource-id "${USER_RESOURCE_ID}" \
            --http-method GET \
            --authorization-type NONE \
            --request-parameters method.request.path.userId=true
        
        log "GET method created"
    fi
    
    # Check if integration exists
    if aws apigateway get-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${USER_RESOURCE_ID}" \
        --http-method GET &>/dev/null; then
        warn "Integration already exists"
    else
        # Create Lambda integration
        aws apigateway put-integration \
            --rest-api-id "${API_ID}" \
            --resource-id "${USER_RESOURCE_ID}" \
            --http-method GET \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}/invocations"
        
        log "Lambda integration created"
    fi
    
    # Add Lambda permission for API Gateway
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id allow-apigateway \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" \
        2>/dev/null || warn "Lambda permission already exists"
    
    log "API Gateway configuration completed"
}

# Function to deploy API Gateway
deploy_api_gateway() {
    log "Deploying API Gateway to production stage..."
    
    # Create deployment
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --description "Production deployment of recommendation API"
    
    # Get API endpoint URL
    export API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log "API deployed successfully"
    info "API URL: ${API_URL}"
    info "Test endpoint: ${API_URL}/recommendations/{userId}"
    
    # Add to env file
    echo "export API_URL=${API_URL}" >> .env
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Enable detailed metrics for API Gateway
    aws apigateway put-stage \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --patch-ops op=replace,path=//*/*/metrics/enabled,value=true \
        2>/dev/null || warn "Could not enable detailed metrics"
    
    # Create CloudWatch alarm for API errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "RecommendationAPI-4xxErrors-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor 4xx errors in recommendation API" \
        --metric-name 4XXError \
        --namespace AWS/ApiGateway \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=ApiName,Value="${API_NAME}" \
        2>/dev/null || warn "Could not create CloudWatch alarm"
    
    log "CloudWatch monitoring configured"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test Personalize campaign directly
    info "Testing Personalize campaign..."
    if aws personalize-runtime get-recommendations \
        --campaign-arn "${CAMPAIGN_ARN}" \
        --user-id user1 \
        --num-results 5 >/dev/null; then
        log "Personalize campaign test: PASSED"
    else
        warn "Personalize campaign test: FAILED"
    fi
    
    # Test API Gateway endpoint
    info "Testing API Gateway endpoint..."
    if command -v curl &> /dev/null; then
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
            "${API_URL}/recommendations/user1?numResults=5")
        
        if [[ "$RESPONSE" == "200" ]]; then
            log "API Gateway test: PASSED"
        else
            warn "API Gateway test: FAILED (HTTP $RESPONSE)"
        fi
    else
        warn "curl not available, skipping API test"
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f personalize-trust-policy.json
    rm -f interactions-schema.json
    rm -f sample-interactions.csv
    rm -f recommendation-handler.py
    rm -f recommendation-handler.zip
    rm -f lambda-trust-policy.json
    
    log "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Real-time Recommendation System..."
    
    # Check for dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be created"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create resources
    create_s3_bucket
    create_personalize_iam_role
    upload_training_data
    create_personalize_resources
    create_dataset_and_import
    create_solution_and_train
    
    # Wait for training to complete
    wait_for_solution_version
    
    # Create campaign and API
    create_campaign
    create_lambda_function
    create_api_gateway
    configure_api_gateway
    deploy_api_gateway
    configure_monitoring
    
    # Test deployment
    test_deployment
    
    # Clean up temporary files
    cleanup_temp_files
    
    log "Deployment completed successfully!"
    log "================================================"
    log "DEPLOYMENT SUMMARY:"
    log "API URL: ${API_URL}"
    log "Test endpoint: ${API_URL}/recommendations/user1"
    log "Environment variables saved to: .env"
    log "================================================"
    
    info "To test the API, run:"
    info "curl -X GET '${API_URL}/recommendations/user1?numResults=5'"
    
    warn "Remember to run destroy.sh to clean up resources and avoid charges"
}

# Run main function
main "$@"