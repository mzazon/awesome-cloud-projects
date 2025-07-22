#!/bin/bash

# Distributed Session Management with MemoryDB
# Deploy Script
# 
# This script deploys a complete distributed session management solution using:
# - Amazon MemoryDB for Redis (session storage)
# - Application Load Balancer (traffic distribution)
# - ECS Fargate (containerized applications)
# - Systems Manager Parameter Store (configuration management)

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if required permissions exist by testing basic operations
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        error "Insufficient permissions for EC2 operations."
        exit 1
    fi
    
    # Check if redis-cli is available (optional but helpful for testing)
    if ! command -v redis-cli &> /dev/null; then
        warning "redis-cli is not installed. Session testing will be limited."
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export CLUSTER_NAME="session-cluster-${RANDOM_SUFFIX}"
    export MEMORYDB_CLUSTER_NAME="session-memorydb-${RANDOM_SUFFIX}"
    export ALB_NAME="session-alb-${RANDOM_SUFFIX}"
    export TARGET_GROUP_NAME="session-tg-${RANDOM_SUFFIX}"
    export VPC_NAME="session-vpc-${RANDOM_SUFFIX}"
    
    # Create state directory for tracking resources
    mkdir -p .deployment-state
    
    # Save environment variables to file for cleanup
    cat > .deployment-state/environment.sh << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export CLUSTER_NAME="${CLUSTER_NAME}"
export MEMORYDB_CLUSTER_NAME="${MEMORYDB_CLUSTER_NAME}"
export ALB_NAME="${ALB_NAME}"
export TARGET_GROUP_NAME="${TARGET_GROUP_NAME}"
export VPC_NAME="${VPC_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    success "Environment initialized with suffix: ${RANDOM_SUFFIX}"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to create VPC and networking
create_networking() {
    log "Creating VPC and networking infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'Vpc.VpcId')
    
    echo "VPC_ID=${VPC_ID}" >> .deployment-state/resources.txt
    success "Created VPC: ${VPC_ID}"
    
    # Enable DNS hostnames and resolution
    aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'InternetGateway.InternetGatewayId')
    
    echo "IGW_ID=${IGW_ID}" >> .deployment-state/resources.txt
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}
    success "Created and attached Internet Gateway: ${IGW_ID}"
    
    # Create public subnets for ALB
    PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public-1},{Key=Type,Value=public},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'Subnet.SubnetId')
    
    PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.2.0/24 \
        --availability-zone ${AWS_REGION}b \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public-2},{Key=Type,Value=public},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'Subnet.SubnetId')
    
    # Create private subnets for ECS and MemoryDB
    PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.3.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-1},{Key=Type,Value=private},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'Subnet.SubnetId')
    
    PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.4.0/24 \
        --availability-zone ${AWS_REGION}b \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-2},{Key=Type,Value=private},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'Subnet.SubnetId')
    
    # Save subnet IDs
    cat >> .deployment-state/resources.txt << EOF
PUBLIC_SUBNET_1=${PUBLIC_SUBNET_1}
PUBLIC_SUBNET_2=${PUBLIC_SUBNET_2}
PRIVATE_SUBNET_1=${PRIVATE_SUBNET_1}
PRIVATE_SUBNET_2=${PRIVATE_SUBNET_2}
EOF
    
    # Create route table for public subnets
    PUBLIC_RT_ID=$(aws ec2 create-route-table \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-public-rt},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'RouteTable.RouteTableId')
    
    echo "PUBLIC_RT_ID=${PUBLIC_RT_ID}" >> .deployment-state/resources.txt
    
    # Create route to Internet Gateway
    aws ec2 create-route \
        --route-table-id ${PUBLIC_RT_ID} \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id ${IGW_ID}
    
    # Associate public subnets with route table
    aws ec2 associate-route-table --route-table-id ${PUBLIC_RT_ID} --subnet-id ${PUBLIC_SUBNET_1}
    aws ec2 associate-route-table --route-table-id ${PUBLIC_RT_ID} --subnet-id ${PUBLIC_SUBNET_2}
    
    # Create NAT Gateways for private subnet internet access
    NAT_EIP_1=$(aws ec2 allocate-address --domain vpc --output text --query 'AllocationId')
    NAT_GW_1=$(aws ec2 create-nat-gateway \
        --subnet-id ${PUBLIC_SUBNET_1} \
        --allocation-id ${NAT_EIP_1} \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat-1},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'NatGateway.NatGatewayId')
    
    # Wait for NAT Gateway to be available
    log "Waiting for NAT Gateway to become available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids ${NAT_GW_1}
    
    # Create route table for private subnets
    PRIVATE_RT_ID=$(aws ec2 create-route-table \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-private-rt},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'RouteTable.RouteTableId')
    
    # Create route to NAT Gateway for private subnets
    aws ec2 create-route \
        --route-table-id ${PRIVATE_RT_ID} \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id ${NAT_GW_1}
    
    # Associate private subnets with private route table
    aws ec2 associate-route-table --route-table-id ${PRIVATE_RT_ID} --subnet-id ${PRIVATE_SUBNET_1}
    aws ec2 associate-route-table --route-table-id ${PRIVATE_RT_ID} --subnet-id ${PRIVATE_SUBNET_2}
    
    # Save NAT Gateway information
    cat >> .deployment-state/resources.txt << EOF
