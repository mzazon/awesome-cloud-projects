#!/bin/bash

# =============================================================================
# ECS Task Definitions with Environment Variable Management - Deployment Script
# =============================================================================
# This script deploys the complete infrastructure for demonstrating ECS task
# definitions with comprehensive environment variable management strategies.
#
# Features:
# - ECS cluster with Fargate support
# - Systems Manager Parameter Store hierarchical configuration
# - S3 environment files for batch configuration
# - IAM roles with least privilege access
# - Multiple task definitions demonstrating different approaches
# - ECS service with proper network configuration
#
# Author: AWS Recipes Team
# Version: 1.0
# =============================================================================

set -euo pipefail

# Enable debug mode if DEBUG environment variable is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# =============================================================================
# CONFIGURATION AND GLOBAL VARIABLES
# =============================================================================

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TEMP_DIR="/tmp/ecs-envvar-deploy-$$"

# Deployment configuration
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-ecs-envvar-demo}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up temporary resources..."
    rm -rf "${TEMP_DIR}"
    exit 1
}

trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid"
        return 1
    fi
    
    # Check required permissions by testing basic operations
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log_error "Insufficient IAM permissions for deployment"
        return 1
    fi
    
    # Validate region
    if ! aws ec2 describe-regions --region-names "${AWS_REGION}" &> /dev/null; then
        log_error "Invalid AWS region: ${AWS_REGION}"
        return 1
    fi
    
    log_success "Prerequisites check passed"
}

# Resource existence checks
check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "${resource_type}" in
        "cluster")
            aws ecs describe-clusters --clusters "${resource_name}" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"
            ;;
        "bucket")
            aws s3api head-bucket --bucket "${resource_name}" 2>/dev/null
            ;;
        "role")
            aws iam get-role --role-name "${resource_name}" &>/dev/null
            ;;
        "parameter")
            aws ssm get-parameter --name "${resource_name}" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# RESOURCE GENERATION FUNCTIONS
# =============================================================================

generate_unique_suffix() {
    aws secretsmanager get-random-password \
        --exclude-punctuation \
        --exclude-uppercase \
        --password-length 6 \
        --require-each-included-type \
        --output text \
        --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)"
}

set_environment_variables() {
    log_info "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export RANDOM_SUFFIX=$(generate_unique_suffix)
    
    # Resource names
    export CLUSTER_NAME="${DEPLOYMENT_NAME}-cluster-${RANDOM_SUFFIX}"
    export TASK_FAMILY="${DEPLOYMENT_NAME}-task"
    export SERVICE_NAME="${DEPLOYMENT_NAME}-service"
    export S3_BUCKET="${DEPLOYMENT_NAME}-configs-${RANDOM_SUFFIX}"
    export EXEC_ROLE_NAME="ecsTaskExecutionRole-${RANDOM_SUFFIX}"
    export TASK_ROLE_NAME="ecsTaskRole-${RANDOM_SUFFIX}"
    export POLICY_NAME="ParameterStoreAccess-${RANDOM_SUFFIX}"
    
    # Create state file for cleanup
    cat > "${SCRIPT_DIR}/.deployment_state" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
CLUSTER_NAME=${CLUSTER_NAME}
TASK_FAMILY=${TASK_FAMILY}
SERVICE_NAME=${SERVICE_NAME}
S3_BUCKET=${S3_BUCKET}
EXEC_ROLE_NAME=${EXEC_ROLE_NAME}
TASK_ROLE_NAME=${TASK_ROLE_NAME}
POLICY_NAME=${POLICY_NAME}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
EOF
    
    log_success "Environment variables configured"
    log_info "  - AWS Region: ${AWS_REGION}"
    log_info "  - AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "  - Cluster Name: ${CLUSTER_NAME}"
    log_info "  - S3 Bucket: ${S3_BUCKET}"
}

# =============================================================================
# INFRASTRUCTURE DEPLOYMENT FUNCTIONS
# =============================================================================

