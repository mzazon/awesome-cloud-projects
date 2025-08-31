#!/bin/bash

# Cross-Account Service Discovery with VPC Lattice and ECS - Deployment Script
# This script deploys VPC Lattice service network infrastructure for cross-account service discovery

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Cross-Account Service Discovery with VPC Lattice and ECS - Deployment Script

Usage: $0 [OPTIONS]

Options:
    -a, --account-b-id ID    AWS Account B ID for cross-account sharing (required)
    -r, --region REGION      AWS region (default: current configured region)
    -s, --suffix SUFFIX      Resource name suffix (default: auto-generated)
    -d, --dry-run           Show what would be deployed without making changes
    -h, --help              Show this help message

Example:
    $0 --account-b-id 123456789012
    $0 --account-b-id 123456789012 --region us-west-2 --suffix prod

Environment Variables:
    AWS_REGION              AWS region override
    ACCOUNT_B_ID           Account B ID for sharing
    RESOURCE_SUFFIX        Resource naming suffix

EOF
}

# Parse command line arguments
DRY_RUN=false
ACCOUNT_B_ID=""
AWS_REGION=""
RESOURCE_SUFFIX=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--account-b-id)
            ACCOUNT_B_ID="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -s|--suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check Account B ID
    if [[ -z "${ACCOUNT_B_ID}" ]]; then
        if [[ -n "${ACCOUNT_B_ID:-}" ]]; then
            ACCOUNT_B_ID="${ACCOUNT_B_ID}"
        else
            log_error "Account B ID is required. Use --account-b-id option or set ACCOUNT_B_ID environment variable."
            exit 1
        fi
    fi
    
    # Validate Account B ID format (12 digits)
    if [[ ! "${ACCOUNT_B_ID}" =~ ^[0-9]{12}$ ]]; then
        log_error "Invalid Account B ID format. Must be 12 digits."
        exit 1
    fi
    
    # Set AWS region
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not configured. Set it using aws configure or --region option."
            exit 1
        fi
    fi
    
    # Check if we can access VPC Lattice (availability in region)
    if ! aws vpc-lattice list-service-networks --region "${AWS_REGION}" &> /dev/null; then
        log_error "VPC Lattice is not available in region ${AWS_REGION} or you don't have permissions."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get account information
    export ACCOUNT_A_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION="${AWS_REGION}"
    export ACCOUNT_B_ID="${ACCOUNT_B_ID}"
    
    # Generate unique suffix if not provided
    if [[ -z "${RESOURCE_SUFFIX}" ]]; then
        RESOURCE_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export CLUSTER_NAME_A="producer-cluster-${RESOURCE_SUFFIX}"
    export SERVICE_NAME_A="producer-service-${RESOURCE_SUFFIX}"
    export LATTICE_SERVICE_A="lattice-producer-${RESOURCE_SUFFIX}"
    export SERVICE_NETWORK_NAME="cross-account-network-${RESOURCE_SUFFIX}"
    
    log_success "Environment configured"
    log "Account A ID: ${ACCOUNT_A_ID}"
    log "Account B ID: ${ACCOUNT_B_ID}"
    log "Region: ${AWS_REGION}"
    log "Resource Suffix: ${RESOURCE_SUFFIX}"
    log "Service Network: ${SERVICE_NETWORK_NAME}"
}

# Function to create IAM role if it doesn't exist
ensure_ecs_execution_role() {
    log "Checking ECS task execution role..."
    
    local role_name="ecsTaskExecutionRole"
    
    if ! aws iam get-role --role-name "${role_name}" &> /dev/null; then
        log "Creating ECS task execution role..."
        
        cat > /tmp/ecs-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            aws iam create-role \
                --role-name "${role_name}" \
                --assume-role-policy-document file:///tmp/ecs-trust-policy.json \
                --description "ECS Task Execution Role for VPC Lattice demo"
            
            aws iam attach-role-policy \
                --role-name "${role_name}" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
            
            # Wait for role to be available
            aws iam wait role-exists --role-name "${role_name}"
        fi
        
        rm -f /tmp/ecs-trust-policy.json
        log_success "ECS task execution role created"
    else
        log_success "ECS task execution role already exists"
    fi
}

