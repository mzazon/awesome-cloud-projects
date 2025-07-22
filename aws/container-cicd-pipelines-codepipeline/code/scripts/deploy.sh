#!/bin/bash

# AWS CI/CD Pipeline Deployment Script
# This script deploys the complete CI/CD pipeline infrastructure for containerized applications
# using AWS CodePipeline, CodeDeploy, CodeBuild, and Amazon ECS

set -e  # Exit on any error

# Color codes for output
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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if we're running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode. No actual resources will be created."
fi

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "DRY-RUN: Would execute: $cmd"
        if [ -n "$description" ]; then
            info "DRY-RUN: $description"
        fi
    else
        log "Executing: $description"
        eval "$cmd"
    fi
}

# Banner
echo "=========================================="
echo "    AWS CI/CD Pipeline Deployment"
echo "=========================================="
log "Starting deployment of advanced CI/CD pipeline infrastructure"

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install it first."
fi

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    warn "jq is not installed. Some operations may be limited."
fi

log "Prerequisites check passed ✓"

# Environment Variables Setup
log "Setting up environment variables..."

# Get AWS region and account ID
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [ -z "$AWS_REGION" ]; then
    error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    error "Failed to get AWS account ID"
fi

# Generate unique identifiers
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 8 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")

PROJECT_NAME=${PROJECT_NAME:-"advanced-cicd-${RANDOM_SUFFIX}"}
DEV_CLUSTER_NAME="${PROJECT_NAME}-dev-cluster"
PROD_CLUSTER_NAME="${PROJECT_NAME}-prod-cluster"
SERVICE_NAME="${PROJECT_NAME}-service"
REPOSITORY_NAME="${PROJECT_NAME}-repo"
PIPELINE_NAME="${PROJECT_NAME}-pipeline"
APPLICATION_NAME="${PROJECT_NAME}-app"
BUILD_PROJECT_NAME="${PROJECT_NAME}-build"

log "Environment variables configured:"
info "  AWS_REGION: $AWS_REGION"
info "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
info "  PROJECT_NAME: $PROJECT_NAME"

# Create artifacts S3 bucket
log "Creating S3 bucket for CodePipeline artifacts..."
execute_cmd "aws s3 mb s3://${PROJECT_NAME}-artifacts-${AWS_REGION} --region ${AWS_REGION}" \
    "Create S3 bucket for artifacts"

execute_cmd "aws s3api put-bucket-versioning \
    --bucket ${PROJECT_NAME}-artifacts-${AWS_REGION} \
    --versioning-configuration Status=Enabled" \
    "Enable versioning on artifacts bucket"

# Create Parameter Store parameters
log "Creating Parameter Store parameters..."
execute_cmd "aws ssm put-parameter \
    --name '/${PROJECT_NAME}/app/environment' \
    --value 'production' \
    --type 'String' \
    --description 'Application environment' \
    --overwrite" \
    "Create environment parameter"

execute_cmd "aws ssm put-parameter \
    --name '/${PROJECT_NAME}/app/version' \
    --value '1.0.0' \
    --type 'String' \
    --description 'Application version' \
    --overwrite" \
    "Create version parameter"

# Create ECR repository with security scanning
log "Creating ECR repository with security scanning..."
execute_cmd "aws ecr create-repository \
    --repository-name ${REPOSITORY_NAME} \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --region ${AWS_REGION}" \
    "Create ECR repository with scanning"

