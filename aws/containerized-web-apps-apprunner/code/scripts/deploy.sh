#!/bin/bash

# Deploy Script for Containerized Web Applications with App Runner and RDS
# This script deploys the complete infrastructure and application stack

set -e
set -o pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    log "Deployment failed. You may need to run cleanup manually."
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed. Please install it first."
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running. Please start Docker first."
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS configuration
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export DB_NAME="webapp-db-${RANDOM_SUFFIX}"
    export APP_NAME="webapp-${RANDOM_SUFFIX}"
    export ECR_REPO="webapp-${RANDOM_SUFFIX}"
    export SECRET_NAME="webapp-db-credentials-${RANDOM_SUFFIX}"
    
    log_success "Environment variables set"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Resource Suffix: $RANDOM_SUFFIX"
}

# Create VPC and networking
create_networking() {
    log "Creating VPC and networking components..."
    
    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --resources ${VPC_ID} \
        --tags Key=Name,Value=webapp-vpc-${RANDOM_SUFFIX} \
              Key=Project,Value=webapp-apprunner-rds
    
    log "Created VPC: $VPC_ID"
    
    # Wait for VPC to be available
    aws ec2 wait vpc-available --vpc-ids ${VPC_ID}
    
    # Create subnets in different AZs
    AVAILABILITY_ZONES=($(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[0:2].ZoneName' --output text))
    
    export SUBNET1_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AVAILABILITY_ZONES[0]} \
        --query 'Subnet.SubnetId' --output text)
    
    export SUBNET2_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.2.0/24 \
        --availability-zone ${AVAILABILITY_ZONES[1]} \
        --query 'Subnet.SubnetId' --output text)
    
    aws ec2 create-tags \
        --resources ${SUBNET1_ID} ${SUBNET2_ID} \
        --tags Key=Project,Value=webapp-apprunner-rds
    
    log "Created subnets: $SUBNET1_ID, $SUBNET2_ID"
    
    # Create security group for RDS
    export SG_ID=$(aws ec2 create-security-group \
        --group-name webapp-rds-sg-${RANDOM_SUFFIX} \
        --description "Security group for RDS database" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 5432 \
        --cidr 10.0.0.0/16
    
    aws ec2 create-tags \
        --resources ${SG_ID} \
        --tags Key=Name,Value=webapp-rds-sg-${RANDOM_SUFFIX} \
              Key=Project,Value=webapp-apprunner-rds
    
    log_success "Networking setup completed"
}

# Create ECR repository
create_ecr_repository() {
    log "Creating ECR repository..."
    
    aws ecr create-repository \
        --repository-name ${ECR_REPO} \
        --region ${AWS_REGION} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 > /dev/null
    
    # Get ECR login token and authenticate Docker
    aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS \
        --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    export ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
    
    log_success "ECR repository created: ${ECR_URI}"
}

# Build and push application
build_and_push_application() {
    log "Building and pushing sample web application..."
    
    # Create temporary application directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "webapp-apprunner",
  "version": "1.0.0",
  "description": "Sample web app for App Runner",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.0",
    "aws-sdk": "^2.1414.0"
  }
}
EOF
    
    # Create server.js
    cat > server.js << 'EOF'
const express = require('express');
const { Client } = require('pg');
const AWS = require('aws-sdk');

const app = express();
const port = process.env.PORT || 8080;

// Configure AWS SDK
AWS.config.update({ region: process.env.AWS_REGION || 'us-east-1' });
const secretsManager = new AWS.SecretsManager();

let dbClient;

// Initialize database connection
async function initDB() {
  try {
    const secretName = process.env.DB_SECRET_NAME;
    if (!secretName) {
      console.log('DB_SECRET_NAME not set, skipping database initialization');
      return;
    }
    
    const secret = await secretsManager.getSecretValue({ SecretId: secretName }).promise();
    const credentials = JSON.parse(secret.SecretString);
    
    dbClient = new Client({
      host: credentials.host,
      port: credentials.port,
      database: credentials.dbname,
      user: credentials.username,
      password: credentials.password,
    });
    
    await dbClient.connect();
    console.log('Connected to database');
  } catch (error) {
    console.error('Database connection error:', error);
  }
}

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    if (dbClient) {
      await dbClient.query('SELECT 1');
      res.json({ status: 'healthy', database: 'connected' });
    } else {
      res.json({ status: 'healthy', database: 'disconnected' });
    }
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', error: error.message });
  }
});

