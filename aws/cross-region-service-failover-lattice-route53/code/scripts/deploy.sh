#!/bin/bash

# =============================================================================
# Cross-Region Service Failover with VPC Lattice and Route53 - Deployment Script
# =============================================================================
# Description: Automated deployment of cross-region failover infrastructure
# Author: AWS Recipe Generator
# Version: 1.0
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="deploy_${TIMESTAMP}.log"
readonly PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
readonly SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Progress tracking
declare -i CURRENT_STEP=0
declare -i TOTAL_STEPS=12

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO: $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS: $*${NC}" | tee -a "$LOG_FILE"
}

progress() {
    ((CURRENT_STEP++))
    echo -e "${BLUE}[Step ${CURRENT_STEP}/${TOTAL_STEPS}] $*${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        warn "Check the log file: $LOG_FILE"
        warn "You may need to run destroy.sh to clean up partial resources"
    fi
    exit $exit_code
}

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install and configure AWS CLI."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        error "Could not retrieve AWS account ID."
        exit 1
    fi
    
    # Verify regions are available
    if ! aws ec2 describe-regions --region-names "$PRIMARY_REGION" "$SECONDARY_REGION" &> /dev/null; then
        error "One or both specified regions are not available."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

wait_for_resource() {
    local service="$1"
    local operation="$2"
    local resource_id="$3"
    local region="$4"
    local max_attempts="${5:-30}"
    local wait_time="${6:-10}"
    
    info "Waiting for $service $operation to complete for $resource_id in $region..."
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if eval "aws $service wait $operation --region $region $resource_id" 2>/dev/null; then
            success "$service $operation completed successfully"
            return 0
        fi
        
        info "Attempt $attempt/$max_attempts - waiting ${wait_time}s..."
        sleep "$wait_time"
        ((attempt++))
    done
    
    warn "$service $operation did not complete within expected time"
    return 1
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

initialize_environment() {
    progress "Initializing environment variables and generating unique identifiers"
    
    # Set AWS Account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffix
    export SERVICE_NETWORK_NAME="microservices-network-${RANDOM_SUFFIX}"
    export SERVICE_NAME="api-service-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="health-check-service-${RANDOM_SUFFIX}"
    export DOMAIN_NAME="api-${RANDOM_SUFFIX}.example.com"
    export IAM_ROLE_NAME="lambda-health-check-role-${RANDOM_SUFFIX}"
    
    log "Environment initialized:"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    log "  Primary Region: $PRIMARY_REGION"
    log "  Secondary Region: $SECONDARY_REGION"
    log "  Service Network: $SERVICE_NETWORK_NAME"
    log "  Function Name: $FUNCTION_NAME"
    log "  Domain Name: $DOMAIN_NAME"
    
    success "Environment initialization completed"
}

create_foundational_vpcs() {
    progress "Creating foundational VPCs in both regions"
    
    # Create primary VPC
    info "Creating primary VPC in $PRIMARY_REGION..."
    export PRIMARY_VPC_ID
    PRIMARY_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --region "$PRIMARY_REGION" \
        --tag-specifications \
        'ResourceType=vpc,Tags=[{Key=Name,Value=primary-vpc-lattice},{Key=Purpose,Value=cross-region-failover}]' \
        --query 'Vpc.VpcId' --output text)
    
    if [[ -z "$PRIMARY_VPC_ID" ]]; then
        error "Failed to create primary VPC"
        exit 1
    fi
    
    # Create secondary VPC
    info "Creating secondary VPC in $SECONDARY_REGION..."
    export SECONDARY_VPC_ID
    SECONDARY_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --region "$SECONDARY_REGION" \
        --tag-specifications \
        'ResourceType=vpc,Tags=[{Key=Name,Value=secondary-vpc-lattice},{Key=Purpose,Value=cross-region-failover}]' \
        --query 'Vpc.VpcId' --output text)
    
    if [[ -z "$SECONDARY_VPC_ID" ]]; then
        error "Failed to create secondary VPC"
        exit 1
    fi
    
    # Wait for VPCs to be available
    wait_for_resource "ec2" "vpc-available" "--vpc-ids $PRIMARY_VPC_ID" "$PRIMARY_REGION"
    wait_for_resource "ec2" "vpc-available" "--vpc-ids $SECONDARY_VPC_ID" "$SECONDARY_REGION"
    
    log "VPCs created successfully:"
    log "  Primary VPC: $PRIMARY_VPC_ID ($PRIMARY_REGION)"
    log "  Secondary VPC: $SECONDARY_VPC_ID ($SECONDARY_REGION)"
    
    success "Foundational VPCs created"
}