# Create lifecycle policy for ECR
cat > /tmp/lifecycle-policy.json << EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 production images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["prod"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Keep last 5 development images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["dev"],
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

execute_cmd "aws ecr put-lifecycle-policy \
    --repository-name ${REPOSITORY_NAME} \
    --lifecycle-policy-text file:///tmp/lifecycle-policy.json" \
    "Set ECR lifecycle policy"

# Get repository URI
REPOSITORY_URI=$(aws ecr describe-repositories \
    --repository-names ${REPOSITORY_NAME} \
    --query 'repositories[0].repositoryUri' \
    --output text)

log "ECR repository created: $REPOSITORY_URI"

# Create VPC infrastructure
log "Creating VPC infrastructure..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --query 'Vpc.VpcId' --output text)

execute_cmd "aws ec2 create-tags \
    --resources ${VPC_ID} \
    --tags Key=Name,Value=${PROJECT_NAME}-vpc" \
    "Tag VPC"

execute_cmd "aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-hostnames" \
    "Enable DNS hostnames"

# Create internet gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

execute_cmd "aws ec2 attach-internet-gateway \
    --vpc-id ${VPC_ID} \
    --internet-gateway-id ${IGW_ID}" \
    "Attach internet gateway"

# Create route table
RT_ID=$(aws ec2 create-route-table \
    --vpc-id ${VPC_ID} \
    --query 'RouteTable.RouteTableId' \
    --output text)

execute_cmd "aws ec2 create-route \
    --route-table-id ${RT_ID} \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id ${IGW_ID}" \
    "Create default route"

# Create subnets across multiple AZs
log "Creating multi-AZ subnets..."
SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${AWS_REGION}a \
    --query 'Subnet.SubnetId' --output text)

SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${AWS_REGION}b \
    --query 'Subnet.SubnetId' --output text)

SUBNET_3=$(aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block 10.0.3.0/24 \
    --availability-zone ${AWS_REGION}c \
    --query 'Subnet.SubnetId' --output text)

# Associate subnets with route table
execute_cmd "aws ec2 associate-route-table \
    --subnet-id ${SUBNET_1} \
    --route-table-id ${RT_ID}" \
    "Associate subnet 1 with route table"

execute_cmd "aws ec2 associate-route-table \
    --subnet-id ${SUBNET_2} \
    --route-table-id ${RT_ID}" \
    "Associate subnet 2 with route table"

execute_cmd "aws ec2 associate-route-table \
    --subnet-id ${SUBNET_3} \
    --route-table-id ${RT_ID}" \
    "Associate subnet 3 with route table"

# Create security groups
log "Creating security groups..."
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-alb-sg \
    --description "Security group for Application Load Balancer" \
    --vpc-id ${VPC_ID} \
    --query 'GroupId' --output text)

ECS_SG_ID=$(aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-ecs-sg \
    --description "Security group for ECS tasks" \
    --vpc-id ${VPC_ID} \
    --query 'GroupId' --output text)

# Configure security group rules
execute_cmd "aws ec2 authorize-security-group-ingress \
    --group-id ${ALB_SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0" \
    "Allow HTTP traffic to ALB"

execute_cmd "aws ec2 authorize-security-group-ingress \
    --group-id ${ALB_SG_ID} \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0" \
    "Allow HTTPS traffic to ALB"

execute_cmd "aws ec2 authorize-security-group-ingress \
    --group-id ${ECS_SG_ID} \
    --protocol tcp \
    --port 8080 \
    --source-group ${ALB_SG_ID}" \
    "Allow ALB to ECS traffic"

