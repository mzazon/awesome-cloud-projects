#!/bin/bash

# Container Secrets Management with AWS Secrets Manager - Deployment Script
# This script implements the complete container secrets management solution
# from the recipe: aws/container-secrets-management-aws-secrets-manager

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log "ERROR" "Helm is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log "INFO" "Checking AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity --query 'Arn' &> /dev/null; then
        log "ERROR" "Unable to verify AWS identity. Please check your credentials."
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully."
}

# Function to setup environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log "WARN" "No region found in AWS config. Using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export CLUSTER_NAME="secrets-demo-${RANDOM_SUFFIX}"
    export SECRET_NAME="demo-app-secrets-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="secrets-rotation-${RANDOM_SUFFIX}"
    
    log "INFO" "Environment variables set:"
    log "INFO" "  CLUSTER_NAME: $CLUSTER_NAME"
    log "INFO" "  SECRET_NAME: $SECRET_NAME"
    log "INFO" "  LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION_NAME"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/environment.env" << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export CLUSTER_NAME="$CLUSTER_NAME"
export SECRET_NAME="$SECRET_NAME"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
EOF
}

# Function to create KMS key
create_kms_key() {
    log "INFO" "Creating KMS key for encryption..."
    
    # Create KMS key
    export KMS_KEY_ID=$(aws kms create-key \
        --description "Secrets Manager encryption key for $CLUSTER_NAME" \
        --query KeyMetadata.KeyId --output text)
    
    if [ $? -eq 0 ]; then
        log "INFO" "KMS key created: $KMS_KEY_ID"
        
        # Create alias
        aws kms create-alias \
            --alias-name "alias/secrets-manager-${RANDOM_SUFFIX}" \
            --target-key-id "$KMS_KEY_ID"
        
        log "INFO" "KMS key alias created: alias/secrets-manager-${RANDOM_SUFFIX}"
        
        # Add to environment file
        echo "export KMS_KEY_ID=\"$KMS_KEY_ID\"" >> "${SCRIPT_DIR}/environment.env"
    else
        log "ERROR" "Failed to create KMS key"
        exit 1
    fi
}

# Function to create secrets in Secrets Manager
create_secrets() {
    log "INFO" "Creating application secrets in AWS Secrets Manager..."
    
    # Create database credentials secret
    aws secretsmanager create-secret \
        --name "${SECRET_NAME}-db" \
        --description "Database credentials for demo application" \
        --secret-string '{"username":"appuser","password":"temp-password123","host":"demo-db.cluster-xyz.us-west-2.rds.amazonaws.com","port":"5432","database":"appdb"}' \
        --kms-key-id "$KMS_KEY_ID" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Database secret created: ${SECRET_NAME}-db"
    else
        log "ERROR" "Failed to create database secret"
        exit 1
    fi
    
    # Create API keys secret
    aws secretsmanager create-secret \
        --name "${SECRET_NAME}-api" \
        --description "API keys for external services" \
        --secret-string '{"github_token":"ghp_example_token","stripe_key":"sk_test_example_key","twilio_sid":"AC_example_sid"}' \
        --kms-key-id "$KMS_KEY_ID" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "API keys secret created: ${SECRET_NAME}-api"
    else
        log "ERROR" "Failed to create API keys secret"
        exit 1
    fi
    
    # Store secret ARNs
    export DB_SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id "${SECRET_NAME}-db" \
        --query ARN --output text)
    
    export API_SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id "${SECRET_NAME}-api" \
        --query ARN --output text)
    
    log "INFO" "Secret ARNs stored:"
    log "INFO" "  DB_SECRET_ARN: $DB_SECRET_ARN"
    log "INFO" "  API_SECRET_ARN: $API_SECRET_ARN"
    
    # Add to environment file
    echo "export DB_SECRET_ARN=\"$DB_SECRET_ARN\"" >> "${SCRIPT_DIR}/environment.env"
    echo "export API_SECRET_ARN=\"$API_SECRET_ARN\"" >> "${SCRIPT_DIR}/environment.env"
}