create_ecs_cluster() {
    log_info "Creating ECS cluster: ${CLUSTER_NAME}"
    
    if check_resource_exists "cluster" "${CLUSTER_NAME}"; then
        log_warning "ECS cluster ${CLUSTER_NAME} already exists, skipping creation"
        return 0
    fi
    
    aws ecs create-cluster \
        --cluster-name "${CLUSTER_NAME}" \
        --capacity-providers FARGATE \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --tags key=Project,value="${DEPLOYMENT_NAME}" \
              key=Environment,value="${ENVIRONMENT}" \
              key=ManagedBy,value="ecs-envvar-deploy-script" \
        --output text &>> "${LOG_FILE}"
    
    # Wait for cluster to become active
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status=$(aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --query 'clusters[0].status' --output text 2>/dev/null || echo "")
        
        if [[ "${status}" == "ACTIVE" ]]; then
            log_success "ECS cluster created successfully"
            return 0
        fi
        
        log_info "Waiting for cluster to become active (attempt ${attempt}/${max_attempts})..."
        sleep 5
        ((attempt++))
    done
    
    log_error "ECS cluster failed to become active within expected time"
    return 1
}

create_s3_bucket() {
    log_info "Creating S3 bucket: ${S3_BUCKET}"
    
    if check_resource_exists "bucket" "${S3_BUCKET}"; then
        log_warning "S3 bucket ${S3_BUCKET} already exists, skipping creation"
        return 0
    fi
    
    # Create bucket with appropriate region configuration
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "${S3_BUCKET}" \
            --output text &>> "${LOG_FILE}"
    else
        aws s3api create-bucket \
            --bucket "${S3_BUCKET}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}" \
            --output text &>> "${LOG_FILE}"
    fi
    
    # Enable versioning and encryption
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET}" \
        --versioning-configuration Status=Enabled \
        --output text &>> "${LOG_FILE}"
    
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }' \
        --output text &>> "${LOG_FILE}"
    
    # Add bucket tags
    aws s3api put-bucket-tagging \
        --bucket "${S3_BUCKET}" \
        --tagging 'TagSet=[
            {Key=Project,Value='${DEPLOYMENT_NAME}'},
            {Key=Environment,Value='${ENVIRONMENT}'},
            {Key=ManagedBy,Value=ecs-envvar-deploy-script}
        ]' \
        --output text &>> "${LOG_FILE}"
    
    log_success "S3 bucket created with versioning and encryption enabled"
}

create_ssm_parameters() {
    log_info "Creating Systems Manager parameters..."
    
    mkdir -p "${TEMP_DIR}"
    
    # Create parameter definitions
    cat > "${TEMP_DIR}/parameters.json" << EOF
[
    {
        "name": "/myapp/${ENVIRONMENT}/database/host",
        "value": "${ENVIRONMENT}-database.internal.com",
        "type": "String",
        "description": "${ENVIRONMENT} database host"
    },
    {
        "name": "/myapp/${ENVIRONMENT}/database/port",
        "value": "5432",
        "type": "String",
        "description": "${ENVIRONMENT} database port"
    },
    {
        "name": "/myapp/${ENVIRONMENT}/api/debug",
        "value": "true",
        "type": "String",
        "description": "${ENVIRONMENT} API debug mode"
    },
    {
        "name": "/myapp/${ENVIRONMENT}/database/password",
        "value": "${ENVIRONMENT}-secure-password-123",
        "type": "SecureString",
        "description": "${ENVIRONMENT} database password"
    },
    {
        "name": "/myapp/${ENVIRONMENT}/api/secret-key",
        "value": "${ENVIRONMENT}-api-secret-key-456",
        "type": "SecureString",
        "description": "${ENVIRONMENT} API secret key"
    },
    {
        "name": "/myapp/shared/region",
        "value": "${AWS_REGION}",
        "type": "String",
        "description": "Shared region parameter"
    },
    {
        "name": "/myapp/shared/account-id",
        "value": "${AWS_ACCOUNT_ID}",
        "type": "String",
        "description": "Shared account ID parameter"
    }
]
EOF

    # Create parameters
    local created_count=0
    while IFS= read -r param_json; do
        local param_name=$(echo "$param_json" | jq -r '.name')
        local param_value=$(echo "$param_json" | jq -r '.value')
        local param_type=$(echo "$param_json" | jq -r '.type')
        local param_description=$(echo "$param_json" | jq -r '.description')
        
        if check_resource_exists "parameter" "${param_name}"; then
            log_warning "Parameter ${param_name} already exists, skipping"
            continue
        fi
        
        aws ssm put-parameter \
            --name "${param_name}" \
            --value "${param_value}" \
            --type "${param_type}" \
            --description "${param_description}" \
            --tags Key=Project,Value="${DEPLOYMENT_NAME}" \
                   Key=Environment,Value="${ENVIRONMENT}" \
                   Key=ManagedBy,Value="ecs-envvar-deploy-script" \
            --output text &>> "${LOG_FILE}"
        
        ((created_count++))
        log_info "Created parameter: ${param_name}"
    done < <(jq -c '.[]' "${TEMP_DIR}/parameters.json")
    
    log_success "Created ${created_count} Systems Manager parameters"
}

