#!/bin/bash

# Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy
# Deployment Script
# 
# This script deploys a comprehensive blue-green deployment infrastructure
# including ECS Fargate services, Lambda functions, ALB, and CodeDeploy applications
# with automated monitoring and rollback capabilities.

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy-errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$ERROR_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check logs: $ERROR_LOG"
    error "You may need to manually clean up partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Advanced Blue-Green Deployments - Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: from AWS CLI config)
    -p, --project PROJECT   Project name prefix (default: auto-generated)
    -s, --skip-build        Skip Docker image build (use existing images)
    -v, --verbose           Enable verbose logging
    -d, --dry-run           Show what would be deployed without executing

EXAMPLES:
    $0                                  # Deploy with default settings
    $0 -r us-west-2 -p my-project     # Deploy to specific region with project name
    $0 --skip-build                     # Deploy without rebuilding Docker images
    $0 --dry-run                        # Preview deployment without executing

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Docker installed and running
    - IAM permissions for ECS, Lambda, ALB, CodeDeploy, ECR, IAM, CloudWatch
    - Sufficient AWS service limits for ECS tasks, ALBs, and Lambda functions

EOF
}

# Default values
AWS_REGION=""
PROJECT_NAME=""
SKIP_BUILD=false
VERBOSE=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
echo "=== Deployment started at $(date) ===" > "$LOG_FILE"
echo "=== Error log for deployment started at $(date) ===" > "$ERROR_LOG"

log "Starting Advanced Blue-Green Deployment setup..."

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$aws_version" =~ ^2\. ]]; then
        warn "AWS CLI v1 detected. AWS CLI v2 is recommended."
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    log "✅ Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
            warn "No region specified, using default: $AWS_REGION"
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate project name if not provided
    if [[ -z "$PROJECT_NAME" ]]; then
        local random_suffix
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 8 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 8)")
        PROJECT_NAME="advanced-deployment-${random_suffix}"
    fi
    
    # Export all required variables
    export PROJECT_NAME
    export ECS_CLUSTER_NAME="deployment-cluster-${PROJECT_NAME##*-}"
    export ECS_SERVICE_NAME="web-service-${PROJECT_NAME##*-}"
    export LAMBDA_FUNCTION_NAME="api-function-${PROJECT_NAME##*-}"
    export ALB_NAME="deployment-alb-${PROJECT_NAME##*-}"
    export ECR_REPOSITORY="web-app-${PROJECT_NAME##*-}"
    export CD_ECS_APP_NAME="ecs-deployment-${PROJECT_NAME##*-}"
    export CD_LAMBDA_APP_NAME="lambda-deployment-${PROJECT_NAME##*-}"
    export ECS_TASK_ROLE="ECSTaskRole-${PROJECT_NAME##*-}"
    export ECS_EXECUTION_ROLE="ECSExecutionRole-${PROJECT_NAME##*-}"
    export CODEDEPLOY_ROLE="CodeDeployRole-${PROJECT_NAME##*-}"
    export LAMBDA_ROLE="LambdaRole-${PROJECT_NAME##*-}"
    
    # Save configuration
    cat > "${SCRIPT_DIR}/.deployment-config" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
PROJECT_NAME=$PROJECT_NAME
ECS_CLUSTER_NAME=$ECS_CLUSTER_NAME
ECS_SERVICE_NAME=$ECS_SERVICE_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
ALB_NAME=$ALB_NAME
ECR_REPOSITORY=$ECR_REPOSITORY
CD_ECS_APP_NAME=$CD_ECS_APP_NAME
CD_LAMBDA_APP_NAME=$CD_LAMBDA_APP_NAME
ECS_TASK_ROLE=$ECS_TASK_ROLE
ECS_EXECUTION_ROLE=$ECS_EXECUTION_ROLE
CODEDEPLOY_ROLE=$CODEDEPLOY_ROLE
LAMBDA_ROLE=$LAMBDA_ROLE
EOF
    
    log "✅ Environment configured"
    log "Project: $PROJECT_NAME"
    log "Region: $AWS_REGION"
    log "Account: $AWS_ACCOUNT_ID"
}