create_service_networks() {
    progress "Creating VPC Lattice Service Networks in both regions"
    
    # Create service network in primary region
    info "Creating service network in $PRIMARY_REGION..."
    aws vpc-lattice create-service-network \
        --name "$SERVICE_NETWORK_NAME" \
        --region "$PRIMARY_REGION" \
        --tags Key=Environment,Value=production Key=Region,Value=primary Key=Purpose,Value=cross-region-failover
    
    # Get primary service network ID
    export PRIMARY_SERVICE_NETWORK_ID
    PRIMARY_SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --region "$PRIMARY_REGION" \
        --query "items[?name=='$SERVICE_NETWORK_NAME'].id" \
        --output text)
    
    if [[ -z "$PRIMARY_SERVICE_NETWORK_ID" ]]; then
        error "Failed to retrieve primary service network ID"
        exit 1
    fi
    
    # Create service network in secondary region
    info "Creating service network in $SECONDARY_REGION..."
    aws vpc-lattice create-service-network \
        --name "$SERVICE_NETWORK_NAME" \
        --region "$SECONDARY_REGION" \
        --tags Key=Environment,Value=production Key=Region,Value=secondary Key=Purpose,Value=cross-region-failover
    
    # Get secondary service network ID
    export SECONDARY_SERVICE_NETWORK_ID
    SECONDARY_SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --region "$SECONDARY_REGION" \
        --query "items[?name=='$SERVICE_NETWORK_NAME'].id" \
        --output text)
    
    if [[ -z "$SECONDARY_SERVICE_NETWORK_ID" ]]; then
        error "Failed to retrieve secondary service network ID"
        exit 1
    fi
    
    log "Service networks created:"
    log "  Primary: $PRIMARY_SERVICE_NETWORK_ID ($PRIMARY_REGION)"
    log "  Secondary: $SECONDARY_SERVICE_NETWORK_ID ($SECONDARY_REGION)"
    
    success "VPC Lattice Service Networks created"
}

create_lambda_function_code() {
    progress "Creating Lambda function code for health checks"
    
    # Create temporary directory for Lambda code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create Lambda function code
    cat > "$temp_dir/health-check-function.py" << 'EOF'
import json
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    """
    Health check endpoint that validates service availability
    Returns HTTP 200 for healthy, 503 for unhealthy
    """
    region = os.environ.get('AWS_REGION', 'unknown')
    simulate_failure = os.environ.get('SIMULATE_FAILURE', 'false').lower()
    
    try:
        current_time = datetime.utcnow().isoformat()
        
        # Check for simulated failure from environment variable
        if simulate_failure == 'true':
            health_status = False
        else:
            # Add actual health validation logic here
            # Example: Check database connectivity, external APIs, etc.
            health_status = check_service_health()
        
        if health_status:
            response = {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'pass'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'region': region,
                    'timestamp': current_time,
                    'version': '1.0'
                })
            }
        else:
            response = {
                'statusCode': 503,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'fail'
                },
                'body': json.dumps({
                    'status': 'unhealthy',
                    'region': region,
                    'timestamp': current_time
                })
            }
            
        return response
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'status': 'error',
                'message': str(e),
                'region': region
            })
        }

def check_service_health():
    """
    Implement actual health check logic
    Returns True if healthy, False otherwise
    """
    # Example health checks:
    # - Database connectivity
    # - External API availability
    # - Cache service status
    # - Disk space checks
    return True
EOF
    
    # Package Lambda function
    info "Packaging Lambda function..."
    (cd "$temp_dir" && zip -q ../function.zip health-check-function.py)
    
    # Move zip file to current directory
    mv "$temp_dir/../function.zip" ./function.zip
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    if [[ ! -f "./function.zip" ]]; then
        error "Failed to create Lambda function package"
        exit 1
    fi
    
    success "Lambda function code packaged"
}

create_iam_role() {
    progress "Creating IAM role for Lambda execution"
    
    # Create trust policy
    cat > lambda-trust-policy.json << 'EOF'
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
    info "Creating IAM role: $IAM_ROLE_NAME"
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --tags Key=Purpose,Value=cross-region-failover Key=Service,Value=lambda
    
    # Attach basic execution policy
    info "Attaching basic execution policy..."
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Wait for role to propagate
    info "Waiting for IAM role to propagate..."
    sleep 15
    
    success "IAM role created and configured"
}

