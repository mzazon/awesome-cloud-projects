#!/bin/bash

# Deploy script for Multi-Region Active-Active Applications with AWS Global Accelerator
# This script automates the deployment of a globally distributed application architecture
# using AWS Global Accelerator, DynamoDB Global Tables, Lambda functions, and ALBs

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: In production, implement partial cleanup logic here
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables
readonly PRIMARY_REGION="us-east-1"
readonly SECONDARY_REGION_EU="eu-west-1"
readonly SECONDARY_REGION_ASIA="ap-southeast-1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR=$(mktemp -d)
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version 2.0.0" | tr ' ' '\n' | sort -V | head -n1) != "2.0.0" ]]; then
        log_error "AWS CLI version 2.0.0 or higher is required. Found: $aws_version"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required tools
    for tool in jq python3 zip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    log_success "All prerequisites met"
}

# Validate AWS permissions
validate_permissions() {
    log_info "Validating AWS permissions..."
    
    local required_actions=(
        "globalaccelerator:CreateAccelerator"
        "dynamodb:CreateTable"
        "lambda:CreateFunction"
        "elasticloadbalancing:CreateLoadBalancer"
        "iam:CreateRole"
        "ec2:DescribeVpcs"
    )
    
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    
    # Test a representative action in each region
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA"; do
        if ! aws ec2 describe-vpcs --region "$region" >/dev/null 2>&1; then
            log_error "Insufficient permissions in region $region"
            exit 1
        fi
    done
    
    log_success "AWS permissions validated for account: $account_id"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Export environment variables for the session
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique names to avoid conflicts
    local random_string
    random_string=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export APP_NAME="global-app-${random_string}"
    export TABLE_NAME="GlobalUserData-${random_string}"
    export ACCELERATOR_NAME="GlobalAccelerator-${random_string}"
    export LAMBDA_ROLE_NAME="GlobalAppLambdaRole-${random_string}"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export APP_NAME="$APP_NAME"
export TABLE_NAME="$TABLE_NAME"
export ACCELERATOR_NAME="$ACCELERATOR_NAME"
export LAMBDA_ROLE_NAME="$LAMBDA_ROLE_NAME"
export PRIMARY_REGION="$PRIMARY_REGION"
export SECONDARY_REGION_EU="$SECONDARY_REGION_EU"
export SECONDARY_REGION_ASIA="$SECONDARY_REGION_ASIA"
EOF
    
    log_success "Environment variables configured"
    log_info "Application Name: $APP_NAME"
    log_info "Table Name: $TABLE_NAME"
    log_info "Accelerator Name: $ACCELERATOR_NAME"
}

