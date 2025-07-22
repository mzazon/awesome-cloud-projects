#!/bin/bash
set -euo pipefail

# AWS EventBridge Scheduler and Lambda Business Automation Cleanup Script
# This script safely removes all resources created by the deployment script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

print_banner() {
    log_info "=============================================================="
    log_info "AWS Business Task Scheduling Automation Cleanup"
    log_info "Recipe: EventBridge Scheduler + Lambda + SNS + S3"
    log_info "=============================================================="
}

check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS authentication failed. Please configure AWS CLI credentials."
        exit 1
    fi
    
    # Check for deployment state file
    if [[ ! -f "${DEPLOYMENT_STATE}" ]]; then
        log_warning "Deployment state file not found. Manual cleanup may be required."
        log_info "Attempting to discover resources by naming pattern..."
        return 1
    fi
    
    log_success "Prerequisites check completed"
    return 0
}

load_deployment_state() {
    if [[ -f "${DEPLOYMENT_STATE}" ]]; then
        log_info "Loading deployment state..."
        source "${DEPLOYMENT_STATE}"
        
        log_info "Found deployment state:"
        log_info "  • AWS Region: ${AWS_REGION:-'Not set'}"
        log_info "  • AWS Account: ${AWS_ACCOUNT_ID:-'Not set'}"
        log_info "  • S3 Bucket: ${BUCKET_NAME:-'Not set'}"
        log_info "  • SNS Topic: ${SNS_TOPIC_NAME:-'Not set'}"
        log_info "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not set'}"
        log_info "  • Schedule Group: ${SCHEDULE_GROUP_NAME:-'Not set'}"
        
        return 0
    else
        log_warning "No deployment state found. Attempting manual discovery..."
        return 1
    fi
}

confirm_destruction() {
    log_warning "⚠️  This will permanently delete ALL resources created by this recipe!"
    log_warning "⚠️  This action CANNOT be undone!"
    log_info ""
    log_info "Resources to be deleted:"
    
    if [[ -f "${DEPLOYMENT_STATE}" ]]; then
        source "${DEPLOYMENT_STATE}"
        [[ -n "${BUCKET_NAME:-}" ]] && log_info "  • S3 Bucket: ${BUCKET_NAME} (and ALL contents)"
        [[ -n "${SNS_TOPIC_NAME:-}" ]] && log_info "  • SNS Topic: ${SNS_TOPIC_NAME}"
        [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && log_info "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        [[ -n "${SCHEDULE_GROUP_NAME:-}" ]] && log_info "  • EventBridge Schedule Group: ${SCHEDULE_GROUP_NAME}"
        [[ -n "${LAMBDA_ROLE_NAME:-}" ]] && log_info "  • Lambda IAM Role: ${LAMBDA_ROLE_NAME}"
        [[ -n "${SCHEDULER_ROLE_NAME:-}" ]] && log_info "  • Scheduler IAM Role: ${SCHEDULER_ROLE_NAME}"
    else
        log_info "  • All business automation resources matching naming patterns"
    fi
    
    log_info ""
    
    # Check for force flag
    if [[ "${1:-}" == "--force" || "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "Force flag detected. Proceeding with automatic cleanup..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

discover_resources() {
    log_info "Attempting to discover resources by naming patterns..."
    
    # Try to find resources by common patterns
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Look for S3 buckets with business automation pattern
    log_info "Searching for S3 buckets..."
    BUCKET_NAMES=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `business-automation`)].Name' --output text || echo "")
    
    # Look for Lambda functions with business task processor pattern
    log_info "Searching for Lambda functions..."
    LAMBDA_FUNCTION_NAMES=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `business-task-processor`)].FunctionName' --output text || echo "")
    
    # Look for SNS topics with business notifications pattern
    log_info "Searching for SNS topics..."
    SNS_TOPIC_NAMES=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `business-notifications`)].TopicArn' --output text | sed 's/.*://' || echo "")
    
    # Look for EventBridge schedule groups
    log_info "Searching for EventBridge schedule groups..."
    SCHEDULE_GROUP_NAMES=$(aws scheduler list-schedule-groups --query 'ScheduleGroups[?contains(Name, `business-automation`)].Name' --output text || echo "")
    
    # Look for IAM roles
    log_info "Searching for IAM roles..."
    IAM_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `business-`) || contains(RoleName, `eventbridge-scheduler-role-`) || contains(RoleName, `lambda-execution-role-`)].RoleName' --output text || echo "")
    
    if [[ -n "${BUCKET_NAMES}" || -n "${LAMBDA_FUNCTION_NAMES}" || -n "${SNS_TOPIC_NAMES}" || -n "${SCHEDULE_GROUP_NAMES}" || -n "${IAM_ROLES}" ]]; then
        log_info "Found resources to clean up:"
        [[ -n "${BUCKET_NAMES}" ]] && log_info "  • S3 Buckets: ${BUCKET_NAMES}"
        [[ -n "${LAMBDA_FUNCTION_NAMES}" ]] && log_info "  • Lambda Functions: ${LAMBDA_FUNCTION_NAMES}"
        [[ -n "${SNS_TOPIC_NAMES}" ]] && log_info "  • SNS Topics: ${SNS_TOPIC_NAMES}"
        [[ -n "${SCHEDULE_GROUP_NAMES}" ]] && log_info "  • Schedule Groups: ${SCHEDULE_GROUP_NAMES}"
        [[ -n "${IAM_ROLES}" ]] && log_info "  • IAM Roles: ${IAM_ROLES}"
        return 0
    else
        log_warning "No resources found to clean up."
        return 1
    fi
}