# Create VPC infrastructure
create_vpc_infrastructure() {
    log "Creating VPC infrastructure and load balancer..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create VPC infrastructure"
        return 0
    fi
    
    # Get default VPC and subnets
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$DEFAULT_VPC_ID" == "None" || -z "$DEFAULT_VPC_ID" ]]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    local subnet_ids
    subnet_ids=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text)
    
    export SUBNET_ID_1=$(echo $subnet_ids | cut -d' ' -f1)
    export SUBNET_ID_2=$(echo $subnet_ids | cut -d' ' -f2)
    
    if [[ -z "$SUBNET_ID_1" || -z "$SUBNET_ID_2" ]]; then
        error "Need at least 2 subnets for ALB. Found subnets: $subnet_ids"
        exit 1
    fi
    
    # Create security group for ALB
    export ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name "${ALB_NAME}-sg" \
        --description "Security group for ALB - ${PROJECT_NAME}" \
        --vpc-id $DEFAULT_VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${ALB_NAME}-sg},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'GroupId' --output text)
    
    # Allow HTTP and HTTPS traffic
    aws ec2 authorize-security-group-ingress \
        --group-id $ALB_SG_ID \
        --protocol tcp --port 80 --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --group-id $ALB_SG_ID \
        --protocol tcp --port 443 --cidr 0.0.0.0/0
    
    # Create security group for ECS tasks
    export ECS_SG_ID=$(aws ec2 create-security-group \
        --group-name "${ECS_SERVICE_NAME}-sg" \
        --description "Security group for ECS tasks - ${PROJECT_NAME}" \
        --vpc-id $DEFAULT_VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${ECS_SERVICE_NAME}-sg},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'GroupId' --output text)
    
    # Allow traffic from ALB
    aws ec2 authorize-security-group-ingress \
        --group-id $ECS_SG_ID \
        --protocol tcp --port 8080 \
        --source-group $ALB_SG_ID
    
    # Create Application Load Balancer
    export ALB_ARN=$(aws elbv2 create-load-balancer \
        --name $ALB_NAME \
        --subnets $SUBNET_ID_1 $SUBNET_ID_2 \
        --security-groups $ALB_SG_ID \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags Key=Name,Value=$ALB_NAME Key=Project,Value=$PROJECT_NAME \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Get ALB DNS name
    export ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns $ALB_ARN \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    # Create target groups for blue-green deployment
    export TG_BLUE_ARN=$(aws elbv2 create-target-group \
        --name "${ECS_SERVICE_NAME}-blue" \
        --protocol HTTP --port 8080 \
        --vpc-id $DEFAULT_VPC_ID \
        --target-type ip \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Name,Value="${ECS_SERVICE_NAME}-blue" Key=Project,Value=$PROJECT_NAME \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    export TG_GREEN_ARN=$(aws elbv2 create-target-group \
        --name "${ECS_SERVICE_NAME}-green" \
        --protocol HTTP --port 8080 \
        --vpc-id $DEFAULT_VPC_ID \
        --target-type ip \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Name,Value="${ECS_SERVICE_NAME}-green" Key=Project,Value=$PROJECT_NAME \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create ALB listener
    export LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTP --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TG_BLUE_ARN \
        --tags Key=Name,Value="${ALB_NAME}-listener" Key=Project,Value=$PROJECT_NAME \
        --query 'Listeners[0].ListenerArn' --output text)
    
    # Update configuration file
    cat >> "${SCRIPT_DIR}/.deployment-config" << EOF
DEFAULT_VPC_ID=$DEFAULT_VPC_ID
SUBNET_ID_1=$SUBNET_ID_1
SUBNET_ID_2=$SUBNET_ID_2
ALB_SG_ID=$ALB_SG_ID
ECS_SG_ID=$ECS_SG_ID
ALB_ARN=$ALB_ARN
ALB_DNS=$ALB_DNS
TG_BLUE_ARN=$TG_BLUE_ARN
TG_GREEN_ARN=$TG_GREEN_ARN
LISTENER_ARN=$LISTENER_ARN
EOF
    
    log "✅ VPC infrastructure created"
    log "ALB DNS: $ALB_DNS"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create IAM roles"
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # ECS task execution role trust policy
    cat > "$temp_dir/ecs-execution-trust-policy.json" << 'EOF'
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
    
    # Create ECS task execution role
    aws iam create-role \
        --role-name $ECS_EXECUTION_ROLE \
        --assume-role-policy-document file://"$temp_dir/ecs-execution-trust-policy.json" \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws iam attach-role-policy \
        --role-name $ECS_EXECUTION_ROLE \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Create ECS task role
    aws iam create-role \
        --role-name $ECS_TASK_ROLE \
        --assume-role-policy-document file://"$temp_dir/ecs-execution-trust-policy.json" \
        --tags Key=Project,Value=$PROJECT_NAME
    
    # Create policy for ECS task role
    cat > "$temp_dir/ecs-task-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam create-policy \
        --policy-name "ECSTaskPolicy-${PROJECT_NAME##*-}" \
        --policy-document file://"$temp_dir/ecs-task-policy.json" \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws iam attach-role-policy \
        --role-name $ECS_TASK_ROLE \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ECSTaskPolicy-${PROJECT_NAME##*-}"
    
    # CodeDeploy service role trust policy
    cat > "$temp_dir/codedeploy-trust-policy.json" << 'EOF'
{
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
}
EOF
    
    # Create CodeDeploy service role
    aws iam create-role \
        --role-name $CODEDEPLOY_ROLE \
        --assume-role-policy-document file://"$temp_dir/codedeploy-trust-policy.json" \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws iam attach-role-policy \
        --role-name $CODEDEPLOY_ROLE \
        --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS
    
    aws iam attach-role-policy \
        --role-name $CODEDEPLOY_ROLE \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda
    
    # Lambda execution role trust policy
    cat > "$temp_dir/lambda-trust-policy.json" << 'EOF'
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
    aws iam create-role \
        --role-name $LAMBDA_ROLE \
        --assume-role-policy-document file://"$temp_dir/lambda-trust-policy.json" \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws iam attach-role-policy \
        --role-name $LAMBDA_ROLE \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create enhanced Lambda policy for deployment hooks
    cat > "$temp_dir/lambda-enhanced-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:PutLifecycleEventHookExecutionStatus",
        "ecs:DescribeServices",
        "ecs:DescribeTasks",
        "lambda:InvokeFunction",
        "lambda:GetFunction",
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam create-policy \
        --policy-name "LambdaEnhancedPolicy-${PROJECT_NAME##*-}" \
        --policy-document file://"$temp_dir/lambda-enhanced-policy.json" \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws iam attach-role-policy \
        --role-name $LAMBDA_ROLE \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaEnhancedPolicy-${PROJECT_NAME##*-}"
    
    # Get role ARNs and wait for propagation
    sleep 10
    
    export ECS_EXECUTION_ROLE_ARN=$(aws iam get-role \
        --role-name $ECS_EXECUTION_ROLE \
        --query Role.Arn --output text)
    
    export ECS_TASK_ROLE_ARN=$(aws iam get-role \
        --role-name $ECS_TASK_ROLE \
        --query Role.Arn --output text)
    
    export CODEDEPLOY_ROLE_ARN=$(aws iam get-role \
        --role-name $CODEDEPLOY_ROLE \
        --query Role.Arn --output text)
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name $LAMBDA_ROLE \
        --query Role.Arn --output text)
    
    # Update configuration file
    cat >> "${SCRIPT_DIR}/.deployment-config" << EOF
ECS_EXECUTION_ROLE_ARN=$ECS_EXECUTION_ROLE_ARN
ECS_TASK_ROLE_ARN=$ECS_TASK_ROLE_ARN
CODEDEPLOY_ROLE_ARN=$CODEDEPLOY_ROLE_ARN
LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN
EOF
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "✅ IAM roles created"
}

# Create ECR repository and build sample application
create_ecr_and_app() {
    log "Creating ECR repository and building sample application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create ECR repository and build application"
        return 0
    fi
    
    # Create ECR repository
    aws ecr create-repository \
        --repository-name $ECR_REPOSITORY \
        --image-scanning-configuration scanOnPush=true \
        --tags Key=Name,Value=$ECR_REPOSITORY Key=Project,Value=$PROJECT_NAME
    
    export ECR_URI=$(aws ecr describe-repositories \
        --repository-names $ECR_REPOSITORY \
        --query 'repositories[0].repositoryUri' --output text)
    
    if [[ "$SKIP_BUILD" == "false" ]]; then
        # Create temporary directory for application build
        local build_dir
        build_dir=$(mktemp -d)
        cd "$build_dir"
        
        # Create sample web application
        cat > package.json << 'EOF'
{
  "name": "blue-green-demo-app",
  "version": "1.0.0",
  "description": "Sample application for blue-green deployment",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^14.2.0"
  }
}
EOF
        
        # Create Express.js server with health checks and metrics
        cat > server.js << 'EOF'
const express = require('express');
const promClient = require('prom-client');

const app = express();
const port = process.env.PORT || 8080;
const version = process.env.APP_VERSION || '1.0.0';
const environment = process.env.ENVIRONMENT || 'blue';

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route'],
  registers: [register]
});

// Middleware for metrics
app.use((req, res, next) => {
  const startTime = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - startTime) / 1000;
    httpRequestsTotal.inc({
      method: req.method,
      route: req.route ? req.route.path : req.path,
      status_code: res.statusCode
    });
    httpRequestDuration.observe({
      method: req.method,
      route: req.route ? req.route.path : req.path
    }, duration);
  });
  
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    version: version,
    environment: environment,
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Ready check endpoint
app.get('/ready', (req, res) => {
  res.status(200).json({
    status: 'ready',
    version: version,
    environment: environment
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (ex) {
    res.status(500).end(ex);
  }
});

// Main application endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Blue-Green Deployment Demo',
    version: version,
    environment: environment,
    timestamp: new Date().toISOString(),
    hostname: require('os').hostname()
  });
});