deploy_lambda_functions() {
    progress "Deploying Lambda functions in both regions"
    
    local role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
    
    # Deploy Lambda function in primary region
    info "Deploying Lambda function in $PRIMARY_REGION..."
    aws lambda create-function \
        --region "$PRIMARY_REGION" \
        --function-name "${FUNCTION_NAME}-primary" \
        --runtime python3.11 \
        --role "$role_arn" \
        --handler health-check-function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 256 \
        --tags Environment=production,Region=primary,Purpose=cross-region-failover
    
    # Deploy Lambda function in secondary region
    info "Deploying Lambda function in $SECONDARY_REGION..."
    aws lambda create-function \
        --region "$SECONDARY_REGION" \
        --function-name "${FUNCTION_NAME}-secondary" \
        --runtime python3.11 \
        --role "$role_arn" \
        --handler health-check-function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 256 \
        --tags Environment=production,Region=secondary,Purpose=cross-region-failover
    
    # Wait for functions to be active
    wait_for_resource "lambda" "function-active" "--function-name ${FUNCTION_NAME}-primary" "$PRIMARY_REGION"
    wait_for_resource "lambda" "function-active" "--function-name ${FUNCTION_NAME}-secondary" "$SECONDARY_REGION"
    
    success "Lambda functions deployed in both regions"
}

create_vpc_lattice_services() {
    progress "Creating VPC Lattice services and target groups"
    
    # Create target group for primary region Lambda
    info "Creating target group in $PRIMARY_REGION..."
    export PRIMARY_TARGET_GROUP_ID
    PRIMARY_TARGET_GROUP_ID=$(aws vpc-lattice create-target-group \
        --region "$PRIMARY_REGION" \
        --name "health-check-targets-primary-${RANDOM_SUFFIX}" \
        --type LAMBDA \
        --tags Key=Environment,Value=production Key=Region,Value=primary Key=Purpose,Value=cross-region-failover \
        --query 'id' --output text)
    
    if [[ -z "$PRIMARY_TARGET_GROUP_ID" ]]; then
        error "Failed to create primary target group"
        exit 1
    fi
    
    # Register Lambda function as target in primary region
    info "Registering Lambda function as target in $PRIMARY_REGION..."
    aws vpc-lattice register-targets \
        --region "$PRIMARY_REGION" \
        --target-group-identifier "$PRIMARY_TARGET_GROUP_ID" \
        --targets "id=arn:aws:lambda:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}-primary"
    
    # Create VPC Lattice service in primary region
    info "Creating VPC Lattice service in $PRIMARY_REGION..."
    export PRIMARY_SERVICE_ID
    PRIMARY_SERVICE_ID=$(aws vpc-lattice create-service \
        --region "$PRIMARY_REGION" \
        --name "${SERVICE_NAME}-primary" \
        --tags Key=Environment,Value=production Key=Region,Value=primary Key=Purpose,Value=cross-region-failover \
        --query 'id' --output text)
    
    if [[ -z "$PRIMARY_SERVICE_ID" ]]; then
        error "Failed to create primary service"
        exit 1
    fi
    
    # Create listener for primary service
    info "Creating listener for primary service..."
    aws vpc-lattice create-listener \
        --region "$PRIMARY_REGION" \
        --service-identifier "$PRIMARY_SERVICE_ID" \
        --name health-check-listener \
        --protocol HTTPS \
        --port 443 \
        --default-action "forward={targetGroups=[{targetGroupIdentifier=$PRIMARY_TARGET_GROUP_ID}]}" \
        --tags Key=Environment,Value=production Key=Region,Value=primary Key=Purpose,Value=cross-region-failover
    
    # Repeat for secondary region
    info "Creating target group in $SECONDARY_REGION..."
    export SECONDARY_TARGET_GROUP_ID
    SECONDARY_TARGET_GROUP_ID=$(aws vpc-lattice create-target-group \
        --region "$SECONDARY_REGION" \
        --name "health-check-targets-secondary-${RANDOM_SUFFIX}" \
        --type LAMBDA \
        --tags Key=Environment,Value=production Key=Region,Value=secondary Key=Purpose,Value=cross-region-failover \
        --query 'id' --output text)
    
    if [[ -z "$SECONDARY_TARGET_GROUP_ID" ]]; then
        error "Failed to create secondary target group"
        exit 1
    fi
    
    # Register Lambda function as target in secondary region
    info "Registering Lambda function as target in $SECONDARY_REGION..."
    aws vpc-lattice register-targets \
        --region "$SECONDARY_REGION" \
        --target-group-identifier "$SECONDARY_TARGET_GROUP_ID" \
        --targets "id=arn:aws:lambda:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}-secondary"
    
    # Create VPC Lattice service in secondary region
    info "Creating VPC Lattice service in $SECONDARY_REGION..."
    export SECONDARY_SERVICE_ID
    SECONDARY_SERVICE_ID=$(aws vpc-lattice create-service \
        --region "$SECONDARY_REGION" \
        --name "${SERVICE_NAME}-secondary" \
        --tags Key=Environment,Value=production Key=Region,Value=secondary Key=Purpose,Value=cross-region-failover \
        --query 'id' --output text)
    
    if [[ -z "$SECONDARY_SERVICE_ID" ]]; then
        error "Failed to create secondary service"
        exit 1
    fi
    
    # Create listener for secondary service
    info "Creating listener for secondary service..."
    aws vpc-lattice create-listener \
        --region "$SECONDARY_REGION" \
        --service-identifier "$SECONDARY_SERVICE_ID" \
        --name health-check-listener \
        --protocol HTTPS \
        --port 443 \
        --default-action "forward={targetGroups=[{targetGroupIdentifier=$SECONDARY_TARGET_GROUP_ID}]}" \
        --tags Key=Environment,Value=production Key=Region,Value=secondary Key=Purpose,Value=cross-region-failover
    
    success "VPC Lattice services and target groups created"
}

