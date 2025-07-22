#!/bin/bash

# Database Connection Pooling with RDS Proxy - Deployment Script
# This script deploys a complete RDS Proxy setup with connection pooling

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=false

# Default values
DEFAULT_DB_NAME="testdb"
DEFAULT_DB_USER="admin"
DEFAULT_DB_PASSWORD="MySecurePassword123!"

# Helper functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy RDS Proxy with connection pooling demonstration

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -r, --region REGION    AWS region (default: current configured region)
    --db-name NAME         Database name (default: $DEFAULT_DB_NAME)
    --db-user USER         Database username (default: $DEFAULT_DB_USER)
    --db-password PASS     Database password (default: $DEFAULT_DB_PASSWORD)
    --skip-vpc             Skip VPC creation (use existing VPC)
    --vpc-id VPC_ID        Use existing VPC ID
    --subnet-ids IDS       Comma-separated subnet IDs (requires --vpc-id)

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --dry-run                         # Show deployment plan
    $0 --region us-west-2                # Deploy to specific region
    $0 --db-password "MyCustomPass123!"  # Use custom password

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --db-name)
                DB_NAME="$2"
                shift 2
                ;;
            --db-user)
                DB_USER="$2"
                shift 2
                ;;
            --db-password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --skip-vpc)
                SKIP_VPC=true
                shift
                ;;
            --vpc-id)
                VPC_ID="$2"
                shift 2
                ;;
            --subnet-ids)
                SUBNET_IDS="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure'."
    fi

    # Check AWS region
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            error "AWS region not configured. Use --region option or run 'aws configure'."
        fi
    fi

    # Check if region supports RDS Proxy
    local supported_regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-central-1" "ap-northeast-1" "ap-southeast-1" "ap-southeast-2")
    if [[ ! " ${supported_regions[@]} " =~ " ${AWS_REGION} " ]]; then
        warn "Region ${AWS_REGION} may not support RDS Proxy. Please verify before proceeding."
    fi

    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    log "Prerequisites check passed"
    info "AWS Account: $AWS_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
}

# Generate unique identifiers
generate_identifiers() {
    log "Generating unique identifiers..."

    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

    # Resource identifiers
    export DB_NAME="${DB_NAME:-$DEFAULT_DB_NAME}"
    export DB_USER="${DB_USER:-$DEFAULT_DB_USER}"
    export DB_PASSWORD="${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}"
    export DB_INSTANCE_ID="rds-proxy-demo-${RANDOM_SUFFIX}"
    export PROXY_NAME="rds-proxy-demo-${RANDOM_SUFFIX}"
    export SECRET_NAME="rds-proxy-secret-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="rds-proxy-test-${RANDOM_SUFFIX}"

    info "Generated resource suffix: $RANDOM_SUFFIX"
}

# Create VPC and networking resources
create_networking() {
    if [ "$SKIP_VPC" = true ]; then
        log "Skipping VPC creation (using existing resources)"
        if [ -z "$VPC_ID" ] || [ -z "$SUBNET_IDS" ]; then
            error "When skipping VPC creation, you must provide --vpc-id and --subnet-ids"
        fi
        IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
        export SUBNET_ID_1="${SUBNET_ARRAY[0]}"
        export SUBNET_ID_2="${SUBNET_ARRAY[1]}"
        return
    fi

    log "Creating VPC and networking resources..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create VPC with CIDR 10.0.0.0/16"
        info "[DRY RUN] Would create two subnets in different AZs"
        info "[DRY RUN] Would create DB subnet group"
        return
    fi

    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)

    aws ec2 create-tags \
        --resources "$VPC_ID" \
        --tags Key=Name,Value="rds-proxy-vpc-${RANDOM_SUFFIX}"

    # Wait for VPC to be available
    aws ec2 wait vpc-available --vpc-ids "$VPC_ID"

    # Create subnets in different AZs
    export SUBNET_ID_1=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)

    export SUBNET_ID_2=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --query 'Subnet.SubnetId' --output text)

    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "rds-proxy-subnet-group-${RANDOM_SUFFIX}" \
        --db-subnet-group-description "Subnet group for RDS Proxy demo" \
        --subnet-ids "$SUBNET_ID_1" "$SUBNET_ID_2"

    log "✅ VPC and networking resources created"
    info "VPC ID: $VPC_ID"
    info "Subnet 1: $SUBNET_ID_1"
    info "Subnet 2: $SUBNET_ID_2"
}