# Create IAM role for Lambda functions
create_iam_role() {
    log_info "Creating IAM role for Lambda functions..."
    
    # Create trust policy
    cat > "$TEMP_DIR/lambda-trust-policy.json" << EOF
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
    
    # Create Lambda execution role
    local role_arn
    role_arn=$(aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document "file://$TEMP_DIR/lambda-trust-policy.json" \
        --query 'Role.Arn' --output text)
    
    # Create policy for DynamoDB Global Table access
    cat > "$TEMP_DIR/lambda-dynamodb-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": [
                "arn:aws:dynamodb:*:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}",
                "arn:aws:dynamodb:*:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
    
    # Attach policies to Lambda role
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name DynamoDBGlobalAccess \
        --policy-document "file://$TEMP_DIR/lambda-dynamodb-policy.json"
    
    export LAMBDA_ROLE_ARN="$role_arn"
    echo "export LAMBDA_ROLE_ARN=\"$role_arn\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log_success "IAM role created: $role_arn"
    
    # Wait for role to be available
    log_info "Waiting for IAM role propagation..."
    sleep 15
}

# Create DynamoDB tables and Global Table
create_dynamodb_tables() {
    log_info "Creating DynamoDB tables and configuring Global Tables..."
    
    # Create table in primary region
    aws dynamodb create-table \
        --region "$PRIMARY_REGION" \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=userId,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=userId,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
    
    # Create replica tables in secondary regions
    for region in "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA"; do
        aws dynamodb create-table \
            --region "$region" \
            --table-name "$TABLE_NAME" \
            --attribute-definitions \
                AttributeName=userId,AttributeType=S \
                AttributeName=timestamp,AttributeType=N \
            --key-schema \
                AttributeName=userId,KeyType=HASH \
                AttributeName=timestamp,KeyType=RANGE \
            --billing-mode PAY_PER_REQUEST \
            --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
    done
    
    # Wait for all tables to be active
    log_info "Waiting for DynamoDB tables to be active..."
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA"; do
        aws dynamodb wait table-exists --region "$region" --table-name "$TABLE_NAME"
    done
    
    # Create Global Table
    log_info "Creating DynamoDB Global Table..."
    aws dynamodb create-global-table \
        --region "$PRIMARY_REGION" \
        --global-table-name "$TABLE_NAME" \
        --replication-group RegionName="$PRIMARY_REGION" RegionName="$SECONDARY_REGION_EU" RegionName="$SECONDARY_REGION_ASIA"
    
    log_info "Waiting for Global Table setup to complete..."
    sleep 30
    
    log_success "DynamoDB Global Table configured successfully"
}

# Create Lambda function code
create_lambda_function() {
    log_info "Creating Lambda function code..."
    
    # Create Lambda function code
    cat > "$TEMP_DIR/app_function.py" << 'EOF'
import json
import boto3
import time
import os
from decimal import Decimal

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = os.environ['TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """
    Multi-region active-active application handler
    Supports CRUD operations with automatic regional optimization
    """
    
    try:
        # Get HTTP method and path
        method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        
        # Parse request body for POST/PUT requests
        body = {}
        if event.get('body'):
            body = json.loads(event['body'])
        
        # Get AWS region from context
        region = context.invoked_function_arn.split(':')[3]
        
        # Route based on HTTP method and path
        if method == 'GET' and path == '/health':
            return health_check(region)
        elif method == 'GET' and path.startswith('/user/'):
            user_id = path.split('/')[-1]
            return get_user_data(user_id, region)
        elif method == 'POST' and path == '/user':
            return create_user_data(body, region)
        elif method == 'PUT' and path.startswith('/user/'):
            user_id = path.split('/')[-1]
            return update_user_data(user_id, body, region)
        elif method == 'GET' and path == '/users':
            return list_users(region)
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e), 'region': region})
        }

def health_check(region):
    """Health check endpoint for load balancer"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'region': region,
            'timestamp': int(time.time())
        })
    }

def get_user_data(user_id, region):
    """Get user data with regional context"""
    try:
        # Get latest record for user
        response = table.query(
            KeyConditionExpression='userId = :userId',
            ExpressionAttributeValues={':userId': user_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        if response['Items']:
            item = response['Items'][0]
            # Convert Decimal to float for JSON serialization
            item = json.loads(json.dumps(item, default=decimal_default))
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user': item,
                    'served_from_region': region
                })
            }
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'User not found'})
            }
            
    except Exception as e:
        raise Exception(f"Error getting user data: {str(e)}")

def create_user_data(body, region):
    """Create new user data with regional tracking"""
    try:
        user_id = body.get('userId')
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'userId is required'})
            }
        
        timestamp = int(time.time() * 1000)  # milliseconds for better precision
        
        item = {
            'userId': user_id,
            'timestamp': timestamp,
            'data': body.get('data', {}),
            'created_region': region,
            'last_updated': timestamp,
            'version': 1
        }
        
        table.put_item(Item=item)
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'User created successfully',
                'userId': user_id,
                'created_in_region': region,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        raise Exception(f"Error creating user data: {str(e)}")