associate_services_with_networks() {
    progress "Associating services with service networks"
    
    # Associate primary service with service network
    info "Associating primary service with service network..."
    aws vpc-lattice create-service-network-service-association \
        --region "$PRIMARY_REGION" \
        --service-network-identifier "$PRIMARY_SERVICE_NETWORK_ID" \
        --service-identifier "$PRIMARY_SERVICE_ID" \
        --tags Key=Environment,Value=production Key=Region,Value=primary Key=Purpose,Value=cross-region-failover
    
    # Associate secondary service with service network
    info "Associating secondary service with service network..."
    aws vpc-lattice create-service-network-service-association \
        --region "$SECONDARY_REGION" \
        --service-network-identifier "$SECONDARY_SERVICE_NETWORK_ID" \
        --service-identifier "$SECONDARY_SERVICE_ID" \
        --tags Key=Environment,Value=production Key=Region,Value=secondary Key=Purpose,Value=cross-region-failover
    
    # Wait for services to be active
    info "Waiting for services to become active..."
    sleep 30
    
    # Get service DNS names for health checks
    export PRIMARY_SERVICE_DNS
    PRIMARY_SERVICE_DNS=$(aws vpc-lattice get-service \
        --region "$PRIMARY_REGION" \
        --service-identifier "$PRIMARY_SERVICE_ID" \
        --query 'dnsEntry.domainName' --output text)
    
    export SECONDARY_SERVICE_DNS
    SECONDARY_SERVICE_DNS=$(aws vpc-lattice get-service \
        --region "$SECONDARY_REGION" \
        --service-identifier "$SECONDARY_SERVICE_ID" \
        --query 'dnsEntry.domainName' --output text)
    
    if [[ -z "$PRIMARY_SERVICE_DNS" || -z "$SECONDARY_SERVICE_DNS" ]]; then
        error "Failed to retrieve service DNS names"
        exit 1
    fi
    
    log "Service DNS endpoints:"
    log "  Primary: $PRIMARY_SERVICE_DNS"
    log "  Secondary: $SECONDARY_SERVICE_DNS"
    
    success "Services associated with service networks"
}