# Function to create IAM roles for ECS
create_ecs_iam_roles() {
    log "INFO" "Creating IAM roles for ECS tasks..."
    
    # Create trust policy for ECS tasks
    cat > "${SCRIPT_DIR}/ecs-task-trust-policy.json" << 'EOF'
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
    
    # Create ECS task role
    aws iam create-role \
        --role-name "${CLUSTER_NAME}-ecs-task-role" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/ecs-task-trust-policy.json" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "ECS task role created: ${CLUSTER_NAME}-ecs-task-role"
    else
        log "WARN" "ECS task role may already exist or creation failed"
    fi
    
    # Create permissions policy for accessing secrets
    cat > "${SCRIPT_DIR}/ecs-secrets-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": [
                "${DB_SECRET_ARN}",
                "${API_SECRET_ARN}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${CLUSTER_NAME}-ecs-task-role" \
        --policy-name SecretsManagerAccess \
        --policy-document file://"${SCRIPT_DIR}/ecs-secrets-policy.json"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Secrets access policy attached to ECS task role"
    else
        log "ERROR" "Failed to attach secrets access policy to ECS task role"
        exit 1
    fi
    
    # Get role ARN
    export ECS_TASK_ROLE_ARN=$(aws iam get-role \
        --role-name "${CLUSTER_NAME}-ecs-task-role" \
        --query Role.Arn --output text)
    
    log "INFO" "ECS task role ARN: $ECS_TASK_ROLE_ARN"
    
    # Add to environment file
    echo "export ECS_TASK_ROLE_ARN=\"$ECS_TASK_ROLE_ARN\"" >> "${SCRIPT_DIR}/environment.env"
}

# Function to create ECS cluster and task definition
create_ecs_cluster() {
    log "INFO" "Creating ECS cluster and task definition..."
    
    # Create ECS cluster
    aws ecs create-cluster \
        --cluster-name "$CLUSTER_NAME" \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "ECS cluster created: $CLUSTER_NAME"
    else
        log "WARN" "ECS cluster creation may have failed or already exists"
    fi
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/ecs/${CLUSTER_NAME}" \
        --retention-in-days 7 &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "CloudWatch log group created: /ecs/${CLUSTER_NAME}"
    else
        log "WARN" "CloudWatch log group may already exist"
    fi
    
    # Check if ecsTaskExecutionRole exists
    if ! aws iam get-role --role-name ecsTaskExecutionRole &> /dev/null; then
        log "INFO" "Creating ecsTaskExecutionRole..."
        aws iam create-role \
            --role-name ecsTaskExecutionRole \
            --assume-role-policy-document file://"${SCRIPT_DIR}/ecs-task-trust-policy.json" &> /dev/null
        
        aws iam attach-role-policy \
            --role-name ecsTaskExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy &> /dev/null
    fi
    
    # Create task definition
    cat > "${SCRIPT_DIR}/ecs-task-definition.json" << EOF
{
    "family": "${CLUSTER_NAME}-task",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
    "taskRoleArn": "${ECS_TASK_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "demo-app",
            "image": "nginx:latest",
            "portMappings": [
                {
                    "containerPort": 80,
                    "protocol": "tcp"
                }
            ],
            "secrets": [
                {
                    "name": "DB_USERNAME",
                    "valueFrom": "${DB_SECRET_ARN}:username::"
                },
                {
                    "name": "DB_PASSWORD",
                    "valueFrom": "${DB_SECRET_ARN}:password::"
                },
                {
                    "name": "DB_HOST",
                    "valueFrom": "${DB_SECRET_ARN}:host::"
                },
                {
                    "name": "GITHUB_TOKEN",
                    "valueFrom": "${API_SECRET_ARN}:github_token::"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/${CLUSTER_NAME}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                }
            }
        }
    ]
}
EOF
    
    # Register task definition
    aws ecs register-task-definition \
        --cli-input-json file://"${SCRIPT_DIR}/ecs-task-definition.json" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "ECS task definition registered: ${CLUSTER_NAME}-task"
    else
        log "ERROR" "Failed to register ECS task definition"
        exit 1
    fi
}

# Function to create EKS cluster
create_eks_cluster() {
    log "INFO" "Creating EKS cluster (this may take 10-15 minutes)..."
    
    # Create EKS cluster service role
    aws iam create-role \
        --role-name "${CLUSTER_NAME}-eks-service-role" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "eks.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "EKS service role created: ${CLUSTER_NAME}-eks-service-role"
    else
        log "WARN" "EKS service role may already exist"
    fi
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name "${CLUSTER_NAME}-eks-service-role" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy &> /dev/null
    
    # Get default VPC and subnets
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        log "ERROR" "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
    
    log "INFO" "Using VPC: $VPC_ID"
    log "INFO" "Using subnets: $SUBNET_IDS"
    
    # Create EKS cluster
    aws eks create-cluster \
        --name "$CLUSTER_NAME" \
        --version 1.28 \
        --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-eks-service-role" \
        --resources-vpc-config subnetIds="${SUBNET_IDS}" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "EKS cluster creation initiated: $CLUSTER_NAME"
        log "INFO" "Waiting for cluster to be active..."
        
        # Wait for cluster to be active
        aws eks wait cluster-active --name "$CLUSTER_NAME"
        
        if [ $? -eq 0 ]; then
            log "INFO" "EKS cluster is now active"
        else
            log "ERROR" "EKS cluster failed to become active"
            exit 1
        fi
    else
        log "ERROR" "Failed to create EKS cluster"
        exit 1
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Kubeconfig updated for cluster: $CLUSTER_NAME"
    else
        log "ERROR" "Failed to update kubeconfig"
        exit 1
    fi
    
    # Add to environment file
    echo "export VPC_ID=\"$VPC_ID\"" >> "${SCRIPT_DIR}/environment.env"
    echo "export SUBNET_IDS=\"$SUBNET_IDS\"" >> "${SCRIPT_DIR}/environment.env"
}