delete_eventbridge_schedules() {
    log_info "Deleting EventBridge schedules..."
    
    # If we have deployment state, use it
    if [[ -n "${SCHEDULE_NAMES:-}" && -n "${SCHEDULE_GROUP_NAME:-}" ]]; then
        for schedule_name in ${SCHEDULE_NAMES}; do
            log_info "Deleting schedule: ${schedule_name}"
            aws scheduler delete-schedule --name "${schedule_name}" 2>/dev/null || {
                log_warning "Failed to delete schedule: ${schedule_name} (may not exist)"
            }
        done
        
        log_info "Deleting schedule group: ${SCHEDULE_GROUP_NAME}"
        aws scheduler delete-schedule-group --name "${SCHEDULE_GROUP_NAME}" 2>/dev/null || {
            log_warning "Failed to delete schedule group: ${SCHEDULE_GROUP_NAME} (may not exist)"
        }
    else
        # Discovery mode
        if [[ -n "${SCHEDULE_GROUP_NAMES:-}" ]]; then
            for group_name in ${SCHEDULE_GROUP_NAMES}; do
                log_info "Deleting schedules in group: ${group_name}"
                
                # List and delete all schedules in the group
                SCHEDULES_IN_GROUP=$(aws scheduler list-schedules --group-name "${group_name}" --query 'Schedules[].Name' --output text 2>/dev/null || echo "")
                
                if [[ -n "${SCHEDULES_IN_GROUP}" ]]; then
                    for schedule in ${SCHEDULES_IN_GROUP}; do
                        log_info "Deleting schedule: ${schedule}"
                        aws scheduler delete-schedule --name "${schedule}" 2>/dev/null || true
                    done
                fi
                
                log_info "Deleting schedule group: ${group_name}"
                aws scheduler delete-schedule-group --name "${group_name}" 2>/dev/null || true
            done
        fi
    fi
    
    log_success "EventBridge schedules cleanup completed"
}

delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    # If we have deployment state, use it
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || {
            log_warning "Failed to delete Lambda function: ${LAMBDA_FUNCTION_NAME} (may not exist)"
        }
    else
        # Discovery mode
        if [[ -n "${LAMBDA_FUNCTION_NAMES:-}" ]]; then
            for function_name in ${LAMBDA_FUNCTION_NAMES}; do
                log_info "Deleting Lambda function: ${function_name}"
                aws lambda delete-function --function-name "${function_name}" 2>/dev/null || {
                    log_warning "Failed to delete Lambda function: ${function_name}"
                }
            done
        fi
    fi
    
    log_success "Lambda function cleanup completed"
}

