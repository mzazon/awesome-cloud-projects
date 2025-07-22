#!/bin/bash

# Deploy script for Blue-Green Deployments with ECS
# This script implements the complete deployment process from the recipe

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export CLUSTER_NAME="bluegreen-cluster-${RANDOM_SUFFIX}"
    export SERVICE_NAME="bluegreen-service-${RANDOM_SUFFIX}"
    export ALB_NAME="bluegreen-alb-${RANDOM_SUFFIX}"
    export ECR_REPO_NAME="bluegreen-app-${RANDOM_SUFFIX}"
    export CODEDEPLOY_APP_NAME="bluegreen-app-${RANDOM_SUFFIX}"
    
    # Store environment variables for cleanup script
    cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
CLUSTER_NAME=$CLUSTER_NAME
SERVICE_NAME=$SERVICE_NAME
ALB_NAME=$ALB_NAME
ECR_REPO_NAME=$ECR_REPO_NAME
CODEDEPLOY_APP_NAME=$CODEDEPLOY_APP_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    success "Environment variables configured"
}

# Function to create VPC and networking resources
create_networking() {
    log "Creating VPC and networking resources..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --resources $VPC_ID \
        --tags Key=Name,Value="BlueGreen-VPC-${RANDOM_SUFFIX}"
    
    # Create subnets in different AZs
    SUBNET_1_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --query 'Subnet.SubnetId' --output text)
    
    SUBNET_2_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.2.0/24 \
        --availability-zone ${AWS_REGION}b \
        --query 'Subnet.SubnetId' --output text)
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --vpc-id $VPC_ID \
        --internet-gateway-id $IGW_ID
    
    # Create and configure route table
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route \
        --route-table-id $ROUTE_TABLE_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID
    
    # Associate subnets with route table
    aws ec2 associate-route-table \
        --subnet-id $SUBNET_1_ID \
        --route-table-id $ROUTE_TABLE_ID
    
    aws ec2 associate-route-table \
        --subnet-id $SUBNET_2_ID \
        --route-table-id $ROUTE_TABLE_ID
    
    # Create security group
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "bluegreen-sg-${RANDOM_SUFFIX}" \
        --description "Security group for blue-green deployment" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    # Store networking variables
    cat >> .env << EOF
VPC_ID=$VPC_ID
SUBNET_1_ID=$SUBNET_1_ID
SUBNET_2_ID=$SUBNET_2_ID
IGW_ID=$IGW_ID
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
SECURITY_GROUP_ID=$SECURITY_GROUP_ID
EOF
    
    success "VPC and networking resources created"
}

# Function to create ECR repository and push sample application
create_ecr_and_push_app() {
    log "Creating ECR repository and pushing sample application..."
    
    # Create ECR repository
    aws ecr create-repository \
        --repository-name $ECR_REPO_NAME \
        --region $AWS_REGION
    
    # Get login token and login to ECR
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    # Create sample application files
    cat > Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
    
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Blue-Green Demo v1.0</title></head>
<body style="background-color: #4CAF50; color: white; text-align: center; padding: 50px;">
    <h1>Blue-Green Deployment Demo</h1>
    <h2>Version 1.0 - Green Environment</h2>
    <p>This is the initial version of the application.</p>
</body>
</html>
EOF
    
    # Build and push Docker image
    docker build -t $ECR_REPO_NAME:v1.0 .
    docker tag $ECR_REPO_NAME:v1.0 \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$ECR_REPO_NAME:v1.0
    
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$ECR_REPO_NAME:v1.0
    
    success "ECR repository created and initial application pushed"
}

# Function to create ECS cluster
create_ecs_cluster() {
    log "Creating ECS cluster..."
    
    aws ecs create-cluster \
        --cluster-name $CLUSTER_NAME \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1 \
        --region $AWS_REGION
    
    success "ECS cluster created: $CLUSTER_NAME"
}

