#!/bin/bash

# ECS Service Discovery with Route 53 and Application Load Balancer - Deployment Script
# This script deploys the complete infrastructure for ECS service discovery with ALB integration

set -euo pipefail

# Color codes for output
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$aws_version" =~ ^2\. ]]; then
        error_exit "AWS CLI v2 is required. Current version: $aws_version"
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Check if cleanup script exists and run it
    if [[ -f "$(dirname "$0")/destroy.sh" ]]; then
        log_info "Running cleanup script..."
        bash "$(dirname "$0")/destroy.sh" --force
    fi
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Main deployment function
deploy_infrastructure() {
    log_info "Starting ECS Service Discovery deployment..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not configured. Please set AWS_REGION environment variable or run 'aws configure'."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export CLUSTER_NAME="microservices-cluster-${RANDOM_SUFFIX}"
    export NAMESPACE_NAME="internal.local"
    export ALB_NAME="microservices-alb-${RANDOM_SUFFIX}"
    
    log_info "Generated resource identifiers:"
    log_info "  Cluster: $CLUSTER_NAME"
    log_info "  Namespace: $NAMESPACE_NAME"
    log_info "  ALB: $ALB_NAME"
    
    # Get default VPC and subnets
    log_info "Discovering VPC and subnets..."
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [[ "$VPC_ID" == "None" ]]; then
        error_exit "No default VPC found. Please ensure you have a default VPC or modify the script to use a custom VPC."
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[*].SubnetId" --output text)
    
    log_info "Using VPC: $VPC_ID"
    log_info "Using subnets: $SUBNET_IDS"
    
    # Step 1: Create ECS cluster
    log_info "Creating ECS cluster..."
    aws ecs create-cluster \
        --cluster-name ${CLUSTER_NAME} \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1 \
        --tags key=Environment,value=Demo key=Project,value=ServiceDiscovery
    
    log_success "Created ECS cluster: ${CLUSTER_NAME}"
    
    # Step 2: Create AWS Cloud Map private DNS namespace
    log_info "Creating AWS Cloud Map private DNS namespace..."
    NAMESPACE_OPERATION=$(aws servicediscovery create-private-dns-namespace \
        --name ${NAMESPACE_NAME} \
        --vpc ${VPC_ID} \
        --description "Private DNS namespace for microservices" \
        --query "OperationId" --output text)
    
    # Wait for namespace creation to complete
    log_info "Waiting for namespace creation to complete..."
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        local operation_status=$(aws servicediscovery get-operation \
            --operation-id ${NAMESPACE_OPERATION} \
            --query "Operation.Status" --output text)
        
        if [[ "$operation_status" == "SUCCESS" ]]; then
            break
        elif [[ "$operation_status" == "FAIL" ]]; then
            error_exit "Namespace creation failed"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error_exit "Timeout waiting for namespace creation"
    fi
    
    # Get the namespace ID
    export NAMESPACE_ID=$(aws servicediscovery list-namespaces \
        --query "Namespaces[?Name=='${NAMESPACE_NAME}'].Id" \
        --output text)
    
    log_success "Created namespace: ${NAMESPACE_NAME} (${NAMESPACE_ID})"
    
    # Step 3: Create security group for ALB
    log_info "Creating security group for Application Load Balancer..."
    export ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name "alb-sg-${RANDOM_SUFFIX}" \
        --description "Security group for Application Load Balancer" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=alb-sg-${RANDOM_SUFFIX}},{Key=Environment,Value=Demo}]" \
        --query "GroupId" --output text)
    
    # Allow HTTP and HTTPS traffic to ALB
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp --port 80 --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp --port 443 --cidr 0.0.0.0/0
    
    log_success "Created ALB security group: ${ALB_SG_ID}"
    
    # Step 4: Create Application Load Balancer
    log_info "Creating Application Load Balancer..."
    export ALB_ARN=$(aws elbv2 create-load-balancer \
        --name ${ALB_NAME} \
        --subnets ${SUBNET_IDS} \
        --security-groups ${ALB_SG_ID} \
        --tags Key=Environment,Value=Demo Key=Project,Value=ServiceDiscovery \
        --query "LoadBalancers[0].LoadBalancerArn" --output text)
    
    log_success "Created ALB: ${ALB_NAME}"
    
    # Step 5: Create security group for ECS tasks
    log_info "Creating security group for ECS tasks..."
    export ECS_SG_ID=$(aws ec2 create-security-group \
        --group-name "ecs-tasks-sg-${RANDOM_SUFFIX}" \
        --description "Security group for ECS tasks" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ecs-tasks-sg-${RANDOM_SUFFIX}},{Key=Environment,Value=Demo}]" \
        --query "GroupId" --output text)
    
    # Allow traffic from ALB to ECS tasks
    aws ec2 authorize-security-group-ingress \
        --group-id ${ECS_SG_ID} \
        --protocol tcp --port 3000 \
        --source-group ${ALB_SG_ID}
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${ECS_SG_ID} \
        --protocol tcp --port 8080 \
        --source-group ${ALB_SG_ID}
    
    # Allow internal communication between services
    aws ec2 authorize-security-group-ingress \
        --group-id ${ECS_SG_ID} \
        --protocol tcp --port 0-65535 \
        --source-group ${ECS_SG_ID}
    
    log_success "Created ECS security group: ${ECS_SG_ID}"
    
    # Step 6: Create Cloud Map services for service discovery
    log_info "Creating Cloud Map services for service discovery..."
    export WEB_SERVICE_ID=$(aws servicediscovery create-service \
        --name "web" \
        --namespace-id ${NAMESPACE_ID} \
        --dns-config "RoutingPolicy=MULTIVALUE,DnsRecords=[{Type=A,TTL=300}]" \
        --health-check-custom-config FailureThreshold=3 \
        --query "Service.Id" --output text)
    
    export API_SERVICE_ID=$(aws servicediscovery create-service \
        --name "api" \
        --namespace-id ${NAMESPACE_ID} \
        --dns-config "RoutingPolicy=MULTIVALUE,DnsRecords=[{Type=A,TTL=300}]" \
        --health-check-custom-config FailureThreshold=3 \
        --query "Service.Id" --output text)
    
    export DB_SERVICE_ID=$(aws servicediscovery create-service \
        --name "database" \
        --namespace-id ${NAMESPACE_ID} \
        --dns-config "RoutingPolicy=MULTIVALUE,DnsRecords=[{Type=A,TTL=300}]" \
        --health-check-custom-config FailureThreshold=3 \
        --query "Service.Id" --output text)
    
    log_success "Created service discovery services"
    
    # Step 7: Create target groups for ALB
    log_info "Creating target groups for ALB..."
    export WEB_TG_ARN=$(aws elbv2 create-target-group \
        --name "web-tg-${RANDOM_SUFFIX}" \
        --protocol HTTP --port 3000 \
        --target-type ip --vpc-id ${VPC_ID} \
        --health-check-path "/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Environment,Value=Demo Key=Project,Value=ServiceDiscovery \
        --query "TargetGroups[0].TargetGroupArn" --output text)
    
    export API_TG_ARN=$(aws elbv2 create-target-group \
        --name "api-tg-${RANDOM_SUFFIX}" \
        --protocol HTTP --port 8080 \
        --target-type ip --vpc-id ${VPC_ID} \
        --health-check-path "/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Environment,Value=Demo Key=Project,Value=ServiceDiscovery \
        --query "TargetGroups[0].TargetGroupArn" --output text)
    
    log_success "Created target groups for ALB"
    
    # Step 8: Create ALB listeners with routing rules
    log_info "Creating ALB listeners and routing rules..."
    export WEB_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn ${ALB_ARN} \
        --protocol HTTP --port 80 \
        --default-actions Type=forward,TargetGroupArn=${WEB_TG_ARN} \
        --query "Listeners[0].ListenerArn" --output text)
    
    # Create listener rule for API service
    aws elbv2 create-rule \
        --listener-arn ${WEB_LISTENER_ARN} \
        --priority 100 \
        --conditions Field=path-pattern,Values="/api/*" \
        --actions Type=forward,TargetGroupArn=${API_TG_ARN} > /dev/null
    
    log_success "Created ALB listeners and routing rules"
    
    # Step 9: Create IAM execution role for ECS tasks
    log_info "Creating IAM execution role for ECS tasks..."
    
    # Create trust policy file
    cat > /tmp/trust-policy.json << 'EOF'
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
        --role-name "ecsTaskExecutionRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --tags Key=Environment,Value=Demo Key=Project,Value=ServiceDiscovery > /dev/null
    
    aws iam attach-role-policy \
        --role-name "ecsTaskExecutionRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    
    export EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole-${RANDOM_SUFFIX}"
    
    log_success "Created ECS execution role"
    
    # Step 10: Create ECS task definitions
    log_info "Creating ECS task definitions..."
    
    # Create task definition for web service
    cat > /tmp/web-task-definition.json << EOF
{
  "family": "web-service-${RANDOM_SUFFIX}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "web-container",
      "image": "nginx:alpine",
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 3000,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/web-service",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ],
  "tags": [
    {
      "key": "Environment",
      "value": "Demo"
    },
    {
      "key": "Project",
      "value": "ServiceDiscovery"
    }
  ]
}
EOF
    
    aws ecs register-task-definition \
        --cli-input-json file:///tmp/web-task-definition.json > /dev/null
    
    # Create task definition for API service
    cat > /tmp/api-task-definition.json << EOF
{
  "family": "api-service-${RANDOM_SUFFIX}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "api-container",
      "image": "httpd:alpine",
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 8080,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/api-service",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ],
  "tags": [
    {
      "key": "Environment",
      "value": "Demo"
    },
    {
      "key": "Project",
      "value": "ServiceDiscovery"
    }
  ]
}
EOF
    
    aws ecs register-task-definition \
        --cli-input-json file:///tmp/api-task-definition.json > /dev/null
    
    log_success "Created ECS task definitions"
    
    # Step 11: Create ECS services with service discovery and load balancer integration
    log_info "Creating ECS services with service discovery and load balancer integration..."
    
    # Get private subnet IDs for ECS services
    export PRIVATE_SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId" \
        --output text)
    
    # If no private subnets, use all subnets
    if [[ -z "$PRIVATE_SUBNET_IDS" ]]; then
        log_warning "No private subnets found, using all subnets"
        PRIVATE_SUBNET_IDS="$SUBNET_IDS"
    fi
    
    # Create web service with service discovery and ALB integration
    aws ecs create-service \
        --cluster ${CLUSTER_NAME} \
        --service-name "web-service" \
        --task-definition "web-service-${RANDOM_SUFFIX}" \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${PRIVATE_SUBNET_IDS// /,}],securityGroups=[${ECS_SG_ID}],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=${WEB_TG_ARN},containerName=web-container,containerPort=80" \
        --service-registries "registryArn=arn:aws:servicediscovery:${AWS_REGION}:${AWS_ACCOUNT_ID}:service/${WEB_SERVICE_ID}" \
        --tags key=Environment,value=Demo key=Project,value=ServiceDiscovery > /dev/null
    
    # Create API service with service discovery and ALB integration
    aws ecs create-service \
        --cluster ${CLUSTER_NAME} \
        --service-name "api-service" \
        --task-definition "api-service-${RANDOM_SUFFIX}" \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${PRIVATE_SUBNET_IDS// /,}],securityGroups=[${ECS_SG_ID}],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=${API_TG_ARN},containerName=api-container,containerPort=80" \
        --service-registries "registryArn=arn:aws:servicediscovery:${AWS_REGION}:${AWS_ACCOUNT_ID}:service/${API_SERVICE_ID}" \
        --tags key=Environment,value=Demo key=Project,value=ServiceDiscovery > /dev/null
    
    log_success "Created ECS services with service discovery"
    
    # Step 12: Save deployment configuration
    log_info "Saving deployment configuration..."
    
    # Create deployment config file
    cat > /tmp/deployment-config.env << EOF
# ECS Service Discovery Deployment Configuration
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export CLUSTER_NAME=${CLUSTER_NAME}
export NAMESPACE_NAME=${NAMESPACE_NAME}
export NAMESPACE_ID=${NAMESPACE_ID}
export ALB_NAME=${ALB_NAME}
export ALB_ARN=${ALB_ARN}
export VPC_ID=${VPC_ID}
export ALB_SG_ID=${ALB_SG_ID}
export ECS_SG_ID=${ECS_SG_ID}
export WEB_SERVICE_ID=${WEB_SERVICE_ID}
export API_SERVICE_ID=${API_SERVICE_ID}
export DB_SERVICE_ID=${DB_SERVICE_ID}
export WEB_TG_ARN=${WEB_TG_ARN}
export API_TG_ARN=${API_TG_ARN}
export WEB_LISTENER_ARN=${WEB_LISTENER_ARN}
export EXECUTION_ROLE_ARN=${EXECUTION_ROLE_ARN}
export RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    # Move config file to script directory
    mv /tmp/deployment-config.env "$(dirname "$0")/deployment-config.env"
    
    log_success "Deployment configuration saved"
    
    # Clean up temporary files
    rm -f /tmp/trust-policy.json /tmp/web-task-definition.json /tmp/api-task-definition.json
    
    log_success "Deployment completed successfully!"
    
    # Display access information
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${ALB_ARN} \
        --query "LoadBalancers[0].DNSName" --output text)
    
    echo ""
    echo "========================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "========================================="
    echo "ECS Cluster: ${CLUSTER_NAME}"
    echo "DNS Namespace: ${NAMESPACE_NAME}"
    echo "Load Balancer: http://${alb_dns}"
    echo "API Endpoint: http://${alb_dns}/api/"
    echo ""
    echo "Services will be available once health checks pass."
    echo "You can monitor service status with:"
    echo "  aws ecs describe-services --cluster ${CLUSTER_NAME} --services web-service api-service"
    echo ""
    echo "To clean up resources, run:"
    echo "  $(dirname "$0")/destroy.sh"
    echo "========================================="
}

# Dry run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log_info "Running in dry-run mode. No resources will be created."
    check_prerequisites
    log_info "Dry-run completed. All prerequisites are met."
    exit 0
fi

# Main execution
main() {
    log_info "Starting ECS Service Discovery deployment..."
    
    check_prerequisites
    deploy_infrastructure
    
    log_success "ECS Service Discovery deployment completed successfully!"
}

# Execute main function
main "$@"