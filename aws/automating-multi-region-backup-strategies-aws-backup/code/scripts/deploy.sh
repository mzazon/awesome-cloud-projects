#!/bin/bash

# =============================================================================
# AWS Multi-Region Backup Strategy Deployment Script
# =============================================================================
# This script deploys a comprehensive multi-region backup strategy using
# AWS Backup, EventBridge, Lambda, and SNS for automated backup management
# with cross-region replication and intelligent monitoring.
#
# Author: Recipe Generator v1.3
# Last Updated: 2025-07-12
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR=$(mktemp -d)
trap 'cleanup' EXIT

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

header() {
    echo -e "\n${PURPLE}=== $1 ===${NC}" | tee -a "$LOG_FILE"
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up temporary directory: $TEMP_DIR"
    fi
}

# =============================================================================
# Prerequisites Validation
# =============================================================================

check_prerequisites() {
    header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS User: $AWS_USER_ARN"
    
    # Check required permissions (basic check)
    info "Validating AWS permissions..."
    if ! aws backup list-backup-plans --region us-east-1 &> /dev/null; then
        warning "Limited AWS Backup permissions detected. Some operations may fail."
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. JSON processing will use basic parsing."
        JQ_AVAILABLE=false
    else
        JQ_AVAILABLE=true
    fi
    
    # Check if zip is available for Lambda packaging
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# =============================================================================
# Configuration Setup
# =============================================================================

setup_configuration() {
    header "Setting Up Configuration"
    
    # Default configuration values
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
    export TERTIARY_REGION="${TERTIARY_REGION:-eu-west-1}"
    export ORGANIZATION_NAME="${ORGANIZATION_NAME:-YourOrg}"
    export BACKUP_PLAN_NAME="${BACKUP_PLAN_NAME:-MultiRegionBackupPlan}"
    export NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-admin@example.com}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(date +%s | tail -c 6)
    export RANDOM_SUFFIX
    
    # Derived configuration
    export BACKUP_VAULT_PRIMARY="${ORGANIZATION_NAME}-primary-vault-${RANDOM_SUFFIX}"
    export BACKUP_VAULT_SECONDARY="${ORGANIZATION_NAME}-secondary-vault-${RANDOM_SUFFIX}"
    export BACKUP_VAULT_TERTIARY="${ORGANIZATION_NAME}-tertiary-vault-${RANDOM_SUFFIX}"
    
    info "Configuration:"
    info "  Primary Region: $PRIMARY_REGION"
    info "  Secondary Region: $SECONDARY_REGION"
    info "  Tertiary Region: $TERTIARY_REGION"
    info "  Organization: $ORGANIZATION_NAME"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Notification Email: $NOTIFICATION_EMAIL"
    
    # Validate regions are accessible
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            error "Region $region is not accessible or does not exist"
            exit 1
        fi
    done
    
    success "Configuration setup completed"
}

# =============================================================================
# IAM Role Creation
# =============================================================================

create_iam_roles() {
    header "Creating IAM Service Roles"
    
    # Create AWS Backup service role
    info "Creating AWS Backup service role..."
    
    cat > "$TEMP_DIR/backup-trust-policy.json" << 'EOF'
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

    if aws iam get-role --role-name AWSBackupServiceRole &> /dev/null; then
        warning "AWSBackupServiceRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name AWSBackupServiceRole \
            --assume-role-policy-document file://"$TEMP_DIR/backup-trust-policy.json" \
            --region "$PRIMARY_REGION"
        
        # Attach managed policies
        aws iam attach-role-policy \
            --role-name AWSBackupServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup
        
        aws iam attach-role-policy \
            --role-name AWSBackupServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores
        
        success "AWS Backup service role created with necessary permissions"
    fi
    
    # Create Lambda execution role
    info "Creating Lambda execution role..."
    
    cat > "$TEMP_DIR/lambda-trust-policy.json" << 'EOF'
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

    if aws iam get-role --role-name BackupValidatorRole &> /dev/null; then
        warning "BackupValidatorRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name BackupValidatorRole \
            --assume-role-policy-document file://"$TEMP_DIR/lambda-trust-policy.json"
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name BackupValidatorRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Create custom policy for backup validation
        cat > "$TEMP_DIR/backup-validator-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "backup:DescribeBackupJob",
                "backup:ListCopyJobs",
                "backup:DescribeRecoveryPoint",
                "backup:ListRecoveryPointsByBackupVault",
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name BackupValidatorRole \
            --policy-name BackupValidatorPolicy \
            --policy-document file://"$TEMP_DIR/backup-validator-policy.json"
        
        success "Lambda execution role created with backup validation permissions"
    fi
    
    # Wait for IAM role propagation
    info "Waiting for IAM role propagation..."
    sleep 30
    
    success "IAM roles creation completed"
}