create_environment_files() {
    log_info "Creating and uploading environment files..."
    
    mkdir -p "${TEMP_DIR}/configs"
    
    # Create development environment file
    cat > "${TEMP_DIR}/configs/app-config.env" << EOF
LOG_LEVEL=info
MAX_CONNECTIONS=100
TIMEOUT_SECONDS=30
FEATURE_FLAGS=auth,logging,metrics
APP_VERSION=1.2.3
DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
CLUSTER_NAME=${CLUSTER_NAME}
EOF

    # Create production-like environment file
    cat > "${TEMP_DIR}/configs/prod-config.env" << EOF
LOG_LEVEL=warn
MAX_CONNECTIONS=500
TIMEOUT_SECONDS=60
FEATURE_FLAGS=auth,logging,metrics,cache
APP_VERSION=1.2.3
MONITORING_ENABLED=true
DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
EOF

    # Upload files to S3
    aws s3 cp "${TEMP_DIR}/configs/" "s3://${S3_BUCKET}/configs/" \
        --recursive \
        --metadata Project="${DEPLOYMENT_NAME}",Environment="${ENVIRONMENT}" \
        --output text &>> "${LOG_FILE}"
    
    log_success "Environment files uploaded to S3"
}

create_iam_roles() {
    log_info "Creating IAM roles and policies..."
    
    mkdir -p "${TEMP_DIR}/iam"
    
    # Create trust policy for ECS tasks
    cat > "${TEMP_DIR}/iam/ecs-trust-policy.json" << EOF
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

    # Create task execution role if it doesn't exist
    if ! check_resource_exists "role" "${EXEC_ROLE_NAME}"; then
        aws iam create-role \
            --role-name "${EXEC_ROLE_NAME}" \
            --assume-role-policy-document "file://${TEMP_DIR}/iam/ecs-trust-policy.json" \
            --description "ECS task execution role for ${DEPLOYMENT_NAME}" \
            --tags Key=Project,Value="${DEPLOYMENT_NAME}" \
                   Key=Environment,Value="${ENVIRONMENT}" \
                   Key=ManagedBy,Value="ecs-envvar-deploy-script" \
            --output text &>> "${LOG_FILE}"
        
        log_info "Created ECS task execution role"
    else
        log_warning "ECS task execution role already exists, skipping creation"
    fi
    
    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "${EXEC_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
        --output text &>> "${LOG_FILE}" 2>&1 || true
    
    # Create custom policy for Parameter Store and S3 access
    cat > "${TEMP_DIR}/iam/parameter-store-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameters",
                "ssm:GetParameter",
                "ssm:GetParametersByPath"
            ],
            "Resource": [
                "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/myapp/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET}/configs/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:CreateLogGroup"
            ],
            "Resource": [
                "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/ecs/${TASK_FAMILY}*"
            ]
        }
    ]
}
EOF

    # Create and attach custom policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if policy exists
    if ! aws iam get-policy --policy-arn "${policy_arn}" &>/dev/null; then
        aws iam create-policy \
            --policy-name "${POLICY_NAME}" \
            --policy-document "file://${TEMP_DIR}/iam/parameter-store-policy.json" \
            --description "Parameter Store and S3 access for ${DEPLOYMENT_NAME}" \
            --tags Key=Project,Value="${DEPLOYMENT_NAME}" \
                   Key=Environment,Value="${ENVIRONMENT}" \
                   Key=ManagedBy,Value="ecs-envvar-deploy-script" \
            --output text &>> "${LOG_FILE}"
        
        log_info "Created custom IAM policy"
    else
        log_warning "Custom IAM policy already exists, skipping creation"
    fi
    
    # Attach custom policy to role
    aws iam attach-role-policy \
        --role-name "${EXEC_ROLE_NAME}" \
        --policy-arn "${policy_arn}" \
        --output text &>> "${LOG_FILE}" 2>&1 || true
    
    log_success "IAM roles and policies configured successfully"
}