# Function to create Application Load Balancer and Target Groups
create_alb_and_target_groups() {
    log "Creating Application Load Balancer and Target Groups..."
    
    # Create Application Load Balancer
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name $ALB_NAME \
        --subnets $SUBNET_1_ID $SUBNET_2_ID \
        --security-groups $SECURITY_GROUP_ID \
        --region $AWS_REGION \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Create blue target group
    BLUE_TG_ARN=$(aws elbv2 create-target-group \
        --name "blue-tg-${RANDOM_SUFFIX}" \
        --protocol HTTP \
        --port 80 \
        --target-type ip \
        --vpc-id $VPC_ID \
        --health-check-path / \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region $AWS_REGION \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create green target group
    GREEN_TG_ARN=$(aws elbv2 create-target-group \
        --name "green-tg-${RANDOM_SUFFIX}" \
        --protocol HTTP \
        --port 80 \
        --target-type ip \
        --vpc-id $VPC_ID \
        --health-check-path / \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region $AWS_REGION \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener (initially points to blue target group)
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=$BLUE_TG_ARN \
        --region $AWS_REGION \
        --query 'Listeners[0].ListenerArn' --output text)
    
    # Store ALB variables
    cat >> .env << EOF
ALB_ARN=$ALB_ARN
BLUE_TG_ARN=$BLUE_TG_ARN
GREEN_TG_ARN=$GREEN_TG_ARN
LISTENER_ARN=$LISTENER_ARN
EOF
    
    success "ALB and target groups created"
}

# Function to create task definition and IAM roles
create_task_definition() {
    log "Creating task definition and IAM roles..."
    
    # Create task execution role
    TASK_EXECUTION_ROLE_ARN=$(aws iam create-role \
        --role-name "ecsTaskExecutionRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document '{
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
        }' \
        --query 'Role.Arn' --output text)
    
    # Attach managed policy to task execution role
    aws iam attach-role-policy \
        --role-name "ecsTaskExecutionRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/ecs/bluegreen-task-${RANDOM_SUFFIX}" \
        --region $AWS_REGION
    
    # Create task definition
    cat > task-definition.json << EOF
{
    "family": "bluegreen-task-${RANDOM_SUFFIX}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${TASK_EXECUTION_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "bluegreen-container",
            "image": "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:v1.0",
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
                    "awslogs-group": "/ecs/bluegreen-task-${RANDOM_SUFFIX}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            }
        }
    ]
}
EOF
    
    # Register task definition
    TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file://task-definition.json \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' --output text)
    
    # Store task definition variables
    cat >> .env << EOF
TASK_EXECUTION_ROLE_ARN=$TASK_EXECUTION_ROLE_ARN
TASK_DEF_ARN=$TASK_DEF_ARN
EOF
    
    success "Task definition and IAM roles created"
}

# Function to create CodeDeploy application and deployment group
create_codedeploy() {
    log "Creating CodeDeploy application and deployment group..."
    
    # Create CodeDeploy service role
    CODEDEPLOY_ROLE_ARN=$(aws iam create-role \
        --role-name "CodeDeployServiceRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "codedeploy.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --query 'Role.Arn' --output text)
    
    # Attach managed policy to CodeDeploy service role
    aws iam attach-role-policy \
        --role-name "CodeDeployServiceRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS
    
    # Wait for role to be ready
    sleep 10
    
    # Create CodeDeploy application
    aws deploy create-application \
        --application-name $CODEDEPLOY_APP_NAME \
        --compute-platform ECS \
        --region $AWS_REGION
    
    # Create deployment group
    aws deploy create-deployment-group \
        --application-name $CODEDEPLOY_APP_NAME \
        --deployment-group-name "bluegreen-dg-${RANDOM_SUFFIX}" \
        --service-role-arn $CODEDEPLOY_ROLE_ARN \
        --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
        --blue-green-deployment-configuration \
        terminateBlueInstancesOnDeploymentSuccess='{terminationWaitTimeInMinutes=5}',deploymentReadyOption='{actionOnTimeout=CONTINUE_DEPLOYMENT}',greenFleetProvisioningOption='{action=COPY_AUTO_SCALING_GROUP}' \
        --load-balancer-info targetGroupInfoList='{name=blue-tg-'${RANDOM_SUFFIX}'}' \
        --region $AWS_REGION
    
    # Store CodeDeploy variables
    cat >> .env << EOF
CODEDEPLOY_ROLE_ARN=$CODEDEPLOY_ROLE_ARN
EOF
    
    success "CodeDeploy application and deployment group created"
}

