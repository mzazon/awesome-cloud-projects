#!/bin/bash

# deploy.sh - Deploy AWS Systems Manager Automated Patching Infrastructure
# Recipe: Automated Patching with Systems Manager

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Remove any temporary files
    if [[ -f "maintenance-window-trust-policy.json" ]]; then
        rm -f maintenance-window-trust-policy.json
    fi
    
    # Note: For full cleanup, run destroy.sh
    warn "Run ./destroy.sh to remove any partially created resources"
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if user has required permissions
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "$account_id" ]]; then
        error "Cannot retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    # Check if Systems Manager is available in the region
    local region
    region=$(aws configure get region 2>/dev/null || echo "")
    if [[ -z "$region" ]]; then
        error "AWS region is not configured. Please set your region."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Export resource names
    export PATCH_BASELINE_NAME="custom-baseline-${RANDOM_SUFFIX}"
    export MAINTENANCE_WINDOW_NAME="patch-window-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="patch-reports-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="patch-notifications-${RANDOM_SUFFIX}"
    export ROLE_NAME="MaintenanceWindowRole-${RANDOM_SUFFIX}"
    export ALARM_NAME="PatchComplianceAlarm-${RANDOM_SUFFIX}"
    export SCAN_WINDOW_NAME="scan-window-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PATCH_BASELINE_NAME=${PATCH_BASELINE_NAME}
MAINTENANCE_WINDOW_NAME=${MAINTENANCE_WINDOW_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
ROLE_NAME=${ROLE_NAME}
ALARM_NAME=${ALARM_NAME}
SCAN_WINDOW_NAME=${SCAN_WINDOW_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Resource suffix: ${RANDOM_SUFFIX}"
}

# Create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create S3 bucket for patch reports
    execute_command "aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}" \
        "Creating S3 bucket for patch reports"
    
    # Create SNS topic for notifications
    execute_command "aws sns create-topic --name ${SNS_TOPIC_NAME} --region ${AWS_REGION}" \
        "Creating SNS topic for notifications"
    
    # Get SNS topic ARN
    if [[ "$DRY_RUN" != "true" ]]; then
        export SNS_TOPIC_ARN=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text)
        echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> .env
    fi
    
    success "Foundational resources created"
}

# Create custom patch baseline
create_patch_baseline() {
    log "Creating custom patch baseline..."
    
    local approval_rules='[{
        "PatchRules": [{
            "PatchFilterGroup": {
                "PatchFilters": [{
                    "Key": "CLASSIFICATION",
                    "Values": ["Security", "Bugfix", "Critical"]
                }]
            },
            "ApproveAfterDays": 7,
            "ComplianceLevel": "CRITICAL"
        }]
    }]'
    
    execute_command "aws ssm create-patch-baseline \
        --name ${PATCH_BASELINE_NAME} \
        --description 'Custom patch baseline for production instances' \
        --operating-system AMAZON_LINUX_2 \
        --approval-rules Rules='${approval_rules}' \
        --approved-patches-compliance-level CRITICAL" \
        "Creating custom patch baseline"
    
    # Store the baseline ID
    if [[ "$DRY_RUN" != "true" ]]; then
        export PATCH_BASELINE_ID=$(aws ssm describe-patch-baselines \
            --filters "Key=Name,Values=${PATCH_BASELINE_NAME}" \
            --query "BaselineIdentities[0].BaselineId" \
            --output text)
        echo "PATCH_BASELINE_ID=${PATCH_BASELINE_ID}" >> .env
        success "Created patch baseline: ${PATCH_BASELINE_ID}"
    else
        success "Would create patch baseline: ${PATCH_BASELINE_NAME}"
    fi
}

# Create IAM role for maintenance window
create_iam_role() {
    log "Creating IAM role for maintenance window..."
    
    # Create trust policy
    cat > maintenance-window-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ssm.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the IAM role
    execute_command "aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file://maintenance-window-trust-policy.json" \
        "Creating IAM role for maintenance window"
    
    # Attach required policies
    execute_command "aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole" \
        "Attaching Systems Manager policy to role"
    
    # Get the role ARN
    if [[ "$DRY_RUN" != "true" ]]; then
        export MW_ROLE_ARN=$(aws iam get-role \
            --role-name ${ROLE_NAME} \
            --query "Role.Arn" --output text)
        echo "MW_ROLE_ARN=${MW_ROLE_ARN}" >> .env
        success "Created IAM role: ${MW_ROLE_ARN}"
    else
        success "Would create IAM role: ${ROLE_NAME}"
    fi
    
    # Wait for role to be available
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Waiting for IAM role to become available..."
        sleep 10
    fi
}