create_route53_health_checks() {
    progress "Creating Route53 health checks"
    
    # Create health check for primary region
    info "Creating health check for primary region..."
    export PRIMARY_HEALTH_CHECK_ID
    PRIMARY_HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "primary-health-check-${RANDOM_SUFFIX}" \
        --health-check-config "{
            \"Type\": \"HTTPS\",
            \"ResourcePath\": \"/\",
            \"FullyQualifiedDomainName\": \"$PRIMARY_SERVICE_DNS\",
            \"Port\": 443,
            \"RequestInterval\": 30,
            \"FailureThreshold\": 3
        }" \
        --query 'HealthCheck.Id' --output text)
    
    if [[ -z "$PRIMARY_HEALTH_CHECK_ID" ]]; then
        error "Failed to create primary health check"
        exit 1
    fi
    
    # Tag the primary health check
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$PRIMARY_HEALTH_CHECK_ID" \
        --add-tags Key=Name,Value=primary-service-health Key=Region,Value="$PRIMARY_REGION" Key=Purpose,Value=cross-region-failover
    
    # Create health check for secondary region
    info "Creating health check for secondary region..."
    export SECONDARY_HEALTH_CHECK_ID
    SECONDARY_HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "secondary-health-check-${RANDOM_SUFFIX}" \
        --health-check-config "{
            \"Type\": \"HTTPS\",
            \"ResourcePath\": \"/\",
            \"FullyQualifiedDomainName\": \"$SECONDARY_SERVICE_DNS\",
            \"Port\": 443,
            \"RequestInterval\": 30,
            \"FailureThreshold\": 3
        }" \
        --query 'HealthCheck.Id' --output text)
    
    if [[ -z "$SECONDARY_HEALTH_CHECK_ID" ]]; then
        error "Failed to create secondary health check"
        exit 1
    fi
    
    # Tag the secondary health check
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$SECONDARY_HEALTH_CHECK_ID" \
        --add-tags Key=Name,Value=secondary-service-health Key=Region,Value="$SECONDARY_REGION" Key=Purpose,Value=cross-region-failover
    
    log "Route53 health checks created:"
    log "  Primary: $PRIMARY_HEALTH_CHECK_ID"
    log "  Secondary: $SECONDARY_HEALTH_CHECK_ID"
    
    success "Route53 health checks created"
}

create_dns_records() {
    progress "Creating Route53 hosted zone and DNS records"
    
    # Create hosted zone
    info "Creating hosted zone for $DOMAIN_NAME..."
    export HOSTED_ZONE_ID
    HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
        --name "$DOMAIN_NAME" \
        --caller-reference "failover-zone-${RANDOM_SUFFIX}" \
        --query 'HostedZone.Id' --output text | cut -d'/' -f3)
    
    if [[ -z "$HOSTED_ZONE_ID" ]]; then
        error "Failed to create hosted zone"
        exit 1
    fi
    
    # Create primary DNS record with failover routing
    info "Creating primary DNS failover record..."
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "{
            \"Comment\": \"Create primary failover record\",
            \"Changes\": [{
                \"Action\": \"CREATE\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$DOMAIN_NAME\",
                    \"Type\": \"CNAME\",
                    \"SetIdentifier\": \"primary\",
                    \"Failover\": \"PRIMARY\",
                    \"TTL\": 60,
                    \"ResourceRecords\": [{\"Value\": \"$PRIMARY_SERVICE_DNS\"}],
                    \"HealthCheckId\": \"$PRIMARY_HEALTH_CHECK_ID\"
                }
            }]
        }"
    
    # Create secondary DNS record with failover routing
    info "Creating secondary DNS failover record..."
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "{
            \"Comment\": \"Create secondary failover record\",
            \"Changes\": [{
                \"Action\": \"CREATE\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$DOMAIN_NAME\",
                    \"Type\": \"CNAME\",
                    \"SetIdentifier\": \"secondary\",
                    \"Failover\": \"SECONDARY\",
                    \"TTL\": 60,
                    \"ResourceRecords\": [{\"Value\": \"$SECONDARY_SERVICE_DNS\"}]
                }
            }]
        }"
    
    log "DNS configuration:"
    log "  Domain: $DOMAIN_NAME"
    log "  Hosted Zone: $HOSTED_ZONE_ID"
    
    success "DNS failover records created"
}

configure_monitoring() {
    progress "Configuring CloudWatch monitoring and alarms"
    
    # Create CloudWatch alarm for primary health check
    info "Creating CloudWatch alarm for primary health check..."
    aws cloudwatch put-metric-alarm \
        --region "$PRIMARY_REGION" \
        --alarm-name "Primary-Service-Health-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor primary region service health" \
        --metric-name HealthCheckStatus \
        --namespace AWS/Route53 \
        --statistic Minimum \
        --period 60 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=HealthCheckId,Value="$PRIMARY_HEALTH_CHECK_ID" \
        --tags Key=Purpose,Value=cross-region-failover Key=Region,Value=primary
    
    # Create CloudWatch alarm for secondary health check
    info "Creating CloudWatch alarm for secondary health check..."
    aws cloudwatch put-metric-alarm \
        --region "$SECONDARY_REGION" \
        --alarm-name "Secondary-Service-Health-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor secondary region service health" \
        --metric-name HealthCheckStatus \
        --namespace AWS/Route53 \
        --statistic Minimum \
        --period 60 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=HealthCheckId,Value="$SECONDARY_HEALTH_CHECK_ID" \
        --tags Key=Purpose,Value=cross-region-failover Key=Region,Value=secondary
    
    success "CloudWatch monitoring configured"
}

