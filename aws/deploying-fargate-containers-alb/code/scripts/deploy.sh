#!/bin/bash

# Deploy script for Serverless Containers with AWS Fargate and Application Load Balancer
# This script automates the deployment of a containerized application using AWS Fargate
# with Application Load Balancer, ECR, and auto-scaling configuration

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export CLUSTER_NAME="fargate-cluster-${RANDOM_SUFFIX}"
    export SERVICE_NAME="fargate-service-${RANDOM_SUFFIX}"
    export TASK_FAMILY="fargate-task-${RANDOM_SUFFIX}"
    export ECR_REPO_NAME="fargate-demo-${RANDOM_SUFFIX}"
    export ALB_NAME="fargate-alb-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="fargate-sg-${RANDOM_SUFFIX}"
    
    # Get default VPC and subnets
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    # Get public subnets in different AZs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
    
    if [ -z "$SUBNET_IDS" ]; then
        error "No subnets found in default VPC. Please check your VPC configuration."
        exit 1
    fi
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLUSTER_NAME=${CLUSTER_NAME}
SERVICE_NAME=${SERVICE_NAME}
TASK_FAMILY=${TASK_FAMILY}
ECR_REPO_NAME=${ECR_REPO_NAME}
ALB_NAME=${ALB_NAME}
SECURITY_GROUP_NAME=${SECURITY_GROUP_NAME}
VPC_ID=${VPC_ID}
SUBNET_IDS=${SUBNET_IDS}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment setup complete"
    info "VPC ID: ${VPC_ID}"
    info "Subnet IDs: ${SUBNET_IDS}"
    info "Random suffix: ${RANDOM_SUFFIX}"
}

# Create ECR repository
create_ecr_repository() {
    log "Creating ECR repository..."
    
    if aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} &>/dev/null; then
        warn "ECR repository ${ECR_REPO_NAME} already exists"
    else
        aws ecr create-repository \
            --repository-name ${ECR_REPO_NAME} \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
    fi
    
    # Get repository URI
    export ECR_URI=$(aws ecr describe-repositories \
        --repository-names ${ECR_REPO_NAME} \
        --query 'repositories[0].repositoryUri' --output text)
    
    # Add to environment file
    echo "ECR_URI=${ECR_URI}" >> .env
    
    log "ECR repository created: ${ECR_REPO_NAME}"
    info "Repository URI: ${ECR_URI}"
}

# Create sample application
create_sample_application() {
    log "Creating sample containerized application..."
    
    # Create application directory
    mkdir -p fargate-demo-app
    cd fargate-demo-app
    
    # Create Node.js application
    cat > app.js << 'EOF'
const express = require('express');
const os = require('os');
const app = express();
const port = process.env.PORT || 3000;

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        hostname: os.hostname(),
        uptime: process.uptime()
    });
});

// Main application endpoint
app.get('/', (req, res) => {
    const response = {
        message: 'Hello from AWS Fargate!',
        container: {
            hostname: os.hostname(),
            platform: os.platform(),
            architecture: os.arch(),
            memory: `${Math.round(process.memoryUsage().rss / 1024 / 1024)} MB`,
            uptime: `${Math.round(process.uptime())} seconds`
        },
        environment: {
            nodeVersion: process.version,
            port: port,
            timestamp: new Date().toISOString()
        },
        request: {
            method: req.method,
            url: req.url,
            headers: req.headers['user-agent'],
            ip: req.ip
        }
    };
    
    res.json(response);
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    const metrics = {
        memory: process.memoryUsage(),
        cpu: process.cpuUsage(),
        uptime: process.uptime(),
        timestamp: Date.now()
    };
    res.json(metrics);
});

app.listen(port, '0.0.0.0', () => {
    console.log(`Server running on port ${port}`);
    console.log(`Health check available at /health`);
    console.log(`Metrics available at /metrics`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully');
    process.exit(0);
});
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
    "name": "fargate-demo-app",
    "version": "1.0.0",
    "description": "Demo application for AWS Fargate",
    "main": "app.js",
    "scripts": {
        "start": "node app.js"
    },
    "dependencies": {
        "express": "^4.18.2"
    },
    "engines": {
        "node": ">=18.0"
    }
}
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application code
COPY app.js .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Change ownership of app directory
RUN chown -R nodejs:nodejs /app
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"

# Start application
CMD ["npm", "start"]
EOF
    
    cd ..
    log "Sample application created"
}

