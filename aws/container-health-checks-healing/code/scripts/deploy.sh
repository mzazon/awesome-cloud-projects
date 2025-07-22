#!/bin/bash

# Deploy script for Container Health Checks and Self-Healing Applications
# This script deploys the complete infrastructure including ECS, EKS, ALB, and monitoring

set -e  # Exit on any error
set -o pipefail  # Exit if any command in pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"
MAX_RETRIES=3
RETRY_DELAY=30

# Cleanup function for script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. Run destroy.sh to clean up partial deployment."
        exit 1
    fi
}

trap cleanup_on_exit EXIT

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it first."
        exit 1
    fi
}

# Function to retry commands with exponential backoff
retry_command() {
    local cmd="$1"
    local retries=0
    
    while [[ $retries -lt $MAX_RETRIES ]]; do
        if eval "$cmd"; then
            return 0
        fi
        
        retries=$((retries + 1))
        if [[ $retries -lt $MAX_RETRIES ]]; then
            log_warning "Command failed (attempt $retries/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "Command failed after $MAX_RETRIES attempts: $cmd"
    return 1
}

# Function to check AWS credentials and permissions
check_aws_credentials() {
    log_info "Validating AWS credentials and permissions..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [[ -z "$region" ]]; then
        log_error "AWS region not configured. Please set AWS_DEFAULT_REGION or configure region."
        exit 1
    fi
    
    log_success "AWS credentials validated (Account: $account_id, Region: $region)"
}

# Function to check required permissions
check_permissions() {
    log_info "Checking required AWS permissions..."
    
    local required_services=("ecs" "eks" "ec2" "elbv2" "iam" "logs" "application-autoscaling" "lambda" "cloudwatch")
    
    for service in "${required_services[@]}"; do
        case $service in
            "ecs")
                if ! aws ecs list-clusters --max-items 1 &> /dev/null; then
                    log_error "Missing ECS permissions. Please ensure you have ECS access."
                    exit 1
                fi
                ;;
            "ec2")
                if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
                    log_error "Missing EC2/VPC permissions. Please ensure you have EC2 access."
                    exit 1
                fi
                ;;
            "elbv2")
                if ! aws elbv2 describe-load-balancers --max-items 1 &> /dev/null; then
                    log_error "Missing ELBv2 permissions. Please ensure you have Load Balancer access."
                    exit 1
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    log_error "Missing IAM permissions. Please ensure you have IAM access."
                    exit 1
                fi
                ;;
        esac
    done
    
    log_success "Required permissions validated"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 3)
    
    export CLUSTER_NAME="health-check-cluster-${random_suffix}"
    export SERVICE_NAME="health-check-service-${random_suffix}"
    export ALB_NAME="health-check-alb-${random_suffix}"
    export VPC_NAME="health-check-vpc-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Save state for cleanup
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
CLUSTER_NAME=$CLUSTER_NAME
SERVICE_NAME=$SERVICE_NAME
ALB_NAME=$ALB_NAME
VPC_NAME=$VPC_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_success "Environment variables configured"
    log_info "Deployment suffix: $RANDOM_SUFFIX"
}

# Function to create VPC and networking
create_networking() {
    log_info "Creating VPC and networking components..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --resources $VPC_ID \
        --tags Key=Name,Value=$VPC_NAME
    
    # Create internet gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID
    
    # Create public subnets in different AZs
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
    
    # Create route table and associate with subnets
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route \
        --route-table-id $ROUTE_TABLE_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID
    
    aws ec2 associate-route-table \
        --route-table-id $ROUTE_TABLE_ID \
        --subnet-id $SUBNET_1_ID
    
    aws ec2 associate-route-table \
        --route-table-id $ROUTE_TABLE_ID \
        --subnet-id $SUBNET_2_ID
    
    # Save networking resources to state
    cat >> "$DEPLOYMENT_STATE_FILE" << EOF
VPC_ID=$VPC_ID
IGW_ID=$IGW_ID
SUBNET_1_ID=$SUBNET_1_ID
SUBNET_2_ID=$SUBNET_2_ID
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
EOF
    
    log_success "VPC and networking components created"
}