# Create maintenance window
create_maintenance_window() {
    log "Creating maintenance window..."
    
    execute_command "aws ssm create-maintenance-window \
        --name ${MAINTENANCE_WINDOW_NAME} \
        --description 'Weekly patching maintenance window' \
        --schedule 'cron(0 2 ? * SUN *)' \
        --duration 4 \
        --cutoff 1 \
        --schedule-timezone 'UTC' \
        --allow-unassociated-targets" \
        "Creating maintenance window"
    
    # Store the maintenance window ID
    if [[ "$DRY_RUN" != "true" ]]; then
        export MAINTENANCE_WINDOW_ID=$(aws ssm describe-maintenance-windows \
            --filters "Key=Name,Values=${MAINTENANCE_WINDOW_NAME}" \
            --query "WindowIdentities[0].WindowId" \
            --output text)
        echo "MAINTENANCE_WINDOW_ID=${MAINTENANCE_WINDOW_ID}" >> .env
        success "Created maintenance window: ${MAINTENANCE_WINDOW_ID}"
    else
        success "Would create maintenance window: ${MAINTENANCE_WINDOW_NAME}"
    fi
}

# Register maintenance window targets
register_targets() {
    log "Registering maintenance window targets..."
    
    execute_command "aws ssm register-target-with-maintenance-window \
        --window-id ${MAINTENANCE_WINDOW_ID} \
        --target-type Instance \
        --targets Key=tag:Environment,Values=Production \
        --resource-type INSTANCE \
        --name 'ProductionInstances'" \
        "Registering EC2 instances as targets"
    
    # Store the target ID
    if [[ "$DRY_RUN" != "true" ]]; then
        export TARGET_ID=$(aws ssm describe-maintenance-window-targets \
            --window-id ${MAINTENANCE_WINDOW_ID} \
            --query "Targets[0].WindowTargetId" \
            --output text)
        echo "TARGET_ID=${TARGET_ID}" >> .env
        success "Registered targets: ${TARGET_ID}"
    else
        success "Would register targets for maintenance window"
    fi
}

# Register patch management task
register_patch_task() {
    log "Registering patch management task..."
    
    local task_parameters='{
        "BaselineOverride": ["'${PATCH_BASELINE_ID}'"],
        "Operation": ["Install"]
    }'
    
    execute_command "aws ssm register-task-with-maintenance-window \
        --window-id ${MAINTENANCE_WINDOW_ID} \
        --target-type Instance \
        --targets Key=WindowTargetIds,Values=${TARGET_ID} \
        --task-type RUN_COMMAND \
        --task-arn 'AWS-RunPatchBaseline' \
        --service-role-arn ${MW_ROLE_ARN} \
        --name 'PatchingTask' \
        --description 'Install patches using custom baseline' \
        --max-concurrency '50%' \
        --max-errors '10%' \
        --priority 1 \
        --task-parameters '${task_parameters}' \
        --logging-info S3BucketName=${S3_BUCKET_NAME},S3KeyPrefix=patch-logs" \
        "Registering patching task"
    
    success "Registered patching task with maintenance window"
}

# Create patch compliance monitoring
create_monitoring() {
    log "Creating patch compliance monitoring..."
    
    execute_command "aws cloudwatch put-metric-alarm \
        --alarm-name ${ALARM_NAME} \
        --alarm-description 'Monitor patch compliance status' \
        --metric-name 'ComplianceByPatchGroup' \
        --namespace 'AWS/SSM-PatchCompliance' \
        --statistic Maximum \
        --period 3600 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions ${SNS_TOPIC_ARN} \
        --dimensions Name=PatchGroup,Value=Production" \
        "Creating CloudWatch alarm for patch compliance"
    
    success "Created patch compliance monitoring"
}