# Build and push container image
build_and_push_image() {
    log "Building and pushing container image..."
    
    cd fargate-demo-app
    
    # Get ECR login token
    aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS --password-stdin ${ECR_URI}
    
    # Build Docker image
    docker build -t ${ECR_REPO_NAME} .
    
    # Tag image for ECR
    docker tag ${ECR_REPO_NAME}:latest ${ECR_URI}:latest
    docker tag ${ECR_REPO_NAME}:latest ${ECR_URI}:v1.0
    
    # Push image to ECR
    docker push ${ECR_URI}:latest
    docker push ${ECR_URI}:v1.0
    
    cd ..
    log "Container image built and pushed"
    info "Image URI: ${ECR_URI}:latest"
}

# Create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Create security group for ALB
    ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name "${ALB_NAME}-sg" \
        --description "Security group for Fargate ALB" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' --output text)
    
    # Allow HTTP and HTTPS traffic to ALB
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Create security group for Fargate tasks
    FARGATE_SG_ID=$(aws ec2 create-security-group \
        --group-name ${SECURITY_GROUP_NAME} \
        --description "Security group for Fargate tasks" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' --output text)
    
    # Allow traffic from ALB to Fargate tasks
    aws ec2 authorize-security-group-ingress \
        --group-id ${FARGATE_SG_ID} \
        --protocol tcp \
        --port 3000 \
        --source-group ${ALB_SG_ID}
    
    # Allow outbound internet access for Fargate tasks
    aws ec2 authorize-security-group-egress \
        --group-id ${FARGATE_SG_ID} \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-egress \
        --group-id ${FARGATE_SG_ID} \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    # Add to environment file
    echo "ALB_SG_ID=${ALB_SG_ID}" >> .env
    echo "FARGATE_SG_ID=${FARGATE_SG_ID}" >> .env
    
    log "Security groups created"
    info "ALB Security Group: ${ALB_SG_ID}"
    info "Fargate Security Group: ${FARGATE_SG_ID}"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create trust policy
    cat > task-execution-role-trust-policy.json << EOF
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
    
    # Create task execution role
    EXECUTION_ROLE_NAME="ecsTaskExecutionRole-${RANDOM_SUFFIX}"
    
    if aws iam get-role --role-name ${EXECUTION_ROLE_NAME} &>/dev/null; then
        warn "Execution role ${EXECUTION_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name ${EXECUTION_ROLE_NAME} \
            --assume-role-policy-document file://task-execution-role-trust-policy.json
    fi
    
    # Attach managed policy for task execution
    aws iam attach-role-policy \
        --role-name ${EXECUTION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Create task role for application permissions
    TASK_ROLE_NAME="ecsTaskRole-${RANDOM_SUFFIX}"
    
    if aws iam get-role --role-name ${TASK_ROLE_NAME} &>/dev/null; then
        warn "Task role ${TASK_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name ${TASK_ROLE_NAME} \
            --assume-role-policy-document file://task-execution-role-trust-policy.json
    fi
    
    # Create custom policy for task role
    cat > task-role-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    TASK_POLICY_NAME="${TASK_ROLE_NAME}-Policy"
    
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${TASK_POLICY_NAME}" &>/dev/null; then
        warn "Task policy ${TASK_POLICY_NAME} already exists"
    else
        aws iam create-policy \
            --policy-name "${TASK_POLICY_NAME}" \
            --policy-document file://task-role-policy.json
    fi
    
    TASK_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${TASK_POLICY_NAME}"
    
    aws iam attach-role-policy \
        --role-name ${TASK_ROLE_NAME} \
        --policy-arn ${TASK_POLICY_ARN}
    
    # Get role ARNs
    EXECUTION_ROLE_ARN=$(aws iam get-role \
        --role-name ${EXECUTION_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    TASK_ROLE_ARN=$(aws iam get-role \
        --role-name ${TASK_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    # Add to environment file
    echo "EXECUTION_ROLE_NAME=${EXECUTION_ROLE_NAME}" >> .env
    echo "TASK_ROLE_NAME=${TASK_ROLE_NAME}" >> .env
    echo "TASK_POLICY_NAME=${TASK_POLICY_NAME}" >> .env
    echo "TASK_POLICY_ARN=${TASK_POLICY_ARN}" >> .env
    echo "EXECUTION_ROLE_ARN=${EXECUTION_ROLE_ARN}" >> .env
    echo "TASK_ROLE_ARN=${TASK_ROLE_ARN}" >> .env
    
    log "IAM roles created"
    info "Execution Role ARN: ${EXECUTION_ROLE_ARN}"
    info "Task Role ARN: ${TASK_ROLE_ARN}"
}

# Create ECS cluster and task definition
create_ecs_cluster() {
    log "Creating ECS cluster and task definition..."
    
    # Create ECS cluster
    if aws ecs describe-clusters --clusters ${CLUSTER_NAME} --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        warn "ECS cluster ${CLUSTER_NAME} already exists"
    else
        aws ecs create-cluster \
            --cluster-name ${CLUSTER_NAME} \
            --capacity-providers FARGATE FARGATE_SPOT \
            --default-capacity-provider-strategy \
                capacityProvider=FARGATE,weight=1,base=1 \
                capacityProvider=FARGATE_SPOT,weight=4
    fi
    
    # Create CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "/ecs/${TASK_FAMILY}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "/ecs/${TASK_FAMILY}"; then
        warn "Log group /ecs/${TASK_FAMILY} already exists"
    else
        aws logs create-log-group \
            --log-group-name "/ecs/${TASK_FAMILY}" \
            --retention-in-days 7
    fi
    
    # Wait for roles to be available
    sleep 10
    
    # Create task definition
    cat > task-definition.json << EOF
{
    "family": "${TASK_FAMILY}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "taskRoleArn": "${TASK_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "fargate-demo-container",
            "image": "${ECR_URI}:latest",
            "portMappings": [
                {
                    "containerPort": 3000,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/${TASK_FAMILY}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                },
                {
                    "name": "PORT",
                    "value": "3000"
                }
            ],
            "healthCheck": {
                "command": [
                    "CMD-SHELL",
                    "curl -f http://localhost:3000/health || exit 1"
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
    aws ecs register-task-definition \
        --cli-input-json file://task-definition.json
    
    log "ECS cluster and task definition created"
    info "Cluster: ${CLUSTER_NAME}"
    info "Task Definition: ${TASK_FAMILY}"
}

# Create Application Load Balancer
create_load_balancer() {
    log "Creating Application Load Balancer..."
    
    # Create Application Load Balancer
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name ${ALB_NAME} \
        --subnets $(echo ${SUBNET_IDS} | tr ',' ' ') \
        --security-groups ${ALB_SG_ID} \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${ALB_ARN} \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    # Create target group for Fargate service
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "fargate-tg-${RANDOM_SUFFIX}" \
        --protocol HTTP \
        --port 3000 \
        --vpc-id ${VPC_ID} \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --matcher HttpCode=200 \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener for ALB
    aws elbv2 create-listener \
        --load-balancer-arn ${ALB_ARN} \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN}
    
    # Add to environment file
    echo "ALB_ARN=${ALB_ARN}" >> .env
    echo "ALB_DNS=${ALB_DNS}" >> .env
    echo "TARGET_GROUP_ARN=${TARGET_GROUP_ARN}" >> .env
    
    log "Application Load Balancer created"
    info "ALB DNS: ${ALB_DNS}"
    info "Target Group ARN: ${TARGET_GROUP_ARN}"
}

# Create ECS service
create_ecs_service() {
    log "Creating ECS service..."
    
    # Create ECS service
    cat > service-definition.json << EOF
{
    "serviceName": "${SERVICE_NAME}",
    "cluster": "${CLUSTER_NAME}",
    "taskDefinition": "${TASK_FAMILY}",
    "desiredCount": 3,
    "launchType": "FARGATE",
    "platformVersion": "LATEST",
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": [$(echo ${SUBNET_IDS} | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')],$
            "securityGroups": ["${FARGATE_SG_ID}"],
            "assignPublicIp": "ENABLED"
        }
    },
    "loadBalancers": [
        {
            "targetGroupArn": "${TARGET_GROUP_ARN}",
            "containerName": "fargate-demo-container",
            "containerPort": 3000
        }
    ],
    "healthCheckGracePeriodSeconds": 120,
    "deploymentConfiguration": {
        "maximumPercent": 200,
        "minimumHealthyPercent": 50,
        "deploymentCircuitBreaker": {
            "enable": true,
            "rollback": true
        }
    },
    "enableExecuteCommand": true
}
EOF
    
    # Create the service
    aws ecs create-service \
        --cli-input-json file://service-definition.json
    
    log "ECS service created"
    info "Service: ${SERVICE_NAME}"
    info "Desired count: 3 tasks"
}

# Setup auto scaling
setup_auto_scaling() {
    log "Setting up auto scaling..."
    
    # Register scalable target
    aws application-autoscaling register-scalable-target \
        --service-namespace ecs \
        --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
        --scalable-dimension ecs:service:DesiredCount \
        --min-capacity 2 \
        --max-capacity 10
    
    # Create scaling policy for CPU utilization
    CPU_SCALING_POLICY_ARN=$(aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name "${SERVICE_NAME}-cpu-scaling" \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration '{
            "TargetValue": 70.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' \
        --query 'PolicyARN' --output text)
    
    # Create scaling policy for memory utilization
    MEMORY_SCALING_POLICY_ARN=$(aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name "${SERVICE_NAME}-memory-scaling" \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration '{
            "TargetValue": 80.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ECSServiceAverageMemoryUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' \
        --query 'PolicyARN' --output text)
    
    # Add to environment file
    echo "CPU_SCALING_POLICY_ARN=${CPU_SCALING_POLICY_ARN}" >> .env
    echo "MEMORY_SCALING_POLICY_ARN=${MEMORY_SCALING_POLICY_ARN}" >> .env
    
    log "Auto scaling configured"
    info "CPU scaling policy: ${CPU_SCALING_POLICY_ARN}"
    info "Memory scaling policy: ${MEMORY_SCALING_POLICY_ARN}"
}

# Wait for deployment
wait_for_deployment() {
    log "Waiting for deployment to complete..."
    
    # Wait for service to be stable
    info "Waiting for ECS service to stabilize (this may take several minutes)..."
    aws ecs wait services-stable \
        --cluster ${CLUSTER_NAME} \
        --services ${SERVICE_NAME}
    
    # Check target group health
    info "Checking target group health..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local healthy_targets=$(aws elbv2 describe-target-health \
            --target-group-arn ${TARGET_GROUP_ARN} \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' \
            --output text | wc -l)
        
        if [ $healthy_targets -ge 2 ]; then
            log "Targets are healthy!"
            break
        fi
        
        info "Attempt $attempt/$max_attempts: $healthy_targets healthy targets. Waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warn "Deployment completed but not all targets are healthy. Check the ECS console for details."
    fi
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check service status
    local service_status=$(aws ecs describe-services \
        --cluster ${CLUSTER_NAME} \
        --services ${SERVICE_NAME} \
        --query 'services[0].status' --output text)
    
    local running_count=$(aws ecs describe-services \
        --cluster ${CLUSTER_NAME} \
        --services ${SERVICE_NAME} \
        --query 'services[0].runningCount' --output text)
    
    info "Service status: ${service_status}"
    info "Running tasks: ${running_count}"
    
    # Test application endpoints
    info "Testing application endpoints..."
    
    # Test main endpoint
    if curl -s -f "http://${ALB_DNS}/" > /dev/null; then
        log "Main endpoint is accessible"
    else
        warn "Main endpoint is not accessible"
    fi
    
    # Test health endpoint
    if curl -s -f "http://${ALB_DNS}/health" > /dev/null; then
        log "Health endpoint is accessible"
    else
        warn "Health endpoint is not accessible"
    fi
    
    # Show application URL
    info "Application URL: http://${ALB_DNS}"
    info "Health check URL: http://${ALB_DNS}/health"
    info "Metrics URL: http://${ALB_DNS}/metrics"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f task-execution-role-trust-policy.json
    rm -f task-role-policy.json
    rm -f task-definition.json
    rm -f service-definition.json
    
    log "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting Fargate deployment..."
    
    check_prerequisites
    setup_environment
    create_ecr_repository
    create_sample_application
    build_and_push_image
    create_security_groups
    create_iam_roles
    create_ecs_cluster
    create_load_balancer
    create_ecs_service
    setup_auto_scaling
    wait_for_deployment
    validate_deployment
    cleanup_temp_files
    
    log "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "Application URL: http://${ALB_DNS}"
    echo "Health Check URL: http://${ALB_DNS}/health"
    echo "Metrics URL: http://${ALB_DNS}/metrics"
    echo "ECS Cluster: ${CLUSTER_NAME}"
    echo "ECS Service: ${SERVICE_NAME}"
    echo "ECR Repository: ${ECR_REPO_NAME}"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"