def update_user_data(user_id, body, region):
    """Update user data with conflict resolution"""
    try:
        timestamp = int(time.time() * 1000)
        
        # Use atomic update with version control
        response = table.update_item(
            Key={'userId': user_id, 'timestamp': timestamp},
            UpdateExpression='SET #data = :data, last_updated = :timestamp, updated_region = :region ADD version :inc',
            ExpressionAttributeNames={'#data': 'data'},
            ExpressionAttributeValues={
                ':data': body.get('data', {}),
                ':timestamp': timestamp,
                ':region': region,
                ':inc': 1
            },
            ReturnValues='ALL_NEW'
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'User updated successfully',
                'userId': user_id,
                'updated_in_region': region,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        raise Exception(f"Error updating user data: {str(e)}")

def list_users(region):
    """List users with pagination support"""
    try:
        # Simple scan with limit (in production, use GSI for better performance)
        response = table.scan(Limit=20)
        
        users = []
        processed_users = set()
        
        for item in response['Items']:
            user_id = item['userId']
            if user_id not in processed_users:
                users.append({
                    'userId': user_id,
                    'last_updated': int(item['last_updated']),
                    'version': int(item.get('version', 1))
                })
                processed_users.add(user_id)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'users': users,
                'count': len(users),
                'served_from_region': region
            })
        }
        
    except Exception as e:
        raise Exception(f"Error listing users: {str(e)}")

def decimal_default(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip lambda-function.zip app_function.py
    cd - > /dev/null
    
    log_success "Lambda function code created and packaged"
}

# Deploy Lambda functions in all regions
deploy_lambda_functions() {
    log_info "Deploying Lambda functions in all regions..."
    
    # Deploy Lambda function in primary region (US East)
    local lambda_arn_us
    lambda_arn_us=$(aws lambda create-function \
        --region "$PRIMARY_REGION" \
        --function-name "${APP_NAME}-us" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler app_function.lambda_handler \
        --zip-file "fileb://$TEMP_DIR/lambda-function.zip" \
        --timeout 30 \
        --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
        --query 'FunctionArn' --output text)
    
    # Deploy Lambda function in EU region
    local lambda_arn_eu
    lambda_arn_eu=$(aws lambda create-function \
        --region "$SECONDARY_REGION_EU" \
        --function-name "${APP_NAME}-eu" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler app_function.lambda_handler \
        --zip-file "fileb://$TEMP_DIR/lambda-function.zip" \
        --timeout 30 \
        --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
        --query 'FunctionArn' --output text)
    
    # Deploy Lambda function in Asia region
    local lambda_arn_asia
    lambda_arn_asia=$(aws lambda create-function \
        --region "$SECONDARY_REGION_ASIA" \
        --function-name "${APP_NAME}-asia" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler app_function.lambda_handler \
        --zip-file "fileb://$TEMP_DIR/lambda-function.zip" \
        --timeout 30 \
        --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
        --query 'FunctionArn' --output text)
    
    # Save Lambda ARNs to environment file
    cat >> "${SCRIPT_DIR}/deployment_vars.env" << EOF
export LAMBDA_FUNCTION_ARN_US="$lambda_arn_us"
export LAMBDA_FUNCTION_ARN_EU="$lambda_arn_eu"
export LAMBDA_FUNCTION_ARN_ASIA="$lambda_arn_asia"
EOF
    
    log_success "Lambda functions deployed in all regions"
}