# Function to create ECS service
create_ecs_service() {
    log "Creating ECS service with blue-green deployment configuration..."
    
    # Create service with CODE_DEPLOY deployment controller
    cat > service-definition.json << EOF
{
    "cluster": "${CLUSTER_NAME}",
    "serviceName": "${SERVICE_NAME}",
    "taskDefinition": "${TASK_DEF_ARN}",
    "loadBalancers": [
        {
            "targetGroupArn": "${BLUE_TG_ARN}",
            "containerName": "bluegreen-container",
            "containerPort": 80
        }
    ],
    "desiredCount": 2,
    "launchType": "FARGATE",
    "deploymentController": {
        "type": "CODE_DEPLOY"
    },
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": ["${SUBNET_1_ID}", "${SUBNET_2_ID}"],
            "securityGroups": ["${SECURITY_GROUP_ID}"],
            "assignPublicIp": "ENABLED"
        }
    }
}
EOF
    
    # Create ECS service
    SERVICE_ARN=$(aws ecs create-service \
        --cli-input-json file://service-definition.json \
        --region $AWS_REGION \
        --query 'service.serviceArn' --output text)
    
    # Wait for service to stabilize
    log "Waiting for service to stabilize..."
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION
    
    # Store service variables
    cat >> .env << EOF
SERVICE_ARN=$SERVICE_ARN
EOF
    
    success "ECS service created with blue-green deployment configuration"
}

# Function to create S3 bucket for deployment artifacts
create_s3_bucket() {
    log "Creating S3 bucket for deployment artifacts..."
    
    DEPLOYMENT_BUCKET="bluegreen-deployments-${RANDOM_SUFFIX}"
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://$DEPLOYMENT_BUCKET --region $AWS_REGION
    else
        aws s3 mb s3://$DEPLOYMENT_BUCKET --region $AWS_REGION \
            --create-bucket-configuration LocationConstraint=$AWS_REGION
    fi
    
    # Store bucket variable
    cat >> .env << EOF
DEPLOYMENT_BUCKET=$DEPLOYMENT_BUCKET
EOF
    
    success "S3 bucket created for deployment artifacts"
}

# Function to get ALB DNS name
get_alb_dns() {
    log "Getting ALB DNS name..."
    
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns $ALB_ARN \
        --region $AWS_REGION \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    # Store ALB DNS
    cat >> .env << EOF
ALB_DNS=$ALB_DNS
EOF
    
    success "Application available at: http://$ALB_DNS"
}

# Function to perform post-deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check service status
    SERVICE_STATUS=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].status' --output text)
    
    if [[ "$SERVICE_STATUS" == "ACTIVE" ]]; then
        success "ECS service is active"
    else
        error "ECS service is not active. Status: $SERVICE_STATUS"
        exit 1
    fi
    
    # Wait for ALB to be ready
    log "Waiting for ALB to be ready..."
    sleep 30
    
    # Test application availability
    MAX_RETRIES=10
    RETRY_COUNT=0
    
    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        if curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS | grep -q "200"; then
            success "Application is responding successfully"
            break
        else
            warning "Application not yet ready, retrying... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
            sleep 30
            ((RETRY_COUNT++))
        fi
    done
    
    if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
        error "Application failed to respond after $MAX_RETRIES retries"
        exit 1
    fi
    
    success "Deployment validation completed successfully"
}