# Create Application Load Balancers
log "Creating Application Load Balancers..."
DEV_ALB_ARN=$(aws elbv2 create-load-balancer \
    --name ${PROJECT_NAME}-dev-alb \
    --subnets ${SUBNET_1} ${SUBNET_2} ${SUBNET_3} \
    --security-groups ${ALB_SG_ID} \
    --scheme internet-facing \
    --type application \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

PROD_ALB_ARN=$(aws elbv2 create-load-balancer \
    --name ${PROJECT_NAME}-prod-alb \
    --subnets ${SUBNET_1} ${SUBNET_2} ${SUBNET_3} \
    --security-groups ${ALB_SG_ID} \
    --scheme internet-facing \
    --type application \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

# Create target groups
log "Creating target groups..."
DEV_TG=$(aws elbv2 create-target-group \
    --name ${PROJECT_NAME}-dev-tg \
    --protocol HTTP \
    --port 8080 \
    --vpc-id ${VPC_ID} \
    --target-type ip \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

PROD_TG_BLUE=$(aws elbv2 create-target-group \
    --name ${PROJECT_NAME}-prod-blue \
    --protocol HTTP \
    --port 8080 \
    --vpc-id ${VPC_ID} \
    --target-type ip \
    --health-check-path /health \
    --health-check-interval-seconds 15 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

PROD_TG_GREEN=$(aws elbv2 create-target-group \
    --name ${PROJECT_NAME}-prod-green \
    --protocol HTTP \
    --port 8080 \
    --vpc-id ${VPC_ID} \
    --target-type ip \
    --health-check-path /health \
    --health-check-interval-seconds 15 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Create listeners
log "Creating load balancer listeners..."
DEV_LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn ${DEV_ALB_ARN} \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=${DEV_TG} \
    --query 'Listeners[0].ListenerArn' \
    --output text)

PROD_LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn ${PROD_ALB_ARN} \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=${PROD_TG_BLUE} \
    --query 'Listeners[0].ListenerArn' \
    --output text)

# Create IAM roles
log "Creating IAM roles..."

# ECS Task Execution Role
execute_cmd "aws iam create-role \
    --role-name ${PROJECT_NAME}-task-execution-role \
    --assume-role-policy-document '{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Principal\": {
            \"Service\": \"ecs-tasks.amazonaws.com\"
          },
          \"Action\": \"sts:AssumeRole\"
        }
      ]
    }'" \
    "Create ECS task execution role"

# ECS Task Role
execute_cmd "aws iam create-role \
    --role-name ${PROJECT_NAME}-task-role \
    --assume-role-policy-document '{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Principal\": {
            \"Service\": \"ecs-tasks.amazonaws.com\"
          },
          \"Action\": \"sts:AssumeRole\"
        }
      ]
    }'" \
    "Create ECS task role"

# Create custom policy for task role
cat > /tmp/task-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
        "secretsmanager:GetSecretValue",
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

execute_cmd "aws iam put-role-policy \
    --role-name ${PROJECT_NAME}-task-role \
    --policy-name ${PROJECT_NAME}-task-policy \
    --policy-document file:///tmp/task-role-policy.json" \
    "Create task role policy"

# Attach managed policies
execute_cmd "aws iam attach-role-policy \
    --role-name ${PROJECT_NAME}-task-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
    "Attach ECS task execution policy"

# CodeDeploy service role
execute_cmd "aws iam create-role \
    --role-name ${PROJECT_NAME}-codedeploy-role \
    --assume-role-policy-document '{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Principal\": {
            \"Service\": \"codedeploy.amazonaws.com\"
          },
          \"Action\": \"sts:AssumeRole\"
        }
      ]
    }'" \
    "Create CodeDeploy service role"

execute_cmd "aws iam attach-role-policy \
    --role-name ${PROJECT_NAME}-codedeploy-role \
    --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS" \
    "Attach CodeDeploy ECS policy"

# Create ECS clusters
log "Creating ECS clusters..."
execute_cmd "aws ecs create-cluster \
    --cluster-name ${DEV_CLUSTER_NAME} \
    --capacity-providers EC2 FARGATE FARGATE_SPOT \
    --default-capacity-provider-strategy \
    capacityProvider=FARGATE_SPOT,weight=1,base=0 \
    --settings name=containerInsights,value=enabled \
    --tags key=Environment,value=development \
    key=Project,value=${PROJECT_NAME}" \
    "Create development ECS cluster"

execute_cmd "aws ecs create-cluster \
    --cluster-name ${PROD_CLUSTER_NAME} \
    --capacity-providers EC2 FARGATE \
    --default-capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1,base=0 \
    --settings name=containerInsights,value=enabled \
    --tags key=Environment,value=production \
    key=Project,value=${PROJECT_NAME}" \
    "Create production ECS cluster"

# Create CloudWatch log groups
log "Creating CloudWatch log groups..."
execute_cmd "aws logs create-log-group \
    --log-group-name /ecs/${PROJECT_NAME}/dev \
    --retention-in-days 7" \
    "Create dev log group"