# Create security groups
create_security_groups() {
    log "Creating security groups..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create security groups for RDS and RDS Proxy"
        info "[DRY RUN] Would configure security group rules for MySQL access"
        return
    fi

    # Create security group for RDS instance
    export DB_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "rds-proxy-db-sg-${RANDOM_SUFFIX}" \
        --description "Security group for RDS instance" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)

    # Create security group for RDS Proxy
    export PROXY_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "rds-proxy-sg-${RANDOM_SUFFIX}" \
        --description "Security group for RDS Proxy" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)

    # Allow RDS Proxy to connect to RDS instance
    aws ec2 authorize-security-group-ingress \
        --group-id "$DB_SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 3306 \
        --source-group "$PROXY_SECURITY_GROUP_ID"

    # Allow Lambda/applications to connect to RDS Proxy
    aws ec2 authorize-security-group-ingress \
        --group-id "$PROXY_SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 3306 \
        --cidr 10.0.0.0/16

    log "✅ Security groups created and configured"
}

# Create RDS instance
create_rds_instance() {
    log "Creating RDS MySQL instance..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create RDS MySQL instance: $DB_INSTANCE_ID"
        info "[DRY RUN] Instance class: db.t3.micro"
        info "[DRY RUN] Storage: 20 GB, encrypted"
        return
    fi

    aws rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username "$DB_USER" \
        --master-user-password "$DB_PASSWORD" \
        --allocated-storage 20 \
        --vpc-security-group-ids "$DB_SECURITY_GROUP_ID" \
        --db-subnet-group-name "rds-proxy-subnet-group-${RANDOM_SUFFIX}" \
        --backup-retention-period 7 \
        --storage-encrypted \
        --no-publicly-accessible

    log "⏳ Creating RDS instance (this will take 10-15 minutes)..."

    # Wait for the RDS instance to be available
    aws rds wait db-instance-available \
        --db-instance-identifier "$DB_INSTANCE_ID"

    # Get RDS instance endpoint
    export DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].Endpoint.Address' --output text)

    log "✅ RDS instance created: $DB_ENDPOINT"
}

# Store database credentials in Secrets Manager
create_secret() {
    log "Storing database credentials in Secrets Manager..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create secret: $SECRET_NAME"
        info "[DRY RUN] Would store database credentials"
        return
    fi

    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Database credentials for RDS Proxy demo" \
        --secret-string "{\"username\":\"$DB_USER\",\"password\":\"$DB_PASSWORD\"}"

    # Get secret ARN
    export SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET_NAME" \
        --query 'ARN' --output text)

    log "✅ Database credentials stored in Secrets Manager"
}

# Create IAM role for RDS Proxy
create_iam_role() {
    log "Creating IAM role for RDS Proxy..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create IAM role: RDSProxyRole-${RANDOM_SUFFIX}"
        info "[DRY RUN] Would attach Secrets Manager access policy"
        return
    fi

    # Create trust policy
    cat > /tmp/rds-proxy-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "rds.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create the IAM role
    aws iam create-role \
        --role-name "RDSProxyRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/rds-proxy-trust-policy.json

    # Create policy for accessing Secrets Manager
    cat > /tmp/rds-proxy-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "$SECRET_ARN"
        }
    ]
}
EOF

    # Create and attach the policy
    aws iam create-policy \
        --policy-name "RDSProxySecretsPolicy-${RANDOM_SUFFIX}" \
        --policy-document file:///tmp/rds-proxy-policy.json

    aws iam attach-role-policy \
        --role-name "RDSProxyRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/RDSProxySecretsPolicy-${RANDOM_SUFFIX}"

    # Get role ARN
    export PROXY_ROLE_ARN=$(aws iam get-role \
        --role-name "RDSProxyRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)

    log "✅ IAM role created for RDS Proxy"
}