// Main endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Hello from App Runner!',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Start server
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
  initDB();
});
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

EXPOSE 8080

CMD ["npm", "start"]
EOF
    
    # Build and push Docker image
    docker build -t ${ECR_URI}:latest .
    docker push ${ECR_URI}:latest
    
    # Return to original directory and cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    log_success "Container image built and pushed to ECR"
}

# Create RDS database
create_rds_database() {
    log "Creating RDS database instance..."
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name webapp-subnet-group-${RANDOM_SUFFIX} \
        --db-subnet-group-description "Subnet group for webapp database" \
        --subnet-ids ${SUBNET1_ID} ${SUBNET2_ID} \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    # Generate secure password
    DB_PASSWORD=$(aws secretsmanager get-random-password \
        --password-length 16 \
        --exclude-characters '"@/\' \
        --require-each-included-type \
        --output text --query RandomPassword)
    
    # Create RDS instance
    aws rds create-db-instance \
        --db-instance-identifier ${DB_NAME} \
        --db-instance-class db.t3.micro \
        --engine postgres \
        --engine-version 14.9 \
        --master-username postgres \
        --master-user-password "$DB_PASSWORD" \
        --allocated-storage 20 \
        --storage-type gp2 \
        --db-subnet-group-name webapp-subnet-group-${RANDOM_SUFFIX} \
        --vpc-security-group-ids ${SG_ID} \
        --backup-retention-period 7 \
        --no-multi-az \
        --no-publicly-accessible \
        --storage-encrypted \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    log "Database creation initiated. Waiting for it to become available..."
    log "⏳ This may take 5-10 minutes..."
    
    # Wait for database to be available
    aws rds wait db-instance-available --db-instance-identifier ${DB_NAME}
    
    # Get database endpoint
    export DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier ${DB_NAME} \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    export DB_PASSWORD
    
    log_success "RDS database created: ${DB_ENDPOINT}"
}

# Store database credentials in Secrets Manager
store_database_credentials() {
    log "Storing database credentials in Secrets Manager..."
    
    aws secretsmanager create-secret \
        --name ${SECRET_NAME} \
        --description "Database credentials for webapp" \
        --secret-string "{
          \"username\": \"postgres\",
          \"password\": \"$DB_PASSWORD\",
          \"host\": \"${DB_ENDPOINT}\",
          \"port\": 5432,
          \"dbname\": \"postgres\"
        }" \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    # Get secret ARN
    export SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id ${SECRET_NAME} \
        --query 'ARN' --output text)
    
    log_success "Database credentials stored in Secrets Manager"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles for App Runner..."
    
    # Create App Runner service role trust policy
    cat > apprunner-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "build.apprunner.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    aws iam create-role \
        --role-name AppRunnerServiceRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://apprunner-trust-policy.json \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    # Create instance role trust policy
    cat > apprunner-instance-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "tasks.apprunner.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    aws iam create-role \
        --role-name AppRunnerInstanceRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://apprunner-instance-trust-policy.json \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    # Create policy for Secrets Manager access
    cat > secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "${SECRET_ARN}"
    }
  ]
}
EOF
    
    aws iam create-policy \
        --policy-name SecretsManagerAccess-${RANDOM_SUFFIX} \
        --policy-document file://secrets-policy.json \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    # Attach policies to roles
    aws iam attach-role-policy \
        --role-name AppRunnerServiceRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess
    
    aws iam attach-role-policy \
        --role-name AppRunnerInstanceRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerAccess-${RANDOM_SUFFIX}
    
    # Get role ARNs
    export SERVICE_ROLE_ARN=$(aws iam get-role \
        --role-name AppRunnerServiceRole-${RANDOM_SUFFIX} \
        --query 'Role.Arn' --output text)
    
    export INSTANCE_ROLE_ARN=$(aws iam get-role \
        --role-name AppRunnerInstanceRole-${RANDOM_SUFFIX} \
        --query 'Role.Arn' --output text)
    
    # Clean up temporary files
    rm -f apprunner-trust-policy.json apprunner-instance-trust-policy.json secrets-policy.json
    
    log_success "IAM roles created for App Runner service"
}

