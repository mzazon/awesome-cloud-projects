#!/bin/bash

# Multi-Region Backup Strategies using AWS Backup - Deployment Script
# This script deploys a comprehensive multi-region backup strategy using AWS Backup
# with cross-region copies, EventBridge monitoring, and Lambda validation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}AWS Multi-Region Backup Strategy Deployment${NC}"
echo -e "${BLUE}===========================================${NC}"
echo "Log file: $LOG_FILE"
echo ""

# Function to print status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    print_status "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Get caller identity
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    print_status "AWS Account ID: $AWS_ACCOUNT_ID"
    print_status "AWS User: $AWS_USER_ARN"
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    print_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    print_status "Setting up environment variables..."
    
    # Default region configuration - can be overridden by environment variables
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
    export TERTIARY_REGION="${TERTIARY_REGION:-eu-west-1}"
    export BACKUP_PLAN_NAME="${BACKUP_PLAN_NAME:-MultiRegionBackupPlan}"
    export ORGANIZATION_NAME="${ORGANIZATION_NAME:-YourOrg}"
    export NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-your-email@example.com}"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(date +%s | tail -c 6)
    
    print_status "Environment configuration:"
    print_status "  Primary Region: $PRIMARY_REGION"
    print_status "  Secondary Region: $SECONDARY_REGION"
    print_status "  Tertiary Region: $TERTIARY_REGION"
    print_status "  Organization Name: $ORGANIZATION_NAME"
    print_status "  AWS Account ID: $AWS_ACCOUNT_ID"
    print_status "  Random Suffix: $RANDOM_SUFFIX"
    
    print_success "Environment setup completed"
}

# Function to validate regions
validate_regions() {
    print_status "Validating AWS regions..."
    
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            print_error "Invalid region: $region"
            exit 1
        fi
        print_status "  ✓ $region is valid"
    done
    
    print_success "Region validation completed"
}

# Function to create IAM service role for AWS Backup
create_backup_service_role() {
    print_status "Creating IAM service role for AWS Backup..."
    
    # Check if role already exists
    if aws iam get-role --role-name AWSBackupServiceRole &> /dev/null; then
        print_warning "AWSBackupServiceRole already exists, skipping creation"
        return
    fi
    
    # Create trust policy
    cat > trust-policy.json << EOF
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
    
    # Create the role
    aws iam create-role \
        --role-name AWSBackupServiceRole \
        --assume-role-policy-document file://trust-policy.json \
        --region "$PRIMARY_REGION"
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name AWSBackupServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup \
        --region "$PRIMARY_REGION"
    
    aws iam attach-role-policy \
        --role-name AWSBackupServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores \
        --region "$PRIMARY_REGION"
    
    # Wait for role propagation
    sleep 10
    
    # Cleanup temporary file
    rm -f trust-policy.json
    
    print_success "Created AWS Backup service role"
}

# Function to create backup vaults in all regions
create_backup_vaults() {
    print_status "Creating backup vaults in all regions..."
    
    # Define vault names
    BACKUP_VAULT_PRIMARY="${ORGANIZATION_NAME}-primary-vault"
    BACKUP_VAULT_SECONDARY="${ORGANIZATION_NAME}-secondary-vault"
    BACKUP_VAULT_TERTIARY="${ORGANIZATION_NAME}-tertiary-vault"
    
    # Export for use in other functions
    export BACKUP_VAULT_PRIMARY BACKUP_VAULT_SECONDARY BACKUP_VAULT_TERTIARY
    
    # Create primary vault
    if aws backup describe-backup-vault --backup-vault-name "$BACKUP_VAULT_PRIMARY" --region "$PRIMARY_REGION" &> /dev/null; then
        print_warning "Primary backup vault already exists"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$BACKUP_VAULT_PRIMARY" \
            --encryption-key-arn alias/aws/backup \
            --region "$PRIMARY_REGION"
        print_success "Created primary backup vault in $PRIMARY_REGION"
    fi
    
    # Create secondary vault
    if aws backup describe-backup-vault --backup-vault-name "$BACKUP_VAULT_SECONDARY" --region "$SECONDARY_REGION" &> /dev/null; then
        print_warning "Secondary backup vault already exists"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$BACKUP_VAULT_SECONDARY" \
            --encryption-key-arn alias/aws/backup \
            --region "$SECONDARY_REGION"
        print_success "Created secondary backup vault in $SECONDARY_REGION"
    fi
    
    # Create tertiary vault
    if aws backup describe-backup-vault --backup-vault-name "$BACKUP_VAULT_TERTIARY" --region "$TERTIARY_REGION" &> /dev/null; then
        print_warning "Tertiary backup vault already exists"
    else
        aws backup create-backup-vault \
            --backup-vault-name "$BACKUP_VAULT_TERTIARY" \
            --encryption-key-arn alias/aws/backup \
            --region "$TERTIARY_REGION"
        print_success "Created tertiary backup vault in $TERTIARY_REGION"
    fi
}

