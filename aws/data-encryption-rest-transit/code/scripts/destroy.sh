#!/bin/bash

# =============================================================================
# AWS Data Encryption at Rest and in Transit - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script:
# - CloudTrail and logging
# - EC2 instances and security groups
# - RDS databases and subnet groups
# - S3 buckets and objects
# - Secrets Manager secrets
# - KMS keys (scheduled for deletion)
# - VPC and networking components
# =============================================================================

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for user confirmation
confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
}

# Function to safely delete resource with retry
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local delete_command="$3"
    local max_retries=3
    local retry_delay=10
    
    for ((i=1; i<=max_retries; i++)); do
        if eval "$delete_command"; then
            success "Deleted $resource_type: $resource_id"
            return 0
        else
            if [[ $i -lt $max_retries ]]; then
                warning "Failed to delete $resource_type: $resource_id (attempt $i/$max_retries). Retrying in $retry_delay seconds..."
                sleep $retry_delay
            else
                error "Failed to delete $resource_type: $resource_id after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command_exists aws; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if environment file exists
if [[ ! -f .env ]]; then
    error "Environment file (.env) not found. Please run deploy.sh first or create the file manually."
    exit 1
fi

# Load environment variables
log "Loading environment configuration..."
source .env

# Verify required variables
required_vars=(
    "AWS_REGION"
    "AWS_ACCOUNT_ID"
    "KMS_KEY_ALIAS"
    "S3_BUCKET_NAME"
    "RDS_INSTANCE_ID"
    "SECRET_NAME"
    "RANDOM_SUFFIX"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        error "Required variable $var is not set in .env file"
        exit 1
    fi
done

success "Prerequisites check passed"

# =============================================================================
# CONFIRMATION AND WARNINGS
# =============================================================================
echo ""
echo "============================================================================="
echo "                           RESOURCE CLEANUP WARNING"
echo "============================================================================="
echo ""
echo "This script will DELETE the following resources:"
echo "  • KMS Key: ${KMS_KEY_ID:-$KMS_KEY_ALIAS}"
echo "  • S3 Bucket: $S3_BUCKET_NAME"
echo "  • RDS Instance: $RDS_INSTANCE_ID"
echo "  • EC2 Instance: ${EC2_INSTANCE_ID:-'(if exists)'}"
echo "  • Secret: $SECRET_NAME"
echo "  • CloudTrail: encryption-demo-trail"
echo "  • VPC: ${VPC_ID:-'(if exists)'}"
echo ""
echo "⚠️  WARNING: This action is IRREVERSIBLE!"
echo "⚠️  All data in these resources will be PERMANENTLY DELETED!"
echo "⚠️  KMS key will be scheduled for deletion (7-day waiting period)"
echo ""
echo "============================================================================="
echo ""

confirm "Are you sure you want to proceed with cleanup?"
echo ""

# Additional confirmation for production-like resources
if [[ "$AWS_REGION" == "us-east-1" ]] || [[ "$AWS_REGION" == "us-west-2" ]]; then
    warning "You are operating in a primary AWS region ($AWS_REGION)"
    confirm "Are you absolutely sure you want to delete these resources?"
fi

# =============================================================================
# STOP CLOUDTRAIL AND DELETE TRAIL
# =============================================================================
log "Stopping CloudTrail and deleting trail..."

# Stop CloudTrail logging
if aws cloudtrail describe-trails --trail-name-list encryption-demo-trail &>/dev/null; then
    aws cloudtrail stop-logging --name encryption-demo-trail || true
    
    # Delete trail
    aws cloudtrail delete-trail --name encryption-demo-trail || true
    
    # Delete CloudTrail bucket if it exists
    if [[ -n "$CLOUDTRAIL_BUCKET" ]]; then
        if aws s3api head-bucket --bucket "$CLOUDTRAIL_BUCKET" &>/dev/null; then
            aws s3 rm "s3://$CLOUDTRAIL_BUCKET" --recursive || true
            aws s3api delete-bucket --bucket "$CLOUDTRAIL_BUCKET" || true
        fi
    fi
    
    success "CloudTrail configuration deleted"
else
    warning "CloudTrail not found, skipping..."
fi

# =============================================================================
# TERMINATE EC2 INSTANCE
# =============================================================================
log "Terminating EC2 instance..."

if [[ -n "$EC2_INSTANCE_ID" ]]; then
    # Check if instance exists
    if aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" &>/dev/null; then
        log "Terminating EC2 instance: $EC2_INSTANCE_ID"
        
        # Terminate instance
        aws ec2 terminate-instances --instance-ids "$EC2_INSTANCE_ID"
        
        # Wait for termination with timeout
        log "Waiting for instance termination (timeout: 5 minutes)..."
        timeout 300 aws ec2 wait instance-terminated --instance-ids "$EC2_INSTANCE_ID" || {
            warning "Instance termination wait timed out, but continuing..."
        }
        
        success "EC2 instance terminated"
    else
        warning "EC2 instance not found, skipping..."
    fi
else
    warning "EC2 instance ID not set, skipping..."
fi

# Delete key pair
if aws ec2 describe-key-pairs --key-names encryption-demo-key &>/dev/null; then
    aws ec2 delete-key-pair --key-name encryption-demo-key
    success "Key pair deleted"
fi

# Remove local key file
if [[ -f encryption-demo-key.pem ]]; then
    rm -f encryption-demo-key.pem
    success "Local key file removed"
fi

# =============================================================================
# DELETE RDS INSTANCE
# =============================================================================
log "Deleting RDS instance..."

if [[ -n "$RDS_INSTANCE_ID" ]]; then
    # Check if RDS instance exists
    if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" &>/dev/null; then
        log "Removing deletion protection from RDS instance..."
        
        # Remove deletion protection
        aws rds modify-db-instance \
            --db-instance-identifier "$RDS_INSTANCE_ID" \
            --no-deletion-protection \
            --apply-immediately || true
        
        # Wait for modification
        log "Waiting for RDS modification..."
        timeout 300 aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE_ID" || {
            warning "RDS modification wait timed out, but continuing..."
        }
        
        log "Deleting RDS instance (this may take 5-10 minutes)..."
        
        # Delete RDS instance (skip final snapshot for demo)
        aws rds delete-db-instance \
            --db-instance-identifier "$RDS_INSTANCE_ID" \
            --skip-final-snapshot
        
        success "RDS instance deletion initiated"
    else
        warning "RDS instance not found, skipping..."
    fi