# Create App Runner service
create_apprunner_service() {
    log "Creating App Runner service..."
    
    # Create App Runner service configuration
    cat > apprunner-service.json << EOF
{
  "ServiceName": "${APP_NAME}",
  "SourceConfiguration": {
    "ImageRepository": {
      "ImageIdentifier": "${ECR_URI}:latest",
      "ImageConfiguration": {
        "Port": "8080",
        "RuntimeEnvironmentVariables": {
          "NODE_ENV": "production",
          "AWS_REGION": "${AWS_REGION}",
          "DB_SECRET_NAME": "${SECRET_NAME}"
        }
      },
      "ImageRepositoryType": "ECR"
    },
    "AutoDeploymentsEnabled": true
  },
  "InstanceConfiguration": {
    "Cpu": "0.25 vCPU",
    "Memory": "0.5 GB",
    "InstanceRoleArn": "${INSTANCE_ROLE_ARN}"
  },
  "HealthCheckConfiguration": {
    "Protocol": "HTTP",
    "Path": "/health",
    "Interval": 10,
    "Timeout": 5,
    "HealthyThreshold": 1,
    "UnhealthyThreshold": 5
  },
  "NetworkConfiguration": {
    "EgressConfiguration": {
      "EgressType": "DEFAULT"
    }
  },
  "ObservabilityConfiguration": {
    "ObservabilityEnabled": true
  }
}
EOF
    
    # Create App Runner service
    aws apprunner create-service \
        --cli-input-json file://apprunner-service.json \
        --service-role-arn ${SERVICE_ROLE_ARN} > /dev/null
    
    log "App Runner service creation initiated. Waiting for it to be running..."
    log "⏳ This may take 5-10 minutes..."
    
    # Wait for service to be running
    export SERVICE_ARN=$(aws apprunner list-services \
        --query "ServiceSummaryList[?ServiceName=='${APP_NAME}'].ServiceArn" \
        --output text)
    
    aws apprunner wait service-running --service-arn ${SERVICE_ARN}
    
    # Get service details
    export SERVICE_URL=$(aws apprunner describe-service \
        --service-arn ${SERVICE_ARN} \
        --query 'Service.ServiceUrl' --output text)
    
    # Clean up temporary file
    rm -f apprunner-service.json
    
    log_success "App Runner service created: https://${SERVICE_URL}"
}