// API endpoint with environment-specific behavior
app.get('/api/data', (req, res) => {
  const data = {
    environment: environment,
    version: version,
    data: [
      { id: 1, value: Math.random(), environment: environment },
      { id: 2, value: Math.random(), environment: environment },
      { id: 3, value: Math.random(), environment: environment }
    ],
    timestamp: new Date().toISOString()
  };
  
  // Simulate version-specific features
  if (version === '2.0.0') {
    data.newFeature = 'Enhanced data processing';
    data.data.push({ id: 4, value: Math.random(), environment: environment });
  }
  
  res.json(data);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Process terminated');
  });
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Server running on port ${port}`);
  console.log(`Version: ${version}, Environment: ${environment}`);
});
EOF
        
        # Create Dockerfile
        cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY server.js ./

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

# Change ownership of the app directory
RUN chown -R nextjs:nodejs /app
USER nextjs

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "const http=require('http');const options={hostname:'localhost',port:8080,path:'/health',timeout:2000};const req=http.request(options,(res)=>{process.exit(res.statusCode===200?0:1)});req.on('error',()=>process.exit(1));req.end();"

CMD ["npm", "start"]
EOF
        
        # Build and push Docker images
        aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI
        
        # Build v1.0.0
        docker build -t $ECR_URI:1.0.0 .
        docker tag $ECR_URI:1.0.0 $ECR_URI:latest
        docker push $ECR_URI:1.0.0
        docker push $ECR_URI:latest
        
        # Build v2.0.0
        sed -i 's/"version": "1.0.0"/"version": "2.0.0"/' package.json
        docker build -t $ECR_URI:2.0.0 .
        docker push $ECR_URI:2.0.0
        
        # Cleanup build directory
        cd "$SCRIPT_DIR"
        rm -rf "$build_dir"
    else
        log "Skipping Docker image build as requested"
    fi
    
    # Update configuration file
    cat >> "${SCRIPT_DIR}/.deployment-config" << EOF
ECR_URI=$ECR_URI
EOF
    
    log "✅ ECR repository created and application built"
}

# Create ECS cluster and task definition
create_ecs_cluster() {
    log "Creating ECS cluster and task definition..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create ECS cluster and service"
        return 0
    fi
    
    # Create ECS cluster
    aws ecs create-cluster \
        --cluster-name $ECS_CLUSTER_NAME \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --tags key=Name,value=$ECS_CLUSTER_NAME key=Project,value=$PROJECT_NAME
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/ecs/${ECS_SERVICE_NAME}" \
        --retention-in-days 7 \
        --tags Project=$PROJECT_NAME
    
    # Create task definition
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "$temp_dir/ecs-task-definition.json" << EOF
{
  "family": "${ECS_SERVICE_NAME}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${ECS_TASK_ROLE_ARN}",
  "tags": [
    {
      "key": "Project",
      "value": "${PROJECT_NAME}"
    }
  ],
  "containerDefinitions": [
    {
      "name": "web-app",
      "image": "${ECR_URI}:1.0.0",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "APP_VERSION",
          "value": "1.0.0"
        },
        {
          "name": "ENVIRONMENT",
          "value": "blue"
        },
        {
          "name": "PORT",
          "value": "8080"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${ECS_SERVICE_NAME}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:8080/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "essential": true
    }
  ]
}
EOF
    
    # Register task definition
    aws ecs register-task-definition \
        --cli-input-json file://"$temp_dir/ecs-task-definition.json"
    
    # Create ECS service
    aws ecs create-service \
        --cluster $ECS_CLUSTER_NAME \
        --service-name $ECS_SERVICE_NAME \
        --task-definition $ECS_SERVICE_NAME \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID_1,$SUBNET_ID_2],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
        --load-balancers targetGroupArn=$TG_BLUE_ARN,containerName=web-app,containerPort=8080 \
        --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" \
        --enable-execute-command \
        --tags key=Name,value=$ECS_SERVICE_NAME key=Project,value=$PROJECT_NAME
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "✅ ECS cluster and service created"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Lambda function"
        return 0
    fi
    
    # Create temporary directory for Lambda function
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create Lambda function code
    cat > lambda-function.py << 'EOF'
import json
import os
import time
import random
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function for blue-green deployment demo
    """
    
    version = os.environ.get('VERSION', '1.0.0')
    environment = os.environ.get('ENVIRONMENT', 'blue')
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Route requests
    if path == '/health':
        return health_check(version, environment)
    elif path == '/api/lambda-data':
        return get_lambda_data(version, environment)
    elif path == '/':
        return home_response(version, environment)
    else:
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Not found'})
        }

def health_check(version, environment):
    """Health check endpoint"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat(),
            'requestId': os.environ.get('AWS_REQUEST_ID', 'unknown')
        })
    }

def get_lambda_data(version, environment):
    """API endpoint returning data"""
    
    data = {
        'version': version,
        'environment': environment,
        'lambda_data': [
            {'id': 1, 'type': 'lambda', 'value': random.random()},
            {'id': 2, 'type': 'lambda', 'value': random.random()},
            {'id': 3, 'type': 'lambda', 'value': random.random()}
        ],
        'timestamp': datetime.utcnow().isoformat(),
        'execution_time_ms': random.randint(50, 200)
    }
    
    # Version-specific features
    if version == '2.0.0':
        data['new_feature'] = 'Enhanced Lambda processing'
        data['lambda_data'].append({
            'id': 4, 'type': 'lambda-enhanced', 'value': random.random()
        })
        
        # Simulate occasional errors in v2.0.0 for rollback testing
        if random.random() < 0.1:  # 10% error rate
            return {
                'statusCode': 500,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'error': 'Simulated error in Lambda v2.0.0',
                    'version': version
                })
            }
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(data)
    }

def home_response(version, environment):
    """Home endpoint response"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': 'Lambda Blue-Green Deployment Demo',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
EOF
    
    # Package Lambda function
    zip lambda-function.zip lambda-function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name $LAMBDA_FUNCTION_NAME \
        --runtime python3.9 \
        --role $LAMBDA_ROLE_ARN \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{VERSION=1.0.0,ENVIRONMENT=blue}" \
        --description "Lambda function for blue-green deployment demo - ${PROJECT_NAME}" \
        --tags Project=$PROJECT_NAME
    
    # Create alias for production traffic
    aws lambda create-alias \
        --function-name $LAMBDA_FUNCTION_NAME \
        --name PROD \
        --function-version '$LATEST' \
        --description "Production alias for blue-green deployments"
    
    # Cleanup
    cd "$SCRIPT_DIR"
    rm -rf "$temp_dir"
    
    log "✅ Lambda function created"
}

# Create CodeDeploy applications
create_codedeploy_apps() {
    log "Creating CodeDeploy applications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create CodeDeploy applications"
        return 0
    fi
    
    # Create CodeDeploy application for ECS
    aws deploy create-application \
        --application-name $CD_ECS_APP_NAME \
        --compute-platform ECS \
        --tags Key=Name,Value=$CD_ECS_APP_NAME Key=Project,Value=$PROJECT_NAME
    
    # Create deployment group for ECS blue-green
    aws deploy create-deployment-group \
        --application-name $CD_ECS_APP_NAME \
        --deployment-group-name "${ECS_SERVICE_NAME}-deployment-group" \
        --service-role-arn $CODEDEPLOY_ROLE_ARN \
        --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE,events=DEPLOYMENT_STOP_ON_ALARM,events=DEPLOYMENT_STOP_ON_INSTANCE_FAILURE \
        --blue-green-deployment-configuration '{
          "deploymentReadyOption": {
            "actionOnTimeout": "CONTINUE_DEPLOYMENT"
          },
          "terminateBlueInstancesOnDeploymentSuccess": {
            "action": "TERMINATE",
            "terminationWaitTimeInMinutes": 5
          },
          "greenFleetProvisioningOption": {
            "action": "COPY_AUTO_SCALING_GROUP"
          }
        }' \
        --ecs-services clusterName=$ECS_CLUSTER_NAME,serviceName=$ECS_SERVICE_NAME \
        --load-balancer-info targetGroupInfoList='[{
          "name": "'$(basename $TG_BLUE_ARN)'"
        },{
          "name": "'$(basename $TG_GREEN_ARN)'"
        }]'
    
    # Create CodeDeploy application for Lambda
    aws deploy create-application \
        --application-name $CD_LAMBDA_APP_NAME \
        --compute-platform Lambda \
        --tags Key=Name,Value=$CD_LAMBDA_APP_NAME Key=Project,Value=$PROJECT_NAME
    
    # Create deployment group for Lambda blue-green
    aws deploy create-deployment-group \
        --application-name $CD_LAMBDA_APP_NAME \
        --deployment-group-name "${LAMBDA_FUNCTION_NAME}-deployment-group" \
        --service-role-arn $CODEDEPLOY_ROLE_ARN \
        --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE,events=DEPLOYMENT_STOP_ON_ALARM
    
    log "✅ CodeDeploy applications created"
}

# Create monitoring and alarms
create_monitoring() {
    log "Creating CloudWatch monitoring and alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create monitoring and alarms"
        return 0
    fi
    
    # Create SNS topic for notifications
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "deployment-notifications-${PROJECT_NAME##*-}" \
        --tags Key=Project,Value=$PROJECT_NAME \
        --output text --query TopicArn)
    
    # Create CloudWatch alarms for ECS service
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ECS_SERVICE_NAME}-high-error-rate" \
        --alarm-description "High error rate in ECS service" \
        --metric-name "HTTPCode_Target_5XX_Count" \
        --namespace "AWS/ApplicationELB" \
        --statistic Sum \
        --period 60 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions $SNS_TOPIC_ARN \
        --dimensions Name=LoadBalancer,Value=$(basename $ALB_ARN) \
                     Name=TargetGroup,Value=$(basename $TG_GREEN_ARN) \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ECS_SERVICE_NAME}-high-response-time" \
        --alarm-description "High response time in ECS service" \
        --metric-name "TargetResponseTime" \
        --namespace "AWS/ApplicationELB" \
        --statistic Average \
        --period 60 \
        --threshold 2.0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 5 \
        --alarm-actions $SNS_TOPIC_ARN \
        --dimensions Name=LoadBalancer,Value=$(basename $ALB_ARN) \
                     Name=TargetGroup,Value=$(basename $TG_GREEN_ARN) \
        --tags Key=Project,Value=$PROJECT_NAME
    
    # Create CloudWatch alarms for Lambda function
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LAMBDA_FUNCTION_NAME}-high-error-rate" \
        --alarm-description "High error rate in Lambda function" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic Sum \
        --period 60 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions $SNS_TOPIC_ARN \
        --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME \
        --tags Key=Project,Value=$PROJECT_NAME
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LAMBDA_FUNCTION_NAME}-high-duration" \
        --alarm-description "High duration in Lambda function" \
        --metric-name "Duration" \
        --namespace "AWS/Lambda" \
        --statistic Average \
        --period 60 \
        --threshold 5000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 5 \
        --alarm-actions $SNS_TOPIC_ARN \
        --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME \
        --tags Key=Project,Value=$PROJECT_NAME
    
    # Update configuration file
    cat >> "${SCRIPT_DIR}/.deployment-config" << EOF
SNS_TOPIC_ARN=$SNS_TOPIC_ARN
EOF
    
    log "✅ Monitoring and alarms created"
}

# Wait for services to stabilize
wait_for_services() {
    log "Waiting for services to stabilize..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would wait for services to stabilize"
        return 0
    fi
    
    # Wait for ECS service to be stable
    log "Waiting for ECS service to stabilize (this may take several minutes)..."
    aws ecs wait services-stable \
        --cluster $ECS_CLUSTER_NAME \
        --services $ECS_SERVICE_NAME
    
    # Verify Lambda function is ready
    log "Verifying Lambda function is ready..."
    local lambda_state
    lambda_state=$(aws lambda get-function \
        --function-name $LAMBDA_FUNCTION_NAME \
        --query 'Configuration.State' --output text)
    
    while [[ "$lambda_state" != "Active" ]]; do
        log "Lambda function state: $lambda_state, waiting..."
        sleep 5
        lambda_state=$(aws lambda get-function \
            --function-name $LAMBDA_FUNCTION_NAME \
            --query 'Configuration.State' --output text)
    done
    
    log "✅ Services are stable and ready"
}

# Test deployment
test_deployment() {
    log "Testing initial deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Test ECS service health
    log "Testing ECS service at: http://$ALB_DNS"
    local retry_count=0
    local max_retries=30
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -sf "http://$ALB_DNS/health" > /dev/null 2>&1; then
            log "✅ ECS service health check passed"
            break
        fi
        ((retry_count++))
        log "Health check attempt $retry_count/$max_retries failed, retrying in 10 seconds..."
        sleep 10
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        error "ECS service health check failed after $max_retries attempts"
        return 1
    fi
    
    # Test Lambda function
    log "Testing Lambda function..."
    local temp_file
    temp_file=$(mktemp)
    
    aws lambda invoke \
        --function-name $LAMBDA_FUNCTION_NAME \
        --payload '{"httpMethod":"GET","path":"/health"}' \
        --cli-binary-format raw-in-base64-out \
        "$temp_file"
    
    if grep -q "healthy" "$temp_file"; then
        log "✅ Lambda function health check passed"
    else
        error "Lambda function health check failed"
        cat "$temp_file" | tee -a "$ERROR_LOG"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    
    log "✅ Deployment testing completed successfully"
}

# Display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    cat << EOF

=== Deployment Summary ===
Project Name: $PROJECT_NAME
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID

=== Deployed Resources ===
ECS Cluster: $ECS_CLUSTER_NAME
ECS Service: $ECS_SERVICE_NAME
Lambda Function: $LAMBDA_FUNCTION_NAME
Application Load Balancer: $ALB_DNS
ECR Repository: $ECR_REPOSITORY

=== CodeDeploy Applications ===
ECS Application: $CD_ECS_APP_NAME
Lambda Application: $CD_LAMBDA_APP_NAME

=== Access URLs ===
Application URL: http://$ALB_DNS
Health Check: http://$ALB_DNS/health
API Endpoint: http://$ALB_DNS/api/data

=== Next Steps ===
1. Test the application using the URLs above
2. Review CloudWatch alarms and monitoring
3. Try blue-green deployments using CodeDeploy
4. When finished, run destroy.sh to clean up resources

=== Configuration ===
Deployment configuration saved to: ${SCRIPT_DIR}/.deployment-config
Logs saved to: $LOG_FILE

EOF
}

# Main execution
main() {
    log "=== Starting Advanced Blue-Green Deployment ==="
    
    check_prerequisites
    setup_environment
    create_vpc_infrastructure
    create_iam_roles
    create_ecr_and_app
    create_ecs_cluster
    create_lambda_function
    create_codedeploy_apps
    create_monitoring
    wait_for_services
    test_deployment
    display_summary
    
    log "=== Deployment completed successfully! ==="
}

# Execute main function
main "$@"