# Function to create CloudWatch log groups
create_log_groups() {
    log "Creating CloudWatch log groups..."
    
    local log_groups=("/ecs/producer" "/aws/events/vpc-lattice")
    
    for log_group in "${log_groups[@]}"; do
        if ! aws logs describe-log-groups --log-group-name-prefix "${log_group}" --query 'logGroups[?logGroupName==`'${log_group}'`]' --output text | grep -q "${log_group}"; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                aws logs create-log-group \
                    --log-group-name "${log_group}" \
                    --retention-in-days 7
            fi
            log_success "Created log group: ${log_group}"
        else
            log "Log group already exists: ${log_group}"
        fi
    done
}

# Function to create VPC Lattice service network
create_service_network() {
    log "Creating VPC Lattice service network..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would create service network ${SERVICE_NETWORK_NAME}"
        export SERVICE_NETWORK_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${ACCOUNT_A_ID}:servicenetwork/dry-run-id"
        export SERVICE_NETWORK_ID="dry-run-id"
        return
    fi
    
    # Check if service network already exists
    if aws vpc-lattice list-service-networks --query "items[?name=='${SERVICE_NETWORK_NAME}'].arn" --output text | grep -q .; then
        export SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks --query "items[?name=='${SERVICE_NETWORK_NAME}'].arn" --output text)
        export SERVICE_NETWORK_ID=$(echo "${SERVICE_NETWORK_ARN}" | cut -d'/' -f2)
        log "Service network already exists: ${SERVICE_NETWORK_ID}"
    else
        export SERVICE_NETWORK_ARN=$(aws vpc-lattice create-service-network \
            --name "${SERVICE_NETWORK_NAME}" \
            --auth-type "AWS_IAM" \
            --query 'arn' --output text)
        
        export SERVICE_NETWORK_ID=$(echo "${SERVICE_NETWORK_ARN}" | cut -d'/' -f2)
        log_success "Service network created: ${SERVICE_NETWORK_ID}"
    fi
}