# Function to create Application Load Balancer
create_alb() {
    log_info "Creating Application Load Balancer and Target Group..."
    
    # Create security group for ALB
    ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name health-check-alb-sg-${RANDOM_SUFFIX} \
        --description "Security group for health check ALB" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id $ALB_SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --group-id $ALB_SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Create Application Load Balancer
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name $ALB_NAME \
        --subnets $SUBNET_1_ID $SUBNET_2_ID \
        --security-groups $ALB_SG_ID \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Create target group with health check configuration
    TG_ARN=$(aws elbv2 create-target-group \
        --name health-check-tg-${RANDOM_SUFFIX} \
        --protocol HTTP \
        --port 80 \
        --vpc-id $VPC_ID \
        --target-type ip \
        --health-check-protocol HTTP \
        --health-check-port traffic-port \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --matcher HttpCode=200 \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Save ALB resources to state
    cat >> "$DEPLOYMENT_STATE_FILE" << EOF
ALB_SG_ID=$ALB_SG_ID
ALB_ARN=$ALB_ARN
TG_ARN=$TG_ARN
EOF
    
    log_success "Application Load Balancer and Target Group created"
}

# Function to create ECS cluster and service
create_ecs_service() {
    log_info "Creating ECS cluster and service..."
    
    # Create ECS cluster
    aws ecs create-cluster \
        --cluster-name $CLUSTER_NAME \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1
    
    # Create security group for ECS tasks
    ECS_SG_ID=$(aws ec2 create-security-group \
        --group-name health-check-ecs-sg-${RANDOM_SUFFIX} \
        --description "Security group for ECS tasks" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id $ECS_SG_ID \
        --protocol tcp \
        --port 80 \
        --source-group $ALB_SG_ID
    
    # Create task execution role
    TASK_EXECUTION_ROLE_ARN=$(aws iam create-role \
        --role-name ecsTaskExecutionRole-${RANDOM_SUFFIX} \
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
    
    aws iam attach-role-policy \
        --role-name ecsTaskExecutionRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 15
    
    # Create task definition
    cat > /tmp/task-definition.json << EOF
{
    "family": "health-check-app-${RANDOM_SUFFIX}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${TASK_EXECUTION_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "health-check-container",
            "image": "nginx:latest",
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 80,
                    "protocol": "tcp"
                }
            ],
            "healthCheck": {
                "command": [
                    "CMD-SHELL",
                    "curl -f http://localhost/health || exit 1"
                ],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/health-check-app-${RANDOM_SUFFIX}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs",
                    "awslogs-create-group": "true"
                }
            },
            "environment": [
                {
                    "name": "NGINX_PORT",
                    "value": "80"
                }
            ],
            "command": [
                "sh",
                "-c",
                "echo 'server { listen 80; location / { return 200 \"Healthy\"; } location /health { return 200 \"OK\"; } }' > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
            ]
        }
    ]
}
EOF
    
    # Register task definition
    aws ecs register-task-definition \
        --cli-input-json file:///tmp/task-definition.json
    
    # Create ECS service
    aws ecs create-service \
        --cluster $CLUSTER_NAME \
        --service-name $SERVICE_NAME \
        --task-definition health-check-app-${RANDOM_SUFFIX} \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1_ID,$SUBNET_2_ID],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=$TG_ARN,containerName=health-check-container,containerPort=80" \
        --health-check-grace-period-seconds 300
    
    # Create ALB listener
    aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TG_ARN
    
    # Save ECS resources to state
    cat >> "$DEPLOYMENT_STATE_FILE" << EOF
ECS_SG_ID=$ECS_SG_ID
TASK_EXECUTION_ROLE_ARN=$TASK_EXECUTION_ROLE_ARN
EOF
    
    log_success "ECS cluster and service created"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms..."
    
    # Create CloudWatch alarm for unhealthy targets
    aws cloudwatch put-metric-alarm \
        --alarm-name "UnhealthyTargets-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when targets are unhealthy" \
        --metric-name UnHealthyHostCount \
        --namespace AWS/ApplicationELB \
        --statistic Average \
        --period 60 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching \
        --dimensions Name=TargetGroup,Value=$(echo $TG_ARN | cut -d'/' -f2-) \
                     Name=LoadBalancer,Value=$(echo $ALB_ARN | cut -d'/' -f2-)
    
    # Create CloudWatch alarm for high response time
    aws cloudwatch put-metric-alarm \
        --alarm-name "HighResponseTime-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when response time is high" \
        --metric-name TargetResponseTime \
        --namespace AWS/ApplicationELB \
        --statistic Average \
        --period 300 \
        --threshold 1.0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching \
        --dimensions Name=TargetGroup,Value=$(echo $TG_ARN | cut -d'/' -f2-) \
                     Name=LoadBalancer,Value=$(echo $ALB_ARN | cut -d'/' -f2-)
    
    # Create CloudWatch alarm for ECS service health
    aws cloudwatch put-metric-alarm \
        --alarm-name "ECSServiceRunningTasks-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when ECS service running tasks are low" \
        --metric-name RunningTaskCount \
        --namespace AWS/ECS \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --treat-missing-data breaching \
        --dimensions Name=ServiceName,Value=$SERVICE_NAME \
                     Name=ClusterName,Value=$CLUSTER_NAME
    
    log_success "CloudWatch alarms created"
}