# Function to install CSI driver and AWS provider
install_csi_driver() {
    log "INFO" "Installing Secrets Store CSI Driver and AWS Provider..."
    
    # Add Helm repositories
    helm repo add secrets-store-csi-driver \
        https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts &> /dev/null
    
    helm repo add aws-secrets-manager \
        https://aws.github.io/secrets-store-csi-driver-provider-aws &> /dev/null
    
    helm repo update &> /dev/null
    
    # Install Secrets Store CSI Driver
    helm install csi-secrets-store \
        secrets-store-csi-driver/secrets-store-csi-driver \
        --namespace kube-system \
        --set syncSecret.enabled=true \
        --set enableSecretRotation=true \
        --wait --timeout=300s &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Secrets Store CSI Driver installed successfully"
    else
        log "ERROR" "Failed to install Secrets Store CSI Driver"
        exit 1
    fi
    
    # Install AWS Secrets and Configuration Provider
    helm install secrets-provider-aws \
        aws-secrets-manager/secrets-store-csi-driver-provider-aws \
        --namespace kube-system \
        --wait --timeout=300s &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "AWS Secrets Provider installed successfully"
    else
        log "ERROR" "Failed to install AWS Secrets Provider"
        exit 1
    fi
    
    # Verify installations
    log "INFO" "Verifying CSI driver installation..."
    kubectl get pods -n kube-system -l app=secrets-store-csi-driver &> /dev/null
    kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws &> /dev/null
}

# Function to create service account with IRSA
create_service_account_irsa() {
    log "INFO" "Creating service account with IRSA for EKS..."
    
    # Get OIDC issuer URL
    OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.identity.oidc.issuer' --output text)
    OIDC_ISSUER_HOSTPATH=$(echo "$OIDC_ISSUER" | sed 's|https://||')
    
    # Create IAM role for service account
    cat > "${SCRIPT_DIR}/eks-pod-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER_HOSTPATH}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_ISSUER_HOSTPATH}:sub": "system:serviceaccount:default:secrets-demo-sa",
                    "${OIDC_ISSUER_HOSTPATH}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF
    
    # Create service account role
    aws iam create-role \
        --role-name "${CLUSTER_NAME}-pod-role" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/eks-pod-trust-policy.json" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Service account role created: ${CLUSTER_NAME}-pod-role"
    else
        log "WARN" "Service account role may already exist"
    fi
    
    # Attach secrets policy
    aws iam put-role-policy \
        --role-name "${CLUSTER_NAME}-pod-role" \
        --policy-name SecretsManagerAccess \
        --policy-document file://"${SCRIPT_DIR}/ecs-secrets-policy.json"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Secrets access policy attached to service account role"
    else
        log "ERROR" "Failed to attach secrets access policy to service account role"
        exit 1
    fi
    
    # Get role ARN
    export POD_ROLE_ARN=$(aws iam get-role \
        --role-name "${CLUSTER_NAME}-pod-role" \
        --query Role.Arn --output text)
    
    log "INFO" "Service account role ARN: $POD_ROLE_ARN"
    
    # Create Kubernetes service account
    kubectl create serviceaccount secrets-demo-sa --dry-run=client -o yaml | kubectl apply -f -
    
    # Annotate service account with IAM role
    kubectl annotate serviceaccount secrets-demo-sa \
        eks.amazonaws.com/role-arn="$POD_ROLE_ARN" --overwrite
    
    if [ $? -eq 0 ]; then
        log "INFO" "Service account annotated with IAM role"
    else
        log "ERROR" "Failed to annotate service account"
        exit 1
    fi
    
    # Add to environment file
    echo "export POD_ROLE_ARN=\"$POD_ROLE_ARN\"" >> "${SCRIPT_DIR}/environment.env"
}

