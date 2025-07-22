#!/bin/bash

# Deploy script for Serverless Container Applications with AWS Fargate
# This script automates the deployment of a containerized application using AWS Fargate

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Error handling function
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Clean up any resources that might have been created
    if [ ! -z "$CLUSTER_NAME" ]; then
        aws ecs delete-cluster --cluster "$CLUSTER_NAME" 2>/dev/null || true
    fi
    
    if [ ! -z "$REPOSITORY_NAME" ]; then
        aws ecr delete-repository --repository-name "$REPOSITORY_NAME" --force 2>/dev/null || true
    fi
    
    if [ ! -z "$FARGATE_SG_ID" ]; then
        aws ec2 delete-security-group --group-id "$FARGATE_SG_ID" 2>/dev/null || true
    fi
    
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker ps &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate random suffix for globally unique resource names
    RANDOM_STRING=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export CLUSTER_NAME="fargate-demo-${RANDOM_STRING}"
    export REPOSITORY_NAME="demo-app-${RANDOM_STRING}"
    export SERVICE_NAME="demo-service"
    export TASK_FAMILY="demo-task"
    
    log_success "Environment variables configured"
    log_info "Cluster Name: $CLUSTER_NAME"
    log_info "Repository Name: $REPOSITORY_NAME"
    log_info "AWS Region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
}

# Create foundational AWS resources
create_foundational_resources() {
    log_info "Creating foundational AWS resources..."
    
    # Create ECS cluster
    log_info "Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster \
        --cluster-name "$CLUSTER_NAME" \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1
    
    # Create ECR repository
    log_info "Creating ECR repository: $REPOSITORY_NAME"
    aws ecr create-repository \
        --repository-name "$REPOSITORY_NAME" \
        --image-scanning-configuration scanOnPush=true
    
    # Get ECR repository URI
    export REPOSITORY_URI=$(aws ecr describe-repositories \
        --repository-names "$REPOSITORY_NAME" \
        --query 'repositories[0].repositoryUri' --output text)
    
    log_success "Foundational resources created"
    log_info "Repository URI: $REPOSITORY_URI"
}