# Function to configure auto-scaling
configure_autoscaling() {
    log_info "Configuring auto-scaling..."
    
    # Create ECS service auto-scaling target
    aws application-autoscaling register-scalable-target \
        --service-namespace ecs \
        --resource-id service/$CLUSTER_NAME/$SERVICE_NAME \
        --scalable-dimension ecs:service:DesiredCount \
        --min-capacity 1 \
        --max-capacity 10
    
    # Create ECS service scaling policy
    aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id service/$CLUSTER_NAME/$SERVICE_NAME \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name health-check-scaling-policy-${RANDOM_SUFFIX} \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration '{
            "TargetValue": 70.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }'
    
    log_success "Auto-scaling configured"
}

# Function to create self-healing Lambda function
create_lambda_function() {
    log_info "Creating self-healing Lambda function..."
    
    # Create Lambda execution role
    LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name health-check-lambda-role-${RANDOM_SUFFIX} \
        --assume-role-policy-document '{
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
        }' \
        --query 'Role.Arn' --output text)
    
    # Attach policies to Lambda role
    aws iam attach-role-policy \
        --role-name health-check-lambda-role-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name health-check-lambda-role-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
    
    # Create Lambda function code
    cat > /tmp/self-healing-lambda.py << 'EOF'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        
        logger.info(f"Processing alarm: {alarm_name}")
        
        if 'ECSServiceRunningTasks' in alarm_name:
            # Handle ECS service health issues
            cluster_name = extract_cluster_name(alarm_name)
            service_name = extract_service_name(alarm_name)
            
            # Force new deployment to restart unhealthy tasks
            response = ecs.update_service(
                cluster=cluster_name,
                service=service_name,
                forceNewDeployment=True
            )
            
            logger.info(f"Forced new deployment for service {service_name}")
            
        elif 'UnhealthyTargets' in alarm_name:
            # Handle load balancer health issues
            logger.info("Unhealthy targets detected, ECS will handle automatically")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Self-healing action completed')
        }
        
    except Exception as e:
        logger.error(f"Error in self-healing: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def extract_cluster_name(alarm_name):
    # Extract cluster name from alarm name
    return alarm_name.split('-')[-1]

def extract_service_name(alarm_name):
    # Extract service name from alarm name
    return alarm_name.split('-')[-1]
EOF
    
    # Create deployment package
    cd /tmp
    zip self-healing-lambda.zip self-healing-lambda.py
    
    # Wait for IAM role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 15
    
    # Create Lambda function
    LAMBDA_ARN=$(aws lambda create-function \
        --function-name self-healing-function-${RANDOM_SUFFIX} \
        --runtime python3.9 \
        --role $LAMBDA_ROLE_ARN \
        --handler self-healing-lambda.lambda_handler \
        --zip-file fileb://self-healing-lambda.zip \
        --timeout 60 \
        --query 'FunctionArn' --output text)
    
    # Save Lambda resources to state
    cat >> "$DEPLOYMENT_STATE_FILE" << EOF
LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN
LAMBDA_ARN=$LAMBDA_ARN
EOF
    
    log_success "Self-healing Lambda function created"
}

# Function to wait for services to stabilize
wait_for_services() {
    log_info "Waiting for ECS service to stabilize..."
    
    retry_command "aws ecs wait services-stable --cluster $CLUSTER_NAME --services $SERVICE_NAME"
    
    log_success "ECS service stabilized"
}

# Function to display deployment information
show_deployment_info() {
    log_info "Deployment completed successfully!"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns $ALB_ARN \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    echo ""
    echo "=== DEPLOYMENT INFORMATION ==="
    echo "Application Load Balancer DNS: http://$ALB_DNS"
    echo "Health Check Endpoint: http://$ALB_DNS/health"
    echo "ECS Cluster: $CLUSTER_NAME"
    echo "ECS Service: $SERVICE_NAME"
    echo "Deployment Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "CloudWatch Alarms:"
    echo "  - UnhealthyTargets-${RANDOM_SUFFIX}"
    echo "  - HighResponseTime-${RANDOM_SUFFIX}"
    echo "  - ECSServiceRunningTasks-${RANDOM_SUFFIX}"
    echo ""
    echo "To test the deployment:"
    echo "  curl http://$ALB_DNS"
    echo "  curl http://$ALB_DNS/health"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "================================"
}

# Main deployment function
main() {
    log_info "Starting Container Health Checks and Self-Healing Applications deployment..."
    
    # Prerequisites check
    check_command "aws"
    check_command "curl"
    check_command "zip"
    
    # AWS validation
    check_aws_credentials
    check_permissions
    
    # Setup
    setup_environment
    
    # Deploy infrastructure
    create_networking
    create_alb
    create_ecs_service
    create_cloudwatch_alarms
    configure_autoscaling
    create_lambda_function
    
    # Wait for services to be ready
    wait_for_services
    
    # Show deployment information
    show_deployment_info
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"