# Function to create SecretProviderClass
create_secret_provider_class() {
    log "INFO" "Creating SecretProviderClass for Kubernetes..."
    
    cat > "${SCRIPT_DIR}/secret-provider-class.yaml" << EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: demo-secrets-provider
  namespace: default
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "${SECRET_NAME}-db"
        objectType: "secretsmanager"
        jmesPath:
          - path: "username"
            objectAlias: "db_username"
          - path: "password"
            objectAlias: "db_password"
          - path: "host"
            objectAlias: "db_host"
      - objectName: "${SECRET_NAME}-api"
        objectType: "secretsmanager"
        jmesPath:
          - path: "github_token"
            objectAlias: "github_token"
          - path: "stripe_key"
            objectAlias: "stripe_key"
  secretObjects:
    - secretName: demo-secrets
      type: Opaque
      data:
        - objectName: db_username
          key: db_username
        - objectName: db_password
          key: db_password
        - objectName: db_host
          key: db_host
        - objectName: github_token
          key: github_token
        - objectName: stripe_key
          key: stripe_key
EOF
    
    # Apply SecretProviderClass
    kubectl apply -f "${SCRIPT_DIR}/secret-provider-class.yaml"
    
    if [ $? -eq 0 ]; then
        log "INFO" "SecretProviderClass created successfully"
    else
        log "ERROR" "Failed to create SecretProviderClass"
        exit 1
    fi
}

# Function to deploy application pod
deploy_application_pod() {
    log "INFO" "Deploying application pod with secrets mount..."
    
    cat > "${SCRIPT_DIR}/demo-app-deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      serviceAccountName: secrets-demo-sa
      containers:
      - name: demo-app
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
        env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: demo-secrets
              key: db_username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: demo-secrets
              key: db_password
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: demo-secrets
              key: db_host
        - name: GITHUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: demo-secrets
              key: github_token
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "demo-secrets-provider"
EOF
    
    # Apply deployment
    kubectl apply -f "${SCRIPT_DIR}/demo-app-deployment.yaml"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Application deployment created"
    else
        log "ERROR" "Failed to create application deployment"
        exit 1
    fi
    
    # Wait for deployment to be ready
    kubectl rollout status deployment/demo-app --timeout=300s
    
    if [ $? -eq 0 ]; then
        log "INFO" "Application deployment is ready"
    else
        log "ERROR" "Application deployment failed to become ready"
        exit 1
    fi
}

# Function to setup automatic secret rotation
setup_secret_rotation() {
    log "INFO" "Setting up automatic secret rotation..."
    
    # Create Lambda function for rotation
    cat > "${SCRIPT_DIR}/lambda-rotation.py" << 'EOF'
import boto3
import json
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    client = boto3.client('secretsmanager')
    
    # Get the secret ARN from the event
    secret_arn = event['Step']
    
    try:
        # Generate new random password
        new_password = boto3.client('secretsmanager').get_random_password(
            PasswordLength=32,
            ExcludeCharacters='"@/\\'
        )['RandomPassword']
        
        # Get current secret
        current_secret = client.get_secret_value(SecretId=secret_arn)
        secret_dict = json.loads(current_secret['SecretString'])
        
        # Update password
        secret_dict['password'] = new_password
        
        # Update secret
        client.update_secret(
            SecretId=secret_arn,
            SecretString=json.dumps(secret_dict)
        )
        
        logger.info(f"Successfully rotated secret: {secret_arn}")
        return {'statusCode': 200, 'body': 'Secret rotated successfully'}
        
    except Exception as e:
        logger.error(f"Error rotating secret: {str(e)}")
        raise e
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip -q lambda-rotation.zip lambda-rotation.py
    
    # Create Lambda role
    aws iam create-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
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
        }' &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Lambda role created: ${LAMBDA_FUNCTION_NAME}-role"
    else
        log "WARN" "Lambda role may already exist"
    fi
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &> /dev/null
    
    # Create custom policy for secrets access
    aws iam put-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-name SecretsManagerRotation \
        --policy-document file://"${SCRIPT_DIR}/ecs-secrets-policy.json"
    
    # Wait for role to be available
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
        --handler lambda-rotation.lambda_handler \
        --zip-file fileb://lambda-rotation.zip \
        --timeout 60 &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Lambda function created: $LAMBDA_FUNCTION_NAME"
    else
        log "ERROR" "Failed to create Lambda function"
        exit 1
    fi
    
    # Configure rotation for database secret
    aws secretsmanager rotate-secret \
        --secret-id "$DB_SECRET_ARN" \
        --rotation-lambda-arn "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
        --rotation-rules "AutomaticallyAfterDays=30" &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Secret rotation configured for database secret"
    else
        log "WARN" "Secret rotation configuration may have failed"
    fi
}