# =============================================================================
# Backup Vault Creation
# =============================================================================

create_backup_vaults() {
    header "Creating Backup Vaults Across Regions"
    
    # Create primary vault
    info "Creating primary backup vault in $PRIMARY_REGION..."
    if aws backup describe-backup-vault --backup-vault-name "$BACKUP_VAULT_PRIMARY" --region "$PRIMARY_REGION" &> /dev/null; then
        warning "Primary backup vault already exists, skipping creation"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$BACKUP_VAULT_PRIMARY" \
            --encryption-key-arn alias/aws/backup \
            --region "$PRIMARY_REGION"
        success "Primary backup vault created: $BACKUP_VAULT_PRIMARY"
    fi
    
    # Create secondary vault
    info "Creating secondary backup vault in $SECONDARY_REGION..."
    if aws backup describe-backup-vault --backup-vault-name "$BACKUP_VAULT_SECONDARY" --region "$SECONDARY_REGION" &> /dev/null; then
        warning "Secondary backup vault already exists, skipping creation"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$BACKUP_VAULT_SECONDARY" \
            --encryption-key-arn alias/aws/backup \
            --region "$SECONDARY_REGION"
        success "Secondary backup vault created: $BACKUP_VAULT_SECONDARY"
    fi
    
    # Create tertiary vault
    info "Creating tertiary backup vault in $TERTIARY_REGION..."
    if aws backup describe-backup-vault --backup-vault-name "$BACKUP_VAULT_TERTIARY" --region "$TERTIARY_REGION" &> /dev/null; then
        warning "Tertiary backup vault already exists, skipping creation"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$BACKUP_VAULT_TERTIARY" \
            --encryption-key-arn alias/aws/backup \
            --region "$TERTIARY_REGION"
        success "Tertiary backup vault created: $BACKUP_VAULT_TERTIARY"
    fi
    
    success "Backup vaults creation completed"
}

# =============================================================================
# Backup Plan Creation
# =============================================================================