# Create automated patch scanning
create_patch_scanning() {
    log "Creating automated patch scanning..."
    
    # Create scan maintenance window
    execute_command "aws ssm create-maintenance-window \
        --name ${SCAN_WINDOW_NAME} \
        --description 'Daily patch scanning window' \
        --schedule 'cron(0 1 * * ? *)' \
        --duration 2 \
        --cutoff 1 \
        --schedule-timezone 'UTC' \
        --allow-unassociated-targets" \
        "Creating scan maintenance window"
    
    # Get scan window ID
    if [[ "$DRY_RUN" != "true" ]]; then
        export SCAN_WINDOW_ID=$(aws ssm describe-maintenance-windows \
            --filters "Key=Name,Values=${SCAN_WINDOW_NAME}" \
            --query "WindowIdentities[0].WindowId" \
            --output text)
        echo "SCAN_WINDOW_ID=${SCAN_WINDOW_ID}" >> .env
    fi
    
    # Register scan targets
    execute_command "aws ssm register-target-with-maintenance-window \
        --window-id ${SCAN_WINDOW_ID} \
        --target-type Instance \
        --targets Key=tag:Environment,Values=Production \
        --resource-type INSTANCE \
        --name 'ScanTargets'" \
        "Registering scan targets"
    
    # Get scan target ID
    if [[ "$DRY_RUN" != "true" ]]; then
        export SCAN_TARGET_ID=$(aws ssm describe-maintenance-window-targets \
            --window-id ${SCAN_WINDOW_ID} \
            --query "Targets[0].WindowTargetId" \
            --output text)
        echo "SCAN_TARGET_ID=${SCAN_TARGET_ID}" >> .env
    fi
    
    # Register scanning task
    local scan_task_parameters='{
        "BaselineOverride": ["'${PATCH_BASELINE_ID}'"],
        "Operation": ["Scan"]
    }'
    
    execute_command "aws ssm register-task-with-maintenance-window \
        --window-id ${SCAN_WINDOW_ID} \
        --target-type Instance \
        --targets Key=WindowTargetIds,Values=${SCAN_TARGET_ID} \
        --task-type RUN_COMMAND \
        --task-arn 'AWS-RunPatchBaseline' \
        --service-role-arn ${MW_ROLE_ARN} \
        --name 'ScanningTask' \
        --description 'Scan for missing patches' \
        --max-concurrency '100%' \
        --max-errors '5%' \
        --priority 1 \
        --task-parameters '${scan_task_parameters}' \
        --logging-info S3BucketName=${S3_BUCKET_NAME},S3KeyPrefix=scan-logs" \
        "Registering scanning task"
    
    success "Created automated patch scanning"
}

# Configure patch group association
configure_patch_group() {
    log "Configuring patch group association..."
    
    execute_command "aws ssm register-patch-baseline-for-patch-group \
        --baseline-id ${PATCH_BASELINE_ID} \
        --patch-group 'Production'" \
        "Associating patch baseline with Production patch group"
    
    success "Associated patch baseline with Production patch group"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [[ -f "maintenance-window-trust-policy.json" ]]; then
        rm -f maintenance-window-trust-policy.json
    fi
    
    success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "=================================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "=================================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN MODE - No resources were actually created"
        echo ""
        echo "The following resources WOULD be created:"
    else
        echo "The following resources have been created:"
    fi
    
    echo ""
    echo "📋 Patch Management Resources:"
    echo "   • Patch Baseline: ${PATCH_BASELINE_NAME}"
    echo "   • Maintenance Window: ${MAINTENANCE_WINDOW_NAME}"
    echo "   • Scan Window: ${SCAN_WINDOW_NAME}"
    echo ""
    echo "🔧 Supporting Resources:"
    echo "   • IAM Role: ${ROLE_NAME}"
    echo "   • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "   • CloudWatch Alarm: ${ALARM_NAME}"
    echo ""
    echo "⏰ Scheduled Operations:"
    echo "   • Patch Installation: Sundays at 2:00 AM UTC"
    echo "   • Patch Scanning: Daily at 1:00 AM UTC"
    echo ""
    echo "🏷️  Target Selection:"
    echo "   • EC2 instances tagged with Environment=Production"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "✅ Next Steps:"
        echo "   1. Tag your EC2 instances with Environment=Production"
        echo "   2. Subscribe to SNS topic for patch notifications"
        echo "   3. Monitor patch compliance in Systems Manager console"
        echo "   4. Review patch reports in S3 bucket"
        echo ""
        echo "🧹 To clean up all resources, run: ./destroy.sh"
    fi
    
    echo ""
    echo "=================================================="
}

# Main execution
main() {
    log "Starting AWS Systems Manager Automated Patching deployment..."
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_patch_baseline
    create_iam_role
    create_maintenance_window
    register_targets
    register_patch_task
    create_monitoring
    create_patch_scanning
    configure_patch_group
    cleanup_temp_files
    
    success "Deployment completed successfully!"
    display_summary
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Systems Manager Automated Patching Infrastructure

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Run in dry-run mode (no resources created)
    -v, --verbose       Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN            Set to 'true' to run in dry-run mode
    AWS_REGION         AWS region to deploy to (defaults to CLI config)
    AWS_PROFILE        AWS profile to use (defaults to CLI config)

EXAMPLES:
    $0                  # Deploy with default settings
    $0 --dry-run        # See what would be deployed
    DRY_RUN=true $0     # Same as --dry-run

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate IAM permissions for Systems Manager, EC2, S3, SNS, IAM, and CloudWatch
    - EC2 instances with SSM Agent installed (for targeting)

For more information, see the recipe documentation.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"