# Function to create ECS cluster
create_ecs_cluster() {
    log "Creating ECS cluster..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would create ECS cluster ${CLUSTER_NAME_A}"
        return
    fi
    
    # Check if cluster already exists
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME_A}" --query 'clusters[?status==`ACTIVE`]' --output text | grep -q .; then
        log "ECS cluster already exists: ${CLUSTER_NAME_A}"
    else
        aws ecs create-cluster \
            --cluster-name "${CLUSTER_NAME_A}" \
            --capacity-providers FARGATE \
            --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
        log_success "ECS cluster created: ${CLUSTER_NAME_A}"
    fi
    
    # Create task definition
    cat > /tmp/producer-task-def.json << EOF
{
    "family": "producer-task-${RESOURCE_SUFFIX}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::${ACCOUNT_A_ID}:role/ecsTaskExecutionRole",
    "containerDefinitions": [
        {
            "name": "producer-container",
            "image": "nginx:latest",
            "portMappings": [
                {
                    "containerPort": 80,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/producer",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            }
        }
    ]
}
EOF
    
    # Register task definition
    aws ecs register-task-definition --cli-input-json file:///tmp/producer-task-def.json > /dev/null
    rm -f /tmp/producer-task-def.json
    log_success "Task definition registered"
}

# Function to create VPC Lattice target group and service
create_lattice_service() {
    log "Creating VPC Lattice target group and service..."
    
    # Get default VPC ID
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "${vpc_id}" == "None" || -z "${vpc_id}" ]]; then
        log_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would create VPC Lattice resources in VPC ${vpc_id}"
        export TARGET_GROUP_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${ACCOUNT_A_ID}:targetgroup/dry-run-tg"
        export LATTICE_SERVICE_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${ACCOUNT_A_ID}:service/dry-run-service"
        export LISTENER_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${ACCOUNT_A_ID}:service/dry-run-service/listener/dry-run-listener"
        return
    fi
    
    # Create target group
    if aws vpc-lattice list-target-groups --query "items[?name=='producer-targets-${RESOURCE_SUFFIX}'].arn" --output text | grep -q .; then
        export TARGET_GROUP_ARN=$(aws vpc-lattice list-target-groups --query "items[?name=='producer-targets-${RESOURCE_SUFFIX}'].arn" --output text)
        log "Target group already exists"
    else
        export TARGET_GROUP_ARN=$(aws vpc-lattice create-target-group \
            --name "producer-targets-${RESOURCE_SUFFIX}" \
            --type "IP" \
            --protocol "HTTP" \
            --port 80 \
            --vpc-identifier "${vpc_id}" \
            --health-check-config enabled=true,protocol=HTTP,path="/",timeoutSeconds=5,intervalSeconds=30,healthyThresholdCount=2,unhealthyThresholdCount=3 \
            --query 'arn' --output text)
        log_success "Target group created"
    fi
    
    # Create VPC Lattice service
    if aws vpc-lattice list-services --query "items[?name=='${LATTICE_SERVICE_A}'].arn" --output text | grep -q .; then
        export LATTICE_SERVICE_ARN=$(aws vpc-lattice list-services --query "items[?name=='${LATTICE_SERVICE_A}'].arn" --output text)
        log "VPC Lattice service already exists"
    else
        export LATTICE_SERVICE_ARN=$(aws vpc-lattice create-service \
            --name "${LATTICE_SERVICE_A}" \
            --auth-type "AWS_IAM" \
            --query 'arn' --output text)
        log_success "VPC Lattice service created"
    fi
    
    # Create listener
    local existing_listener=$(aws vpc-lattice list-listeners \
        --service-identifier "${LATTICE_SERVICE_ARN}" \
        --query 'items[?name==`http-listener`].arn' --output text)
    
    if [[ -n "${existing_listener}" ]]; then
        export LISTENER_ARN="${existing_listener}"
        log "Listener already exists"
    else
        export LISTENER_ARN=$(aws vpc-lattice create-listener \
            --service-identifier "${LATTICE_SERVICE_ARN}" \
            --name "http-listener" \
            --protocol "HTTP" \
            --port 80 \
            --default-action "{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"${TARGET_GROUP_ARN}\"}]}}" \
            --query 'arn' --output text)
        log_success "Listener created"
    fi
}

# Function to associate service with network
associate_service_network() {
    log "Associating service with service network..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would associate service with network"
        return
    fi
    
    # Check if service is already associated
    local existing_assoc=$(aws vpc-lattice list-service-network-service-associations \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" \
        --query "items[?serviceArn=='${LATTICE_SERVICE_ARN}'].id" --output text)
    
    if [[ -n "${existing_assoc}" ]]; then
        log "Service already associated with network"
    else
        aws vpc-lattice create-service-network-service-association \
            --service-network-identifier "${SERVICE_NETWORK_ARN}" \
            --service-identifier "${LATTICE_SERVICE_ARN}" > /dev/null
        log_success "Service associated with network"
    fi
    
    # Associate VPC with service network
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    local existing_vpc_assoc=$(aws vpc-lattice list-service-network-vpc-associations \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" \
        --query "items[?vpcId=='${vpc_id}'].id" --output text)
    
    if [[ -n "${existing_vpc_assoc}" ]]; then
        log "VPC already associated with network"
    else
        aws vpc-lattice create-service-network-vpc-association \
            --service-network-identifier "${SERVICE_NETWORK_ARN}" \
            --vpc-identifier "${vpc_id}" > /dev/null
        log_success "VPC associated with network"
    fi
}

# Function to create ECS service
create_ecs_service() {
    log "Creating ECS service..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would create ECS service ${SERVICE_NAME_A}"
        return
    fi
    
    # Check if service already exists
    if aws ecs describe-services --cluster "${CLUSTER_NAME_A}" --services "${SERVICE_NAME_A}" --query 'services[?status==`ACTIVE`]' --output text | grep -q .; then
        log "ECS service already exists: ${SERVICE_NAME_A}"
        return
    fi
    
    # Get subnet IDs
    local subnet_ids=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters 'Name=is-default,Values=true' --query 'Vpcs[0].VpcId' --output text)" \
        --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' \
        --output text | tr '\t' ',')
    
    if [[ -z "${subnet_ids}" ]]; then
        log_error "No public subnets found in default VPC"
        exit 1
    fi
    
    # Create ECS service
    aws ecs create-service \
        --cluster "${CLUSTER_NAME_A}" \
        --service-name "${SERVICE_NAME_A}" \
        --task-definition "producer-task-${RESOURCE_SUFFIX}" \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${subnet_ids}],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=${TARGET_GROUP_ARN},containerName=producer-container,containerPort=80" > /dev/null
    
    log_success "ECS service created, waiting for stabilization..."
    
    # Wait for service to stabilize
    aws ecs wait services-stable \
        --cluster "${CLUSTER_NAME_A}" \
        --services "${SERVICE_NAME_A}"
    
    log_success "ECS service is stable"
}