create_backup_plan() {
    header "Creating Multi-Region Backup Plan"
    
    info "Generating backup plan configuration..."
    
    cat > "$TEMP_DIR/backup-plan.json" << EOF
{
  "BackupPlan": {
    "BackupPlanName": "$BACKUP_PLAN_NAME",
    "Rules": [
      {
        "RuleName": "DailyBackupsWithCrossRegionCopy",
        "TargetBackupVaultName": "$BACKUP_VAULT_PRIMARY",
        "ScheduleExpression": "cron(0 2 ? * * *)",
        "ScheduleExpressionTimezone": "UTC",
        "StartWindowMinutes": 480,
        "CompletionWindowMinutes": 10080,
        "Lifecycle": {
          "MoveToColdStorageAfterDays": 30,
          "DeleteAfterDays": 365
        },
        "CopyActions": [
          {
            "DestinationBackupVaultArn": "arn:aws:backup:$SECONDARY_REGION:$AWS_ACCOUNT_ID:backup-vault:$BACKUP_VAULT_SECONDARY",
            "Lifecycle": {
              "MoveToColdStorageAfterDays": 30,
              "DeleteAfterDays": 365
            }
          }
        ],
        "RecoveryPointTags": {
          "BackupType": "Daily",
          "Environment": "Production",
          "CrossRegion": "true"
        }
      },
      {
        "RuleName": "WeeklyLongTermArchival",
        "TargetBackupVaultName": "$BACKUP_VAULT_PRIMARY",
        "ScheduleExpression": "cron(0 3 ? * SUN *)",
        "ScheduleExpressionTimezone": "UTC",
        "StartWindowMinutes": 480,
        "CompletionWindowMinutes": 10080,
        "Lifecycle": {
          "MoveToColdStorageAfterDays": 90,
          "DeleteAfterDays": 2555
        },
        "CopyActions": [
          {
            "DestinationBackupVaultArn": "arn:aws:backup:$TERTIARY_REGION:$AWS_ACCOUNT_ID:backup-vault:$BACKUP_VAULT_TERTIARY",
            "Lifecycle": {
              "MoveToColdStorageAfterDays": 90,
              "DeleteAfterDays": 2555
            }
          }
        ],
        "RecoveryPointTags": {
          "BackupType": "Weekly",
          "Environment": "Production",
          "LongTerm": "true"
        }
      }
    ]
  }
}
EOF

    # Check if backup plan already exists
    if EXISTING_PLAN_ID=$(aws backup list-backup-plans --region "$PRIMARY_REGION" --query "BackupPlansList[?BackupPlanName=='$BACKUP_PLAN_NAME'].BackupPlanId" --output text 2>/dev/null) && [[ -n "$EXISTING_PLAN_ID" ]]; then
        warning "Backup plan '$BACKUP_PLAN_NAME' already exists with ID: $EXISTING_PLAN_ID"
        export BACKUP_PLAN_ID="$EXISTING_PLAN_ID"
    else
        # Create the backup plan
        export BACKUP_PLAN_ID=$(aws backup create-backup-plan \
            --cli-input-json file://"$TEMP_DIR/backup-plan.json" \
            --region "$PRIMARY_REGION" \
            --query 'BackupPlanId' --output text)
        
        success "Backup plan created with ID: $BACKUP_PLAN_ID"
    fi
    
    # Store backup plan ID for later use
    echo "$BACKUP_PLAN_ID" > "$TEMP_DIR/backup-plan-id.txt"
    
    success "Backup plan creation completed"
}

# =============================================================================
# Backup Selection Creation
# =============================================================================

create_backup_selection() {
    header "Creating Backup Selection"
    
    info "Creating tag-based backup selection..."
    
    cat > "$TEMP_DIR/backup-selection.json" << EOF
{
  "BackupSelection": {
    "SelectionName": "ProductionResourcesSelection",
    "IamRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/AWSBackupServiceRole",
    "Resources": ["*"],
    "Conditions": {
      "StringEquals": {
        "aws:ResourceTag/Environment": ["Production"],
        "aws:ResourceTag/BackupEnabled": ["true"]
      }
    }
  }
}
EOF

    # Check if backup selection already exists
    if aws backup list-backup-selections --backup-plan-id "$BACKUP_PLAN_ID" --region "$PRIMARY_REGION" --query "BackupSelectionsList[?SelectionName=='ProductionResourcesSelection']" --output text | grep -q "ProductionResourcesSelection"; then
        warning "Backup selection 'ProductionResourcesSelection' already exists"
    else
        aws backup create-backup-selection \
            --backup-plan-id "$BACKUP_PLAN_ID" \
            --cli-input-json file://"$TEMP_DIR/backup-selection.json" \
            --region "$PRIMARY_REGION"
        
        success "Backup selection created for tag-based resource discovery"
    fi
    
    success "Backup selection creation completed"
}

