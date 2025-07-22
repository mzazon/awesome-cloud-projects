#!/bin/bash

# Destroy Script for Containerized Web Applications with App Runner and RDS
# This script removes all infrastructure and resources created by the deployment

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

# Error handling (but don't exit on errors for cleanup)
error_continue() {
    log_error "$1"
    log_warning "Continuing cleanup of other resources..."
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [ -f "deployment-info.json" ]; then
        if command -v jq &> /dev/null; then
            export DEPLOYMENT_ID=$(jq -r '.deployment_id' deployment-info.json)
            export AWS_REGION=$(jq -r '.aws_region' deployment-info.json)
            export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-info.json)
            export SERVICE_ARN=$(jq -r '.service_arn' deployment-info.json)
            export SERVICE_URL=$(jq -r '.service_url' deployment-info.json | sed 's|https://||')
            export DB_ENDPOINT=$(jq -r '.database_endpoint' deployment-info.json)
            export DB_NAME=$(jq -r '.database_name' deployment-info.json)
            export SECRET_NAME=$(jq -r '.secret_name' deployment-info.json)
            export SECRET_ARN=$(jq -r '.secret_arn' deployment-info.json)
            export ECR_REPO=$(jq -r '.ecr_repository' deployment-info.json | cut -d'/' -f2)
            export VPC_ID=$(jq -r '.vpc_id' deployment-info.json)
            export SUBNET1_ID=$(jq -r '.subnet_ids[0]' deployment-info.json)
            export SUBNET2_ID=$(jq -r '.subnet_ids[1]' deployment-info.json)
            export SG_ID=$(jq -r '.security_group_id' deployment-info.json)
            export SERVICE_ROLE_ARN=$(jq -r '.service_role_arn' deployment-info.json)
            export INSTANCE_ROLE_ARN=$(jq -r '.instance_role_arn' deployment-info.json)
            
            # Extract role names from ARNs
            export SERVICE_ROLE_NAME=$(echo $SERVICE_ROLE_ARN | cut -d'/' -f2)
            export INSTANCE_ROLE_NAME=$(echo $INSTANCE_ROLE_ARN | cut -d'/' -f2)
            
            log_success "Loaded deployment information from deployment-info.json"
        else
            log_error "jq is not installed. Cannot parse deployment-info.json automatically."
            log "Please install jq or provide resource identifiers manually."
            exit 1
        fi
    else
        log_warning "deployment-info.json not found. Attempting to discover resources..."
        discover_resources
    fi
    
    log "Deployment ID: $DEPLOYMENT_ID"
    log "AWS Region: $AWS_REGION"
}