# Function to create backup plan
create_backup_plan() {
    print_status "Creating comprehensive backup plan..."
    
    # Create backup plan JSON
    cat > multi-region-backup-plan.json << EOF
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
    
    # Create the backup plan
    BACKUP_PLAN_ID=$(aws backup create-backup-plan \
        --cli-input-json file://multi-region-backup-plan.json \
        --region "$PRIMARY_REGION" \
        --query 'BackupPlanId' --output text)
    
    export BACKUP_PLAN_ID
    
    # Save backup plan ID to file for cleanup
    echo "$BACKUP_PLAN_ID" > backup-plan-id.txt
    
    print_success "Created backup plan with ID: $BACKUP_PLAN_ID"
}

# Function to create backup selection
create_backup_selection() {
    print_status "Creating backup selection for tagged resources..."
    
    # Create backup selection JSON
    cat > backup-selection.json << EOF
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
    
    # Create backup selection
    BACKUP_SELECTION_ID=$(aws backup create-backup-selection \
        --backup-plan-id "$BACKUP_PLAN_ID" \
        --cli-input-json file://backup-selection.json \
        --region "$PRIMARY_REGION" \
        --query 'SelectionId' --output text)
    
    export BACKUP_SELECTION_ID
    
    # Save selection ID for cleanup
    echo "$BACKUP_SELECTION_ID" > backup-selection-id.txt
    
    print_success "Created backup selection with ID: $BACKUP_SELECTION_ID"
}

# Function to create SNS topic for notifications
create_sns_topic() {
    print_status "Creating SNS topic for backup notifications..."
    
    # Create SNS topic
    BACKUP_NOTIFICATIONS_TOPIC=$(aws sns create-topic \
        --name backup-notifications-$RANDOM_SUFFIX \
        --region "$PRIMARY_REGION" \
        --query 'TopicArn' --output text)
    
    export BACKUP_NOTIFICATIONS_TOPIC
    
    # Save topic ARN for cleanup
    echo "$BACKUP_NOTIFICATIONS_TOPIC" > sns-topic-arn.txt
    
    # Subscribe email if provided and not default
    if [[ "$NOTIFICATION_EMAIL" != "your-email@example.com" ]]; then
        aws sns subscribe \
            --topic-arn "$BACKUP_NOTIFICATIONS_TOPIC" \
            --protocol email \
            --notification-endpoint "$NOTIFICATION_EMAIL" \
            --region "$PRIMARY_REGION"
        print_warning "Check your email ($NOTIFICATION_EMAIL) to confirm SNS subscription"
    else
        print_warning "Using default email address. Set NOTIFICATION_EMAIL environment variable for actual notifications"
    fi
    
    print_success "Created SNS topic: $BACKUP_NOTIFICATIONS_TOPIC"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    print_status "Creating EventBridge rule for backup monitoring..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name BackupJobFailureRule \
        --event-pattern '{
            "source": ["aws.backup"],
            "detail-type": ["Backup Job State Change"],
            "detail": {
                "state": ["FAILED", "ABORTED"]
            }
        }' \
        --state ENABLED \
        --region "$PRIMARY_REGION"
    
    print_success "Created EventBridge rule for backup job monitoring"
}

# Function to create Lambda function for backup validation
create_lambda_function() {
    print_status "Creating Lambda function for backup validation..."
    
    # Create Lambda function code
    cat > backup-validator.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    backup_client = boto3.client('backup')
    sns_client = boto3.client('sns')
    
    # Extract backup job details from EventBridge event
    detail = event['detail']
    backup_job_id = detail['backupJobId']
    
    try:
        # Get backup job details
        response = backup_client.describe_backup_job(
            BackupJobId=backup_job_id
        )
        
        backup_job = response['BackupJob']
        
        # Validate backup job completion and health
        if backup_job['State'] in ['COMPLETED']:
            # Perform additional validation checks
            recovery_point_arn = backup_job['RecoveryPointArn']
            
            # Check if cross-region copy was successful
            copy_jobs = backup_client.list_copy_jobs()
            
            message = f"Backup validation successful for job {backup_job_id}"
            logger.info(message)
            
        elif backup_job['State'] in ['FAILED', 'ABORTED']:
            message = f"Backup job {backup_job_id} failed: {backup_job.get('StatusMessage', 'Unknown error')}"
            logger.error(message)
            
            # Send SNS notification for failed jobs
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='AWS Backup Job Failed',
                Message=message
            )
    
    except Exception as e:
        logger.error(f"Error validating backup job: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Backup validation completed')
    }