execute_cmd "aws logs create-log-group \
    --log-group-name /ecs/${PROJECT_NAME}/prod \
    --retention-in-days 30" \
    "Create prod log group"

# Create task definitions
log "Creating ECS task definitions..."

# Development task definition
cat > /tmp/dev-task-definition.json << EOF
{
  "family": "${PROJECT_NAME}-dev-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-task-execution-role",
  "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-task-role",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "nginx:latest",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "environment": [
        {
          "name": "ENV",
          "value": "development"
        },
        {
          "name": "AWS_XRAY_TRACING_NAME",
          "value": "${PROJECT_NAME}-dev"
        }
      ],
      "secrets": [
        {
          "name": "APP_VERSION",
          "valueFrom": "/${PROJECT_NAME}/app/version"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT_NAME}/dev",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:80/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    },
    {
      "name": "xray-daemon",
      "image": "amazon/aws-xray-daemon:latest",
      "portMappings": [
        {
          "containerPort": 2000,
          "protocol": "udp"
        }
      ],
      "essential": false,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT_NAME}/dev",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "xray"
        }
      }
    }
  ]
}
EOF

execute_cmd "aws ecs register-task-definition \
    --cli-input-json file:///tmp/dev-task-definition.json" \
    "Register development task definition"

# Production task definition
cat > /tmp/prod-task-definition.json << EOF
{
  "family": "${PROJECT_NAME}-prod-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-task-execution-role",
  "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-task-role",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "${REPOSITORY_URI}:latest",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "environment": [
        {
          "name": "ENV",
          "value": "production"
        },
        {
          "name": "AWS_XRAY_TRACING_NAME",
          "value": "${PROJECT_NAME}-prod"
        }
      ],
      "secrets": [
        {
          "name": "APP_VERSION",
          "valueFrom": "/${PROJECT_NAME}/app/version"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT_NAME}/prod",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:80/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    },
    {
      "name": "xray-daemon",
      "image": "amazon/aws-xray-daemon:latest",
      "portMappings": [
        {
          "containerPort": 2000,
          "protocol": "udp"
        }
      ],
      "essential": false,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${PROJECT_NAME}/prod",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "xray"
        }
      }
    }
  ]
}
EOF

execute_cmd "aws ecs register-task-definition \
    --cli-input-json file:///tmp/prod-task-definition.json" \
    "Register production task definition"

# Create ECS services
log "Creating ECS services..."

# Development service
execute_cmd "aws ecs create-service \
    --cluster ${DEV_CLUSTER_NAME} \
    --service-name ${SERVICE_NAME}-dev \
    --task-definition ${PROJECT_NAME}-dev-task:1 \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration \"awsvpcConfiguration={subnets=[${SUBNET_1},${SUBNET_2}],securityGroups=[${ECS_SG_ID}],assignPublicIp=ENABLED}\" \
    --load-balancers \"targetGroupArn=${DEV_TG},containerName=app,containerPort=80\" \
    --enable-execute-command \
    --tags key=Environment,value=development" \
    "Create development ECS service"

# Production service with CODE_DEPLOY deployment controller
execute_cmd "aws ecs create-service \
    --cluster ${PROD_CLUSTER_NAME} \
    --service-name ${SERVICE_NAME}-prod \
    --task-definition ${PROJECT_NAME}-prod-task:1 \
    --desired-count 3 \
    --launch-type FARGATE \
    --deployment-controller type=CODE_DEPLOY \
    --network-configuration \"awsvpcConfiguration={subnets=[${SUBNET_1},${SUBNET_2}],securityGroups=[${ECS_SG_ID}],assignPublicIp=ENABLED}\" \
    --load-balancers \"targetGroupArn=${PROD_TG_BLUE},containerName=app,containerPort=80\" \
    --enable-execute-command \
    --tags key=Environment,value=production" \
    "Create production ECS service"

# Create CodeDeploy application
log "Creating CodeDeploy application..."
execute_cmd "aws deploy create-application \
    --application-name ${APPLICATION_NAME} \
    --compute-platform ECS" \
    "Create CodeDeploy application"