# Discover resources if deployment-info.json is not available
discover_resources() {
    log "Attempting to discover resources..."
    
    # Get AWS region and account
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find resources by tags or naming patterns
    log "Searching for App Runner services with webapp pattern..."
    SERVICES=$(aws apprunner list-services --query 'ServiceSummaryList[?contains(ServiceName, `webapp`)].ServiceName' --output text 2>/dev/null || echo "")
    
    if [ -n "$SERVICES" ]; then
        log_warning "Found potential App Runner services: $SERVICES"
        log_warning "Please specify which deployment to destroy or provide deployment-info.json"
    else
        log_warning "No App Runner services found with webapp pattern"
    fi
    
    # Set generic pattern for manual cleanup
    export DEPLOYMENT_ID="manual"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "========================================================================"
    log_warning "WARNING: This will permanently destroy the following resources:"
    log_warning "========================================================================"
    
    if [ -f "deployment-info.json" ]; then
        log_warning "  📱 App Runner Service: ${SERVICE_URL}"
        log_warning "  🗄️  RDS Database: ${DB_NAME}"
        log_warning "  🔒 Secrets Manager Secret: ${SECRET_NAME}"
        log_warning "  📦 ECR Repository: ${ECR_REPO}"
        log_warning "  🌐 VPC and networking components"
        log_warning "  📊 CloudWatch alarms and log groups"
        log_warning "  🔑 IAM roles and policies"
    else
        log_warning "  ❓ Resources will be discovered and destroyed based on naming patterns"
        log_warning "  ⚠️  This may affect resources not created by this deployment"
    fi
    
    log_warning "========================================================================"
    
    # Skip confirmation if --yes flag is provided
    if [[ "$1" != "--yes" && "$1" != "-y" ]]; then
        echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
        read -r confirmation
        
        if [ "$confirmation" != "yes" ]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Delete App Runner service
delete_apprunner_service() {
    log "Deleting App Runner service..."
    
    if [ -n "$SERVICE_ARN" ]; then
        # Delete the specific service
        aws apprunner delete-service --service-arn ${SERVICE_ARN} > /dev/null 2>&1 || error_continue "Failed to delete App Runner service ${SERVICE_ARN}"
        
        if [ $? -eq 0 ]; then
            log "Waiting for App Runner service to be deleted..."
            aws apprunner wait service-deleted --service-arn ${SERVICE_ARN} 2>/dev/null || log_warning "Timeout waiting for service deletion"
            log_success "App Runner service deleted"
        fi
    else
        # Try to find and delete services by pattern
        log "Searching for App Runner services to delete..."
        SERVICES=$(aws apprunner list-services --query "ServiceSummaryList[?contains(ServiceName, 'webapp-${DEPLOYMENT_ID}')].ServiceArn" --output text 2>/dev/null || echo "")
        
        if [ -n "$SERVICES" ]; then
            for service_arn in $SERVICES; do
                log "Deleting App Runner service: $service_arn"
                aws apprunner delete-service --service-arn "$service_arn" > /dev/null 2>&1 || error_continue "Failed to delete App Runner service $service_arn"
                aws apprunner wait service-deleted --service-arn "$service_arn" 2>/dev/null || log_warning "Timeout waiting for service deletion"
            done
            log_success "App Runner services deleted"
        else
            log_warning "No App Runner services found to delete"
        fi
    fi
}

# Delete RDS database
delete_rds_database() {
    log "Deleting RDS database..."
    
    if [ -n "$DB_NAME" ]; then
        # Delete specific database
        aws rds delete-db-instance \
            --db-instance-identifier ${DB_NAME} \
            --skip-final-snapshot \
            --delete-automated-backups > /dev/null 2>&1 || error_continue "Failed to delete RDS instance ${DB_NAME}"
        
        if [ $? -eq 0 ]; then
            log "Waiting for RDS instance to be deleted..."
            aws rds wait db-instance-deleted --db-instance-identifier ${DB_NAME} 2>/dev/null || log_warning "Timeout waiting for database deletion"
            log_success "RDS database instance deleted"
        fi
        
        # Delete DB subnet group
        aws rds delete-db-subnet-group \
            --db-subnet-group-name webapp-subnet-group-${DEPLOYMENT_ID} > /dev/null 2>&1 || error_continue "Failed to delete DB subnet group"
        
        if [ $? -eq 0 ]; then
            log_success "DB subnet group deleted"
        fi
    else
        # Try to find and delete databases by pattern
        log "Searching for RDS databases to delete..."
        DATABASES=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'webapp-db-')].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
        
        if [ -n "$DATABASES" ]; then
            for db_name in $DATABASES; do
                log "Deleting RDS database: $db_name"
                aws rds delete-db-instance \
                    --db-instance-identifier "$db_name" \
                    --skip-final-snapshot \
                    --delete-automated-backups > /dev/null 2>&1 || error_continue "Failed to delete RDS instance $db_name"
                aws rds wait db-instance-deleted --db-instance-identifier "$db_name" 2>/dev/null || log_warning "Timeout waiting for database deletion"
            done
            log_success "RDS databases deleted"
        else
            log_warning "No RDS databases found to delete"
        fi
    fi
}