# Create RDS Proxy
create_rds_proxy() {
    log "Creating RDS Proxy..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create RDS Proxy: $PROXY_NAME"
        info "[DRY RUN] Would configure connection pooling settings"
        return
    fi

    aws rds create-db-proxy \
        --db-proxy-name "$PROXY_NAME" \
        --engine-family MYSQL \
        --auth '{
            "AuthScheme": "SECRETS",
            "SecretArn": "'"$SECRET_ARN"'",
            "Description": "Database authentication for RDS Proxy"
        }' \
        --role-arn "$PROXY_ROLE_ARN" \
        --vpc-subnet-ids "$SUBNET_ID_1" "$SUBNET_ID_2" \
        --vpc-security-group-ids "$PROXY_SECURITY_GROUP_ID" \
        --idle-client-timeout 1800 \
        --max-connections-percent 100 \
        --max-idle-connections-percent 50

    log "⏳ Creating RDS Proxy (this will take 3-5 minutes)..."

    # Wait for proxy to be available
    aws rds wait db-proxy-available --db-proxy-name "$PROXY_NAME"

    # Get proxy endpoint
    export PROXY_ENDPOINT=$(aws rds describe-db-proxies \
        --db-proxy-name "$PROXY_NAME" \
        --query 'DBProxies[0].Endpoint' --output text)

    log "✅ RDS Proxy created: $PROXY_ENDPOINT"
}

# Register database target with RDS Proxy
register_proxy_target() {
    log "Registering database target with RDS Proxy..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would register RDS instance as proxy target"
        return
    fi

    aws rds register-db-proxy-targets \
        --db-proxy-name "$PROXY_NAME" \
        --db-instance-identifiers "$DB_INSTANCE_ID"

    # Wait for target to be available
    sleep 30

    log "✅ Database target registered with RDS Proxy"
}

# Create Lambda function for testing
create_lambda_function() {
    log "Creating Lambda function for testing..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        info "[DRY RUN] Would configure VPC access and environment variables"
        return
    fi

    # Create Lambda execution role
    cat > /tmp/lambda-trust-policy.json << EOF
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

    aws iam create-role \
        --role-name "LambdaRDSProxyRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json

    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "LambdaRDSProxyRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"

    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "LambdaRDSProxyRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)

    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import pymysql
import os

def lambda_handler(event, context):
    try:
        # Connect to database through RDS Proxy
        connection = pymysql.connect(
            host=os.environ['PROXY_ENDPOINT'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            database=os.environ['DB_NAME'],
            port=3306,
            cursorclass=pymysql.cursors.DictCursor
        )
        
        with connection.cursor() as cursor:
            # Execute a simple query
            cursor.execute("SELECT 1 as connection_test, CONNECTION_ID() as connection_id")
            result = cursor.fetchone()
            
        connection.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully connected through RDS Proxy',
                'result': result
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF

    # Create deployment package
    cd /tmp
    zip lambda_function.zip lambda_function.py

    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --timeout 30 \
        --environment Variables="{
            PROXY_ENDPOINT=$PROXY_ENDPOINT,
            DB_USER=$DB_USER,
            DB_PASSWORD=$DB_PASSWORD,
            DB_NAME=$DB_NAME
        }" \
        --vpc-config SubnetIds="$SUBNET_ID_1","$SUBNET_ID_2",SecurityGroupIds="$PROXY_SECURITY_GROUP_ID"

    log "✅ Lambda function created for testing"
}

