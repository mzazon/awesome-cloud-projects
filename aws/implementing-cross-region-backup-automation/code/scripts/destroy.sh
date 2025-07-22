#!/bin/bash

# Multi-Region Backup Strategies using AWS Backup - Cleanup Script
# This script safely removes all resources created by the multi-region backup deployment
# with proper dependency handling and confirmation prompts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="destroy_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo -e "${RED}===========================================${NC}"
echo -e "${RED}AWS Multi-Region Backup Strategy Cleanup${NC}"
echo -e "${RED}===========================================${NC}"
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
    print_status "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
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
    
    print_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    print_status "Loading deployment state..."
    
    if [[ ! -f "deployment-state.json" ]]; then
        print_warning "deployment-state.json not found. Will attempt cleanup using environment variables and discovery."
        
        # Use environment variables or defaults
        export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
        export SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
        export TERTIARY_REGION="${TERTIARY_REGION:-eu-west-1}"
        export ORGANIZATION_NAME="${ORGANIZATION_NAME:-YourOrg}"
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to discover resources
        discover_resources
    else
        # Load from deployment state
        export PRIMARY_REGION=$(jq -r '.primary_region' deployment-state.json)
        export SECONDARY_REGION=$(jq -r '.secondary_region' deployment-state.json)
        export TERTIARY_REGION=$(jq -r '.tertiary_region' deployment-state.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-state.json)
        export ORGANIZATION_NAME=$(jq -r '.organization_name' deployment-state.json)
        export BACKUP_PLAN_ID=$(jq -r '.backup_plan_id' deployment-state.json)
        export BACKUP_SELECTION_ID=$(jq -r '.backup_selection_id' deployment-state.json)
        export SNS_TOPIC_ARN=$(jq -r '.sns_topic_arn' deployment-state.json)
        export LAMBDA_FUNCTION_ARN=$(jq -r '.lambda_function_arn' deployment-state.json)
        export BACKUP_VAULT_PRIMARY=$(jq -r '.backup_vault_primary' deployment-state.json)
        export BACKUP_VAULT_SECONDARY=$(jq -r '.backup_vault_secondary' deployment-state.json)
        export BACKUP_VAULT_TERTIARY=$(jq -r '.backup_vault_tertiary' deployment-state.json)
        
        print_success "Loaded deployment state from deployment-state.json"
    fi
    
    # Load individual resource IDs from files if they exist
    if [[ -f "backup-plan-id.txt" ]]; then
        export BACKUP_PLAN_ID=$(cat backup-plan-id.txt)
    fi
    
    if [[ -f "backup-selection-id.txt" ]]; then
        export BACKUP_SELECTION_ID=$(cat backup-selection-id.txt)
    fi
    
    if [[ -f "sns-topic-arn.txt" ]]; then
        export SNS_TOPIC_ARN=$(cat sns-topic-arn.txt)
    fi
    
    if [[ -f "lambda-function-arn.txt" ]]; then
        export LAMBDA_FUNCTION_ARN=$(cat lambda-function-arn.txt)
    fi
    
    print_status "Configuration loaded:"
    print_status "  Primary Region: $PRIMARY_REGION"
    print_status "  Secondary Region: $SECONDARY_REGION"
    print_status "  Tertiary Region: $TERTIARY_REGION"
    print_status "  Organization Name: $ORGANIZATION_NAME"
    print_status "  AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to discover resources if deployment state is missing