# Delete Secrets Manager secrets
delete_secrets() {
    log "Deleting Secrets Manager secrets..."
    
    if [ -n "$SECRET_NAME" ]; then
        # Delete specific secret
        aws secretsmanager delete-secret \
            --secret-id ${SECRET_NAME} \
            --force-delete-without-recovery > /dev/null 2>&1 || error_continue "Failed to delete secret ${SECRET_NAME}"
        
        if [ $? -eq 0 ]; then
            log_success "Secret deleted: ${SECRET_NAME}"
        fi
    else
        # Try to find and delete secrets by pattern
        log "Searching for secrets to delete..."
        SECRETS=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'webapp-db-credentials-')].Name" --output text 2>/dev/null || echo "")
        
        if [ -n "$SECRETS" ]; then
            for secret_name in $SECRETS; do
                log "Deleting secret: $secret_name"
                aws secretsmanager delete-secret \
                    --secret-id "$secret_name" \
                    --force-delete-without-recovery > /dev/null 2>&1 || error_continue "Failed to delete secret $secret_name"
            done
            log_success "Secrets deleted"
        else
            log_warning "No secrets found to delete"
        fi
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    if [ -n "$SERVICE_ROLE_NAME" ] && [ -n "$INSTANCE_ROLE_NAME" ]; then
        # Delete specific roles
        # Detach policies from service role
        aws iam detach-role-policy \
            --role-name ${SERVICE_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess > /dev/null 2>&1 || error_continue "Failed to detach service policy"
        
        # Detach policies from instance role
        aws iam detach-role-policy \
            --role-name ${INSTANCE_ROLE_NAME} \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerAccess-${DEPLOYMENT_ID} > /dev/null 2>&1 || error_continue "Failed to detach secrets policy"
        
        # Delete custom policy
        aws iam delete-policy \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerAccess-${DEPLOYMENT_ID} > /dev/null 2>&1 || error_continue "Failed to delete custom policy"
        
        # Delete roles
        aws iam delete-role --role-name ${SERVICE_ROLE_NAME} > /dev/null 2>&1 || error_continue "Failed to delete service role"
        aws iam delete-role --role-name ${INSTANCE_ROLE_NAME} > /dev/null 2>&1 || error_continue "Failed to delete instance role"
        
        log_success "IAM resources deleted"
    else
        # Try to find and delete roles by pattern
        log "Searching for IAM roles to delete..."
        SERVICE_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'AppRunnerServiceRole-')].RoleName" --output text 2>/dev/null || echo "")
        INSTANCE_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'AppRunnerInstanceRole-')].RoleName" --output text 2>/dev/null || echo "")
        
        # Delete service roles
        if [ -n "$SERVICE_ROLES" ]; then
            for role_name in $SERVICE_ROLES; do
                log "Deleting service role: $role_name"
                aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess > /dev/null 2>&1
                aws iam delete-role --role-name "$role_name" > /dev/null 2>&1 || error_continue "Failed to delete role $role_name"
            done
        fi
        
        # Delete instance roles
        if [ -n "$INSTANCE_ROLES" ]; then
            for role_name in $INSTANCE_ROLES; do
                log "Deleting instance role: $role_name"
                # Try to find and detach associated policies
                POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[?contains(PolicyArn, `SecretsManagerAccess`)].PolicyArn' --output text 2>/dev/null || echo "")
                for policy_arn in $POLICIES; do
                    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" > /dev/null 2>&1
                    aws iam delete-policy --policy-arn "$policy_arn" > /dev/null 2>&1
                done
                aws iam delete-role --role-name "$role_name" > /dev/null 2>&1 || error_continue "Failed to delete role $role_name"
            done
        fi
        
        if [ -n "$SERVICE_ROLES" ] || [ -n "$INSTANCE_ROLES" ]; then
            log_success "IAM resources deleted"
        else
            log_warning "No IAM roles found to delete"
        fi
    fi
}