# Function to share service network
share_service_network() {
    log "Sharing service network with Account B..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would share service network with account ${ACCOUNT_B_ID}"
        return
    fi
    
    # Check if resource share already exists
    local existing_share=$(aws ram get-resource-shares \
        --resource-owner SELF \
        --name "lattice-network-share-${RESOURCE_SUFFIX}" \
        --query 'resourceShares[0].resourceShareArn' --output text)
    
    if [[ "${existing_share}" != "None" && -n "${existing_share}" ]]; then
        export RESOURCE_SHARE_ARN="${existing_share}"
        log "Resource share already exists"
    else
        export RESOURCE_SHARE_ARN=$(aws ram create-resource-share \
            --name "lattice-network-share-${RESOURCE_SUFFIX}" \
            --resource-arns "${SERVICE_NETWORK_ARN}" \
            --principals "${ACCOUNT_B_ID}" \
            --allow-external-principals \
            --query 'resourceShare.resourceShareArn' --output text)
        log_success "Service network shared with Account B"
    fi
    
    log "Resource Share ARN: ${RESOURCE_SHARE_ARN}"
}

# Function to create EventBridge configuration
create_eventbridge_config() {
    log "Creating EventBridge configuration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would create EventBridge configuration"
        return
    fi
    
    # Check if IAM role exists
    if ! aws iam get-role --role-name "EventBridgeLogsRole" &> /dev/null; then
        # Create IAM role for EventBridge
        cat > /tmp/eventbridge-role-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        cat > /tmp/eventbridge-logs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_A_ID}:log-group:/aws/events/vpc-lattice:*"
        }
    ]
}
EOF
        
        aws iam create-role \
            --role-name "EventBridgeLogsRole" \
            --assume-role-policy-document file:///tmp/eventbridge-role-policy.json > /dev/null
        
        aws iam put-role-policy \
            --role-name "EventBridgeLogsRole" \
            --policy-name "EventBridgeLogsPolicy" \
            --policy-document file:///tmp/eventbridge-logs-policy.json
        
        rm -f /tmp/eventbridge-role-policy.json /tmp/eventbridge-logs-policy.json
        log_success "EventBridge IAM role created"
    else
        log "EventBridge IAM role already exists"
    fi
    
    # Create EventBridge rule
    if ! aws events describe-rule --name "vpc-lattice-events" &> /dev/null; then
        aws events put-rule \
            --name "vpc-lattice-events" \
            --event-pattern '{"source":["aws.vpc-lattice"],"detail-type":["VPC Lattice Service Network State Change","VPC Lattice Service State Change"]}' \
            --state ENABLED > /dev/null
        
        # Add CloudWatch Logs target
        aws events put-targets \
            --rule "vpc-lattice-events" \
            --targets "Id=1,Arn=arn:aws:logs:${AWS_REGION}:${ACCOUNT_A_ID}:log-group:/aws/events/vpc-lattice,RoleArn=arn:aws:iam::${ACCOUNT_A_ID}:role/EventBridgeLogsRole" > /dev/null
        
        log_success "EventBridge rule created"
    else
        log "EventBridge rule already exists"
    fi
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would create CloudWatch dashboard"
        return
    fi
    
    cat > /tmp/dashboard-config.json << EOF
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
                    ["AWS/VpcLattice", "ActiveConnectionCount", "ServiceName", "${LATTICE_SERVICE_A}"],
                    [".", "NewConnectionCount", ".", "."],
                    [".", "ProcessedBytes", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "VPC Lattice Service Metrics"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/events/vpc-lattice'\\n| fields @timestamp, source, detail-type, detail\\n| sort @timestamp desc\\n| limit 100",
                "region": "${AWS_REGION}",
                "title": "VPC Lattice Events"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "cross-account-service-discovery-${RESOURCE_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-config.json > /dev/null
    
    rm -f /tmp/dashboard-config.json
    log_success "CloudWatch dashboard created"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > /tmp/deployment-state.env << EOF
# Cross-Account Service Discovery Deployment State
# Generated on $(date)
export AWS_REGION="${AWS_REGION}"
export ACCOUNT_A_ID="${ACCOUNT_A_ID}"
export ACCOUNT_B_ID="${ACCOUNT_B_ID}"
export RESOURCE_SUFFIX="${RESOURCE_SUFFIX}"
export CLUSTER_NAME_A="${CLUSTER_NAME_A}"
export SERVICE_NAME_A="${SERVICE_NAME_A}"
export LATTICE_SERVICE_A="${LATTICE_SERVICE_A}"
export SERVICE_NETWORK_NAME="${SERVICE_NETWORK_NAME}"
export SERVICE_NETWORK_ARN="${SERVICE_NETWORK_ARN:-}"
export SERVICE_NETWORK_ID="${SERVICE_NETWORK_ID:-}"
export TARGET_GROUP_ARN="${TARGET_GROUP_ARN:-}"
export LATTICE_SERVICE_ARN="${LATTICE_SERVICE_ARN:-}"
export LISTENER_ARN="${LISTENER_ARN:-}"
export RESOURCE_SHARE_ARN="${RESOURCE_SHARE_ARN:-}"
EOF
    
    log_success "Deployment state saved to /tmp/deployment-state.env"
    log "To use these variables in another session, run: source /tmp/deployment-state.env"
}