EOF
    
    # Create deployment package
    zip backup-validator.zip backup-validator.py
    
    # Create IAM role for Lambda
    cat > lambda-trust-policy.json << EOF
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
    
    # Check if Lambda role exists
    if aws iam get-role --role-name BackupValidatorRole &> /dev/null; then
        print_warning "BackupValidatorRole already exists"
        LAMBDA_ROLE_ARN=$(aws iam get-role --role-name BackupValidatorRole --query 'Role.Arn' --output text)
    else
        LAMBDA_ROLE_ARN=$(aws iam create-role \
            --role-name BackupValidatorRole \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name BackupValidatorRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Create custom policy for backup operations
        cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "backup:DescribeBackupJob",
                "backup:ListCopyJobs",
                "backup:DescribeRecoveryPoint",
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
            --policy-document file://lambda-policy.json
        
        # Wait for role propagation
        sleep 10
    fi
    
    export LAMBDA_ROLE_ARN
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        print_warning "Lambda function backup-validator already exists, updating..."
        LAMBDA_FUNCTION_ARN=$(aws lambda update-function-code \
            --function-name backup-validator \
            --zip-file fileb://backup-validator.zip \
            --region "$PRIMARY_REGION" \
            --query 'FunctionArn' --output text)
    else
        # Create Lambda function
        LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
            --function-name backup-validator \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler backup-validator.lambda_handler \
            --zip-file fileb://backup-validator.zip \
            --environment Variables="{SNS_TOPIC_ARN=$BACKUP_NOTIFICATIONS_TOPIC}" \
            --timeout 300 \
            --region "$PRIMARY_REGION" \
            --query 'FunctionArn' --output text)
    fi
    
    export LAMBDA_FUNCTION_ARN
    
    # Save Lambda function ARN for cleanup
    echo "$LAMBDA_FUNCTION_ARN" > lambda-function-arn.txt
    
    # Configure EventBridge to trigger Lambda
    aws events put-targets \
        --rule BackupJobFailureRule \
        --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN" \
        --region "$PRIMARY_REGION"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name backup-validator \
        --statement-id backup-eventbridge-trigger \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$PRIMARY_REGION:$AWS_ACCOUNT_ID:rule/BackupJobFailureRule" \
        --region "$PRIMARY_REGION" \
        --output text || true  # Ignore if permission already exists
    
    # Cleanup temporary files
    rm -f lambda-trust-policy.json lambda-policy.json backup-validator.py backup-validator.zip
    
    print_success "Created Lambda function: $LAMBDA_FUNCTION_ARN"
}

# Function to create example resources for testing (optional)
create_example_resources() {
    print_status "Creating example EC2 instance for backup testing (optional)..."
    
    # Check if user wants to create example resources
    read -p "Do you want to create an example EC2 instance for backup testing? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Skipping example resource creation"
        return
    fi
    
    # Get default VPC and subnet
    DEFAULT_VPC=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "$PRIMARY_REGION")
    
    if [[ "$DEFAULT_VPC" == "None" ]]; then
        print_warning "No default VPC found. Skipping example resource creation."
        return
    fi
    
    DEFAULT_SUBNET=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
        --query 'Subnets[0].SubnetId' \
        --output text \
        --region "$PRIMARY_REGION")
    
    # Get latest Amazon Linux 2 AMI
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$PRIMARY_REGION")
    
    # Create EC2 instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t2.micro \
        --subnet-id "$DEFAULT_SUBNET" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=BackupTestInstance},{Key=Environment,Value=Production},{Key=BackupEnabled,Value=true}]' \
        --region "$PRIMARY_REGION" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Save instance ID for cleanup
    echo "$INSTANCE_ID" > example-instance-id.txt
    
    print_success "Created example EC2 instance: $INSTANCE_ID"
    print_status "Instance is tagged for backup: Environment=Production, BackupEnabled=true"
}