discover_resources() {
    print_status "Discovering deployed resources..."
    
    # Set default vault names
    export BACKUP_VAULT_PRIMARY="${ORGANIZATION_NAME}-primary-vault"
    export BACKUP_VAULT_SECONDARY="${ORGANIZATION_NAME}-secondary-vault"
    export BACKUP_VAULT_TERTIARY="${ORGANIZATION_NAME}-tertiary-vault"
    
    # Try to find backup plan
    BACKUP_PLANS=$(aws backup list-backup-plans --region "$PRIMARY_REGION" --query 'BackupPlansList[?BackupPlanName==`MultiRegionBackupPlan`].BackupPlanId' --output text)
    if [[ -n "$BACKUP_PLANS" ]]; then
        export BACKUP_PLAN_ID="$BACKUP_PLANS"
        print_status "Discovered backup plan: $BACKUP_PLAN_ID"
    fi
    
    # Try to find SNS topic
    SNS_TOPICS=$(aws sns list-topics --region "$PRIMARY_REGION" --query 'Topics[?contains(TopicArn, `backup-notifications`)].TopicArn' --output text)
    if [[ -n "$SNS_TOPICS" ]]; then
        export SNS_TOPIC_ARN="$SNS_TOPICS"
        print_status "Discovered SNS topic: $SNS_TOPIC_ARN"
    fi
    
    # Try to find Lambda function
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        export LAMBDA_FUNCTION_ARN=$(aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" --query 'Configuration.FunctionArn' --output text)
        print_status "Discovered Lambda function: $LAMBDA_FUNCTION_ARN"
    fi
    
    print_success "Resource discovery completed"
}

# Function to display confirmation prompt
confirm_destruction() {
    echo ""
    echo -e "${RED}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo ""
    echo "1. AWS Backup Plans and Selections"
    echo "2. Backup Vaults in multiple regions (if empty)"
    echo "3. All Recovery Points (backups) in the vaults"
    echo "4. EventBridge Rules and Targets"
    echo "5. Lambda Functions for backup validation"
    echo "6. SNS Topics and Subscriptions"
    echo "7. IAM Roles and Policies"
    echo "8. Example EC2 instances (if created)"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    # Check for recovery points
    check_recovery_points
    
    read -p "Are you sure you want to proceed with the cleanup? Type 'yes' to continue: " -r
    if [[ ! $REPLY == "yes" ]]; then
        print_status "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    print_status "Proceeding with resource cleanup..."
}

# Function to check for existing recovery points
check_recovery_points() {
    print_status "Checking for existing recovery points..."
    
    local has_recovery_points=false
    
    # Check each region for recovery points
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        vault_name=""
        case $region in
            "$PRIMARY_REGION") vault_name="$BACKUP_VAULT_PRIMARY" ;;
            "$SECONDARY_REGION") vault_name="$BACKUP_VAULT_SECONDARY" ;;
            "$TERTIARY_REGION") vault_name="$BACKUP_VAULT_TERTIARY" ;;
        esac
        
        if [[ -n "$vault_name" ]] && aws backup describe-backup-vault --backup-vault-name "$vault_name" --region "$region" &> /dev/null; then
            local recovery_points=$(aws backup list-recovery-points-by-backup-vault \
                --backup-vault-name "$vault_name" \
                --region "$region" \
                --query 'RecoveryPoints | length(@)' \
                --output text 2>/dev/null || echo "0")
            
            if [[ "$recovery_points" -gt 0 ]]; then
                print_warning "Found $recovery_points recovery points in $vault_name ($region)"
                has_recovery_points=true
            fi
        fi
    done
    
    if [[ "$has_recovery_points" == "true" ]]; then
        echo ""
        print_warning "Recovery points (backups) exist in your backup vaults."
        print_warning "These will be permanently deleted during cleanup."
        echo ""
    fi
}

# Function to delete backup selections and plans
delete_backup_resources() {
    print_status "Deleting backup selections and plans..."
    
    if [[ -n "${BACKUP_PLAN_ID:-}" ]]; then
        # Get and delete backup selections
        if [[ -n "${BACKUP_SELECTION_ID:-}" ]]; then
            print_status "Deleting backup selection: $BACKUP_SELECTION_ID"
            aws backup delete-backup-selection \
                --backup-plan-id "$BACKUP_PLAN_ID" \
                --selection-id "$BACKUP_SELECTION_ID" \
                --region "$PRIMARY_REGION" || print_warning "Failed to delete backup selection"
            print_success "Deleted backup selection"
        else
            # Try to find and delete all selections for the plan
            SELECTIONS=$(aws backup list-backup-selections \
                --backup-plan-id "$BACKUP_PLAN_ID" \
                --region "$PRIMARY_REGION" \
                --query 'BackupSelectionsList[].SelectionId' \
                --output text)
            
            for selection_id in $SELECTIONS; do
                print_status "Deleting backup selection: $selection_id"
                aws backup delete-backup-selection \
                    --backup-plan-id "$BACKUP_PLAN_ID" \
                    --selection-id "$selection_id" \
                    --region "$PRIMARY_REGION" || print_warning "Failed to delete backup selection $selection_id"
            done
        fi
        
        # Delete backup plan
        print_status "Deleting backup plan: $BACKUP_PLAN_ID"
        aws backup delete-backup-plan \
            --backup-plan-id "$BACKUP_PLAN_ID" \
            --region "$PRIMARY_REGION" || print_warning "Failed to delete backup plan"
        print_success "Deleted backup plan"
    else
        print_warning "No backup plan ID found, skipping backup plan deletion"
    fi
}