# Function to print deployment summary
print_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "Account A (Producer): ${ACCOUNT_A_ID}"
    echo "Account B (Consumer): ${ACCOUNT_B_ID}"
    echo "Resource Suffix: ${RESOURCE_SUFFIX}"
    echo ""
    echo "=== Created Resources ==="
    echo "ECS Cluster: ${CLUSTER_NAME_A}"
    echo "ECS Service: ${SERVICE_NAME_A}"
    echo "VPC Lattice Service: ${LATTICE_SERVICE_A}"
    echo "Service Network: ${SERVICE_NETWORK_NAME}"
    echo "CloudWatch Dashboard: cross-account-service-discovery-${RESOURCE_SUFFIX}"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Accept the resource share invitation in Account B"
    echo "2. Associate Account B's VPC with the shared service network"
    echo "3. Create consumer services in Account B that can discover this producer service"
    echo "4. Monitor the CloudWatch dashboard for service metrics and events"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh --suffix ${RESOURCE_SUFFIX}"
}

# Main deployment function
main() {
    log "Starting Cross-Account Service Discovery deployment..."
    
    check_prerequisites
    setup_environment
    ensure_ecs_execution_role
    create_log_groups
    create_service_network
    create_ecs_cluster
    create_lattice_service
    associate_service_network
    create_ecs_service
    share_service_network
    create_eventbridge_config
    create_dashboard
    save_deployment_state
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN completed - no resources were actually created"
    else
        print_summary
    fi
}

# Trap errors and cleanup
trap 'log_error "Deployment failed on line $LINENO. Check the logs above for details."' ERR

# Run main function
main "$@"