# Function to create deployment helper script
create_deployment_script() {
    log "Creating deployment helper script..."
    
    cat > blue-green-deploy.sh << 'EOF'
#!/bin/bash

# Blue-Green Deployment Helper Script
# This script performs a blue-green deployment with a new application version

set -e

# Load environment variables
source .env

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to create updated application version
create_updated_version() {
    log "Creating updated application version..."
    
    # Create updated index.html for v2.0
    cat > index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Blue-Green Demo v2.0</title></head>
<body style="background-color: #2196F3; color: white; text-align: center; padding: 50px;">
    <h1>Blue-Green Deployment Demo</h1>
    <h2>Version 2.0 - Blue Environment</h2>
    <p>This is the updated version with new features!</p>
    <p>Deployed using blue-green deployment strategy.</p>
</body>
</html>
HTMLEOF
    
    # Build and push new version
    docker build -t $ECR_REPO_NAME:v2.0 .
    docker tag $ECR_REPO_NAME:v2.0 \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$ECR_REPO_NAME:v2.0
    
    # Get login token and login to ECR
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$ECR_REPO_NAME:v2.0
    
    success "Updated application version created and pushed"
}

# Function to create AppSpec file
create_appspec() {
    log "Creating AppSpec file for deployment..."
    
    cat > appspec.yaml << APPSPECEOF
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: "${UPDATED_TASK_DEF_ARN}"
        LoadBalancerInfo:
          ContainerName: "bluegreen-container"
          ContainerPort: 80
        PlatformVersion: "LATEST"
        NetworkConfiguration:
          AwsvpcConfiguration:
            Subnets: ["${SUBNET_1_ID}", "${SUBNET_2_ID}"]
            SecurityGroups: ["${SECURITY_GROUP_ID}"]
            AssignPublicIp: "ENABLED"
APPSPECEOF
    
    # Upload AppSpec file to S3
    aws s3 cp appspec.yaml s3://$DEPLOYMENT_BUCKET/appspec.yaml
    
    success "AppSpec file created and uploaded to S3"
}

# Function to register updated task definition
register_updated_task_definition() {
    log "Registering updated task definition..."
    
    # Create new task definition with updated image
    cat > updated-task-definition.json << TASKDEFEOF
{
    "family": "bluegreen-task-${RANDOM_SUFFIX}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${TASK_EXECUTION_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "bluegreen-container",
            "image": "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:v2.0",
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
                    "awslogs-group": "/ecs/bluegreen-task-${RANDOM_SUFFIX}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            }
        }
    ]
}
TASKDEFEOF
    
    # Register updated task definition
    UPDATED_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file://updated-task-definition.json \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' --output text)
    
    # Update environment file
    echo "UPDATED_TASK_DEF_ARN=$UPDATED_TASK_DEF_ARN" >> .env
    
    success "Updated task definition registered"
}

# Function to execute blue-green deployment
execute_deployment() {
    log "Executing blue-green deployment..."
    
    # Create deployment
    DEPLOYMENT_ID=$(aws deploy create-deployment \
        --application-name $CODEDEPLOY_APP_NAME \
        --deployment-group-name "bluegreen-dg-${RANDOM_SUFFIX}" \
        --revision revisionType=S3,s3Location='{bucket='$DEPLOYMENT_BUCKET',key=appspec.yaml,bundleType=YAML}' \
        --region $AWS_REGION \
        --query 'deploymentId' --output text)
    
    log "Blue-green deployment started with ID: $DEPLOYMENT_ID"
    
    # Monitor deployment status
    log "Monitoring deployment progress..."
    while true; do
        DEPLOYMENT_STATUS=$(aws deploy get-deployment \
            --deployment-id $DEPLOYMENT_ID \
            --region $AWS_REGION \
            --query 'deploymentInfo.status' --output text)
        
        log "Deployment status: $DEPLOYMENT_STATUS"
        
        if [ "$DEPLOYMENT_STATUS" = "Succeeded" ]; then
            success "Deployment completed successfully!"
            break
        elif [ "$DEPLOYMENT_STATUS" = "Failed" ] || [ "$DEPLOYMENT_STATUS" = "Stopped" ]; then
            error "Deployment failed or was stopped"
            exit 1
        fi
        
        sleep 30
    done
    
    success "Blue-green deployment completed successfully"
    success "Application available at: http://$ALB_DNS"
}

# Main deployment flow
main() {
    log "Starting blue-green deployment process..."
    
    create_updated_version
    register_updated_task_definition
    create_appspec
    execute_deployment
    
    success "Blue-green deployment process completed successfully!"
}

# Execute main function
main "$@"
EOF
    
    chmod +x blue-green-deploy.sh
    
    success "Deployment helper script created"
}

# Main deployment function
main() {
    log "Starting blue-green deployment infrastructure setup..."
    
    check_prerequisites
    setup_environment
    create_networking
    create_ecr_and_push_app
    create_ecs_cluster
    create_alb_and_target_groups
    create_task_definition
    create_codedeploy
    create_ecs_service
    create_s3_bucket
    get_alb_dns
    validate_deployment
    create_deployment_script
    
    success "Blue-green deployment infrastructure setup completed successfully!"
    success "Application is available at: http://$ALB_DNS"
    success "To perform a blue-green deployment, run: ./blue-green-deploy.sh"
    success "To clean up resources, run: ./destroy.sh"
}

# Execute main function
main "$@"