save_deployment_state() {
    progress "Saving deployment state for cleanup"
    
    # Create state file for cleanup script
    cat > deployment_state.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "random_suffix": "$RANDOM_SUFFIX",
    "primary_region": "$PRIMARY_REGION",
    "secondary_region": "$SECONDARY_REGION",
    "resources": {
        "vpcs": {
            "primary_vpc_id": "$PRIMARY_VPC_ID",
            "secondary_vpc_id": "$SECONDARY_VPC_ID"
        },
        "service_networks": {
            "primary_service_network_id": "$PRIMARY_SERVICE_NETWORK_ID",
            "secondary_service_network_id": "$SECONDARY_SERVICE_NETWORK_ID"
        },
        "services": {
            "primary_service_id": "$PRIMARY_SERVICE_ID",
            "secondary_service_id": "$SECONDARY_SERVICE_ID"
        },
        "target_groups": {
            "primary_target_group_id": "$PRIMARY_TARGET_GROUP_ID",
            "secondary_target_group_id": "$SECONDARY_TARGET_GROUP_ID"
        },
        "lambda_functions": {
            "primary_function_name": "${FUNCTION_NAME}-primary",
            "secondary_function_name": "${FUNCTION_NAME}-secondary"
        },
        "iam_role": {
            "role_name": "$IAM_ROLE_NAME"
        },
        "route53": {
            "hosted_zone_id": "$HOSTED_ZONE_ID",
            "primary_health_check_id": "$PRIMARY_HEALTH_CHECK_ID",
            "secondary_health_check_id": "$SECONDARY_HEALTH_CHECK_ID",
            "domain_name": "$DOMAIN_NAME",
            "primary_service_dns": "$PRIMARY_SERVICE_DNS",
            "secondary_service_dns": "$SECONDARY_SERVICE_DNS"
        },
        "cloudwatch_alarms": {
            "primary_alarm_name": "Primary-Service-Health-${RANDOM_SUFFIX}",
            "secondary_alarm_name": "Secondary-Service-Health-${RANDOM_SUFFIX}"
        }
    }
}
EOF
    
    success "Deployment state saved to deployment_state.json"
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    info "Starting Cross-Region Service Failover deployment"
    info "Script: $SCRIPT_NAME"
    info "Timestamp: $TIMESTAMP"
    info "Log file: $LOG_FILE"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_foundational_vpcs
    create_service_networks
    create_lambda_function_code
    create_iam_role
    deploy_lambda_functions
    create_vpc_lattice_services
    associate_services_with_networks
    create_route53_health_checks
    create_dns_records
    configure_monitoring
    save_deployment_state
    
    # Cleanup temporary files
    rm -f function.zip lambda-trust-policy.json
    
    # Display final status
    echo ""
    success "==================================================================="
    success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    success "==================================================================="
    echo ""
    info "Deployment Summary:"
    info "  Domain Name: $DOMAIN_NAME"
    info "  Primary Region: $PRIMARY_REGION ($PRIMARY_SERVICE_DNS)"
    info "  Secondary Region: $SECONDARY_REGION ($SECONDARY_SERVICE_DNS)"
    info "  Health Checks: $PRIMARY_HEALTH_CHECK_ID, $SECONDARY_HEALTH_CHECK_ID"
    info "  Hosted Zone: $HOSTED_ZONE_ID"
    echo ""
    warn "IMPORTANT NOTES:"
    warn "1. Health checks may take 2-3 minutes to show healthy status"
    warn "2. DNS propagation may take several minutes"
    warn "3. Update your DNS nameservers to point to the Route53 hosted zone"
    warn "4. Test failover by setting SIMULATE_FAILURE=true on the primary Lambda function"
    warn "5. Monitor CloudWatch alarms for health check status"
    warn "6. Run destroy.sh to clean up all resources when done"
    echo ""
    info "Log file: $LOG_FILE"
    info "State file: deployment_state.json"
    success "Deployment completed at $(date)"
}

# Run main function
main "$@"