# =============================================================================
# SNS Topic Creation
# =============================================================================

create_sns_topic() {
    header "Creating SNS Notification Topic"
    
    info "Creating SNS topic for backup notifications..."
    
    # Check if topic already exists
    if EXISTING_TOPIC=$(aws sns list-topics --region "$PRIMARY_REGION" --query "Topics[?contains(TopicArn, 'backup-notifications')].TopicArn" --output text 2>/dev/null) && [[ -n "$EXISTING_TOPIC" ]]; then
        warning "SNS topic already exists: $EXISTING_TOPIC"
        export BACKUP_NOTIFICATIONS_TOPIC="$EXISTING_TOPIC"
    else
        export BACKUP_NOTIFICATIONS_TOPIC=$(aws sns create-topic \
            --name "backup-notifications-${RANDOM_SUFFIX}" \
            --region "$PRIMARY_REGION" \
            --query 'TopicArn' --output text)
        
        success "SNS topic created: $BACKUP_NOTIFICATIONS_TOPIC"
    fi
    
    # Subscribe email endpoint if provided and not a placeholder
    if [[ "$NOTIFICATION_EMAIL" != "admin@example.com" ]]; then
        info "Subscribing email endpoint: $NOTIFICATION_EMAIL"
        aws sns subscribe \
            --topic-arn "$BACKUP_NOTIFICATIONS_TOPIC" \
            --protocol email \
            --notification-endpoint "$NOTIFICATION_EMAIL" \
            --region "$PRIMARY_REGION"
        
        info "Email subscription created. Please confirm the subscription in your email."
    else
        warning "Default email address detected. Please update NOTIFICATION_EMAIL variable and manually subscribe to the topic."
    fi
    
    # Store topic ARN for later use
    echo "$BACKUP_NOTIFICATIONS_TOPIC" > "$TEMP_DIR/sns-topic-arn.txt"
    
    success "SNS topic creation completed"
}

# =============================================================================
# Lambda Function Creation
# =============================================================================