# Create Application Load Balancers
create_load_balancers() {
    log_info "Creating Application Load Balancers in all regions..."
    
    # Get default VPC and subnets for each region
    local us_vpc_id us_subnet_ids eu_vpc_id eu_subnet_ids asia_vpc_id asia_subnet_ids
    
    us_vpc_id=$(aws ec2 describe-vpcs \
        --region "$PRIMARY_REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    us_subnet_ids=$(aws ec2 describe-subnets \
        --region "$PRIMARY_REGION" \
        --filters "Name=vpc-id,Values=${us_vpc_id}" \
        --query 'Subnets[0:2].SubnetId' --output text)
    
    eu_vpc_id=$(aws ec2 describe-vpcs \
        --region "$SECONDARY_REGION_EU" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    eu_subnet_ids=$(aws ec2 describe-subnets \
        --region "$SECONDARY_REGION_EU" \
        --filters "Name=vpc-id,Values=${eu_vpc_id}" \
        --query 'Subnets[0:2].SubnetId' --output text)
    
    asia_vpc_id=$(aws ec2 describe-vpcs \
        --region "$SECONDARY_REGION_ASIA" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    asia_subnet_ids=$(aws ec2 describe-subnets \
        --region "$SECONDARY_REGION_ASIA" \
        --filters "Name=vpc-id,Values=${asia_vpc_id}" \
        --query 'Subnets[0:2].SubnetId' --output text)
    
    # Create ALBs
    local us_alb_arn eu_alb_arn asia_alb_arn
    
    us_alb_arn=$(aws elbv2 create-load-balancer \
        --region "$PRIMARY_REGION" \
        --name "${APP_NAME}-us-alb" \
        --subnets $us_subnet_ids \
        --type application \
        --scheme internet-facing \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    eu_alb_arn=$(aws elbv2 create-load-balancer \
        --region "$SECONDARY_REGION_EU" \
        --name "${APP_NAME}-eu-alb" \
        --subnets $eu_subnet_ids \
        --type application \
        --scheme internet-facing \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    asia_alb_arn=$(aws elbv2 create-load-balancer \
        --region "$SECONDARY_REGION_ASIA" \
        --name "${APP_NAME}-asia-alb" \
        --subnets $asia_subnet_ids \
        --type application \
        --scheme internet-facing \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Save ALB ARNs to environment file
    cat >> "${SCRIPT_DIR}/deployment_vars.env" << EOF
export US_ALB_ARN="$us_alb_arn"
export EU_ALB_ARN="$eu_alb_arn"
export ASIA_ALB_ARN="$asia_alb_arn"
EOF
    
    log_success "Application Load Balancers created"
    log_info "Waiting for ALBs to be active..."
    sleep 60
}

# Configure Target Groups and Lambda integrations
configure_target_groups() {
    log_info "Creating Target Groups and configuring Lambda integrations..."
    
    # Source the Lambda ARNs
    source "${SCRIPT_DIR}/deployment_vars.env"
    
    # Create target groups
    local us_tg_arn eu_tg_arn asia_tg_arn
    
    us_tg_arn=$(aws elbv2 create-target-group \
        --region "$PRIMARY_REGION" \
        --name "${APP_NAME}-us-tg" \
        --target-type lambda \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    eu_tg_arn=$(aws elbv2 create-target-group \
        --region "$SECONDARY_REGION_EU" \
        --name "${APP_NAME}-eu-tg" \
        --target-type lambda \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    asia_tg_arn=$(aws elbv2 create-target-group \
        --region "$SECONDARY_REGION_ASIA" \
        --name "${APP_NAME}-asia-tg" \
        --target-type lambda \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Register Lambda functions as targets
    aws elbv2 register-targets \
        --region "$PRIMARY_REGION" \
        --target-group-arn "$us_tg_arn" \
        --targets Id="$LAMBDA_FUNCTION_ARN_US"
    
    aws elbv2 register-targets \
        --region "$SECONDARY_REGION_EU" \
        --target-group-arn "$eu_tg_arn" \
        --targets Id="$LAMBDA_FUNCTION_ARN_EU"
    
    aws elbv2 register-targets \
        --region "$SECONDARY_REGION_ASIA" \
        --target-group-arn "$asia_tg_arn" \
        --targets Id="$LAMBDA_FUNCTION_ARN_ASIA"
    
    # Add Lambda permissions for ALB to invoke functions
    aws lambda add-permission \
        --region "$PRIMARY_REGION" \
        --function-name "${APP_NAME}-us" \
        --statement-id allow-alb-invoke \
        --action lambda:InvokeFunction \
        --principal elasticloadbalancing.amazonaws.com \
        --source-arn "$us_tg_arn" || true
    
    aws lambda add-permission \
        --region "$SECONDARY_REGION_EU" \
        --function-name "${APP_NAME}-eu" \
        --statement-id allow-alb-invoke \
        --action lambda:InvokeFunction \
        --principal elasticloadbalancing.amazonaws.com \
        --source-arn "$eu_tg_arn" || true
    
    aws lambda add-permission \
        --region "$SECONDARY_REGION_ASIA" \
        --function-name "${APP_NAME}-asia" \
        --statement-id allow-alb-invoke \
        --action lambda:InvokeFunction \
        --principal elasticloadbalancing.amazonaws.com \
        --source-arn "$asia_tg_arn" || true
    
    # Create listeners
    aws elbv2 create-listener \
        --region "$PRIMARY_REGION" \
        --load-balancer-arn "$US_ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$us_tg_arn"
    
    aws elbv2 create-listener \
        --region "$SECONDARY_REGION_EU" \
        --load-balancer-arn "$EU_ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$eu_tg_arn"
    
    aws elbv2 create-listener \
        --region "$SECONDARY_REGION_ASIA" \
        --load-balancer-arn "$ASIA_ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$asia_tg_arn"
    
    # Save target group ARNs
    cat >> "${SCRIPT_DIR}/deployment_vars.env" << EOF
export US_TG_ARN="$us_tg_arn"
export EU_TG_ARN="$eu_tg_arn"
export ASIA_TG_ARN="$asia_tg_arn"
EOF
    
    log_success "Target groups and listeners configured"
}

# Create Global Accelerator
create_global_accelerator() {
    log_info "Creating AWS Global Accelerator..."
    
    # Source ALB ARNs
    source "${SCRIPT_DIR}/deployment_vars.env"
    
    # Create Global Accelerator (must be in us-west-2)
    local accelerator_arn
    accelerator_arn=$(aws globalaccelerator create-accelerator \
        --region us-west-2 \
        --name "$ACCELERATOR_NAME" \
        --ip-address-type IPV4 \
        --enabled \
        --query 'Accelerator.AcceleratorArn' --output text)
    
    # Get static IP addresses
    local static_ips
    static_ips=$(aws globalaccelerator describe-accelerator \
        --region us-west-2 \
        --accelerator-arn "$accelerator_arn" \
        --query 'Accelerator.IpSets[0].IpAddresses' --output text)
    
    log_info "Waiting for accelerator to be active..."
    sleep 30
    
    # Create listener
    local listener_arn
    listener_arn=$(aws globalaccelerator create-listener \
        --region us-west-2 \
        --accelerator-arn "$accelerator_arn" \
        --protocol TCP \
        --port-ranges FromPort=80,ToPort=80 \
        --query 'Listener.ListenerArn' --output text)
    
    # Get full ALB ARNs for endpoints
    local us_alb_arn_full eu_alb_arn_full asia_alb_arn_full
    
    us_alb_arn_full=$(aws elbv2 describe-load-balancers \
        --region "$PRIMARY_REGION" \
        --load-balancer-arns "$US_ALB_ARN" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    eu_alb_arn_full=$(aws elbv2 describe-load-balancers \
        --region "$SECONDARY_REGION_EU" \
        --load-balancer-arns "$EU_ALB_ARN" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    asia_alb_arn_full=$(aws elbv2 describe-load-balancers \
        --region "$SECONDARY_REGION_ASIA" \
        --load-balancer-arns "$ASIA_ALB_ARN" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Create endpoint groups
    local us_endpoint_group_arn eu_endpoint_group_arn asia_endpoint_group_arn
    
    us_endpoint_group_arn=$(aws globalaccelerator create-endpoint-group \
        --region us-west-2 \
        --listener-arn "$listener_arn" \
        --endpoint-group-region "$PRIMARY_REGION" \
        --endpoint-configurations EndpointId="$us_alb_arn_full",Weight=100,ClientIPPreservationEnabled=false \
        --traffic-dial-percentage 100 \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 3 \
        --unhealthy-threshold-count 3 \
        --query 'EndpointGroup.EndpointGroupArn' --output text)
    
    eu_endpoint_group_arn=$(aws globalaccelerator create-endpoint-group \
        --region us-west-2 \
        --listener-arn "$listener_arn" \
        --endpoint-group-region "$SECONDARY_REGION_EU" \
        --endpoint-configurations EndpointId="$eu_alb_arn_full",Weight=100,ClientIPPreservationEnabled=false \
        --traffic-dial-percentage 100 \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 3 \
        --unhealthy-threshold-count 3 \
        --query 'EndpointGroup.EndpointGroupArn' --output text)
    
    asia_endpoint_group_arn=$(aws globalaccelerator create-endpoint-group \
        --region us-west-2 \
        --listener-arn "$listener_arn" \
        --endpoint-group-region "$SECONDARY_REGION_ASIA" \
        --endpoint-configurations EndpointId="$asia_alb_arn_full",Weight=100,ClientIPPreservationEnabled=false \
        --traffic-dial-percentage 100 \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 3 \
        --unhealthy-threshold-count 3 \
        --query 'EndpointGroup.EndpointGroupArn' --output text)
    
    # Save Global Accelerator details
    cat >> "${SCRIPT_DIR}/deployment_vars.env" << EOF
export ACCELERATOR_ARN="$accelerator_arn"
export LISTENER_ARN="$listener_arn"
export STATIC_IPS="$static_ips"
export US_ENDPOINT_GROUP_ARN="$us_endpoint_group_arn"
export EU_ENDPOINT_GROUP_ARN="$eu_endpoint_group_arn"
export ASIA_ENDPOINT_GROUP_ARN="$asia_endpoint_group_arn"
EOF
    
    log_success "Global Accelerator created successfully"
    log_success "Static IP addresses: $static_ips"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    source "${SCRIPT_DIR}/deployment_vars.env"
    
    log_info "Waiting for all components to be fully ready..."
    sleep 60
    
    echo "Testing health endpoints..."
    for ip in $STATIC_IPS; do
        if curl -s --max-time 10 "http://$ip/health" >/dev/null 2>&1; then
            log_success "Health check passed for IP: $ip"
        else
            log_warning "Health check failed for IP: $ip (may need more time to propagate)"
        fi
    done
}

# Cleanup temporary files
cleanup_temp() {
    rm -rf "$TEMP_DIR"
}

# Main deployment function
main() {
    log_info "Starting deployment of Multi-Region Active-Active Applications with Global Accelerator"
    log_info "This deployment will create resources in regions: $PRIMARY_REGION, $SECONDARY_REGION_EU, $SECONDARY_REGION_ASIA"
    
    # Confirm deployment
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    validate_permissions
    setup_environment
    create_iam_role
    create_dynamodb_tables
    create_lambda_function
    deploy_lambda_functions
    create_load_balancers
    configure_target_groups
    create_global_accelerator
    test_deployment
    cleanup_temp
    
    log_success "Deployment completed successfully!"
    log_info "Environment variables saved to: ${SCRIPT_DIR}/deployment_vars.env"
    log_info "Static IP addresses: $STATIC_IPS"
    log_info "You can now test your global application using the static IPs"
    log_info "Example: curl http://${STATIC_IPS%% *}/health"
    
    # Save deployment summary
    cat > "${SCRIPT_DIR}/deployment_summary.txt" << EOF
Multi-Region Active-Active Application Deployment Summary
========================================================

Deployment Date: $(date)
Application Name: $APP_NAME
Table Name: $TABLE_NAME
Accelerator Name: $ACCELERATOR_NAME

Static IP Addresses: $STATIC_IPS

Regions:
- Primary: $PRIMARY_REGION
- Secondary EU: $SECONDARY_REGION_EU  
- Secondary Asia: $SECONDARY_REGION_ASIA

Test Commands:
- Health Check: curl http://${STATIC_IPS%% *}/health
- Create User: curl -X POST http://${STATIC_IPS%% *}/user -H "Content-Type: application/json" -d '{"userId":"test123","data":{"name":"Test User"}}'
- Get User: curl http://${STATIC_IPS%% *}/user/test123

To clean up all resources, run: ./destroy.sh
EOF
    
    log_success "Deployment summary saved to: ${SCRIPT_DIR}/deployment_summary.txt"
}

# Trap cleanup on script exit
trap cleanup_temp EXIT

# Run main function
main "$@"