create_task_definitions() {
    log_info "Creating ECS task definitions..."
    
    mkdir -p "${TEMP_DIR}/task-definitions"
    
    # Get the execution role ARN
    local exec_role_arn=$(aws iam get-role --role-name "${EXEC_ROLE_NAME}" --query 'Role.Arn' --output text)
    
    # Create primary task definition with multiple environment variable sources
    cat > "${TEMP_DIR}/task-definitions/primary-task.json" << EOF
{
    "family": "${TASK_FAMILY}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${exec_role_arn}",
    "tags": [
        {
            "key": "Project",
            "value": "${DEPLOYMENT_NAME}"
        },
        {
            "key": "Environment",
            "value": "${ENVIRONMENT}"
        },
        {
            "key": "ManagedBy",
            "value": "ecs-envvar-deploy-script"
        }
    ],
    "containerDefinitions": [
        {
            "name": "app-container",
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
                    "name": "NODE_ENV",
                    "value": "${ENVIRONMENT}"
                },
                {
                    "name": "SERVICE_NAME",
                    "value": "${SERVICE_NAME}"
                },
                {
                    "name": "CLUSTER_NAME",
                    "value": "${CLUSTER_NAME}"
                }
            ],
            "secrets": [
                {
                    "name": "DATABASE_HOST",
                    "valueFrom": "/myapp/${ENVIRONMENT}/database/host"
                },
                {
                    "name": "DATABASE_PORT",
                    "valueFrom": "/myapp/${ENVIRONMENT}/database/port"
                },
                {
                    "name": "DATABASE_PASSWORD",
                    "valueFrom": "/myapp/${ENVIRONMENT}/database/password"
                },
                {
                    "name": "API_SECRET_KEY",
                    "valueFrom": "/myapp/${ENVIRONMENT}/api/secret-key"
                },
                {
                    "name": "API_DEBUG",
                    "valueFrom": "/myapp/${ENVIRONMENT}/api/debug"
                },
                {
                    "name": "SHARED_REGION",
                    "valueFrom": "/myapp/shared/region"
                },
                {
                    "name": "SHARED_ACCOUNT_ID",
                    "valueFrom": "/myapp/shared/account-id"
                }
            ],
            "environmentFiles": [
                {
                    "value": "arn:aws:s3:::${S3_BUCKET}/configs/app-config.env",
                    "type": "s3"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/${TASK_FAMILY}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs",
                    "awslogs-create-group": "true"
                }
            }
        }
    ]
}
EOF

    # Create environment files focused task definition
    cat > "${TEMP_DIR}/task-definitions/envfiles-task.json" << EOF
{
    "family": "${TASK_FAMILY}-envfiles",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${exec_role_arn}",
    "tags": [
        {
            "key": "Project",
            "value": "${DEPLOYMENT_NAME}"
        },
        {
            "key": "Environment",
            "value": "${ENVIRONMENT}"
        },
        {
            "key": "ManagedBy",
            "value": "ecs-envvar-deploy-script"
        }
    ],
    "containerDefinitions": [
        {
            "name": "app-container",
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
                    "name": "DEPLOYMENT_TYPE",
                    "value": "environment-files"
                },
                {
                    "name": "DEPLOYMENT_NAME",
                    "value": "${DEPLOYMENT_NAME}"
                }
            ],
            "environmentFiles": [
                {
                    "value": "arn:aws:s3:::${S3_BUCKET}/configs/app-config.env",
                    "type": "s3"
                },
                {
                    "value": "arn:aws:s3:::${S3_BUCKET}/configs/prod-config.env",
                    "type": "s3"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/${TASK_FAMILY}-envfiles",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs",
                    "awslogs-create-group": "true"
                }
            }
        }
    ]
}
EOF

    # Register task definitions
    aws ecs register-task-definition \
        --cli-input-json "file://${TEMP_DIR}/task-definitions/primary-task.json" \
        --output text &>> "${LOG_FILE}"
    
    aws ecs register-task-definition \
        --cli-input-json "file://${TEMP_DIR}/task-definitions/envfiles-task.json" \
        --output text &>> "${LOG_FILE}"
    
    log_success "ECS task definitions registered successfully"
}