# Create deployment group configuration
cat > /tmp/prod-deployment-group-config.json << EOF
{
  "applicationName": "${APPLICATION_NAME}",
  "deploymentGroupName": "${PROJECT_NAME}-prod-deployment-group",
  "serviceRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-codedeploy-role",
  "deploymentConfigName": "CodeDeployDefault.ECSCanary10Percent5Minutes",
  "ecsServices": [
    {
      "serviceName": "${SERVICE_NAME}-prod",
      "clusterName": "${PROD_CLUSTER_NAME}"
    }
  ],
  "loadBalancerInfo": {
    "targetGroupInfoList": [
      {
        "name": "${PROJECT_NAME}-prod-blue"
      },
      {
        "name": "${PROJECT_NAME}-prod-green"
      }
    ]
  },
  "productionTrafficRoute": {
    "listenerArns": ["${PROD_LISTENER_ARN}"]
  },
  "deploymentStyle": {
    "deploymentType": "BLUE_GREEN",
    "deploymentOption": "WITH_TRAFFIC_CONTROL"
  },
  "blueGreenDeploymentConfiguration": {
    "terminateBlueInstancesOnDeploymentSuccess": {
      "action": "TERMINATE",
      "terminationWaitTimeInMinutes": 5
    },
    "deploymentReadyOption": {
      "actionOnTimeout": "CONTINUE_DEPLOYMENT"
    }
  },
  "autoRollbackConfiguration": {
    "enabled": true,
    "events": ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }
}
EOF

execute_cmd "aws deploy create-deployment-group \
    --cli-input-json file:///tmp/prod-deployment-group-config.json" \
    "Create production deployment group"

# Create CodeBuild service role
log "Creating CodeBuild service role..."
execute_cmd "aws iam create-role \
    --role-name ${PROJECT_NAME}-codebuild-role \
    --assume-role-policy-document '{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Principal\": {
            \"Service\": \"codebuild.amazonaws.com\"
          },
          \"Action\": \"sts:AssumeRole\"
        }
      ]
    }'" \
    "Create CodeBuild service role"

# Create CodeBuild policy
cat > /tmp/codebuild-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:GetAuthorizationToken",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "s3:GetObject",
        "s3:PutObject",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "secretsmanager:GetSecretValue",
        "codebuild:CreateReportGroup",
        "codebuild:CreateReport",
        "codebuild:UpdateReport",
        "codebuild:BatchPutTestCases",
        "codebuild:BatchPutCodeCoverages"
      ],
      "Resource": "*"
    }
  ]
}
EOF

execute_cmd "aws iam put-role-policy \
    --role-name ${PROJECT_NAME}-codebuild-role \
    --policy-name ${PROJECT_NAME}-codebuild-policy \
    --policy-document file:///tmp/codebuild-policy.json" \
    "Create CodeBuild policy"

# Create CodeBuild project
execute_cmd "aws codebuild create-project \
    --name ${BUILD_PROJECT_NAME} \
    --source type=CODEPIPELINE \
    --artifacts type=CODEPIPELINE \
    --environment type=LINUX_CONTAINER,image=aws/codebuild/amazonlinux2-x86_64-standard:3.0,computeType=BUILD_GENERAL1_MEDIUM,privilegedMode=true \
    --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-codebuild-role" \
    "Create CodeBuild project"

# Create SNS topic for alerts
log "Creating SNS topic for alerts..."
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name ${PROJECT_NAME}-alerts \
    --query 'TopicArn' --output text)

# Create CloudWatch alarms
log "Creating CloudWatch alarms..."
execute_cmd "aws cloudwatch put-metric-alarm \
    --alarm-name ${PROJECT_NAME}-high-error-rate \
    --alarm-description \"High error rate detected\" \
    --metric-name 4XXError \
    --namespace AWS/ApplicationELB \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions ${SNS_TOPIC_ARN} \
    --dimensions Name=LoadBalancer,Value=${PROD_ALB_ARN##*/}" \
    "Create high error rate alarm"