# Delete ECR repository
delete_ecr_repository() {
    log "Deleting ECR repository..."
    
    if [ -n "$ECR_REPO" ]; then
        # Delete specific repository
        aws ecr delete-repository \
            --repository-name ${ECR_REPO} \
            --force > /dev/null 2>&1 || error_continue "Failed to delete ECR repository ${ECR_REPO}"
        
        if [ $? -eq 0 ]; then
            log_success "ECR repository deleted: ${ECR_REPO}"
        fi
    else
        # Try to find and delete repositories by pattern
        log "Searching for ECR repositories to delete..."
        REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'webapp-')].repositoryName" --output text 2>/dev/null || echo "")
        
        if [ -n "$REPOS" ]; then
            for repo_name in $REPOS; do
                log "Deleting ECR repository: $repo_name"
                aws ecr delete-repository \
                    --repository-name "$repo_name" \
                    --force > /dev/null 2>&1 || error_continue "Failed to delete ECR repository $repo_name"
            done
            log_success "ECR repositories deleted"
        else
            log_warning "No ECR repositories found to delete"
        fi
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch alarms and log groups..."
    
    if [ -n "$DEPLOYMENT_ID" ]; then
        # Delete specific CloudWatch alarms
        APP_NAME_PATTERN="webapp-${DEPLOYMENT_ID}"
        
        aws cloudwatch delete-alarms \
            --alarm-names "${APP_NAME_PATTERN}-high-cpu" "${APP_NAME_PATTERN}-high-memory" "${APP_NAME_PATTERN}-high-latency" > /dev/null 2>&1 || error_continue "Failed to delete CloudWatch alarms"
        
        # Delete log group
        aws logs delete-log-group \
            --log-group-name "/aws/apprunner/${APP_NAME_PATTERN}/application" > /dev/null 2>&1 || error_continue "Failed to delete log group"
        
        log_success "CloudWatch resources deleted"
    else
        # Try to find and delete alarms by pattern
        log "Searching for CloudWatch resources to delete..."
        ALARMS=$(aws cloudwatch describe-alarms --query "MetricAlarms[?contains(AlarmName, 'webapp-')].AlarmName" --output text 2>/dev/null || echo "")
        
        if [ -n "$ALARMS" ]; then
            aws cloudwatch delete-alarms --alarm-names $ALARMS > /dev/null 2>&1 || error_continue "Failed to delete CloudWatch alarms"
            log_success "CloudWatch alarms deleted"
        else
            log_warning "No CloudWatch alarms found to delete"
        fi
        
        # Delete log groups
        LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/aws/apprunner/webapp-')].logGroupName" --output text 2>/dev/null || echo "")
        
        if [ -n "$LOG_GROUPS" ]; then
            for log_group in $LOG_GROUPS; do
                aws logs delete-log-group --log-group-name "$log_group" > /dev/null 2>&1 || error_continue "Failed to delete log group $log_group"
            done
            log_success "CloudWatch log groups deleted"
        else
            log_warning "No log groups found to delete"
        fi
    fi
}