create_lambda_function() {
    header "Creating Lambda Function for Backup Validation"
    
    info "Creating Lambda function code..."
    
    cat > "$TEMP_DIR/backup_validator.py" << 'EOF'
import json
import boto3
import os
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to validate AWS Backup job completion and send notifications.
    
    This function processes EventBridge events from AWS Backup and performs
    validation checks on backup jobs, sending SNS notifications for failures.
    """
    backup_client = boto3.client('backup')
    sns_client = boto3.client('sns')
    
    try:
        # Extract backup job details from EventBridge event
        detail = event.get('detail', {})
        backup_job_id = detail.get('backupJobId')
        
        if not backup_job_id:
            logger.error("No backup job ID found in event")
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event structure')
            }
        
        logger.info(f"Processing backup job: {backup_job_id}")
        
        # Get backup job details
        response = backup_client.describe_backup_job(
            BackupJobId=backup_job_id
        )
        
        backup_job = response['BackupJob']
        job_state = backup_job.get('State')
        resource_arn = backup_job.get('ResourceArn', 'Unknown')
        
        # Process based on backup job state
        if job_state == 'COMPLETED':
            logger.info(f"Backup job {backup_job_id} completed successfully")
            
            # Validate recovery point creation
            recovery_point_arn = backup_job.get('RecoveryPointArn')
            if recovery_point_arn:
                logger.info(f"Recovery point created: {recovery_point_arn}")
            
            message = f"""
Backup Validation Success
========================
Job ID: {backup_job_id}
Resource: {resource_arn}
State: {job_state}
Recovery Point: {recovery_point_arn}
Completion Time: {backup_job.get('CompletionDate', 'Unknown')}
            """.strip()
            
        elif job_state in ['FAILED', 'ABORTED']:
            error_message = backup_job.get('StatusMessage', 'Unknown error')
            logger.error(f"Backup job {backup_job_id} failed: {error_message}")
            
            message = f"""
Backup Job Failure Alert
=======================
Job ID: {backup_job_id}
Resource: {resource_arn}
State: {job_state}
Error: {error_message}
Start Time: {backup_job.get('CreationDate', 'Unknown')}
            """.strip()
            
            # Send SNS notification for failed jobs
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if sns_topic_arn:
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Subject=f'AWS Backup Job Failed - {backup_job_id}',
                    Message=message
                )
                logger.info("SNS notification sent for failed backup job")
            
        else:
            logger.info(f"Backup job {backup_job_id} is in state: {job_state}")
            message = f"Backup job {backup_job_id} status: {job_state}"
    
    except Exception as e:
        error_msg = f"Error processing backup job validation: {str(e)}"
        logger.error(error_msg)
        
        # Send error notification
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic_arn:
            try:
                sns_client = boto3.client('sns')
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Subject='AWS Backup Validation Error',
                    Message=f"Lambda function error: {error_msg}"
                )
            except Exception as sns_error:
                logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Backup validation completed',
            'backup_job_id': backup_job_id,
            'status': job_state
        })
    }
EOF

    # Create deployment package
    cd "$TEMP_DIR"
    zip backup-validator.zip backup_validator.py
    cd - > /dev/null
    
    info "Creating Lambda function..."
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        warning "Lambda function 'backup-validator' already exists, updating code..."
        
        aws lambda update-function-code \
            --function-name backup-validator \
            --zip-file fileb://"$TEMP_DIR/backup-validator.zip" \
            --region "$PRIMARY_REGION"
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name backup-validator \
            --environment Variables="{SNS_TOPIC_ARN=$BACKUP_NOTIFICATIONS_TOPIC}" \
            --region "$PRIMARY_REGION"
        
        export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
            --function-name backup-validator \
            --region "$PRIMARY_REGION" \
            --query 'Configuration.FunctionArn' --output text)
    else
        export LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
            --function-name backup-validator \
            --runtime python3.9 \
            --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/BackupValidatorRole" \
            --handler backup_validator.lambda_handler \
            --zip-file fileb://"$TEMP_DIR/backup-validator.zip" \
            --environment Variables="{SNS_TOPIC_ARN=$BACKUP_NOTIFICATIONS_TOPIC}" \
            --timeout 300 \
            --description "Validates AWS Backup job completion and sends notifications" \
            --region "$PRIMARY_REGION" \
            --query 'FunctionArn' --output text)
    fi
    
    # Store Lambda function ARN for later use
    echo "$LAMBDA_FUNCTION_ARN" > "$TEMP_DIR/lambda-function-arn.txt"
    
    success "Lambda function created: $LAMBDA_FUNCTION_ARN"
    success "Lambda function creation completed"
}

# =============================================================================
# EventBridge Configuration
# =============================================================================

configure_eventbridge() {
    header "Configuring EventBridge for Backup Monitoring"
    
    info "Creating EventBridge rule for backup job monitoring..."
    
    # Check if EventBridge rule already exists
    if aws events describe-rule --name BackupJobFailureRule --region "$PRIMARY_REGION" &> /dev/null; then
        warning "EventBridge rule 'BackupJobFailureRule' already exists"
    else
        aws events put-rule \
            --name BackupJobFailureRule \
            --event-pattern '{
                "source": ["aws.backup"],
                "detail-type": ["Backup Job State Change"],
                "detail": {
                    "state": ["FAILED", "ABORTED", "COMPLETED"]
                }
            }' \
            --state ENABLED \
            --description "Monitor AWS Backup job state changes" \
            --region "$PRIMARY_REGION"
        
        success "EventBridge rule created for backup monitoring"
    fi
    
    info "Configuring EventBridge integration with Lambda..."
    
    # Add Lambda function as target
    if aws events list-targets-by-rule --rule BackupJobFailureRule --region "$PRIMARY_REGION" --query "Targets[?Arn=='$LAMBDA_FUNCTION_ARN']" --output text | grep -q "$LAMBDA_FUNCTION_ARN"; then
        warning "Lambda target already configured for EventBridge rule"
    else
        aws events put-targets \
            --rule BackupJobFailureRule \
            --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN" \
            --region "$PRIMARY_REGION"
        
        success "Lambda target added to EventBridge rule"
    fi
    
    # Grant EventBridge permission to invoke Lambda
    info "Granting EventBridge permission to invoke Lambda function..."
    
    if aws lambda get-policy --function-name backup-validator --region "$PRIMARY_REGION" 2>/dev/null | grep -q "backup-eventbridge-trigger"; then
        warning "EventBridge Lambda permission already exists"
    else
        aws lambda add-permission \
            --function-name backup-validator \
            --statement-id backup-eventbridge-trigger \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:rule/BackupJobFailureRule" \
            --region "$PRIMARY_REGION"
        
        success "EventBridge permission granted to invoke Lambda function"
    fi
    
    success "EventBridge configuration completed"
}

# =============================================================================
# Resource Tagging Example
# =============================================================================

demonstrate_resource_tagging() {
    header "Demonstrating Resource Tagging for Backup Inclusion"
    
    info "This step demonstrates how to tag resources for automatic backup inclusion."
    info "The backup selection looks for resources with these tags:"
    info "  - Environment=Production"
    info "  - BackupEnabled=true"
    
    warning "Resource tagging examples:"
    warning "For EC2 instances:"
    warning "  aws ec2 create-tags --resources i-1234567890abcdef0 --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true"
    warning "For RDS instances:"
    warning "  aws rds add-tags-to-resource --resource-name arn:aws:rds:region:account:db:mydb --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true"
    warning "For EFS file systems:"
    warning "  aws efs put-backup-policy --file-system-id fs-12345678 --backup-policy Status=ENABLED"
    warning "  aws efs tag-resource --resource-id fs-12345678 --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true"
    
    info "After tagging your resources, they will be automatically included in backup operations."
    success "Resource tagging demonstration completed"
}

# =============================================================================
# Deployment Validation
# =============================================================================

validate_deployment() {
    header "Validating Deployment"
    
    info "Checking backup plan status..."
    aws backup get-backup-plan \
        --backup-plan-id "$BACKUP_PLAN_ID" \
        --region "$PRIMARY_REGION" > /dev/null
    success "Backup plan validation passed"
    
    info "Checking backup vaults across regions..."
    aws backup describe-backup-vault \
        --backup-vault-name "$BACKUP_VAULT_PRIMARY" \
        --region "$PRIMARY_REGION" > /dev/null
    success "Primary backup vault validation passed"
    
    aws backup describe-backup-vault \
        --backup-vault-name "$BACKUP_VAULT_SECONDARY" \
        --region "$SECONDARY_REGION" > /dev/null
    success "Secondary backup vault validation passed"
    
    aws backup describe-backup-vault \
        --backup-vault-name "$BACKUP_VAULT_TERTIARY" \
        --region "$TERTIARY_REGION" > /dev/null
    success "Tertiary backup vault validation passed"
    
    info "Checking Lambda function..."
    aws lambda get-function \
        --function-name backup-validator \
        --region "$PRIMARY_REGION" > /dev/null
    success "Lambda function validation passed"
    
    info "Checking EventBridge rule..."
    aws events describe-rule \
        --name BackupJobFailureRule \
        --region "$PRIMARY_REGION" > /dev/null
    success "EventBridge rule validation passed"
    
    info "Checking SNS topic..."
    aws sns get-topic-attributes \
        --topic-arn "$BACKUP_NOTIFICATIONS_TOPIC" \
        --region "$PRIMARY_REGION" > /dev/null
    success "SNS topic validation passed"
    
    success "All deployment validations passed"
}

# =============================================================================
# Deployment Summary
# =============================================================================

display_deployment_summary() {
    header "Deployment Summary"
    
    echo -e "\n${GREEN}✅ Multi-Region Backup Strategy Deployment Completed Successfully!${NC}\n"
    
    echo -e "${CYAN}Deployed Resources:${NC}"
    echo -e "  📋 Backup Plan ID: ${BACKUP_PLAN_ID}"
    echo -e "  🏛️  Primary Vault: ${BACKUP_VAULT_PRIMARY} (${PRIMARY_REGION})"
    echo -e "  🏛️  Secondary Vault: ${BACKUP_VAULT_SECONDARY} (${SECONDARY_REGION})"
    echo -e "  🏛️  Tertiary Vault: ${BACKUP_VAULT_TERTIARY} (${TERTIARY_REGION})"
    echo -e "  ⚡ Lambda Function: backup-validator"
    echo -e "  📡 EventBridge Rule: BackupJobFailureRule"
    echo -e "  📧 SNS Topic: ${BACKUP_NOTIFICATIONS_TOPIC}"
    
    echo -e "\n${CYAN}Next Steps:${NC}"
    echo -e "  1. Tag your AWS resources with Environment=Production and BackupEnabled=true"
    echo -e "  2. Confirm the email subscription in your inbox (if provided)"
    echo -e "  3. Monitor backup jobs in the AWS Backup console"
    echo -e "  4. Review CloudWatch logs for Lambda function execution"
    
    echo -e "\n${CYAN}Important Notes:${NC}"
    echo -e "  • Daily backups will start at 02:00 UTC"
    echo -e "  • Weekly archival backups run on Sundays at 03:00 UTC"
    echo -e "  • Cross-region copies will be created automatically"
    echo -e "  • Email notifications will be sent for backup failures"
    
    echo -e "\n${YELLOW}Cost Optimization:${NC}"
    echo -e "  • Backups move to cold storage after 30 days (daily) or 90 days (weekly)"
    echo -e "  • Automatic deletion after 365 days (daily) or 2555 days (weekly)"
    echo -e "  • Monitor costs using AWS Cost Explorer and Backup reports"
    
    echo -e "\n${CYAN}Logs and Cleanup:${NC}"
    echo -e "  📋 Deployment log: ${LOG_FILE}"
    echo -e "  🗑️  To remove all resources: ./destroy.sh"
    
    echo -e "\n${GREEN}Deployment completed at $(date)${NC}\n"
}

# =============================================================================
# Main Execution Function
# =============================================================================

main() {
    echo -e "${PURPLE}"
    echo "============================================================================="
    echo "               AWS Multi-Region Backup Strategy Deployment"
    echo "============================================================================="
    echo -e "${NC}"
    echo "This script deploys a comprehensive multi-region backup strategy using"
    echo "AWS Backup with cross-region replication, automated monitoring, and"
    echo "intelligent lifecycle management."
    echo ""
    echo "Deployment will create resources in the following regions:"
    echo "  - Primary: ${PRIMARY_REGION:-us-east-1}"
    echo "  - Secondary: ${SECONDARY_REGION:-us-west-2}" 
    echo "  - Tertiary: ${TERTIARY_REGION:-eu-west-1}"
    echo ""
    
    # Confirmation prompt
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled by user."
        exit 0
    fi
    
    # Start deployment
    log "Starting multi-region backup strategy deployment"
    
    # Execute deployment steps
    check_prerequisites
    setup_configuration
    create_iam_roles
    create_backup_vaults
    create_backup_plan
    create_backup_selection
    create_sns_topic
    create_lambda_function
    configure_eventbridge
    demonstrate_resource_tagging
    validate_deployment
    display_deployment_summary
    
    log "Multi-region backup strategy deployment completed successfully"
    
    return 0
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Handle script interruption
trap 'error "Script interrupted by user"; cleanup; exit 1' INT TERM

# Start main execution
main "$@"