create_ecs_service() {
    log_info "Creating ECS service..."
    
    # Get network configuration
    local default_vpc=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    local default_subnet=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${default_vpc}" \
        --query 'Subnets[0].SubnetId' --output text)
    
    local default_sg=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${default_vpc}" "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Check if service already exists
    if aws ecs describe-services --cluster "${CLUSTER_NAME}" --services "${SERVICE_NAME}" --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        log_warning "ECS service ${SERVICE_NAME} already exists and is active, skipping creation"
        return 0
    fi
    
    # Create the service
    aws ecs create-service \
        --cluster "${CLUSTER_NAME}" \
        --service-name "${SERVICE_NAME}" \
        --task-definition "${TASK_FAMILY}" \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${default_subnet}],securityGroups=[${default_sg}],assignPublicIp=ENABLED}" \
        --tags key=Project,value="${DEPLOYMENT_NAME}" \
              key=Environment,value="${ENVIRONMENT}" \
              key=ManagedBy,value="ecs-envvar-deploy-script" \
        --output text &>> "${LOG_FILE}"
    
    # Wait for service to stabilize
    log_info "Waiting for ECS service to stabilize..."
    
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local running_count=$(aws ecs describe-services \
            --cluster "${CLUSTER_NAME}" \
            --services "${SERVICE_NAME}" \
            --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
        
        if [[ "${running_count}" == "1" ]]; then
            log_success "ECS service is running successfully"
            return 0
        fi
        
        log_info "Waiting for service to start tasks (attempt ${attempt}/${max_attempts})..."
        sleep 15
        ((attempt++))
    done
    
    log_warning "Service created but tasks may still be starting. Check ECS console for status."
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check ECS cluster
    if ! check_resource_exists "cluster" "${CLUSTER_NAME}"; then
        log_error "ECS cluster validation failed"
        ((validation_errors++))
    else
        log_success "ECS cluster validation passed"
    fi
    
    # Check S3 bucket
    if ! check_resource_exists "bucket" "${S3_BUCKET}"; then
        log_error "S3 bucket validation failed"
        ((validation_errors++))
    else
        log_success "S3 bucket validation passed"
    fi
    
    # Check IAM role
    if ! check_resource_exists "role" "${EXEC_ROLE_NAME}"; then
        log_error "IAM role validation failed"
        ((validation_errors++))
    else
        log_success "IAM role validation passed"
    fi
    
    # Check Parameters
    local param_count=$(aws ssm get-parameters-by-path \
        --path "/myapp" \
        --recursive \
        --query 'length(Parameters)' --output text 2>/dev/null || echo "0")
    
    if [[ "${param_count}" -lt 5 ]]; then
        log_error "Systems Manager parameters validation failed (found ${param_count}, expected at least 5)"
        ((validation_errors++))
    else
        log_success "Systems Manager parameters validation passed (${param_count} parameters found)"
    fi
    
    # Check ECS service
    local service_status=$(aws ecs describe-services \
        --cluster "${CLUSTER_NAME}" \
        --services "${SERVICE_NAME}" \
        --query 'services[0].status' --output text 2>/dev/null || echo "")
    
    if [[ "${service_status}" != "ACTIVE" ]]; then
        log_warning "ECS service validation warning (status: ${service_status})"
    else
        log_success "ECS service validation passed"
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All validation checks passed"
        return 0
    else
        log_error "Validation failed with ${validation_errors} errors"
        return 1
    fi
}