execute_cmd "aws cloudwatch put-metric-alarm \
    --alarm-name ${PROJECT_NAME}-high-response-time \
    --alarm-description \"High response time detected\" \
    --metric-name TargetResponseTime \
    --namespace AWS/ApplicationELB \
    --statistic Average \
    --period 300 \
    --threshold 2.0 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions ${SNS_TOPIC_ARN} \
    --dimensions Name=LoadBalancer,Value=${PROD_ALB_ARN##*/}" \
    "Create high response time alarm"

# Create CodePipeline service role
log "Creating CodePipeline service role..."
execute_cmd "aws iam create-role \
    --role-name ${PROJECT_NAME}-codepipeline-role \
    --assume-role-policy-document '{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Principal\": {
            \"Service\": \"codepipeline.amazonaws.com\"
          },
          \"Action\": \"sts:AssumeRole\"
        }
      ]
    }'" \
    "Create CodePipeline service role"

# Create CodePipeline policy
cat > /tmp/codepipeline-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketVersioning",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild",
        "codedeploy:CreateDeployment",
        "codedeploy:GetApplication",
        "codedeploy:GetApplicationRevision",
        "codedeploy:GetDeployment",
        "codedeploy:GetDeploymentConfig",
        "codedeploy:RegisterApplicationRevision",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "iam:PassRole",
        "sns:Publish"
      ],
      "Resource": "*"
    }
  ]
}
EOF

execute_cmd "aws iam put-role-policy \
    --role-name ${PROJECT_NAME}-codepipeline-role \
    --policy-name ${PROJECT_NAME}-codepipeline-policy \
    --policy-document file:///tmp/codepipeline-policy.json" \
    "Create CodePipeline policy"