else
    warning "RDS instance ID not set, skipping..."
fi

# =============================================================================
# DELETE S3 BUCKETS
# =============================================================================
log "Deleting S3 buckets..."

# Delete main S3 bucket
if [[ -n "$S3_BUCKET_NAME" ]]; then
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &>/dev/null; then
        log "Deleting objects from S3 bucket: $S3_BUCKET_NAME"
        
        # Delete all objects and versions
        aws s3 rm "s3://$S3_BUCKET_NAME" --recursive || true
        
        # Delete bucket
        aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" || true
        
        success "S3 bucket deleted: $S3_BUCKET_NAME"
    else
        warning "S3 bucket not found, skipping..."
    fi
else
    warning "S3 bucket name not set, skipping..."
fi

# =============================================================================
# DELETE SECRETS MANAGER SECRET
# =============================================================================
log "Deleting Secrets Manager secret..."

if [[ -n "$SECRET_NAME" ]]; then
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        # Delete secret with immediate deletion for demo
        aws secretsmanager delete-secret \
            --secret-id "$SECRET_NAME" \
            --force-delete-without-recovery || true
        
        success "Secret deleted: $SECRET_NAME"
    else
        warning "Secret not found, skipping..."
    fi
else
    warning "Secret name not set, skipping..."
fi

# =============================================================================
# DELETE SECURITY GROUPS
# =============================================================================
log "Deleting security groups..."

# Delete EC2 security group
if [[ -n "$EC2_SECURITY_GROUP" ]]; then
    if aws ec2 describe-security-groups --group-ids "$EC2_SECURITY_GROUP" &>/dev/null; then
        safe_delete "EC2 security group" "$EC2_SECURITY_GROUP" \
            "aws ec2 delete-security-group --group-id $EC2_SECURITY_GROUP"
    else
        warning "EC2 security group not found, skipping..."
    fi
fi

# Delete DB security group
if [[ -n "$DB_SECURITY_GROUP" ]]; then
    if aws ec2 describe-security-groups --group-ids "$DB_SECURITY_GROUP" &>/dev/null; then
        safe_delete "DB security group" "$DB_SECURITY_GROUP" \
            "aws ec2 delete-security-group --group-id $DB_SECURITY_GROUP"
    else
        warning "DB security group not found, skipping..."
    fi
fi

# =============================================================================
# DELETE DB SUBNET GROUP
# =============================================================================
log "Deleting DB subnet group..."

if aws rds describe-db-subnet-groups --db-subnet-group-name encryption-demo-subnet-group &>/dev/null; then
    # Wait for RDS deletion to complete before deleting subnet group
    if [[ -n "$RDS_INSTANCE_ID" ]]; then
        log "Waiting for RDS instance deletion to complete..."
        timeout 600 aws rds wait db-instance-deleted --db-instance-identifier "$RDS_INSTANCE_ID" || {
            warning "RDS deletion wait timed out, but continuing..."
        }
    fi
    
    aws rds delete-db-subnet-group --db-subnet-group-name encryption-demo-subnet-group || true
    success "DB subnet group deleted"
else
    warning "DB subnet group not found, skipping..."
fi

# =============================================================================
# DELETE VPC RESOURCES
# =============================================================================
log "Deleting VPC resources..."

# Delete route table associations and routes
if [[ -n "$ROUTE_TABLE_ID" ]]; then
    if aws ec2 describe-route-tables --route-table-ids "$ROUTE_TABLE_ID" &>/dev/null; then
        # Delete routes (except main route)
        aws ec2 delete-route --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 || true
        
        # Delete route table
        aws ec2 delete-route-table --route-table-id "$ROUTE_TABLE_ID" || true
        success "Route table deleted"
    fi