display_deployment_info() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "======================================================================"
    echo "                    DEPLOYMENT INFORMATION"
    echo "======================================================================"
    echo ""
    echo "AWS Region:           ${AWS_REGION}"
    echo "AWS Account ID:       ${AWS_ACCOUNT_ID}"
    echo "Deployment Name:      ${DEPLOYMENT_NAME}"
    echo "Environment:          ${ENVIRONMENT}"
    echo ""
    echo "ECS Resources:"
    echo "  Cluster Name:       ${CLUSTER_NAME}"
    echo "  Service Name:       ${SERVICE_NAME}"
    echo "  Task Family:        ${TASK_FAMILY}"
    echo ""
    echo "Configuration Resources:"
    echo "  S3 Bucket:          ${S3_BUCKET}"
    echo "  IAM Execution Role: ${EXEC_ROLE_NAME}"
    echo "  Parameter Prefix:   /myapp/${ENVIRONMENT}/"
    echo ""
    echo "Useful Commands:"
    echo "  View service:       aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}"
    echo "  View parameters:    aws ssm get-parameters-by-path --path /myapp --recursive"
    echo "  View logs:          aws logs describe-log-groups --log-group-name-prefix /ecs/${TASK_FAMILY}"
    echo ""
    echo "Next Steps:"
    echo "  1. Monitor the ECS service in the AWS Console"
    echo "  2. Check CloudWatch Logs for container output"
    echo "  3. Test environment variable configuration by examining task logs"
    echo "  4. Experiment with parameter updates and service redeployment"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "======================================================================"
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    log_info "Starting ECS Environment Variable Management deployment..."
    log_info "Deployment Name: ${DEPLOYMENT_NAME}"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "AWS Region: ${AWS_REGION}"
    echo ""
    
    # Initialize
    mkdir -p "${TEMP_DIR}"
    
    # Prerequisites
    check_prerequisites
    set_environment_variables
    
    # Infrastructure deployment
    create_ecs_cluster
    create_s3_bucket
    create_ssm_parameters
    create_environment_files
    create_iam_roles
    
    # Wait for IAM propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    # ECS resources
    create_task_definitions
    create_ecs_service
    
    # Validation
    validate_deployment
    
    # Display results
    display_deployment_info
    
    # Cleanup temporary files
    rm -rf "${TEMP_DIR}"
    
    log_success "Deployment completed successfully!"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment-name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --deployment-name NAME    Set deployment name (default: ecs-envvar-demo)"
            echo "  --environment ENV         Set environment (default: dev)"
            echo "  --region REGION          Set AWS region (default: from AWS CLI config)"
            echo "  --help                   Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  DEBUG=true               Enable debug output"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"