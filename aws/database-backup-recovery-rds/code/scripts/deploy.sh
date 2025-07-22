#!/bin/bash

# AWS Database Backup and Point-in-Time Recovery Strategies - Deployment Script
# This script deploys the complete infrastructure for database backup and recovery

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=${DRY_RUN:-false}
SKIP_CLEANUP=${SKIP_CLEANUP:-false}

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        *)       echo -e "${timestamp} - $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup function
cleanup() {
    if [[ "$SKIP_CLEANUP" == "true" ]]; then
        log "INFO" "Skipping cleanup as requested"
        return 0
    fi
    
    log "INFO" "Cleaning up temporary files..."
    rm -f backup-plan.json backup-selection.json vault-access-policy.json backup-trust-policy.json
    log "INFO" "Cleanup completed"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    log "INFO" "Checking AWS permissions..."
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log "INFO" "Authenticated as: $identity"
    
    # Test basic permissions
    if ! aws ec2 describe-regions --region us-east-1 &> /dev/null; then
        error_exit "Insufficient permissions to access AWS services"
    fi
    
    # Check if jq is available (optional but helpful)
    if command -v jq &> /dev/null; then
        log "INFO" "jq is available for JSON parsing"
    else
        log "WARN" "jq not found. Some output formatting may be limited."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Environment setup
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log "WARN" "No region configured, using default: $AWS_REGION"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export DB_INSTANCE_ID="production-db-${random_suffix}"
    export BACKUP_VAULT_NAME="rds-backup-vault-${random_suffix}"
    export BACKUP_ROLE_NAME="rds-backup-role-${random_suffix}"
    export KMS_KEY_ALIAS="alias/rds-backup-key-${random_suffix}"
    export DR_REGION="us-west-2"
    
    # Check VPC
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$VPC_ID" == "None" ]] || [[ -z "$VPC_ID" ]]; then
        error_exit "No default VPC found. Please create a VPC first."
    fi
    
    export SUBNET_GROUP_NAME="default"
    
    log "INFO" "Environment setup completed"
    log "INFO" "Database Instance ID: $DB_INSTANCE_ID"
    log "INFO" "Backup Vault Name: $BACKUP_VAULT_NAME"
    log "INFO" "Using VPC: $VPC_ID"
}

# Deploy KMS key
deploy_kms() {
    log "INFO" "Creating KMS encryption key..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create KMS key for backup encryption"
        return 0
    fi
    
    # Create KMS key
    KMS_KEY_ID=$(aws kms create-key \
        --description "RDS backup encryption key" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    
    if [[ -z "$KMS_KEY_ID" ]]; then
        error_exit "Failed to create KMS key"
    fi
    
    # Create alias for the key
    aws kms create-alias \
        --alias-name "$KMS_KEY_ALIAS" \
        --target-key-id "$KMS_KEY_ID"
    
    log "INFO" "KMS key created successfully: $KMS_KEY_ID"
    log "INFO" "KMS key alias: $KMS_KEY_ALIAS"
    
    # Export for use in other functions
    export KMS_KEY_ID
}

# Deploy IAM role
deploy_iam_role() {
    log "INFO" "Creating IAM role for AWS Backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create IAM role for backup operations"
        return 0
    fi
    
    # Create trust policy
    cat > backup-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "backup.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$BACKUP_ROLE_NAME" \
        --assume-role-policy-document file://backup-trust-policy.json \
        --description "IAM role for AWS Backup service operations"
    
    # Attach AWS managed backup policy
    aws iam attach-role-policy \
        --role-name "$BACKUP_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
    
    # Attach restore policy
    aws iam attach-role-policy \
        --role-name "$BACKUP_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
    
    export BACKUP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${BACKUP_ROLE_NAME}"
    
    log "INFO" "IAM role created successfully: $BACKUP_ROLE_NAME"
    
    # Wait for role to be available
    log "INFO" "Waiting for IAM role to become available..."
    sleep 10
}

# Deploy RDS instance
deploy_rds() {
    log "INFO" "Creating RDS instance with backup configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create RDS instance with automated backups"
        return 0
    fi
    
    # Create RDS instance
    aws rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "TempPassword123!" \
        --allocated-storage 20 \
        --storage-type gp2 \
        --backup-retention-period 7 \
        --preferred-backup-window "03:00-04:00" \
        --preferred-maintenance-window "sun:04:00-sun:05:00" \
        --storage-encrypted \
        --kms-key-id "$KMS_KEY_ID" \
        --copy-tags-to-snapshot \
        --delete-automated-backups \
        --no-deletion-protection
    
    log "INFO" "RDS instance creation initiated: $DB_INSTANCE_ID"
    log "INFO" "Waiting for RDS instance to become available..."
    
    # Wait for instance to be available
    aws rds wait db-instance-available \
        --db-instance-identifier "$DB_INSTANCE_ID"
    
    log "INFO" "RDS instance is now available"
}

# Deploy backup vault
deploy_backup_vault() {
    log "INFO" "Creating AWS Backup vault..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create backup vault with encryption"
        return 0
    fi
    
    # Create backup vault
    aws backup create-backup-vault \
        --backup-vault-name "$BACKUP_VAULT_NAME" \
        --encryption-key-arn "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"
    
    log "INFO" "Backup vault created successfully: $BACKUP_VAULT_NAME"
}

# Deploy backup plan
deploy_backup_plan() {
    log "INFO" "Creating backup plan..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create backup plan with daily and weekly schedules"
        return 0
    fi
    
    # Generate random suffix for backup plan
    local random_suffix=$(echo $DB_INSTANCE_ID | cut -d'-' -f3)
    
    # Create backup plan configuration
    cat > backup-plan.json << EOF
{
    "BackupPlanName": "rds-backup-plan-${random_suffix}",
    "Rules": [
        {
            "RuleName": "DailyBackups",
            "TargetBackupVaultName": "${BACKUP_VAULT_NAME}",
            "ScheduleExpression": "cron(0 5 ? * * *)",
            "StartWindowMinutes": 60,
            "CompletionWindowMinutes": 120,
            "Lifecycle": {
                "DeleteAfterDays": 30,
                "MoveToColdStorageAfterDays": 7
            },
            "RecoveryPointTags": {
                "Environment": "Production",
                "BackupType": "Automated"
            },
            "CopyActions": [
                {
                    "DestinationBackupVaultArn": "arn:aws:backup:${DR_REGION}:${AWS_ACCOUNT_ID}:backup-vault:${BACKUP_VAULT_NAME}-dr",
                    "Lifecycle": {
                        "DeleteAfterDays": 30
                    }
                }
            ]
        },
        {
            "RuleName": "WeeklyBackups",
            "TargetBackupVaultName": "${BACKUP_VAULT_NAME}",
            "ScheduleExpression": "cron(0 3 ? * SUN *)",
            "StartWindowMinutes": 60,
            "CompletionWindowMinutes": 180,
            "Lifecycle": {
                "DeleteAfterDays": 90,
                "MoveToColdStorageAfterDays": 14
            },
            "RecoveryPointTags": {
                "Environment": "Production",
                "BackupType": "Weekly"
            }
        }
    ]
}
EOF
    
    # Create backup plan
    BACKUP_PLAN_ID=$(aws backup create-backup-plan \
        --backup-plan file://backup-plan.json \
        --query 'BackupPlanId' --output text)
    
    if [[ -z "$BACKUP_PLAN_ID" ]]; then
        error_exit "Failed to create backup plan"
    fi
    
    log "INFO" "Backup plan created successfully: $BACKUP_PLAN_ID"
    export BACKUP_PLAN_ID
}

# Deploy DR infrastructure
deploy_dr_infrastructure() {
    log "INFO" "Setting up disaster recovery infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create DR region backup vault and enable cross-region replication"
        return 0
    fi
    
    # Create KMS key in DR region
    DR_KMS_KEY_ID=$(aws kms create-key \
        --region "$DR_REGION" \
        --description "RDS backup encryption key - DR region" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    
    if [[ -z "$DR_KMS_KEY_ID" ]]; then
        error_exit "Failed to create DR KMS key"
    fi
    
    # Create backup vault in DR region
    aws backup create-backup-vault \
        --region "$DR_REGION" \
        --backup-vault-name "${BACKUP_VAULT_NAME}-dr" \
        --encryption-key-arn "arn:aws:kms:${DR_REGION}:${AWS_ACCOUNT_ID}:key/${DR_KMS_KEY_ID}"
    
    # Enable cross-region automated backup replication
    aws rds start-db-instance-automated-backups-replication \
        --region "$DR_REGION" \
        --source-db-instance-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${DB_INSTANCE_ID}" \
        --backup-retention-period 14 \
        --kms-key-id "$DR_KMS_KEY_ID"
    
    log "INFO" "DR infrastructure setup completed"
    log "INFO" "DR KMS Key ID: $DR_KMS_KEY_ID"
    
    export DR_KMS_KEY_ID
}

# Deploy backup selection
deploy_backup_selection() {
    log "INFO" "Creating backup selection..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create backup selection and tag RDS instance"
        return 0
    fi
    
    # Create backup selection configuration
    cat > backup-selection.json << EOF
{
    "SelectionName": "rds-backup-selection-$(echo $DB_INSTANCE_ID | cut -d'-' -f3)",
    "IamRoleArn": "${BACKUP_ROLE_ARN}",
    "Resources": [
        "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${DB_INSTANCE_ID}"
    ],
    "Conditions": {
        "StringEquals": {
            "aws:ResourceTag/Environment": ["Production"]
        }
    }
}
EOF
    
    # Add resource tag to RDS instance
    aws rds add-tags-to-resource \
        --resource-name "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${DB_INSTANCE_ID}" \
        --tags Key=Environment,Value=Production Key=BackupStrategy,Value=Automated
    
    # Create backup selection
    aws backup create-backup-selection \
        --backup-plan-id "$BACKUP_PLAN_ID" \
        --backup-selection file://backup-selection.json
    
    log "INFO" "Backup selection created successfully"
}

# Deploy monitoring
deploy_monitoring() {
    log "INFO" "Setting up monitoring and alerting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create SNS topic and CloudWatch alarms"
        return 0
    fi
    
    # Generate random suffix for monitoring resources
    local random_suffix=$(echo $DB_INSTANCE_ID | cut -d'-' -f3)
    
    # Create SNS topic for backup notifications
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "rds-backup-notifications-${random_suffix}" \
        --query 'TopicArn' --output text)
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        error_exit "Failed to create SNS topic"
    fi
    
    # Create CloudWatch alarm for failed backup jobs
    aws cloudwatch put-metric-alarm \
        --alarm-name "RDS-Backup-Failures-${random_suffix}" \
        --alarm-description "Alert on RDS backup failures" \
        --metric-name "NumberOfBackupJobsFailed" \
        --namespace "AWS/Backup" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --treat-missing-data notBreaching
    
    log "INFO" "Monitoring setup completed"
    log "INFO" "SNS Topic ARN: $SNS_TOPIC_ARN"
    
    export SNS_TOPIC_ARN
}

# Create manual backup
create_manual_backup() {
    log "INFO" "Creating manual backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create manual RDS snapshot and backup job"
        return 0
    fi
    
    # Create manual RDS snapshot
    MANUAL_SNAPSHOT_ID="${DB_INSTANCE_ID}-manual-snapshot-$(date +%Y%m%d-%H%M%S)"
    
    aws rds create-db-snapshot \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --db-snapshot-identifier "$MANUAL_SNAPSHOT_ID"
    
    # Start on-demand backup job through AWS Backup
    aws backup start-backup-job \
        --backup-vault-name "$BACKUP_VAULT_NAME" \
        --resource-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${DB_INSTANCE_ID}" \
        --iam-role-arn "$BACKUP_ROLE_ARN" \
        --recovery-point-tags Environment=Production,BackupType=OnDemand
    
    log "INFO" "Manual backup created: $MANUAL_SNAPSHOT_ID"
    export MANUAL_SNAPSHOT_ID
}

# Validation function
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would validate RDS instance and backup configuration"
        return 0
    fi
    
    # Verify RDS instance
    local rds_status=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].DBInstanceStatus' --output text)
    
    if [[ "$rds_status" != "available" ]]; then
        error_exit "RDS instance is not available: $rds_status"
    fi
    
    # Verify backup vault
    local vault_status=$(aws backup describe-backup-vault \
        --backup-vault-name "$BACKUP_VAULT_NAME" \
        --query 'BackupVaultName' --output text)
    
    if [[ "$vault_status" != "$BACKUP_VAULT_NAME" ]]; then
        error_exit "Backup vault not found or not accessible"
    fi
    
    # Verify backup plan
    local plan_status=$(aws backup get-backup-plan \
        --backup-plan-id "$BACKUP_PLAN_ID" \
        --query 'BackupPlan.BackupPlanName' --output text)
    
    if [[ -z "$plan_status" ]]; then
        error_exit "Backup plan not found or not accessible"
    fi
    
    log "INFO" "Deployment validation completed successfully"
}

# Generate deployment summary
generate_summary() {
    log "INFO" "Generating deployment summary..."
    
    cat << EOF | tee -a "$LOG_FILE"

===============================================
    DEPLOYMENT SUMMARY
===============================================
Date: $(date)
Region: $AWS_REGION
DR Region: $DR_REGION
Account: $AWS_ACCOUNT_ID

RESOURCES CREATED:
• RDS Instance: $DB_INSTANCE_ID
• Backup Vault: $BACKUP_VAULT_NAME
• Backup Plan: $BACKUP_PLAN_ID
• IAM Role: $BACKUP_ROLE_NAME
• KMS Key: $KMS_KEY_ID
• DR KMS Key: $DR_KMS_KEY_ID
• SNS Topic: $SNS_TOPIC_ARN
• Manual Snapshot: $MANUAL_SNAPSHOT_ID

NEXT STEPS:
1. Review backup vault and recovery points
2. Test point-in-time recovery
3. Verify cross-region replication
4. Set up SNS subscription for alerts
5. Review and adjust backup schedules as needed

IMPORTANT:
• Default RDS password is: TempPassword123!
• Change the password immediately for production use
• Review and adjust backup retention policies
• Test disaster recovery procedures regularly

For cleanup, run: ./destroy.sh
===============================================
EOF
}

# Main deployment function
main() {
    log "INFO" "Starting AWS Database Backup and Recovery deployment..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Check if dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    deploy_kms
    deploy_iam_role
    deploy_rds
    deploy_backup_vault
    deploy_backup_plan
    deploy_dr_infrastructure
    deploy_backup_selection
    deploy_monitoring
    create_manual_backup
    validate_deployment
    generate_summary
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Check $LOG_FILE for detailed logs"
}

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Run in dry-run mode (no resources created)
    -s, --skip-cleanup  Skip cleanup of temporary files
    -v, --verbose       Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN=true       Enable dry-run mode
    SKIP_CLEANUP=true  Skip cleanup of temporary files
    AWS_REGION         Override AWS region (default: from AWS config)

EXAMPLES:
    $0                 # Normal deployment
    $0 --dry-run       # Dry run mode
    DRY_RUN=true $0    # Dry run via environment variable

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"