# Delete VPC and networking resources
delete_networking() {
    log "Deleting VPC and networking resources..."
    
    if [ -n "$VPC_ID" ] && [ -n "$SG_ID" ] && [ -n "$SUBNET1_ID" ] && [ -n "$SUBNET2_ID" ]; then
        # Delete specific networking resources
        # Delete security group
        aws ec2 delete-security-group --group-id ${SG_ID} > /dev/null 2>&1 || error_continue "Failed to delete security group ${SG_ID}"
        
        # Delete subnets
        aws ec2 delete-subnet --subnet-id ${SUBNET1_ID} > /dev/null 2>&1 || error_continue "Failed to delete subnet ${SUBNET1_ID}"
        aws ec2 delete-subnet --subnet-id ${SUBNET2_ID} > /dev/null 2>&1 || error_continue "Failed to delete subnet ${SUBNET2_ID}"
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id ${VPC_ID} > /dev/null 2>&1 || error_continue "Failed to delete VPC ${VPC_ID}"
        
        log_success "VPC and networking resources deleted"
    else
        # Try to find and delete VPCs by tag
        log "Searching for VPCs to delete..."
        VPCS=$(aws ec2 describe-vpcs --filters Name=tag:Project,Values=webapp-apprunner-rds --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
        
        if [ -n "$VPCS" ]; then
            for vpc_id in $VPCS; do
                log "Deleting VPC and associated resources: $vpc_id"
                
                # Delete security groups
                SGS=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$vpc_id Name=group-name,Values='webapp-rds-sg-*' --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
                for sg_id in $SGS; do
                    aws ec2 delete-security-group --group-id $sg_id > /dev/null 2>&1
                done
                
                # Delete subnets
                SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpc_id --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
                for subnet_id in $SUBNETS; do
                    aws ec2 delete-subnet --subnet-id $subnet_id > /dev/null 2>&1
                done
                
                # Delete VPC
                aws ec2 delete-vpc --vpc-id $vpc_id > /dev/null 2>&1
            done
            log_success "VPC resources deleted"
        else
            log_warning "No VPCs found to delete"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "deployment-info.json" ]; then
        rm -f deployment-info.json
        log_success "Removed deployment-info.json"
    fi
    
    # Remove any temporary files
    rm -f apprunner-*.json *.json.tmp
    
    log_success "Local cleanup completed"
}

# Main destruction function
main() {
    log "Starting destruction of Containerized Web Application infrastructure..."
    log "========================================================================"
    
    # Check if running with --help
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --yes, -y     Skip confirmation prompt"
        echo "  --dry-run     Show what would be destroyed without actually destroying"
        echo ""
        echo "This script destroys all resources created by the deployment script including:"
        echo "  - AWS App Runner service"
        echo "  - Amazon RDS database"
        echo "  - AWS Secrets Manager secrets"
        echo "  - Amazon ECR repository"
        echo "  - VPC and networking components"
        echo "  - CloudWatch alarms and log groups"
        echo "  - IAM roles and policies"
        echo ""
        echo "IMPORTANT: This action is irreversible!"
        echo ""
        exit 0
    fi
    
    # Check for dry-run
    if [[ "$1" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be destroyed"
        log "Would destroy the following types of resources:"
        log "  ❌ App Runner services matching pattern 'webapp-*'"
        log "  ❌ RDS databases matching pattern 'webapp-db-*'"
        log "  ❌ Secrets Manager secrets matching pattern 'webapp-db-credentials-*'"
        log "  ❌ ECR repositories matching pattern 'webapp-*'"
        log "  ❌ VPCs tagged with 'Project=webapp-apprunner-rds'"
        log "  ❌ CloudWatch alarms and log groups for webapp applications"
        log "  ❌ IAM roles matching patterns 'AppRunnerServiceRole-*' and 'AppRunnerInstanceRole-*'"
        exit 0
    fi
    
    # Execute destruction steps
    check_prerequisites
    load_deployment_info
    confirm_destruction "$1"
    
    # Delete resources in reverse order of creation
    delete_apprunner_service
    delete_cloudwatch_resources
    delete_rds_database
    delete_secrets
    delete_iam_resources
    delete_ecr_repository
    delete_networking
    cleanup_local_files
    
    log_success "========================================================================"
    log_success "Infrastructure destruction completed!"
    log_success "========================================================================"
    log ""
    log "🧹 Cleanup Summary:"
    log "   ✅ App Runner services removed"
    log "   ✅ RDS databases deleted"
    log "   ✅ Secrets Manager secrets deleted"
    log "   ✅ ECR repositories deleted"
    log "   ✅ VPC and networking resources deleted"
    log "   ✅ CloudWatch alarms and log groups deleted"
    log "   ✅ IAM roles and policies deleted"
    log "   ✅ Local files cleaned up"
    log ""
    log "💡 Note: It may take a few minutes for all AWS resources to be fully removed."
    log "         Check the AWS Console to verify complete deletion if needed."
    log ""
    log_success "All resources have been successfully destroyed!"
}

# Run main function with all arguments
main "$@"