delete_iam_roles() {
    log_info "Deleting IAM roles and policies..."
    
    # Function to safely delete a role and its policies
    delete_role_safely() {
        local role_name="$1"
        local role_suffix="$2"
        
        log_info "Processing IAM role: ${role_name}"
        
        # List attached policies
        local attached_policies=$(aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        # Detach and delete policies
        if [[ -n "${attached_policies}" ]]; then
            for policy_arn in ${attached_policies}; do
                log_info "Detaching policy: ${policy_arn}"
                aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}" 2>/dev/null || true
                
                # Only delete custom policies (not AWS managed)
                if [[ "${policy_arn}" == *":${AWS_ACCOUNT_ID}:policy/"* ]]; then
                    log_info "Deleting custom policy: ${policy_arn}"
                    aws iam delete-policy --policy-arn "${policy_arn}" 2>/dev/null || true
                fi
            done
        fi
        
        # Delete the role
        log_info "Deleting IAM role: ${role_name}"
        aws iam delete-role --role-name "${role_name}" 2>/dev/null || {
            log_warning "Failed to delete IAM role: ${role_name}"
        }
    }
    
    # If we have deployment state, use it
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        delete_role_safely "${LAMBDA_ROLE_NAME}" "lambda"
    fi
    
    if [[ -n "${SCHEDULER_ROLE_NAME:-}" ]]; then
        delete_role_safely "${SCHEDULER_ROLE_NAME}" "scheduler"
    fi
    
    # Discovery mode - clean up any matching roles
    if [[ -n "${IAM_ROLES:-}" ]]; then
        for role_name in ${IAM_ROLES}; do
            delete_role_safely "${role_name}" "discovered"
        done
    fi
    
    log_success "IAM roles and policies cleanup completed"
}

delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    # If we have deployment state, use it
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        log_info "Deleting SNS topic: ${TOPIC_ARN}"
        aws sns delete-topic --topic-arn "${TOPIC_ARN}" 2>/dev/null || {
            log_warning "Failed to delete SNS topic: ${TOPIC_ARN} (may not exist)"
        }
    elif [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
        local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        log_info "Deleting SNS topic: ${topic_arn}"
        aws sns delete-topic --topic-arn "${topic_arn}" 2>/dev/null || {
            log_warning "Failed to delete SNS topic: ${topic_arn} (may not exist)"
        }
    else
        # Discovery mode
        if [[ -n "${SNS_TOPIC_NAMES:-}" ]]; then
            for topic_name in ${SNS_TOPIC_NAMES}; do
                local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${topic_name}"
                log_info "Deleting SNS topic: ${topic_arn}"
                aws sns delete-topic --topic-arn "${topic_arn}" 2>/dev/null || {
                    log_warning "Failed to delete SNS topic: ${topic_arn}"
                }
            done
        fi
    fi
    
    log_success "SNS topic cleanup completed"
}

delete_s3_bucket() {
    log_info "Deleting S3 bucket and contents..."
    
    delete_bucket_safely() {
        local bucket_name="$1"
        
        log_info "Processing S3 bucket: ${bucket_name}"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "${bucket_name}" 2>/dev/null; then
            # Get object count for logging
            local object_count=$(aws s3 ls "s3://${bucket_name}" --recursive | wc -l || echo "0")
            
            if [[ ${object_count} -gt 0 ]]; then
                log_info "Removing ${object_count} objects from bucket: ${bucket_name}"
                aws s3 rm "s3://${bucket_name}" --recursive 2>/dev/null || {
                    log_warning "Some objects may not have been deleted from ${bucket_name}"
                }
            fi
            
            # Delete all object versions if versioning is enabled
            log_info "Checking for versioned objects..."
            local versions=$(aws s3api list-object-versions --bucket "${bucket_name}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || echo "")
            
            if [[ -n "${versions}" && "${versions}" != "None" ]]; then
                log_info "Deleting versioned objects..."
                while read -r key version_id; do
                    [[ -n "${key}" && -n "${version_id}" ]] && {
                        aws s3api delete-object --bucket "${bucket_name}" --key "${key}" --version-id "${version_id}" 2>/dev/null || true
                    }
                done <<< "${versions}"
            fi
            
            # Delete delete markers
            local delete_markers=$(aws s3api list-object-versions --bucket "${bucket_name}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || echo "")
            
            if [[ -n "${delete_markers}" && "${delete_markers}" != "None" ]]; then
                log_info "Deleting delete markers..."
                while read -r key version_id; do
                    [[ -n "${key}" && -n "${version_id}" ]] && {
                        aws s3api delete-object --bucket "${bucket_name}" --key "${key}" --version-id "${version_id}" 2>/dev/null || true
                    }
                done <<< "${delete_markers}"
            fi
            
            # Delete the bucket
            log_info "Deleting S3 bucket: ${bucket_name}"
            aws s3 rb "s3://${bucket_name}" 2>/dev/null || {
                log_warning "Failed to delete S3 bucket: ${bucket_name} (may still contain objects)"
            }
        else
            log_info "S3 bucket ${bucket_name} does not exist or is not accessible"
        fi
    }
    
    # If we have deployment state, use it
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        delete_bucket_safely "${BUCKET_NAME}"
    else
        # Discovery mode
        if [[ -n "${BUCKET_NAMES:-}" ]]; then
            for bucket_name in ${BUCKET_NAMES}; do
                delete_bucket_safely "${bucket_name}"
            done
        fi
    fi
    
    log_success "S3 bucket cleanup completed"
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f "${DEPLOYMENT_STATE}" ]]; then
        rm -f "${DEPLOYMENT_STATE}"
        log_info "Removed deployment state file"
    fi
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/lambda-permissions-policy.json"
        "${SCRIPT_DIR}/scheduler-trust-policy.json"
        "${SCRIPT_DIR}/scheduler-policy.json"
        "${SCRIPT_DIR}/business_task_processor.py"
        "${SCRIPT_DIR}/business-task-processor.zip"
        "${SCRIPT_DIR}/bucket-lifecycle.json"
        "${SCRIPT_DIR}/response.json"
        "${SCRIPT_DIR}/test-response-"*.json
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed temporary file: $(basename "${file}")"
        fi
    done
    
    log_success "Local file cleanup completed"
}

verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining resources
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
            log_warning "⚠️  S3 bucket still exists: ${BUCKET_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null; then
            log_warning "⚠️  Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ -n "${SCHEDULE_GROUP_NAME:-}" ]]; then
        if aws scheduler get-schedule-group --name "${SCHEDULE_GROUP_NAME}" 2>/dev/null; then
            log_warning "⚠️  Schedule group still exists: ${SCHEDULE_GROUP_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "✅ Cleanup verification passed - no remaining resources detected"
    else
        log_warning "⚠️  ${cleanup_issues} potential cleanup issues detected"
        log_info "Some resources may require manual deletion or additional time to propagate"
    fi
    
    return ${cleanup_issues}
}

print_cleanup_summary() {
    log_info "=============================================================="
    log_success "🧹 Business Automation Cleanup Summary"
    log_info "=============================================================="
    log_info ""
    log_info "✅ Completed cleanup tasks:"
    log_info "  • EventBridge schedules and schedule groups"
    log_info "  • Lambda function and execution logs"
    log_info "  • IAM roles and custom policies"
    log_info "  • SNS topics and subscriptions"
    log_info "  • S3 buckets and all contents"
    log_info "  • Local temporary files"
    log_info ""
    log_info "💡 Additional Notes:"
    log_info "  • CloudWatch logs are retained by default (check CloudWatch console)"
    log_info "  • SNS subscription confirmations in email are automatically removed"
    log_info "  • AWS Config rules (if any) may need manual cleanup"
    log_info "  • Check AWS billing for any unexpected charges"
    log_info ""
    log_info "📖 If you need to redeploy, run the deploy.sh script again"
    log_info "=============================================================="
}

# Main execution function
main() {
    print_banner
    
    # Check prerequisites (continue even if deployment state is missing)
    check_prerequisites || true
    
    # Try to load deployment state, fall back to discovery
    if ! load_deployment_state; then
        if ! discover_resources; then
            log_info "No resources found to clean up. Exiting."
            exit 0
        fi
    fi
    
    # Confirm destruction
    confirm_destruction "$@"
    
    # Perform cleanup in reverse order of creation
    log_info "Starting cleanup process..."
    
    delete_eventbridge_schedules
    delete_lambda_function
    delete_iam_roles
    delete_sns_topic
    delete_s3_bucket
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    print_cleanup_summary
    
    log_success "🎉 Cleanup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "AWS Business Automation Cleanup Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --help     Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  FORCE_DESTROY=true    Skip confirmation prompts"
        echo ""
        exit 0
        ;;
    --force)
        FORCE_DESTROY=true
        shift
        ;;
esac

# Execute main function
main "$@"