# Function to delete recovery points
delete_recovery_points() {
    print_status "Deleting recovery points from backup vaults..."
    
    # Delete recovery points in each region
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        vault_name=""
        case $region in
            "$PRIMARY_REGION") vault_name="$BACKUP_VAULT_PRIMARY" ;;
            "$SECONDARY_REGION") vault_name="$BACKUP_VAULT_SECONDARY" ;;
            "$TERTIARY_REGION") vault_name="$BACKUP_VAULT_TERTIARY" ;;
        esac
        
        if [[ -n "$vault_name" ]] && aws backup describe-backup-vault --backup-vault-name "$vault_name" --region "$region" &> /dev/null; then
            print_status "Deleting recovery points in $vault_name ($region)..."
            
            # Get all recovery points
            RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
                --backup-vault-name "$vault_name" \
                --region "$region" \
                --query 'RecoveryPoints[].RecoveryPointArn' \
                --output text)
            
            for recovery_point in $RECOVERY_POINTS; do
                if [[ -n "$recovery_point" && "$recovery_point" != "None" ]]; then
                    print_status "Deleting recovery point: $(basename "$recovery_point")"
                    aws backup delete-recovery-point \
                        --backup-vault-name "$vault_name" \
                        --recovery-point-arn "$recovery_point" \
                        --region "$region" || print_warning "Failed to delete recovery point $(basename "$recovery_point")"
                fi
            done
            
            print_success "Completed recovery point deletion in $region"
        fi
    done
    
    # Wait for recovery point deletions to complete
    print_status "Waiting for recovery point deletions to complete..."
    sleep 30
}

# Function to delete EventBridge rules and targets
delete_eventbridge_resources() {
    print_status "Deleting EventBridge rules and targets..."
    
    # Remove targets from EventBridge rule
    if aws events describe-rule --name BackupJobFailureRule --region "$PRIMARY_REGION" &> /dev/null; then
        print_status "Removing targets from EventBridge rule..."
        aws events remove-targets \
            --rule BackupJobFailureRule \
            --ids "1" \
            --region "$PRIMARY_REGION" || print_warning "Failed to remove EventBridge targets"
        
        # Delete EventBridge rule
        print_status "Deleting EventBridge rule..."
        aws events delete-rule \
            --name BackupJobFailureRule \
            --region "$PRIMARY_REGION" || print_warning "Failed to delete EventBridge rule"
        
        print_success "Deleted EventBridge resources"
    else
        print_warning "EventBridge rule BackupJobFailureRule not found"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    print_status "Deleting Lambda function and resources..."
    
    # Remove Lambda permissions
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        print_status "Removing Lambda permissions..."
        aws lambda remove-permission \
            --function-name backup-validator \
            --statement-id backup-eventbridge-trigger \
            --region "$PRIMARY_REGION" || print_warning "Failed to remove Lambda permission"
        
        # Delete Lambda function
        print_status "Deleting Lambda function..."
        aws lambda delete-function \
            --function-name backup-validator \
            --region "$PRIMARY_REGION" || print_warning "Failed to delete Lambda function"
        
        print_success "Deleted Lambda function"
    else
        print_warning "Lambda function backup-validator not found"
    fi
}

# Function to delete SNS topic and subscriptions
delete_sns_resources() {
    print_status "Deleting SNS topic and subscriptions..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        print_status "Deleting SNS topic: $SNS_TOPIC_ARN"
        aws sns delete-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --region "$PRIMARY_REGION" || print_warning "Failed to delete SNS topic"
        print_success "Deleted SNS topic"
    else
        print_warning "No SNS topic ARN found, attempting to find and delete backup notification topics"
        
        # Try to find and delete backup notification topics
        SNS_TOPICS=$(aws sns list-topics --region "$PRIMARY_REGION" --query 'Topics[?contains(TopicArn, `backup-notifications`)].TopicArn' --output text)
        for topic in $SNS_TOPICS; do
            if [[ -n "$topic" ]]; then
                print_status "Deleting discovered SNS topic: $topic"
                aws sns delete-topic --topic-arn "$topic" --region "$PRIMARY_REGION" || print_warning "Failed to delete SNS topic $topic"
            fi
        done
    fi
}