# Optimize connection pooling settings
optimize_proxy_settings() {
    log "Optimizing connection pooling settings..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would optimize proxy connection pooling settings"
        info "[DRY RUN] Would enable debug logging"
        return
    fi

    # Modify proxy configuration for optimal connection pooling
    aws rds modify-db-proxy \
        --db-proxy-name "$PROXY_NAME" \
        --idle-client-timeout 900 \
        --max-connections-percent 75 \
        --max-idle-connections-percent 25

    # Wait for modification to complete
    sleep 30

    # Enable enhanced monitoring
    aws rds modify-db-proxy \
        --db-proxy-name "$PROXY_NAME" \
        --debug-logging

    log "✅ Connection pooling settings optimized"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."

    cat > "${SCRIPT_DIR}/deployment-info.txt" << EOF
RDS Proxy Deployment Information
================================

Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID
Resource Suffix: $RANDOM_SUFFIX

Resources Created:
- VPC ID: $VPC_ID
- Subnet 1: $SUBNET_ID_1
- Subnet 2: $SUBNET_ID_2
- DB Security Group: $DB_SECURITY_GROUP_ID
- Proxy Security Group: $PROXY_SECURITY_GROUP_ID
- RDS Instance: $DB_INSTANCE_ID
- RDS Endpoint: $DB_ENDPOINT
- RDS Proxy: $PROXY_NAME
- Proxy Endpoint: $PROXY_ENDPOINT
- Secret Name: $SECRET_NAME
- Secret ARN: $SECRET_ARN
- Lambda Function: $LAMBDA_FUNCTION_NAME

IAM Roles:
- RDS Proxy Role: RDSProxyRole-${RANDOM_SUFFIX}
- Lambda Role: LambdaRDSProxyRole-${RANDOM_SUFFIX}

Connection Information:
- Database Name: $DB_NAME
- Database User: $DB_USER
- Connect via Proxy: $PROXY_ENDPOINT:3306

Cleanup Command:
./destroy.sh --suffix $RANDOM_SUFFIX
EOF

    log "✅ Deployment information saved to ${SCRIPT_DIR}/deployment-info.txt"
}

# Test the deployment
test_deployment() {
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would test Lambda function connectivity"
        return
    fi

    log "Testing deployment..."

    # Test Lambda function
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{}' \
        /tmp/lambda_test_response.json

    if [ $? -eq 0 ]; then
        log "✅ Lambda function test completed"
        info "Response saved to /tmp/lambda_test_response.json"
    else
        warn "Lambda function test failed"
    fi
}

# Main deployment function
main() {
    log "Starting RDS Proxy deployment..."

    if [ "$DRY_RUN" = true ]; then
        info "Running in DRY RUN mode - no resources will be created"
    fi

    check_prerequisites
    generate_identifiers
    create_networking
    create_security_groups
    create_rds_instance
    create_secret
    create_iam_role
    create_rds_proxy
    register_proxy_target
    create_lambda_function
    optimize_proxy_settings

    if [ "$DRY_RUN" = false ]; then
        save_deployment_info
        test_deployment
    fi

    log "🎉 RDS Proxy deployment completed successfully!"

    if [ "$DRY_RUN" = false ]; then
        echo ""
        echo "========================="
        echo "Deployment Summary"
        echo "========================="
        echo "RDS Proxy Endpoint: $PROXY_ENDPOINT"
        echo "Database Name: $DB_NAME"
        echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
        echo ""
        echo "Next Steps:"
        echo "1. Test the Lambda function: aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{}' response.json"
        echo "2. Monitor CloudWatch metrics for connection pooling behavior"
        echo "3. Review deployment-info.txt for complete resource list"
        echo ""
        echo "To clean up: ./destroy.sh --suffix $RANDOM_SUFFIX"
    fi
}

# Cleanup temporary files on exit
cleanup() {
    rm -f /tmp/rds-proxy-*.json /tmp/lambda-trust-policy.json /tmp/lambda_function.* 2>/dev/null || true
}

trap cleanup EXIT

# Parse arguments and run main function
parse_args "$@"
main