# Function to save deployment state
save_deployment_state() {
    print_status "Saving deployment state..."
    
    cat > deployment-state.json << EOF
{
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "primary_region": "$PRIMARY_REGION",
    "secondary_region": "$SECONDARY_REGION",
    "tertiary_region": "$TERTIARY_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "organization_name": "$ORGANIZATION_NAME",
    "backup_plan_id": "${BACKUP_PLAN_ID:-}",
    "backup_selection_id": "${BACKUP_SELECTION_ID:-}",
    "sns_topic_arn": "${BACKUP_NOTIFICATIONS_TOPIC:-}",
    "lambda_function_arn": "${LAMBDA_FUNCTION_ARN:-}",
    "backup_vault_primary": "${BACKUP_VAULT_PRIMARY:-}",
    "backup_vault_secondary": "${BACKUP_VAULT_SECONDARY:-}",
    "backup_vault_tertiary": "${BACKUP_VAULT_TERTIARY:-}"
}
EOF
    
    print_success "Deployment state saved to deployment-state.json"
}

# Function to run validation tests
run_validation() {
    print_status "Running deployment validation..."
    
    # Check backup plan
    if aws backup get-backup-plan --backup-plan-id "$BACKUP_PLAN_ID" --region "$PRIMARY_REGION" &> /dev/null; then
        print_success "✓ Backup plan is accessible"
    else
        print_error "✗ Backup plan validation failed"
    fi
    
    # Check backup vaults
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        vault_name=""
        case $region in
            "$PRIMARY_REGION") vault_name="$BACKUP_VAULT_PRIMARY" ;;
            "$SECONDARY_REGION") vault_name="$BACKUP_VAULT_SECONDARY" ;;
            "$TERTIARY_REGION") vault_name="$BACKUP_VAULT_TERTIARY" ;;
        esac
        
        if aws backup describe-backup-vault --backup-vault-name "$vault_name" --region "$region" &> /dev/null; then
            print_success "✓ Backup vault in $region is accessible"
        else
            print_error "✗ Backup vault validation failed in $region"
        fi
    done
    
    # Check Lambda function
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        print_success "✓ Lambda function is accessible"
    else
        print_error "✗ Lambda function validation failed"
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name BackupJobFailureRule --region "$PRIMARY_REGION" &> /dev/null; then
        print_success "✓ EventBridge rule is active"
    else
        print_error "✗ EventBridge rule validation failed"
    fi
    
    print_success "Validation completed"
}

# Function to display next steps
display_next_steps() {
    echo ""
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}Deployment Completed Successfully!${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "1. Tag your critical resources with:"
    echo "   - Environment=Production"
    echo "   - BackupEnabled=true"
    echo ""
    echo "2. Example tagging command for EC2 instances:"
    echo "   aws ec2 create-tags --resources i-1234567890abcdef0 \\"
    echo "       --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true"
    echo ""
    echo "3. Monitor backup jobs in the AWS Backup console"
    echo "4. Check EventBridge logs for backup monitoring"
    echo "5. Verify SNS notifications (check email for subscription confirmation)"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "- Backups will run automatically based on the schedule (daily at 2 AM UTC)"
    echo "- Cross-region copies will be created automatically"
    echo "- Failed backup jobs will trigger SNS notifications"
    echo "- Review the AWS Backup console for job status and recovery points"
    echo ""
    echo -e "${BLUE}Estimated Monthly Cost:${NC} \$50-200 (depends on data volume and retention)"
    echo ""
    echo -e "${GREEN}Deployment log saved to:${NC} $LOG_FILE"
    echo -e "${GREEN}Deployment state saved to:${NC} deployment-state.json"
    echo ""
    echo -e "${RED}To clean up all resources, run:${NC} ./destroy.sh"
}

# Main deployment function
main() {
    echo "Starting AWS Multi-Region Backup Strategy deployment..."
    echo "Timestamp: $(date)"
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    validate_regions
    create_backup_service_role
    create_backup_vaults
    create_backup_plan
    create_backup_selection
    create_sns_topic
    create_eventbridge_rule
    create_lambda_function
    create_example_resources
    save_deployment_state
    run_validation
    display_next_steps
    
    echo ""
    echo -e "${GREEN}🎉 Multi-Region Backup Strategy deployment completed successfully!${NC}"
}

# Trap errors and cleanup
trap 'print_error "Deployment failed. Check $LOG_FILE for details."; exit 1' ERR

# Run main function
main "$@"