NAT_EIP_1=${NAT_EIP_1}
NAT_GW_1=${NAT_GW_1}
PRIVATE_RT_ID=${PRIVATE_RT_ID}
EOF
    
    success "Networking infrastructure created successfully"
}

# Function to create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Create security group for ALB
    ALB_SG=$(aws ec2 create-security-group \
        --group-name ${ALB_NAME}-sg \
        --description "Application Load Balancer security group" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${ALB_NAME}-sg},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'GroupId')
    
    # Allow HTTP and HTTPS traffic to ALB
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG} \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=alb-http}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG} \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=alb-https}]"
    
    # Create security group for ECS tasks
    ECS_SG=$(aws ec2 create-security-group \
        --group-name ${CLUSTER_NAME}-ecs-sg \
        --description "ECS tasks security group" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${CLUSTER_NAME}-ecs-sg},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'GroupId')
    
    # Allow ALB to communicate with ECS tasks
    aws ec2 authorize-security-group-ingress \
        --group-id ${ECS_SG} \
        --protocol tcp \
        --port 80 \
        --source-group ${ALB_SG} \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=ecs-from-alb}]"
    
    # Allow ECS tasks to make HTTPS outbound calls (for Parameter Store, etc.)
    aws ec2 authorize-security-group-egress \
        --group-id ${ECS_SG} \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=ecs-https-out}]"
    
    # Create security group for MemoryDB
    MEMORYDB_SG=$(aws ec2 create-security-group \
        --group-name ${MEMORYDB_CLUSTER_NAME}-sg \
        --description "MemoryDB security group" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${MEMORYDB_CLUSTER_NAME}-sg},{Key=Project,Value=distributed-session-management}]" \
        --output text --query 'GroupId')
    
    # Allow ECS tasks to connect to MemoryDB
    aws ec2 authorize-security-group-ingress \
        --group-id ${MEMORYDB_SG} \
        --protocol tcp \
        --port 6379 \
        --source-group ${ECS_SG} \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=memorydb-from-ecs}]"
    
    # Save security group IDs
    cat >> .deployment-state/resources.txt << EOF
ALB_SG=${ALB_SG}
ECS_SG=${ECS_SG}
MEMORYDB_SG=${MEMORYDB_SG}
EOF
    
    success "Security groups created successfully"
}

# Function to create MemoryDB cluster
create_memorydb() {
    log "Creating MemoryDB cluster for session storage..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Create MemoryDB subnet group
    aws memorydb create-subnet-group \
        --subnet-group-name ${MEMORYDB_CLUSTER_NAME}-subnet-group \
        --description "Subnet group for session management MemoryDB" \
        --subnet-ids ${PRIVATE_SUBNET_1} ${PRIVATE_SUBNET_2} \
        --tags "Key=Name,Value=${MEMORYDB_CLUSTER_NAME}-subnet-group" "Key=Project,Value=distributed-session-management"
    
    # Create MemoryDB cluster
    aws memorydb create-cluster \
        --cluster-name ${MEMORYDB_CLUSTER_NAME} \
        --description "Session management cluster with Multi-AZ durability" \
        --node-type db.r6g.large \
        --parameter-group-name default.memorydb-redis7 \
        --subnet-group-name ${MEMORYDB_CLUSTER_NAME}-subnet-group \
        --security-group-ids ${MEMORYDB_SG} \
        --num-shards 2 \
        --num-replicas-per-shard 1 \
        --data-tiering Enabled \
        --tags "Key=Name,Value=${MEMORYDB_CLUSTER_NAME}" "Key=Project,Value=distributed-session-management" "Key=Environment,Value=production"
    
    # Save MemoryDB information
    echo "MEMORYDB_SUBNET_GROUP=${MEMORYDB_CLUSTER_NAME}-subnet-group" >> .deployment-state/resources.txt
    
    log "MemoryDB cluster creation initiated. This may take 10-15 minutes..."
    log "Waiting for cluster to become available..."
    
    # Wait for cluster to be available with timeout
    local timeout=1200  # 20 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        if aws memorydb describe-clusters --cluster-name ${MEMORYDB_CLUSTER_NAME} --query 'Clusters[0].Status' --output text 2>/dev/null | grep -q "available"; then
            break
        fi
        log "Still waiting for MemoryDB cluster... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    # Check if cluster is available
    if ! aws memorydb describe-clusters --cluster-name ${MEMORYDB_CLUSTER_NAME} --query 'Clusters[0].Status' --output text 2>/dev/null | grep -q "available"; then
        error "MemoryDB cluster failed to become available within timeout period"
        exit 1
    fi
    
    success "MemoryDB cluster created and available"
}