# Create pipeline configuration
cat > /tmp/pipeline-config.json << EOF
{
  "pipeline": {
    "name": "${PIPELINE_NAME}",
    "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-codepipeline-role",
    "artifactStore": {
      "type": "S3",
      "location": "${PROJECT_NAME}-artifacts-${AWS_REGION}"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "Source",
            "actionTypeId": {
              "category": "Source",
              "owner": "AWS",
              "provider": "S3",
              "version": "1"
            },
            "configuration": {
              "S3Bucket": "${PROJECT_NAME}-artifacts-${AWS_REGION}",
              "S3ObjectKey": "source.zip"
            },
            "outputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "Build",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": {
              "ProjectName": "${BUILD_PROJECT_NAME}",
              "EnvironmentVariables": "[{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"${AWS_REGION}\"},{\"name\":\"AWS_ACCOUNT_ID\",\"value\":\"${AWS_ACCOUNT_ID}\"},{\"name\":\"IMAGE_REPO_NAME\",\"value\":\"${REPOSITORY_NAME}\"}]"
            },
            "inputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ],
            "outputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Deploy-Dev",
        "actions": [
          {
            "name": "Deploy-Dev",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "ECS",
              "version": "1"
            },
            "configuration": {
              "ClusterName": "${DEV_CLUSTER_NAME}",
              "ServiceName": "${SERVICE_NAME}-dev",
              "FileName": "imagedefinitions.json"
            },
            "inputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ],
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Approval",
        "actions": [
          {
            "name": "ManualApproval",
            "actionTypeId": {
              "category": "Approval",
              "owner": "AWS",
              "provider": "Manual",
              "version": "1"
            },
            "configuration": {
              "NotificationArn": "${SNS_TOPIC_ARN}",
              "CustomData": "Please review the development deployment and approve for production deployment."
            }
          }
        ]
      },
      {
        "name": "Deploy-Production",
        "actions": [
          {
            "name": "Deploy-Production",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CodeDeployToECS",
              "version": "1"
            },
            "configuration": {
              "ApplicationName": "${APPLICATION_NAME}",
              "DeploymentGroupName": "${PROJECT_NAME}-prod-deployment-group",
              "TaskDefinitionTemplateArtifact": "BuildOutput",
              "TaskDefinitionTemplatePath": "taskdef.json",
              "AppSpecTemplateArtifact": "BuildOutput",
              "AppSpecTemplatePath": "appspec.yaml"
            },
            "inputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      }
    ]
  }
}
EOF

execute_cmd "aws codepipeline create-pipeline \
    --cli-input-json file:///tmp/pipeline-config.json" \
    "Create advanced CodePipeline"

# Wait for services to stabilize
log "Waiting for ECS services to stabilize..."
if [ "$DRY_RUN" = "false" ]; then
    aws ecs wait services-stable \
        --cluster ${DEV_CLUSTER_NAME} \
        --services ${SERVICE_NAME}-dev &
    
    aws ecs wait services-stable \
        --cluster ${PROD_CLUSTER_NAME} \
        --services ${SERVICE_NAME}-prod &
    
    wait
fi

# Get load balancer DNS names
DEV_ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns ${DEV_ALB_ARN} \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

PROD_ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns ${PROD_ALB_ARN} \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Save deployment info
cat > /tmp/deployment-info.json << EOF
{
  "project_name": "${PROJECT_NAME}",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "dev_cluster_name": "${DEV_CLUSTER_NAME}",
  "prod_cluster_name": "${PROD_CLUSTER_NAME}",
  "service_name": "${SERVICE_NAME}",
  "repository_name": "${REPOSITORY_NAME}",
  "repository_uri": "${REPOSITORY_URI}",
  "pipeline_name": "${PIPELINE_NAME}",
  "application_name": "${APPLICATION_NAME}",
  "build_project_name": "${BUILD_PROJECT_NAME}",
  "dev_alb_dns": "${DEV_ALB_DNS}",
  "prod_alb_dns": "${PROD_ALB_DNS}",
  "sns_topic_arn": "${SNS_TOPIC_ARN}",
  "vpc_id": "${VPC_ID}",
  "subnet_1": "${SUBNET_1}",
  "subnet_2": "${SUBNET_2}",
  "subnet_3": "${SUBNET_3}",
  "alb_sg_id": "${ALB_SG_ID}",
  "ecs_sg_id": "${ECS_SG_ID}",
  "dev_alb_arn": "${DEV_ALB_ARN}",
  "prod_alb_arn": "${PROD_ALB_ARN}",
  "dev_tg": "${DEV_TG}",
  "prod_tg_blue": "${PROD_TG_BLUE}",
  "prod_tg_green": "${PROD_TG_GREEN}",
  "dev_listener_arn": "${DEV_LISTENER_ARN}",
  "prod_listener_arn": "${PROD_LISTENER_ARN}",
  "igw_id": "${IGW_ID}",
  "rt_id": "${RT_ID}"
}
EOF

# Clean up temporary files
rm -f /tmp/lifecycle-policy.json /tmp/task-role-policy.json /tmp/dev-task-definition.json /tmp/prod-task-definition.json /tmp/prod-deployment-group-config.json /tmp/codebuild-policy.json /tmp/codepipeline-policy.json /tmp/pipeline-config.json

# Final summary
echo "=========================================="
echo "    AWS CI/CD Pipeline Deployment Complete"
echo "=========================================="
log "Deployment completed successfully!"
info "Project Name: ${PROJECT_NAME}"
info "Development Environment: http://${DEV_ALB_DNS}"
info "Production Environment: http://${PROD_ALB_DNS}"
info "ECR Repository: ${REPOSITORY_URI}"
info "CodePipeline: ${PIPELINE_NAME}"
info "CodeBuild Project: ${BUILD_PROJECT_NAME}"
info "CodeDeploy Application: ${APPLICATION_NAME}"
warn "Resources are billable - remember to clean up when done!"
log "Deployment information saved to /tmp/deployment-info.json"
log "Use the destroy.sh script to clean up resources"

echo "=========================================="
echo "Next Steps:"
echo "1. Push a sample container image to ECR"
echo "2. Upload source code to S3 to trigger pipeline"
echo "3. Monitor pipeline execution in AWS Console"
echo "4. Test both development and production endpoints"
echo "=========================================="