# Configure CloudWatch monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${APP_NAME}-high-cpu" \
        --alarm-description "Alert when CPU exceeds 80%" \
        --metric-name CPUUtilization \
        --namespace AWS/AppRunner \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ServiceName,Value=${APP_NAME} \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${APP_NAME}-high-memory" \
        --alarm-description "Alert when memory exceeds 80%" \
        --metric-name MemoryUtilization \
        --namespace AWS/AppRunner \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ServiceName,Value=${APP_NAME} \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${APP_NAME}-high-latency" \
        --alarm-description "Alert when response time exceeds 2 seconds" \
        --metric-name RequestLatency \
        --namespace AWS/AppRunner \
        --statistic Average \
        --period 300 \
        --threshold 2000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ServiceName,Value=${APP_NAME} \
        --tags Key=Project,Value=webapp-apprunner-rds > /dev/null
    
    # Create custom log group
    aws logs create-log-group \
        --log-group-name "/aws/apprunner/${APP_NAME}/application" \
        --retention-in-days 7 \
        --tags Project=webapp-apprunner-rds > /dev/null
    
    log_success "CloudWatch monitoring configured with alarms and log groups"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Test application endpoint
    if command -v curl &> /dev/null; then
        log "Testing application endpoint..."
        RESPONSE=$(curl -s -w "%{http_code}" https://${SERVICE_URL}/)
        HTTP_CODE=$(echo $RESPONSE | tail -c 4)
        
        if [ "$HTTP_CODE" = "200" ]; then
            log_success "Application endpoint is responding correctly"
        else
            log_warning "Application endpoint returned HTTP $HTTP_CODE"
        fi
    fi
    
    # Test health endpoint
    if command -v curl &> /dev/null; then
        log "Testing health check endpoint..."
        HEALTH_RESPONSE=$(curl -s -w "%{http_code}" https://${SERVICE_URL}/health)
        HEALTH_CODE=$(echo $HEALTH_RESPONSE | tail -c 4)
        
        if [ "$HEALTH_CODE" = "200" ]; then
            log_success "Health check endpoint is responding correctly"
        else
            log_warning "Health check endpoint returned HTTP $HEALTH_CODE"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment_id": "${RANDOM_SUFFIX}",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "service_url": "https://${SERVICE_URL}",
  "service_arn": "${SERVICE_ARN}",
  "database_endpoint": "${DB_ENDPOINT}",
  "database_name": "${DB_NAME}",
  "secret_name": "${SECRET_NAME}",
  "secret_arn": "${SECRET_ARN}",
  "ecr_repository": "${ECR_URI}",
  "vpc_id": "${VPC_ID}",
  "subnet_ids": ["${SUBNET1_ID}", "${SUBNET2_ID}"],
  "security_group_id": "${SG_ID}",
  "service_role_arn": "${SERVICE_ROLE_ARN}",
  "instance_role_arn": "${INSTANCE_ROLE_ARN}",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Main deployment function
main() {
    log "Starting deployment of Containerized Web Application with App Runner and RDS..."
    log "========================================================================"
    
    # Check if running with --help
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --dry-run     Show what would be deployed without actually deploying"
        echo ""
        echo "This script deploys a complete containerized web application stack including:"
        echo "  - Amazon ECR repository for container images"
        echo "  - VPC with subnets and security groups"
        echo "  - Amazon RDS PostgreSQL database"
        echo "  - AWS Secrets Manager for credential storage"
        echo "  - IAM roles with appropriate permissions"
        echo "  - AWS App Runner service for container deployment"
        echo "  - CloudWatch monitoring and alarms"
        echo ""
        exit 0
    fi
    
    # Check for dry-run
    if [[ "$1" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be created"
        log "Would deploy the following components:"
        log "  ✓ VPC with 2 private subnets"
        log "  ✓ RDS PostgreSQL database (db.t3.micro)"
        log "  ✓ ECR repository for container images"
        log "  ✓ Secrets Manager secret for database credentials"
        log "  ✓ IAM roles for App Runner service"
        log "  ✓ App Runner service with health checks"
        log "  ✓ CloudWatch alarms and log groups"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_networking
    create_ecr_repository
    build_and_push_application
    create_rds_database
    store_database_credentials
    create_iam_roles
    create_apprunner_service
    configure_monitoring
    validate_deployment
    save_deployment_info
    
    log_success "========================================================================"
    log_success "Deployment completed successfully!"
    log_success "========================================================================"
    log ""
    log "📋 Deployment Summary:"
    log "   Application URL: https://${SERVICE_URL}"
    log "   Health Check: https://${SERVICE_URL}/health"
    log "   Database Endpoint: ${DB_ENDPOINT}"
    log "   ECR Repository: ${ECR_URI}"
    log ""
    log "🔧 Management Commands:"
    log "   View App Runner service: aws apprunner describe-service --service-arn ${SERVICE_ARN}"
    log "   View RDS instance: aws rds describe-db-instances --db-instance-identifier ${DB_NAME}"
    log "   View CloudWatch logs: aws logs tail /aws/apprunner/${APP_NAME}/application --follow"
    log ""
    log "🧹 Cleanup:"
    log "   To remove all resources, run: ./destroy.sh"
    log ""
    log "💰 Cost Estimation:"
    log "   App Runner: ~\$7-15/month (depending on usage)"
    log "   RDS db.t3.micro: ~\$12-15/month"
    log "   Other services: ~\$1-3/month"
    log "   Total estimated: ~\$20-35/month"
    log ""
    log_success "Deployment information saved to deployment-info.json"
}

# Run main function with all arguments
main "$@"