# Function to delete backup vaults
delete_backup_vaults() {
    print_status "Deleting backup vaults..."
    
    # Wait a bit more for recovery point deletions to propagate
    print_status "Waiting for recovery point deletions to fully propagate..."
    sleep 60
    
    # Delete backup vaults in each region (will fail if recovery points still exist)
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        vault_name=""
        case $region in
            "$PRIMARY_REGION") vault_name="$BACKUP_VAULT_PRIMARY" ;;
            "$SECONDARY_REGION") vault_name="$BACKUP_VAULT_SECONDARY" ;;
            "$TERTIARY_REGION") vault_name="$BACKUP_VAULT_TERTIARY" ;;
        esac
        
        if [[ -n "$vault_name" ]] && aws backup describe-backup-vault --backup-vault-name "$vault_name" --region "$region" &> /dev/null; then
            print_status "Deleting backup vault: $vault_name in $region"
            
            # Check if vault still has recovery points
            recovery_count=$(aws backup list-recovery-points-by-backup-vault \
                --backup-vault-name "$vault_name" \
                --region "$region" \
                --query 'RecoveryPoints | length(@)' \
                --output text 2>/dev/null || echo "0")
            
            if [[ "$recovery_count" -gt 0 ]]; then
                print_warning "Backup vault $vault_name still contains $recovery_count recovery points. Skipping deletion."
                print_warning "You may need to wait longer for recovery point deletions to complete, then manually delete the vault."
            else
                aws backup delete-backup-vault \
                    --backup-vault-name "$vault_name" \
                    --region "$region" || print_warning "Failed to delete backup vault $vault_name in $region"
                print_success "Deleted backup vault: $vault_name in $region"
            fi
        else
            print_warning "Backup vault $vault_name not found in $region"
        fi
    done
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    print_status "Deleting IAM roles and policies..."
    
    # Clean up AWS Backup service role
    if aws iam get-role --role-name AWSBackupServiceRole &> /dev/null; then
        print_status "Cleaning up AWSBackupServiceRole..."
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name AWSBackupServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup || print_warning "Failed to detach backup policy"
        
        aws iam detach-role-policy \
            --role-name AWSBackupServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores || print_warning "Failed to detach restore policy"
        
        # Delete role
        aws iam delete-role --role-name AWSBackupServiceRole || print_warning "Failed to delete AWSBackupServiceRole"
        print_success "Deleted AWSBackupServiceRole"
    else
        print_warning "AWSBackupServiceRole not found"
    fi
    
    # Clean up Lambda role
    if aws iam get-role --role-name BackupValidatorRole &> /dev/null; then
        print_status "Cleaning up BackupValidatorRole..."
        
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name BackupValidatorRole \
            --policy-name BackupValidatorPolicy || print_warning "Failed to delete inline policy"
        
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name BackupValidatorRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || print_warning "Failed to detach Lambda basic execution policy"
        
        # Delete role
        aws iam delete-role --role-name BackupValidatorRole || print_warning "Failed to delete BackupValidatorRole"
        print_success "Deleted BackupValidatorRole"
    else
        print_warning "BackupValidatorRole not found"
    fi
}

# Function to delete example resources
delete_example_resources() {
    print_status "Deleting example resources..."
    
    if [[ -f "example-instance-id.txt" ]]; then
        INSTANCE_ID=$(cat example-instance-id.txt)
        if [[ -n "$INSTANCE_ID" ]]; then
            print_status "Terminating example EC2 instance: $INSTANCE_ID"
            aws ec2 terminate-instances \
                --instance-ids "$INSTANCE_ID" \
                --region "$PRIMARY_REGION" || print_warning "Failed to terminate instance $INSTANCE_ID"
            print_success "Initiated termination of example EC2 instance"
        fi
    else
        # Try to find and delete tagged test instances
        TEST_INSTANCES=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=BackupTestInstance" "Name=instance-state-name,Values=running,stopped" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text \
            --region "$PRIMARY_REGION")
        
        for instance in $TEST_INSTANCES; do
            if [[ -n "$instance" && "$instance" != "None" ]]; then
                print_status "Terminating discovered test instance: $instance"
                aws ec2 terminate-instances \
                    --instance-ids "$instance" \
                    --region "$PRIMARY_REGION" || print_warning "Failed to terminate instance $instance"
            fi
        done
    fi
}