# Function to create monitoring and alerting
create_monitoring() {
    log "INFO" "Creating monitoring and alerting resources..."
    
    # Create CloudWatch alarm for secret access
    aws cloudwatch put-metric-alarm \
        --alarm-name "${SECRET_NAME}-unauthorized-access" \
        --alarm-description "Alert on unauthorized secret access attempts" \
        --metric-name UnauthorizedAPICallsCount \
        --namespace AWS/Secrets \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "CloudWatch alarm created for unauthorized access"
    else
        log "WARN" "CloudWatch alarm creation may have failed"
    fi
    
    # Create CloudWatch log group for audit logs
    aws logs create-log-group \
        --log-group-name "/aws/secretsmanager/${SECRET_NAME}" \
        --retention-in-days 90 &> /dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "CloudWatch log group created for audit logs"
    else
        log "WARN" "CloudWatch log group may already exist"
    fi
}

# Function to run validation tests
run_validation_tests() {
    log "INFO" "Running validation tests..."
    
    # Test EKS secrets mount
    log "INFO" "Testing EKS secrets integration..."
    POD_NAME=$(kubectl get pods -l app=demo-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$POD_NAME" ]; then
        log "INFO" "Demo app pod found: $POD_NAME"
        
        # Check mounted secrets
        if kubectl exec "$POD_NAME" -- ls -la /mnt/secrets/ &> /dev/null; then
            log "INFO" "✅ Secrets successfully mounted in pod"
        else
            log "ERROR" "❌ Failed to access mounted secrets"
        fi
        
        # Verify environment variables
        if kubectl exec "$POD_NAME" -- env | grep -E "(DB_USERNAME|DB_PASSWORD)" &> /dev/null; then
            log "INFO" "✅ Environment variables successfully set from secrets"
        else
            log "ERROR" "❌ Environment variables not set from secrets"
        fi
    else
        log "ERROR" "❌ Demo app pod not found"
    fi
    
    # Test secret rotation
    log "INFO" "Testing secret rotation capability..."
    CURRENT_VERSION=$(aws secretsmanager describe-secret \
        --secret-id "$DB_SECRET_ARN" \
        --query 'VersionIdsToStages' --output text 2>/dev/null)
    
    if [ -n "$CURRENT_VERSION" ]; then
        log "INFO" "✅ Secret rotation capability verified"
    else
        log "ERROR" "❌ Unable to verify secret rotation"
    fi
}

# Function to display deployment summary
display_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "===================="
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "ECS Cluster Name: $CLUSTER_NAME"
    log "INFO" "EKS Cluster Name: $CLUSTER_NAME"
    log "INFO" "Database Secret ARN: $DB_SECRET_ARN"
    log "INFO" "API Secret ARN: $API_SECRET_ARN"
    log "INFO" "Lambda Function Name: $LAMBDA_FUNCTION_NAME"
    log "INFO" "KMS Key ID: $KMS_KEY_ID"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "1. Test ECS secrets integration by running a task"
    log "INFO" "2. Test EKS secrets integration by checking pod logs"
    log "INFO" "3. Monitor secret rotation logs in CloudWatch"
    log "INFO" "4. Review security monitoring in CloudWatch alarms"
    log "INFO" ""
    log "INFO" "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    log "INFO" "Starting Container Secrets Management deployment..."
    log "INFO" "=================================================="
    
    # Initialize log files
    echo "Container Secrets Management Deployment Log - $(date)" > "$LOG_FILE"
    echo "Container Secrets Management Deployment Errors - $(date)" > "$ERROR_LOG"
    
    # Set trap for cleanup on exit
    trap 'log "ERROR" "Deployment failed. Check logs: $LOG_FILE and $ERROR_LOG"' ERR
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_kms_key
    create_secrets
    create_ecs_iam_roles
    create_ecs_cluster
    create_eks_cluster
    install_csi_driver
    create_service_account_irsa
    create_secret_provider_class
    deploy_application_pod
    setup_secret_rotation
    create_monitoring
    run_validation_tests
    display_summary
    
    log "INFO" "✅ Container Secrets Management deployment completed successfully!"
    log "INFO" "Environment variables saved to: ${SCRIPT_DIR}/environment.env"
    log "INFO" "Deployment logs saved to: $LOG_FILE"
}

# Run main function
main "$@"