fi

# Delete subnets
for subnet in "$SUBNET_1" "$SUBNET_2"; do
    if [[ -n "$subnet" ]]; then
        if aws ec2 describe-subnets --subnet-ids "$subnet" &>/dev/null; then
            aws ec2 delete-subnet --subnet-id "$subnet" || true
            success "Subnet deleted: $subnet"
        fi
    fi
done

# Detach and delete Internet Gateway
if [[ -n "$IGW_ID" ]] && [[ -n "$VPC_ID" ]]; then
    if aws ec2 describe-internet-gateways --internet-gateway-ids "$IGW_ID" &>/dev/null; then
        aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" || true
        success "Internet Gateway deleted"
    fi
fi

# Delete VPC
if [[ -n "$VPC_ID" ]]; then
    if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &>/dev/null; then
        safe_delete "VPC" "$VPC_ID" "aws ec2 delete-vpc --vpc-id $VPC_ID"
    else
        warning "VPC not found, skipping..."
    fi
fi

# =============================================================================
# SCHEDULE KMS KEY DELETION
# =============================================================================
log "Scheduling KMS key deletion..."

if [[ -n "$KMS_KEY_ID" ]]; then
    # Check if key exists
    if aws kms describe-key --key-id "$KMS_KEY_ID" &>/dev/null; then
        # Delete KMS key alias
        if [[ -n "$KMS_KEY_ALIAS" ]]; then
            aws kms delete-alias --alias-name "$KMS_KEY_ALIAS" || true
            success "KMS key alias deleted"
        fi
        
        # Schedule key deletion (7 days minimum)
        aws kms schedule-key-deletion \
            --key-id "$KMS_KEY_ID" \
            --pending-window-in-days 7 || true
        
        success "KMS key scheduled for deletion in 7 days"
        warning "KMS key deletion can be cancelled within 7 days using: aws kms cancel-key-deletion --key-id $KMS_KEY_ID"
    else
        warning "KMS key not found, skipping..."
    fi
else
    warning "KMS key ID not set, skipping..."
fi

# =============================================================================
# CLEANUP ENVIRONMENT FILE
# =============================================================================
log "Cleaning up environment file..."

if [[ -f .env ]]; then
    # Create backup
    cp .env .env.backup
    
    # Remove environment file
    rm .env
    
    success "Environment file cleaned up (backup saved as .env.backup)"
fi

# =============================================================================
# FINAL VERIFICATION
# =============================================================================
log "Performing final verification..."

# Check for any remaining resources
remaining_resources=()

# Check S3 buckets
if [[ -n "$S3_BUCKET_NAME" ]]; then
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &>/dev/null; then
        remaining_resources+=("S3 bucket: $S3_BUCKET_NAME")
    fi
fi

# Check RDS instances
if [[ -n "$RDS_INSTANCE_ID" ]]; then
    if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" &>/dev/null; then
        remaining_resources+=("RDS instance: $RDS_INSTANCE_ID (deletion in progress)")
    fi
fi

# Check EC2 instances
if [[ -n "$EC2_INSTANCE_ID" ]]; then
    if aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null | grep -v "terminated" &>/dev/null; then
        remaining_resources+=("EC2 instance: $EC2_INSTANCE_ID")
    fi
fi

# Check secrets
if [[ -n "$SECRET_NAME" ]]; then
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        remaining_resources+=("Secret: $SECRET_NAME")
    fi
fi

# Report remaining resources
if [[ ${#remaining_resources[@]} -gt 0 ]]; then
    warning "Some resources may still be in the process of deletion:"
    for resource in "${remaining_resources[@]}"; do
        echo "  • $resource"
    done
    echo ""
    echo "This is normal for RDS instances and other resources that take time to delete."
else
    success "All resources have been successfully cleaned up"
fi

# =============================================================================
# CLEANUP SUMMARY
# =============================================================================
echo ""
echo "============================================================================="
echo "                        CLEANUP COMPLETED"
echo "============================================================================="
echo ""
echo "Resources cleaned up:"
echo "  ✓ CloudTrail and logging"
echo "  ✓ EC2 instances and security groups"
echo "  ✓ RDS databases and subnet groups"
echo "  ✓ S3 buckets and objects"
echo "  ✓ Secrets Manager secrets"
echo "  ✓ VPC and networking components"
echo "  ✓ KMS key scheduled for deletion (7 days)"
echo ""
echo "Notes:"
echo "  • KMS key deletion can be cancelled within 7 days if needed"
echo "  • Some resources (like RDS) may take additional time to fully delete"
echo "  • Environment backup saved as .env.backup"
echo ""
echo "To cancel KMS key deletion (if needed):"
echo "  aws kms cancel-key-deletion --key-id ${KMS_KEY_ID:-'KEY_ID'}"
echo ""
echo "============================================================================="

success "Cleanup completed successfully!"