# Function to cleanup temporary files
cleanup_temporary_files() {
    print_status "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    rm -f multi-region-backup-plan.json
    rm -f backup-selection.json
    rm -f backup-plan-id.txt
    rm -f backup-selection-id.txt
    rm -f sns-topic-arn.txt
    rm -f lambda-function-arn.txt
    rm -f example-instance-id.txt
    rm -f deployment-state.json
    
    print_success "Cleaned up temporary files"
}

# Function to run final validation
run_final_validation() {
    print_status "Running final validation..."
    
    local cleanup_issues=false
    
    # Check if backup plan still exists
    if [[ -n "${BACKUP_PLAN_ID:-}" ]] && aws backup get-backup-plan --backup-plan-id "$BACKUP_PLAN_ID" --region "$PRIMARY_REGION" &> /dev/null; then
        print_warning "⚠️  Backup plan still exists: $BACKUP_PLAN_ID"
        cleanup_issues=true
    else
        print_success "✓ Backup plan successfully deleted"
    fi
    
    # Check backup vaults
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        vault_name=""
        case $region in
            "$PRIMARY_REGION") vault_name="$BACKUP_VAULT_PRIMARY" ;;
            "$SECONDARY_REGION") vault_name="$BACKUP_VAULT_SECONDARY" ;;
            "$TERTIARY_REGION") vault_name="$BACKUP_VAULT_TERTIARY" ;;
        esac
        
        if [[ -n "$vault_name" ]] && aws backup describe-backup-vault --backup-vault-name "$vault_name" --region "$region" &> /dev/null; then
            print_warning "⚠️  Backup vault still exists: $vault_name in $region"
            cleanup_issues=true
        else
            print_success "✓ Backup vault successfully deleted in $region"
        fi
    done
    
    # Check Lambda function
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        print_warning "⚠️  Lambda function still exists: backup-validator"
        cleanup_issues=true
    else
        print_success "✓ Lambda function successfully deleted"
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name BackupJobFailureRule --region "$PRIMARY_REGION" &> /dev/null; then
        print_warning "⚠️  EventBridge rule still exists: BackupJobFailureRule"
        cleanup_issues=true
    else
        print_success "✓ EventBridge rule successfully deleted"
    fi
    
    if [[ "$cleanup_issues" == "true" ]]; then
        print_warning "Some resources may still exist. Please check the AWS console and manually delete any remaining resources."
    else
        print_success "All resources successfully cleaned up!"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${GREEN}Cleanup Process Completed${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo ""
    echo -e "${BLUE}Resources Processed:${NC}"
    echo "✓ Backup Plans and Selections"
    echo "✓ Recovery Points (backups)"
    echo "✓ Backup Vaults (if empty)"
    echo "✓ EventBridge Rules and Targets"
    echo "✓ Lambda Functions"
    echo "✓ SNS Topics and Subscriptions"
    echo "✓ IAM Roles and Policies"
    echo "✓ Example EC2 instances"
    echo "✓ Temporary files"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "- Backup vaults may take time to delete if recovery points are still being processed"
    echo "- Check the AWS console to verify all resources have been removed"
    echo "- Some IAM roles may have been used by other services and might remain"
    echo ""
    echo -e "${GREEN}Cleanup log saved to:${NC} $LOG_FILE"
    echo ""
    echo -e "${GREEN}🎉 Multi-Region Backup Strategy cleanup completed!${NC}"
}

# Main cleanup function
main() {
    echo "Starting AWS Multi-Region Backup Strategy cleanup..."
    echo "Timestamp: $(date)"
    echo ""
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_destruction
    delete_backup_resources
    delete_recovery_points
    delete_eventbridge_resources
    delete_lambda_function
    delete_sns_resources
    delete_backup_vaults
    delete_iam_resources
    delete_example_resources
    cleanup_temporary_files
    run_final_validation
    display_cleanup_summary
    
    echo ""
    echo -e "${GREEN}🧹 Multi-Region Backup Strategy cleanup process completed!${NC}"
}

# Trap errors
trap 'print_error "Cleanup encountered an error. Check $LOG_FILE for details."; exit 1' ERR

# Run main function
main "$@"