# Create sample application
create_sample_application() {
    log_info "Creating sample containerized application..."
    
    # Create application directory
    mkdir -p fargate-demo-app
    cd fargate-demo-app
    
    # Create Node.js application
    cat << 'EOF' > app.js
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from AWS Fargate!',
    timestamp: new Date().toISOString(),
    hostname: require('os').hostname()
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Server running on port ${port}`);
});
EOF
    
    # Create package.json
    cat << 'EOF' > package.json
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
  }
}
EOF
    
    # Create Dockerfile
    cat << 'EOF' > Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --only=production
COPY . .
EXPOSE 3000
USER node
CMD ["npm", "start"]
EOF
    
    cd ..
    log_success "Sample application created"
}

# Build and push container image
build_and_push_image() {
    log_info "Building and pushing container image to ECR..."
    
    cd fargate-demo-app
    
    # Build the Docker image
    log_info "Building Docker image..."
    docker build -t "$REPOSITORY_NAME" .
    
    # Tag the image for ECR
    docker tag "$REPOSITORY_NAME:latest" "$REPOSITORY_URI:latest"
    
    # Get ECR login token and authenticate Docker client
    log_info "Authenticating Docker with ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$REPOSITORY_URI"
    
    # Push the image to ECR
    log_info "Pushing image to ECR..."
    docker push "$REPOSITORY_URI:latest"
    
    cd ..
    log_success "Container image pushed to ECR"
}

# Create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles for ECS task execution..."
    
    # Create task execution role trust policy
    cat << 'EOF' > task-execution-assume-role-policy.json
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
    
    # Create the task execution role
    log_info "Creating ECS task execution role..."
    aws iam create-role \
        --role-name "ecsTaskExecutionRole-${RANDOM_STRING}" \
        --assume-role-policy-document file://task-execution-assume-role-policy.json
    
    # Attach the required policy for task execution
    aws iam attach-role-policy \
        --role-name "ecsTaskExecutionRole-${RANDOM_STRING}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Get the execution role ARN
    export EXECUTION_ROLE_ARN=$(aws iam get-role \
        --role-name "ecsTaskExecutionRole-${RANDOM_STRING}" \
        --query 'Role.Arn' --output text)
    
    # Save role name for cleanup
    export EXECUTION_ROLE_NAME="ecsTaskExecutionRole-${RANDOM_STRING}"
    
    log_success "IAM roles created"
    log_info "Execution Role ARN: $EXECUTION_ROLE_ARN"
}

# Create task definition
create_task_definition() {
    log_info "Creating ECS task definition..."
    
    # Get default VPC information for networking
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    # Create CloudWatch log group
    log_info "Creating CloudWatch log group..."
    aws logs create-log-group \
        --log-group-name "/ecs/$TASK_FAMILY" \
        --region "$AWS_REGION" || log_warning "Log group may already exist"
    
    # Create task definition JSON
    cat << EOF > task-definition.json
{
  "family": "$TASK_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "demo-container",
      "image": "$REPOSITORY_URI:latest",
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
          "awslogs-group": "/ecs/$TASK_FAMILY",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
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
    
    # Register the task definition
    log_info "Registering task definition..."
    aws ecs register-task-definition \
        --cli-input-json file://task-definition.json
    
    log_success "Task definition registered: $TASK_FAMILY"
}

# Create networking configuration
create_networking() {
    log_info "Creating security groups and networking configuration..."
    
    # Create security group for the Fargate tasks
    export FARGATE_SG_ID=$(aws ec2 create-security-group \
        --group-name "fargate-demo-sg-${RANDOM_STRING}" \
        --description "Security group for Fargate demo application" \
        --vpc-id "$DEFAULT_VPC_ID" \
        --query 'GroupId' --output text)
    
    # Allow inbound traffic on port 3000
    aws ec2 authorize-security-group-ingress \
        --group-id "$FARGATE_SG_ID" \
        --protocol tcp --port 3000 --cidr 0.0.0.0/0
    
    # Get default subnets for the VPC
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
    
    log_success "Networking configured"
    log_info "Security Group ID: $FARGATE_SG_ID"
    log_info "Subnet IDs: $SUBNET_IDS"
}

# Create ECS service
create_ecs_service() {
    log_info "Creating ECS service with high availability..."
    
    # Create the ECS service
    aws ecs create-service \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --task-definition "$TASK_FAMILY" \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$FARGATE_SG_ID],assignPublicIp=ENABLED}" \
        --enable-execute-command
    
    # Wait for the service to stabilize
    log_info "Waiting for service to become stable (this may take a few minutes)..."
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME"
    
    log_success "ECS service created and stable: $SERVICE_NAME"
}

# Configure auto-scaling
configure_autoscaling() {
    log_info "Configuring service auto-scaling policies..."
    
    # Register the service as a scalable target
    aws application-autoscaling register-scalable-target \
        --service-namespace ecs \
        --resource-id "service/$CLUSTER_NAME/$SERVICE_NAME" \
        --scalable-dimension ecs:service:DesiredCount \
        --min-capacity 1 \
        --max-capacity 10
    
    # Create target tracking scaling policy based on CPU utilization
    aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id "service/$CLUSTER_NAME/$SERVICE_NAME" \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name cpu-target-tracking-scaling-policy \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration '{
            "TargetValue": 50.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }'
    
    log_success "Auto-scaling configured for the service"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check cluster status
    CLUSTER_STATUS=$(aws ecs describe-clusters \
        --clusters "$CLUSTER_NAME" \
        --query 'clusters[0].status' --output text)
    
    if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
        log_success "ECS cluster is active"
    else
        log_error "ECS cluster status: $CLUSTER_STATUS"
        return 1
    fi
    
    # Check service status
    SERVICE_INFO=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query 'services[0].[runningCount,desiredCount]' \
        --output text)
    
    RUNNING_COUNT=$(echo $SERVICE_INFO | cut -d' ' -f1)
    DESIRED_COUNT=$(echo $SERVICE_INFO | cut -d' ' -f2)
    
    if [ "$RUNNING_COUNT" = "$DESIRED_COUNT" ]; then
        log_success "Service is running $RUNNING_COUNT/$DESIRED_COUNT tasks"
    else
        log_warning "Service running $RUNNING_COUNT/$DESIRED_COUNT tasks"
    fi
    
    # Test application connectivity
    log_info "Testing application connectivity..."
    TASK_ARNS=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --query 'taskArns[*]' --output text)
    
    SUCCESSFUL_TESTS=0
    TOTAL_TESTS=0
    
    for TASK_ARN in $TASK_ARNS; do
        ((TOTAL_TESTS++))
        
        # Get task details including network interface
        TASK_DETAILS=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN")
        
        # Extract public IP address
        PUBLIC_IP=$(echo $TASK_DETAILS | \
            jq -r '.tasks[0].attachments[0].details[] | select(.name=="networkInterfaceId").value' | \
            xargs -I {} aws ec2 describe-network-interfaces \
            --network-interface-ids {} \
            --query 'NetworkInterfaces[0].Association.PublicIp' --output text 2>/dev/null || echo "null")
        
        if [ "$PUBLIC_IP" != "null" ] && [ "$PUBLIC_IP" != "" ] && [ "$PUBLIC_IP" != "None" ]; then
            log_info "Testing task at IP: $PUBLIC_IP"
            if curl -f -s --max-time 10 "http://$PUBLIC_IP:3000" > /dev/null; then
                log_success "Task responding at $PUBLIC_IP"
                ((SUCCESSFUL_TESTS++))
            else
                log_warning "Task not responding at $PUBLIC_IP"
            fi
        else
            log_warning "Could not get public IP for task"
        fi
    done
    
    log_info "Connectivity test results: $SUCCESSFUL_TESTS/$TOTAL_TESTS tasks responding"
    
    # Check auto-scaling policies
    SCALING_POLICIES=$(aws application-autoscaling describe-scaling-policies \
        --service-namespace ecs \
        --resource-id "service/$CLUSTER_NAME/$SERVICE_NAME" \
        --query 'ScalingPolicies[*].PolicyName' --output text)
    
    if [ -n "$SCALING_POLICIES" ]; then
        log_success "Auto-scaling policies configured: $SCALING_POLICIES"
    else
        log_warning "No auto-scaling policies found"
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat << EOF > deployment-info.json
{
    "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "clusterName": "$CLUSTER_NAME",
    "serviceName": "$SERVICE_NAME",
    "taskFamily": "$TASK_FAMILY",
    "repositoryName": "$REPOSITORY_NAME",
    "repositoryUri": "$REPOSITORY_URI",
    "executionRoleName": "$EXECUTION_ROLE_NAME",
    "executionRoleArn": "$EXECUTION_ROLE_ARN",
    "securityGroupId": "$FARGATE_SG_ID",
    "vpcId": "$DEFAULT_VPC_ID",
    "subnetIds": "$SUBNET_IDS",
    "awsRegion": "$AWS_REGION",
    "awsAccountId": "$AWS_ACCOUNT_ID"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Main deployment function
main() {
    log_info "Starting deployment of Serverless Container Applications with AWS Fargate"
    log_info "========================================================================"
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_sample_application
    build_and_push_image
    create_iam_roles
    create_task_definition
    create_networking
    create_ecs_service
    configure_autoscaling
    validate_deployment
    save_deployment_info
    
    log_success "========================================================================"
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "Resources created:"
    log_info "- ECS Cluster: $CLUSTER_NAME"
    log_info "- ECR Repository: $REPOSITORY_NAME"
    log_info "- ECS Service: $SERVICE_NAME"
    log_info "- Task Definition: $TASK_FAMILY"
    log_info "- Execution Role: $EXECUTION_ROLE_NAME"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_warning "Remember to clean up resources to avoid ongoing charges!"
}

# Run main function
main "$@"