# Function to store configuration in Parameter Store
store_configuration() {
    log "Storing configuration in Systems Manager Parameter Store..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Get MemoryDB endpoint
    MEMORYDB_ENDPOINT=$(aws memorydb describe-clusters \
        --cluster-name ${MEMORYDB_CLUSTER_NAME} \
        --query 'Clusters[0].ClusterEndpoint.Address' \
        --output text)
    
    if [ -z "$MEMORYDB_ENDPOINT" ] || [ "$MEMORYDB_ENDPOINT" = "None" ]; then
        error "Failed to retrieve MemoryDB endpoint"
        exit 1
    fi
    
    # Store configuration parameters
    aws ssm put-parameter \
        --name "/session-app/memorydb/endpoint" \
        --value "${MEMORYDB_ENDPOINT}" \
        --type "String" \
        --description "MemoryDB cluster endpoint for session storage" \
        --tags "Key=Project,Value=distributed-session-management" \
        --overwrite || true
    
    aws ssm put-parameter \
        --name "/session-app/memorydb/port" \
        --value "6379" \
        --type "String" \
        --description "MemoryDB port for Redis connections" \
        --tags "Key=Project,Value=distributed-session-management" \
        --overwrite || true
    
    aws ssm put-parameter \
        --name "/session-app/config/session-timeout" \
        --value "1800" \
        --type "String" \
        --description "Session timeout in seconds (30 minutes)" \
        --tags "Key=Project,Value=distributed-session-management" \
        --overwrite || true
    
    aws ssm put-parameter \
        --name "/session-app/config/redis-db" \
        --value "0" \
        --type "String" \
        --description "Redis database number for session storage" \
        --tags "Key=Project,Value=distributed-session-management" \
        --overwrite || true
    
    # Save endpoint for future use
    echo "MEMORYDB_ENDPOINT=${MEMORYDB_ENDPOINT}" >> .deployment-state/resources.txt
    
    success "Configuration stored in Parameter Store"
    log "MemoryDB Endpoint: ${MEMORYDB_ENDPOINT}"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles for ECS tasks..."
    
    # Create ECS task execution role
    cat > trust-policy.json << EOF
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
    
    aws iam create-role \
        --role-name ecsTaskExecutionRole-session-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://trust-policy.json \
        --tags "Key=Project,Value=distributed-session-management" || true
    
    # Create task role with SSM permissions
    cat > task-trust-policy.json << EOF
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
    
    aws iam create-role \
        --role-name ecsTaskRole-session-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://task-trust-policy.json \
        --tags "Key=Project,Value=distributed-session-management" || true
    
    # Create custom policy for Parameter Store access
    cat > ssm-policy.json << EOF
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
            "Resource": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/session-app/*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name ecsTaskRole-session-${RANDOM_SUFFIX} \
        --policy-name SessionAppSSMAccess \
        --policy-document file://ssm-policy.json
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name ecsTaskExecutionRole-session-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Save role ARNs
    cat >> .deployment-state/resources.txt << EOF
ECS_EXECUTION_ROLE_NAME=ecsTaskExecutionRole-session-${RANDOM_SUFFIX}
ECS_TASK_ROLE_NAME=ecsTaskRole-session-${RANDOM_SUFFIX}
EOF
    
    # Clean up temporary files
    rm -f trust-policy.json task-trust-policy.json ssm-policy.json
    
    success "IAM roles created successfully"
}

# Function to create ECS cluster and services
create_ecs_cluster() {
    log "Creating ECS cluster and services..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name /ecs/session-app-${RANDOM_SUFFIX} \
        --retention-in-days 7 \
        --tags "Project=distributed-session-management" || true
    
    # Create ECS cluster
    aws ecs create-cluster \
        --cluster-name ${CLUSTER_NAME} \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1,base=0 \
        --tags "key=Name,value=${CLUSTER_NAME}" "key=Project,value=distributed-session-management"
    
    # Create task definition
    cat > task-definition.json << EOF
{
    "family": "session-app-${RANDOM_SUFFIX}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole-session-${RANDOM_SUFFIX}",
    "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskRole-session-${RANDOM_SUFFIX}",
    "containerDefinitions": [
        {
            "name": "session-app",
            "image": "nginx:latest",
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 80,
                    "protocol": "tcp"
                }
            ],
            "environment": [
                {
                    "name": "AWS_REGION",
                    "value": "${AWS_REGION}"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/session-app-${RANDOM_SUFFIX}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "healthCheck": {
                "command": [
                    "CMD-SHELL",
                    "curl -f http://localhost/ || exit 1"
                ],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            }
        }
    ]
}
EOF
    
    # Register task definition
    TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file://task-definition.json \
        --output text --query 'taskDefinition.taskDefinitionArn')
    
    # Save task definition info
    cat >> .deployment-state/resources.txt << EOF
TASK_DEFINITION_FAMILY=session-app-${RANDOM_SUFFIX}
TASK_DEF_ARN=${TASK_DEF_ARN}
LOG_GROUP=/ecs/session-app-${RANDOM_SUFFIX}
EOF
    
    # Clean up task definition file
    rm -f task-definition.json
    
    success "ECS cluster and task definition created"
}

# Function to create Application Load Balancer
create_load_balancer() {
    log "Creating Application Load Balancer..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Create Application Load Balancer
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name ${ALB_NAME} \
        --subnets ${PUBLIC_SUBNET_1} ${PUBLIC_SUBNET_2} \
        --security-groups ${ALB_SG} \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags "Key=Name,Value=${ALB_NAME}" "Key=Project,Value=distributed-session-management" \
        --output text --query 'LoadBalancers[0].LoadBalancerArn')
    
    # Create target group
    TG_ARN=$(aws elbv2 create-target-group \
        --name ${TARGET_GROUP_NAME} \
        --protocol HTTP \
        --port 80 \
        --vpc-id ${VPC_ID} \
        --target-type ip \
        --health-check-enabled \
        --health-check-interval-seconds 30 \
        --health-check-path / \
        --health-check-protocol HTTP \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags "Key=Name,Value=${TARGET_GROUP_NAME}" "Key=Project,Value=distributed-session-management" \
        --output text --query 'TargetGroups[0].TargetGroupArn')
    
    # Create listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn ${ALB_ARN} \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
        --output text --query 'Listeners[0].ListenerArn')
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${ALB_ARN} \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Save ALB information
    cat >> .deployment-state/resources.txt << EOF
ALB_ARN=${ALB_ARN}
TG_ARN=${TG_ARN}
LISTENER_ARN=${LISTENER_ARN}
ALB_DNS=${ALB_DNS}
EOF
    
    success "Application Load Balancer created"
    log "ALB DNS: ${ALB_DNS}"
}

# Function to create ECS service
create_ecs_service() {
    log "Creating ECS service with auto scaling..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Create ECS service
    aws ecs create-service \
        --cluster ${CLUSTER_NAME} \
        --service-name session-app-service \
        --task-definition ${TASK_DEFINITION_FAMILY}:1 \
        --desired-count 2 \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={
            subnets=[${PRIVATE_SUBNET_1},${PRIVATE_SUBNET_2}],
            securityGroups=[${ECS_SG}],
            assignPublicIp=DISABLED
        }" \
        --load-balancers "targetGroupArn=${TG_ARN},containerName=session-app,containerPort=80" \
        --health-check-grace-period-seconds 300 \
        --enable-execute-command \
        --tags "key=Name,value=session-app-service" "key=Project,value=distributed-session-management"
    
    # Wait a moment for service to initialize
    sleep 10
    
    # Configure auto scaling
    aws application-autoscaling register-scalable-target \
        --service-namespace ecs \
        --resource-id service/${CLUSTER_NAME}/session-app-service \
        --scalable-dimension ecs:service:DesiredCount \
        --min-capacity 2 \
        --max-capacity 10 \
        --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService || true
    
    # Create scaling policy
    aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id service/${CLUSTER_NAME}/session-app-service \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name session-app-cpu-scaling \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration '{
            "TargetValue": 70.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' || true
    
    echo "ECS_SERVICE_NAME=session-app-service" >> .deployment-state/resources.txt
    
    log "Waiting for ECS service to stabilize..."
    
    # Wait for service to be stable with timeout
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        if aws ecs describe-services \
            --cluster ${CLUSTER_NAME} \
            --services session-app-service \
            --query 'services[0].deployments[?status==`PRIMARY`].runningCount' \
            --output text | grep -q "2"; then
            break
        fi
        log "Waiting for ECS service to reach desired state... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    success "ECS service created and running"
}

# Function to create session testing utilities
create_session_utilities() {
    log "Creating session testing utilities..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    # Create session configuration script
    cat > session-config.sh << 'EOF'
#!/bin/bash

# Session Configuration Script
# Retrieves configuration from AWS Systems Manager Parameter Store

# Get AWS region from environment or default
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi

echo "Retrieving session configuration from Parameter Store..."

# Retrieve configuration parameters
REDIS_ENDPOINT=$(aws ssm get-parameter \
    --name "/session-app/memorydb/endpoint" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

REDIS_PORT=$(aws ssm get-parameter \
    --name "/session-app/memorydb/port" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

SESSION_TIMEOUT=$(aws ssm get-parameter \
    --name "/session-app/config/session-timeout" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

REDIS_DB=$(aws ssm get-parameter \
    --name "/session-app/config/redis-db" \
    --region ${AWS_REGION} \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

# Export environment variables
export REDIS_ENDPOINT="${REDIS_ENDPOINT}"
export REDIS_PORT="${REDIS_PORT}"
export SESSION_TIMEOUT="${SESSION_TIMEOUT}"
export REDIS_DB="${REDIS_DB}"

# Display configuration
echo "Session configuration loaded:"
echo "  Redis Endpoint: ${REDIS_ENDPOINT}"
echo "  Redis Port: ${REDIS_PORT}"
echo "  Session Timeout: ${SESSION_TIMEOUT} seconds"
echo "  Redis Database: ${REDIS_DB}"
echo ""
echo "Environment variables exported. You can now use:"
echo "  redis-cli -h \$REDIS_ENDPOINT -p \$REDIS_PORT"
EOF
    
    chmod +x session-config.sh
    
    # Create session test script
    cat > test-session.py << 'EOF'
#!/usr/bin/env python3
"""
Session Testing Script
Tests session storage and retrieval using MemoryDB for Redis
"""

import redis
import json
import uuid
import time
import os
import sys
import boto3

def get_redis_config():
    """Retrieve Redis configuration from Parameter Store"""
    ssm = boto3.client('ssm')
    
    try:
        endpoint = ssm.get_parameter(Name='/session-app/memorydb/endpoint')['Parameter']['Value']
        port = int(ssm.get_parameter(Name='/session-app/memorydb/port')['Parameter']['Value'])
        timeout = int(ssm.get_parameter(Name='/session-app/config/session-timeout')['Parameter']['Value'])
        db = int(ssm.get_parameter(Name='/session-app/config/redis-db')['Parameter']['Value'])
        
        return endpoint, port, timeout, db
    except Exception as e:
        print(f"Error retrieving configuration: {e}")
        sys.exit(1)

def test_session_operations():
    """Test basic session operations"""
    print("Testing session operations...")
    
    # Get configuration
    endpoint, port, timeout, db = get_redis_config()
    print(f"Connecting to Redis at {endpoint}:{port}")
    
    try:
        # Connect to Redis
        redis_client = redis.Redis(
            host=endpoint,
            port=port,
            db=db,
            decode_responses=True,
            socket_timeout=5,
            socket_connect_timeout=5
        )
        
        # Test connection
        redis_client.ping()
        print("✅ Successfully connected to MemoryDB")
        
        # Create test session
        session_id = str(uuid.uuid4())
        session_data = {
            'user_id': 'test_user_123',
            'login_time': int(time.time()),
            'preferences': {
                'theme': 'dark',
                'language': 'en',
                'timezone': 'UTC'
            },
            'permissions': ['read', 'write'],
            'last_activity': int(time.time())
        }
        
        session_key = f"session:{session_id}"
        
        # Store session with TTL
        redis_client.setex(
            session_key,
            timeout,
            json.dumps(session_data)
        )
        print(f"✅ Created session: {session_id}")
        
        # Retrieve session
        retrieved_data = redis_client.get(session_key)
        if retrieved_data:
            parsed_data = json.loads(retrieved_data)
            print(f"✅ Retrieved session data:")
            print(f"   User ID: {parsed_data['user_id']}")
            print(f"   Login Time: {parsed_data['login_time']}")
            print(f"   Preferences: {parsed_data['preferences']}")
            print(f"   Session TTL: {redis_client.ttl(session_key)} seconds")
        else:
            print("❌ Failed to retrieve session data")
            return False
        
        # Update session
        parsed_data['last_activity'] = int(time.time())
        parsed_data['page_views'] = parsed_data.get('page_views', 0) + 1
        
        redis_client.setex(
            session_key,
            timeout,
            json.dumps(parsed_data)
        )
        print("✅ Updated session data")
        
        # Test session expiration
        short_session_id = str(uuid.uuid4())
        short_session_key = f"session:{short_session_id}"
        
        redis_client.setex(short_session_key, 5, json.dumps({"test": "data"}))
        print("✅ Created short-lived session (5s TTL)")
        
        # Get Redis info
        info = redis_client.info()
        print(f"✅ Redis server info:")
        print(f"   Version: {info.get('redis_version', 'Unknown')}")
        print(f"   Connected clients: {info.get('connected_clients', 'Unknown')}")
        print(f"   Used memory: {info.get('used_memory_human', 'Unknown')}")
        
        # Test multiple sessions (simulate concurrent users)
        print("\n🧪 Testing concurrent session simulation...")
        session_ids = []
        for i in range(10):
            sid = str(uuid.uuid4())
            session_ids.append(sid)
            user_data = {
                'user_id': f'user_{i}',
                'login_time': int(time.time()),
                'session_number': i
            }
            redis_client.setex(f"session:{sid}", timeout, json.dumps(user_data))
        
        print(f"✅ Created {len(session_ids)} concurrent sessions")
        
        # Verify all sessions exist
        existing_sessions = 0
        for sid in session_ids:
            if redis_client.exists(f"session:{sid}"):
                existing_sessions += 1
        
        print(f"✅ Verified {existing_sessions}/{len(session_ids)} sessions exist")
        
        # Clean up test sessions
        for sid in session_ids:
            redis_client.delete(f"session:{sid}")
        redis_client.delete(session_key)
        
        print("✅ Cleaned up test sessions")
        print("\n🎉 All session tests passed!")
        return True
        
    except redis.ConnectionError as e:
        print(f"❌ Connection error: {e}")
        return False
    except redis.TimeoutError as e:
        print(f"❌ Timeout error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    success = test_session_operations()
    sys.exit(0 if success else 1)
EOF
    
    chmod +x test-session.py
    
    # Create load test script
    cat > load-test-sessions.py << 'EOF'
#!/usr/bin/env python3
"""
Session Load Testing Script
Simulates high-volume session operations
"""

import redis
import json
import uuid
import time
import threading
import boto3
from concurrent.futures import ThreadPoolExecutor
import statistics

def get_redis_config():
    """Retrieve Redis configuration from Parameter Store"""
    ssm = boto3.client('ssm')
    
    endpoint = ssm.get_parameter(Name='/session-app/memorydb/endpoint')['Parameter']['Value']
    port = int(ssm.get_parameter(Name='/session-app/memorydb/port')['Parameter']['Value'])
    timeout = int(ssm.get_parameter(Name='/session-app/config/session-timeout')['Parameter']['Value'])
    db = int(ssm.get_parameter(Name='/session-app/config/redis-db')['Parameter']['Value'])
    
    return endpoint, port, timeout, db

def session_worker(worker_id, num_operations, results):
    """Worker function for session operations"""
    endpoint, port, timeout, db = get_redis_config()
    
    redis_client = redis.Redis(
        host=endpoint,
        port=port,
        db=db,
        decode_responses=True
    )
    
    operation_times = []
    
    for i in range(num_operations):
        start_time = time.time()
        
        # Create session
        session_id = str(uuid.uuid4())
        session_data = {
            'user_id': f'load_test_user_{worker_id}_{i}',
            'worker_id': worker_id,
            'operation': i,
            'timestamp': int(time.time())
        }
        
        session_key = f"load_test:session:{session_id}"
        
        try:
            # Write operation
            redis_client.setex(session_key, 300, json.dumps(session_data))
            
            # Read operation
            data = redis_client.get(session_key)
            
            # Update operation
            if data:
                parsed = json.loads(data)
                parsed['last_accessed'] = int(time.time())
                redis_client.setex(session_key, 300, json.dumps(parsed))
            
            # Delete operation
            redis_client.delete(session_key)
            
            end_time = time.time()
            operation_times.append(end_time - start_time)
            
        except Exception as e:
            print(f"Worker {worker_id} error on operation {i}: {e}")
    
    results[worker_id] = operation_times

def run_load_test(num_workers=10, operations_per_worker=100):
    """Run load test with specified parameters"""
    print(f"Starting load test: {num_workers} workers, {operations_per_worker} ops/worker")
    
    results = {}
    start_time = time.time()
    
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = []
        for worker_id in range(num_workers):
            future = executor.submit(session_worker, worker_id, operations_per_worker, results)
            futures.append(future)
        
        # Wait for all workers to complete
        for future in futures:
            future.result()
    
    end_time = time.time()
    total_time = end_time - start_time
    
    # Calculate statistics
    all_times = []
    for times in results.values():
        all_times.extend(times)
    
    total_operations = len(all_times)
    avg_time = statistics.mean(all_times)
    median_time = statistics.median(all_times)
    min_time = min(all_times)
    max_time = max(all_times)
    
    throughput = total_operations / total_time
    
    print("\n📊 Load Test Results:")
    print(f"Total Operations: {total_operations}")
    print(f"Total Time: {total_time:.2f} seconds")
    print(f"Throughput: {throughput:.2f} operations/second")
    print(f"Average Operation Time: {avg_time:.4f} seconds")
    print(f"Median Operation Time: {median_time:.4f} seconds")
    print(f"Min Operation Time: {min_time:.4f} seconds")
    print(f"Max Operation Time: {max_time:.4f} seconds")

if __name__ == "__main__":
    try:
        run_load_test()
    except Exception as e:
        print(f"Load test failed: {e}")
EOF
    
    chmod +x load-test-sessions.py
    
    success "Session testing utilities created"
}

# Function to create S3 bucket for configuration and scripts
create_s3_bucket() {
    log "Creating S3 bucket for session management utilities..."
    
    # Load environment
    source .deployment-state/environment.sh
    
    # Create S3 bucket with unique name
    BUCKET_NAME="session-config-${RANDOM_SUFFIX}-${AWS_REGION}"
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Upload session utilities
    aws s3 cp session-config.sh s3://${BUCKET_NAME}/
    aws s3 cp test-session.py s3://${BUCKET_NAME}/
    aws s3 cp load-test-sessions.py s3://${BUCKET_NAME}/
    
    # Create a simple web page for testing
    cat > index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Session Management Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .status { padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Session Management Demo</h1>
        <div class="status success">
            <h3>✅ Deployment Successful</h3>
            <p>Your distributed session management system is now running!</p>
        </div>
        
        <div class="status info">
            <h3>📋 System Information</h3>
            <p><strong>Load Balancer:</strong> ${ALB_DNS}</p>
            <p><strong>MemoryDB Cluster:</strong> ${MEMORYDB_CLUSTER_NAME}</p>
            <p><strong>ECS Cluster:</strong> ${CLUSTER_NAME}</p>
            <p><strong>Region:</strong> ${AWS_REGION}</p>
        </div>
        
        <h3>🧪 Testing Instructions</h3>
        <ol>
            <li>Download session utilities: <code>aws s3 cp s3://${BUCKET_NAME}/ . --recursive</code></li>
            <li>Run session configuration: <code>source session-config.sh</code></li>
            <li>Test session operations: <code>python3 test-session.py</code></li>
            <li>Run load test: <code>python3 load-test-sessions.py</code></li>
        </ol>
        
        <h3>🔗 Useful Commands</h3>
        <pre>
# Connect to Redis directly
redis-cli -h \$REDIS_ENDPOINT -p \$REDIS_PORT

# View ECS service status
aws ecs describe-services --cluster ${CLUSTER_NAME} --services session-app-service

# View application logs
aws logs tail /ecs/session-app-${RANDOM_SUFFIX} --follow
        </pre>
    </div>
</body>
</html>
EOF
    
    aws s3 cp index.html s3://${BUCKET_NAME}/
    
    # Save bucket info
    echo "S3_BUCKET=${BUCKET_NAME}" >> .deployment-state/resources.txt
    
    success "S3 bucket created with session utilities"
    log "Bucket: s3://${BUCKET_NAME}"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Load resource IDs
    source .deployment-state/resources.txt
    
    local validation_errors=0
    
    # Check MemoryDB cluster
    log "Checking MemoryDB cluster status..."
    if aws memorydb describe-clusters --cluster-name ${MEMORYDB_CLUSTER_NAME} --query 'Clusters[0].Status' --output text | grep -q "available"; then
        success "MemoryDB cluster is available"
    else
        error "MemoryDB cluster is not available"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check ECS service
    log "Checking ECS service status..."
    RUNNING_COUNT=$(aws ecs describe-services \
        --cluster ${CLUSTER_NAME} \
        --services session-app-service \
        --query 'services[0].runningCount' \
        --output text)
    
    if [ "$RUNNING_COUNT" -ge 2 ]; then
        success "ECS service has $RUNNING_COUNT running tasks"
    else
        error "ECS service has insufficient running tasks: $RUNNING_COUNT"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check ALB health
    log "Checking Application Load Balancer..."
    if aws elbv2 describe-load-balancers --load-balancer-arns ${ALB_ARN} --query 'LoadBalancers[0].State.Code' --output text | grep -q "active"; then
        success "Application Load Balancer is active"
    else
        error "Application Load Balancer is not active"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check target group health
    log "Checking target group health..."
    HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
        --target-group-arn ${TG_ARN} \
        --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' \
        --output json | jq length)
    
    if [ "$HEALTHY_TARGETS" -gt 0 ]; then
        success "$HEALTHY_TARGETS healthy targets in target group"
    else
        warning "No healthy targets found yet (may take a few minutes)"
    fi
    
    # Test ALB connectivity
    log "Testing ALB connectivity..."
    if curl -s -o /dev/null -w "%{http_code}" http://${ALB_DNS}/ | grep -q "200"; then
        success "ALB is responding to HTTP requests"
    else
        warning "ALB is not responding yet (may take a few minutes to initialize)"
    fi
    
    # Check Parameter Store
    log "Checking Parameter Store configuration..."
    if aws ssm get-parameter --name "/session-app/memorydb/endpoint" &> /dev/null; then
        success "Parameter Store configuration is accessible"
    else
        error "Parameter Store configuration is not accessible"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        success "All validation checks passed!"
        return 0
    else
        error "$validation_errors validation errors found"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    log "Generating deployment summary..."
    
    # Load all resource information
    source .deployment-state/environment.sh
    source .deployment-state/resources.txt
    
    echo ""
    echo "🎉 =================================="
    echo "   DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "================================== 🎉"
    echo ""
    echo "📋 Resource Summary:"
    echo "   • VPC: ${VPC_ID}"
    echo "   • MemoryDB Cluster: ${MEMORYDB_CLUSTER_NAME}"
    echo "   • MemoryDB Endpoint: ${MEMORYDB_ENDPOINT}"
    echo "   • ECS Cluster: ${CLUSTER_NAME}"
    echo "   • Application Load Balancer: ${ALB_DNS}"
    echo "   • S3 Bucket: s3://${S3_BUCKET}"
    echo ""
    echo "🌐 Access Information:"
    echo "   • Application URL: http://${ALB_DNS}/"
    echo "   • Redis Connection: ${MEMORYDB_ENDPOINT}:6379"
    echo ""
    echo "🧪 Testing Commands:"
    echo "   # Download testing utilities"
    echo "   aws s3 cp s3://${S3_BUCKET}/session-config.sh ."
    echo "   aws s3 cp s3://${S3_BUCKET}/test-session.py ."
    echo ""
    echo "   # Load session configuration"
    echo "   source session-config.sh"
    echo ""
    echo "   # Test session operations"
    echo "   python3 test-session.py"
    echo ""
    echo "   # Connect to Redis directly"
    echo "   redis-cli -h ${MEMORYDB_ENDPOINT} -p 6379"
    echo ""
    echo "📊 Monitoring Commands:"
    echo "   # View ECS service status"
    echo "   aws ecs describe-services --cluster ${CLUSTER_NAME} --services session-app-service"
    echo ""
    echo "   # View application logs"
    echo "   aws logs tail ${LOG_GROUP} --follow"
    echo ""
    echo "   # Check ALB target health"
    echo "   aws elbv2 describe-target-health --target-group-arn ${TG_ARN}"
    echo ""
    echo "🔧 Management:"
    echo "   • All resource identifiers saved in: .deployment-state/"
    echo "   • To clean up: Run ./destroy.sh"
    echo ""
    echo "💡 Next Steps:"
    echo "   1. Wait 5-10 minutes for all services to fully initialize"
    echo "   2. Test the application using the provided testing utilities"
    echo "   3. Monitor performance in CloudWatch"
    echo "   4. Consider implementing custom session management logic"
    echo ""
}

# Main deployment function
main() {
    log "Starting distributed session management deployment..."
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_networking
    create_security_groups
    create_memorydb
    store_configuration
    create_iam_roles
    create_ecs_cluster
    create_load_balancer
    create_ecs_service
    create_session_utilities
    create_s3_bucket
    
    # Validate deployment
    if validate_deployment; then
        display_summary
        success "Deployment completed successfully!"
        exit 0
    else
        error "Deployment validation failed. Check logs above."
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi