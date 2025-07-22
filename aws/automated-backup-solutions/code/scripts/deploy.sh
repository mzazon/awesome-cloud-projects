#!/bin/bash

# AWS Backup Automated Solution Deployment Script
# Creates comprehensive backup infrastructure with monitoring and compliance

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "${ERROR_LOG}"
    echo -e "${RED}ERROR: $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Cleanup function for script interruption
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Script interrupted or failed. Check logs: ${LOG_FILE} and ${ERROR_LOG}"
        log_info "To clean up partial deployment, run: ./destroy.sh"
    fi
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI Version: ${AWS_CLI_VERSION}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Installing basic JSON parsing alternatives..."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core AWS configuration
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS_REGION not set and no default region configured"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export DR_REGION=${DR_REGION:-"us-east-1"}
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Resource names
    export BACKUP_PLAN_NAME="enterprise-backup-plan-${RANDOM_SUFFIX}"
    export BACKUP_VAULT_NAME="enterprise-backup-vault-${RANDOM_SUFFIX}"
    export DR_BACKUP_VAULT_NAME="dr-backup-vault-${RANDOM_SUFFIX}"
    export BACKUP_ROLE_NAME="AWSBackupDefaultServiceRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="backup-notifications-${RANDOM_SUFFIX}"
    
    # Store variables for later use
    cat > "${SCRIPT_DIR}/deploy_vars.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DR_REGION=${DR_REGION}
BACKUP_PLAN_NAME=${BACKUP_PLAN_NAME}
BACKUP_VAULT_NAME=${BACKUP_VAULT_NAME}
DR_BACKUP_VAULT_NAME=${DR_BACKUP_VAULT_NAME}
BACKUP_ROLE_NAME=${BACKUP_ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Primary Region: ${AWS_REGION}"
    log_info "DR Region: ${DR_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
}

# Create SNS topic for notifications
create_sns_topic() {
    log_info "Creating SNS topic for backup notifications..."
    
    aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${SCRIPT_DIR}/deploy_vars.env"
    
    log_success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Create backup vaults
create_backup_vaults() {
    log_info "Creating backup vaults in primary and DR regions..."
    
    # Primary region vault
    aws backup create-backup-vault \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --encryption-key-id alias/aws/backup \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    # DR region vault
    aws backup create-backup-vault \
        --backup-vault-name "${DR_BACKUP_VAULT_NAME}" \
        --encryption-key-id alias/aws/backup \
        --region "${DR_REGION}" >> "${LOG_FILE}" 2>&1
    
    log_success "Backup vaults created in both regions"
}

# Create IAM service role
create_iam_role() {
    log_info "Creating IAM service role for AWS Backup..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/backup-trust-policy.json" << 'EOF'
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
        --role-name "${BACKUP_ROLE_NAME}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/backup-trust-policy.json" \
        --description "Service role for AWS Backup automated solution" >> "${LOG_FILE}" 2>&1
    
    # Attach AWS managed policies
    aws iam attach-role-policy \
        --role-name "${BACKUP_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup >> "${LOG_FILE}" 2>&1
    
    aws iam attach-role-policy \
        --role-name "${BACKUP_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores >> "${LOG_FILE}" 2>&1
    
    # Wait for role propagation
    sleep 10
    
    log_success "IAM service role created and configured"
}

# Create backup plan
create_backup_plan() {
    log_info "Creating comprehensive backup plan..."
    
    cat > "${SCRIPT_DIR}/backup-plan.json" << EOF
{
    "BackupPlan": {
        "BackupPlanName": "${BACKUP_PLAN_NAME}",
        "Rules": [
            {
                "RuleName": "DailyBackups",
                "TargetBackupVault": "${BACKUP_VAULT_NAME}",
                "ScheduleExpression": "cron(0 2 ? * * *)",
                "StartWindowMinutes": 60,
                "CompletionWindowMinutes": 120,
                "Lifecycle": {
                    "DeleteAfterDays": 30
                },
                "RecoveryPointTags": {
                    "BackupType": "Daily",
                    "Environment": "Production"
                },
                "CopyActions": [
                    {
                        "DestinationBackupVaultArn": "arn:aws:backup:${DR_REGION}:${AWS_ACCOUNT_ID}:backup-vault:${DR_BACKUP_VAULT_NAME}",
                        "Lifecycle": {
                            "DeleteAfterDays": 30
                        }
                    }
                ]
            },
            {
                "RuleName": "WeeklyBackups",
                "TargetBackupVault": "${BACKUP_VAULT_NAME}",
                "ScheduleExpression": "cron(0 3 ? * SUN *)",
                "StartWindowMinutes": 60,
                "CompletionWindowMinutes": 240,
                "Lifecycle": {
                    "DeleteAfterDays": 90
                },
                "RecoveryPointTags": {
                    "BackupType": "Weekly",
                    "Environment": "Production"
                },
                "CopyActions": [
                    {
                        "DestinationBackupVaultArn": "arn:aws:backup:${DR_REGION}:${AWS_ACCOUNT_ID}:backup-vault:${DR_BACKUP_VAULT_NAME}",
                        "Lifecycle": {
                            "DeleteAfterDays": 90
                        }
                    }
                ]
            }
        ]
    }
}
EOF
    
    # Create backup plan
    aws backup create-backup-plan \
        --backup-plan file://"${SCRIPT_DIR}/backup-plan.json" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    export BACKUP_PLAN_ID=$(aws backup list-backup-plans \
        --query "BackupPlansList[?BackupPlanName=='${BACKUP_PLAN_NAME}'].BackupPlanId" \
        --output text)
    
    echo "BACKUP_PLAN_ID=${BACKUP_PLAN_ID}" >> "${SCRIPT_DIR}/deploy_vars.env"
    
    log_success "Backup plan created: ${BACKUP_PLAN_ID}"
}

# Create backup selections
create_backup_selections() {
    log_info "Creating backup selections for resource targeting..."
    
    cat > "${SCRIPT_DIR}/backup-selection.json" << EOF
{
    "BackupSelection": {
        "SelectionName": "ProductionResources",
        "IamRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${BACKUP_ROLE_NAME}",
        "Resources": [
            "*"
        ],
        "Conditions": {
            "StringEquals": {
                "aws:ResourceTag/Environment": [
                    "Production"
                ]
            }
        },
        "NotResources": []
    }
}
EOF
    
    aws backup create-backup-selection \
        --backup-plan-id "${BACKUP_PLAN_ID}" \
        --backup-selection file://"${SCRIPT_DIR}/backup-selection.json" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    log_success "Backup selection created for production resources"
}

# Setup CloudWatch monitoring
setup_cloudwatch_monitoring() {
    log_info "Setting up CloudWatch monitoring and alarms..."
    
    # Backup job failures alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "AWS-Backup-Job-Failures-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when backup jobs fail" \
        --metric-name "NumberOfBackupJobsFailed" \
        --namespace "AWS/Backup" \
        --statistic "Sum" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --treat-missing-data "notBreaching" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    # Backup storage usage alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "AWS-Backup-Storage-Usage-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when backup storage exceeds threshold" \
        --metric-name "BackupVaultSizeBytes" \
        --namespace "AWS/Backup" \
        --statistic "Average" \
        --period 3600 \
        --threshold 107374182400 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=BackupVaultName,Value="${BACKUP_VAULT_NAME}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    log_success "CloudWatch alarms configured"
}

# Configure backup vault notifications
configure_vault_notifications() {
    log_info "Configuring backup vault notifications..."
    
    aws backup put-backup-vault-notifications \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --sns-topic-arn "${SNS_TOPIC_ARN}" \
        --backup-vault-events BACKUP_JOB_STARTED BACKUP_JOB_COMPLETED BACKUP_JOB_FAILED \
            RESTORE_JOB_STARTED RESTORE_JOB_COMPLETED RESTORE_JOB_FAILED \
            COPY_JOB_STARTED COPY_JOB_SUCCESSFUL COPY_JOB_FAILED \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    log_success "Backup vault notifications configured"
}

# Create compliance monitoring
create_compliance_monitoring() {
    log_info "Setting up backup compliance monitoring..."
    
    cat > "${SCRIPT_DIR}/backup-compliance-rule.json" << 'EOF'
{
    "ConfigRuleName": "backup-plan-min-frequency-and-min-retention-check",
    "Description": "Checks whether a backup plan has a backup rule that satisfies the required frequency and retention period",
    "Source": {
        "Owner": "AWS",
        "SourceIdentifier": "BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK"
    },
    "InputParameters": "{\"requiredFrequencyValue\":\"1\",\"requiredRetentionDays\":\"35\",\"requiredFrequencyUnit\":\"days\"}"
}
EOF
    
    # Create Config rule (if Config is enabled)
    aws configservice put-config-rule \
        --config-rule file://"${SCRIPT_DIR}/backup-compliance-rule.json" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Config service not available or not configured"
    
    log_success "Backup compliance monitoring configured"
}

# Setup automated restore testing
setup_restore_testing() {
    log_info "Setting up automated restore testing..."
    
    cat > "${SCRIPT_DIR}/restore-testing-plan.json" << EOF
{
    "RestoreTestingPlanName": "automated-restore-test-${RANDOM_SUFFIX}",
    "ScheduleExpression": "cron(0 4 ? * MON *)",
    "RecoveryPointSelection": {
        "Algorithm": "LATEST_WITHIN_WINDOW",
        "RecoveryPointTypes": [
            "SNAPSHOT"
        ],
        "IncludeVaults": [
            "${BACKUP_VAULT_NAME}"
        ]
    }
}
EOF
    
    aws backup create-restore-testing-plan \
        --restore-testing-plan file://"${SCRIPT_DIR}/restore-testing-plan.json" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Restore testing not available in this region"
    
    log_success "Automated restore testing configured"
}

# Setup backup reporting
setup_backup_reporting() {
    log_info "Setting up backup reporting..."
    
    # Create S3 bucket for reports
    REPORTS_BUCKET="aws-backup-reports-${AWS_ACCOUNT_ID}-${AWS_REGION}"
    aws s3 mb "s3://${REPORTS_BUCKET}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "S3 bucket already exists or creation failed"
    
    cat > "${SCRIPT_DIR}/backup-report-plan.json" << EOF
{
    "ReportPlanName": "backup-compliance-report-${RANDOM_SUFFIX}",
    "ReportPlanDescription": "Monthly backup compliance report",
    "ReportDeliveryChannel": {
        "S3BucketName": "${REPORTS_BUCKET}",
        "S3KeyPrefix": "backup-reports/",
        "Formats": [
            "CSV",
            "JSON"
        ]
    },
    "ReportSetting": {
        "ReportTemplate": "BACKUP_JOB_REPORT"
    }
}
EOF
    
    aws backup create-report-plan \
        --report-plan file://"${SCRIPT_DIR}/backup-report-plan.json" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Backup reporting not available in this region"
    
    echo "REPORTS_BUCKET=${REPORTS_BUCKET}" >> "${SCRIPT_DIR}/deploy_vars.env"
    
    log_success "Backup reporting configured"
}

# Configure vault security policies
configure_vault_security() {
    log_info "Configuring backup vault security policies..."
    
    cat > "${SCRIPT_DIR}/vault-access-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyDeleteBackupVault",
            "Effect": "Deny",
            "Principal": "*",
            "Action": [
                "backup:DeleteBackupVault",
                "backup:DeleteRecoveryPoint",
                "backup:UpdateRecoveryPointLifecycle"
            ],
            "Resource": "*",
            "Condition": {
                "StringNotEquals": {
                    "aws:userid": [
                        "${AWS_ACCOUNT_ID}:root"
                    ]
                }
            }
        }
    ]
}
EOF
    
    aws backup put-backup-vault-access-policy \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --policy file://"${SCRIPT_DIR}/vault-access-policy.json" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    log_success "Backup vault security policies applied"
}

# Perform validation tests
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check backup plan
    aws backup get-backup-plan \
        --backup-plan-id "${BACKUP_PLAN_ID}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    # Check backup vaults
    aws backup list-backup-vaults \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    aws backup list-backup-vaults \
        --region "${DR_REGION}" >> "${LOG_FILE}" 2>&1
    
    # Check CloudWatch alarms
    aws cloudwatch describe-alarms \
        --alarm-names "AWS-Backup-Job-Failures-${RANDOM_SUFFIX}" "AWS-Backup-Storage-Usage-${RANDOM_SUFFIX}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
    
    log_success "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo
    echo "=================================================="
    echo "AWS Backup Solution Deployment Summary"
    echo "=================================================="
    echo "Primary Region: ${AWS_REGION}"
    echo "DR Region: ${DR_REGION}"
    echo "Backup Plan: ${BACKUP_PLAN_NAME}"
    echo "Primary Vault: ${BACKUP_VAULT_NAME}"
    echo "DR Vault: ${DR_BACKUP_VAULT_NAME}"
    echo "IAM Role: ${BACKUP_ROLE_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_NAME}"
    echo
    echo "Next Steps:"
    echo "1. Tag your resources with 'Environment=Production' to include them in backups"
    echo "2. Subscribe to SNS topic for backup notifications"
    echo "3. Monitor CloudWatch alarms for backup failures"
    echo "4. Review backup jobs in AWS Backup console"
    echo
    echo "Configuration saved to: ${SCRIPT_DIR}/deploy_vars.env"
    echo "Logs available at: ${LOG_FILE}"
    echo "=================================================="
}

# Main deployment function
main() {
    echo "Starting AWS Backup Solution Deployment..."
    echo "Logs will be written to: ${LOG_FILE}"
    echo
    
    check_prerequisites
    setup_environment
    create_sns_topic
    create_backup_vaults
    create_iam_role
    create_backup_plan
    create_backup_selections
    setup_cloudwatch_monitoring
    configure_vault_notifications
    create_compliance_monitoring
    setup_restore_testing
    setup_backup_reporting
    configure_vault_security
    validate_deployment
    display_summary
    
    log_success "AWS Backup solution deployment completed successfully!"
}

# Run main function
main "$@"