#!/bin/bash

# Advanced Multi-Service Monitoring Dashboards with Custom Metrics - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/advanced-monitoring-destroy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false
FORCE=false
AUTO_CONFIRM=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

print_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "${LOG_FILE}"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm destructive actions
confirm_action() {
    if [[ "${AUTO_CONFIRM}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}[CONFIRM]${NC} $1"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled by user"
        exit 0
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    print_status "Validating AWS credentials..."
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        print_error "AWS region not configured"
        exit 1
    fi
    
    print_status "AWS Account ID: ${AWS_ACCOUNT_ID}"
    print_status "AWS Region: ${AWS_REGION}"
}

# Function to load environment variables
load_environment() {
    print_status "Loading environment variables..."
    
    # Try to find environment file from deployment
    local env_files=(
        "/tmp/advanced-monitoring-*/environment.sh"
        "${SCRIPT_DIR}/../environment.sh"
        "./environment.sh"
    )
    
    local env_file=""
    for pattern in "${env_files[@]}"; do
        if compgen -G "${pattern}" > /dev/null 2>&1; then
            env_file=$(ls ${pattern} | head -1)
            break
        fi
    done
    
    if [[ -n "${env_file}" && -f "${env_file}" ]]; then
        print_status "Loading environment from: ${env_file}"
        source "${env_file}"
    else
        print_warning "Environment file not found. Using interactive mode."
        
        # Get project name from user
        read -p "Enter project name (or press Enter to search): " PROJECT_NAME
        
        if [[ -z "${PROJECT_NAME}" ]]; then
            print_status "Searching for monitoring resources..."
            
            # Try to find resources with monitoring pattern
            local functions=($(aws lambda list-functions --query 'Functions[?contains(FunctionName, `advanced-monitoring`) || contains(FunctionName, `monitoring`)].FunctionName' --output text 2>/dev/null || echo ""))
            
            if [[ ${#functions[@]} -gt 0 ]]; then
                print_status "Found potential monitoring functions:"
                for func in "${functions[@]}"; do
                    echo "  - ${func}"
                done
                
                # Extract project name from first function
                PROJECT_NAME=$(echo "${functions[0]}" | sed 's/-business-metrics$//' | sed 's/-infrastructure-health$//' | sed 's/-cost-monitoring$//')
                print_status "Detected project name: ${PROJECT_NAME}"
            else
                print_error "No monitoring resources found. Please specify project name."
                exit 1
            fi
        fi
        
        # Set derived variables
        LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
        SNS_TOPIC_NAME="${PROJECT_NAME}-alerts"
        DASHBOARD_PREFIX="${PROJECT_NAME}"
        TEMP_DIR="/tmp/${PROJECT_NAME}"
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_NAME}" ]]; then
        print_error "PROJECT_NAME not set"
        exit 1
    fi
    
    print_status "Project Name: ${PROJECT_NAME}"
    print_status "Lambda Role: ${LAMBDA_ROLE_NAME}"
    print_status "SNS Topic Prefix: ${SNS_TOPIC_NAME}"
    print_status "Dashboard Prefix: ${DASHBOARD_PREFIX}"
}

# Function to list resources that will be deleted
list_resources() {
    print_status "Scanning for resources to delete..."
    
    local resources_found=0
    
    # Check Lambda functions
    print_status "Lambda Functions:"
    local functions=($(aws lambda list-functions --query "Functions[?contains(FunctionName, '${PROJECT_NAME}')].FunctionName" --output text 2>/dev/null || echo ""))
    for func in "${functions[@]}"; do
        if [[ "${func}" != "" ]]; then
            echo "  - ${func}"
            resources_found=$((resources_found + 1))
        fi
    done
    
    # Check IAM roles
    print_status "IAM Roles:"
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        echo "  - ${LAMBDA_ROLE_NAME}"
        resources_found=$((resources_found + 1))
    fi
    
    # Check SNS topics
    print_status "SNS Topics:"
    local topics=($(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text 2>/dev/null || echo ""))
    for topic in "${topics[@]}"; do
        if [[ "${topic}" != "" ]]; then
            local topic_name=$(echo "${topic}" | awk -F':' '{print $NF}')
            echo "  - ${topic_name}"
            resources_found=$((resources_found + 1))
        fi
    done
    
    # Check EventBridge rules
    print_status "EventBridge Rules:"
    local rules=($(aws events list-rules --name-prefix "${PROJECT_NAME}" --query "Rules[].Name" --output text 2>/dev/null || echo ""))
    for rule in "${rules[@]}"; do
        if [[ "${rule}" != "" ]]; then
            echo "  - ${rule}"
            resources_found=$((resources_found + 1))
        fi
    done
    
    # Check CloudWatch dashboards
    print_status "CloudWatch Dashboards:"
    local dashboards=($(aws cloudwatch list-dashboards --dashboard-name-prefix "${DASHBOARD_PREFIX}" --query "DashboardEntries[].DashboardName" --output text 2>/dev/null || echo ""))
    for dashboard in "${dashboards[@]}"; do
        if [[ "${dashboard}" != "" ]]; then
            echo "  - ${dashboard}"
            resources_found=$((resources_found + 1))
        fi
    done
    
    # Check CloudWatch alarms
    print_status "CloudWatch Alarms:"
    local alarms=($(aws cloudwatch describe-alarms --alarm-name-prefix "${PROJECT_NAME}" --query "MetricAlarms[].AlarmName" --output text 2>/dev/null || echo ""))
    for alarm in "${alarms[@]}"; do
        if [[ "${alarm}" != "" ]]; then
            echo "  - ${alarm}"
            resources_found=$((resources_found + 1))
        fi
    done
    
    # Check anomaly detectors
    print_status "CloudWatch Anomaly Detectors:"
    local detectors=($(aws cloudwatch describe-anomaly-detectors --query "AnomalyDetectors[].{Namespace:Namespace,MetricName:MetricName}" --output text 2>/dev/null | grep -E "(Business/|Infrastructure/)" | wc -l || echo "0"))
    if [[ "${detectors}" -gt 0 ]]; then
        echo "  - ${detectors} anomaly detectors found"
        resources_found=$((resources_found + detectors))
    fi
    
    echo
    print_status "Total resources found: ${resources_found}"
    
    if [[ ${resources_found} -eq 0 ]]; then
        print_warning "No resources found to delete"
        exit 0
    fi
    
    return ${resources_found}
}

# Function to delete CloudWatch dashboards
delete_dashboards() {
    print_status "Deleting CloudWatch dashboards..."
    
    local dashboards=($(aws cloudwatch list-dashboards --dashboard-name-prefix "${DASHBOARD_PREFIX}" --query "DashboardEntries[].DashboardName" --output text 2>/dev/null || echo ""))
    
    if [[ ${#dashboards[@]} -eq 0 || "${dashboards[0]}" == "" ]]; then
        print_debug "No dashboards found to delete"
        return 0
    fi
    
    # Convert array to comma-separated string for batch deletion
    local dashboard_names=""
    for dashboard in "${dashboards[@]}"; do
        if [[ "${dashboard}" != "" ]]; then
            dashboard_names="${dashboard_names}${dashboard},"
        fi
    done
    dashboard_names="${dashboard_names%,}"  # Remove trailing comma
    
    if [[ -n "${dashboard_names}" ]]; then
        if [[ "${DRY_RUN}" == "false" ]]; then
            if aws cloudwatch delete-dashboards --dashboard-names ${dashboard_names} >/dev/null 2>&1; then
                print_status "Deleted CloudWatch dashboards: ${dashboard_names}"
            else
                print_warning "Failed to delete some dashboards (may not exist)"
            fi
        else
            print_status "DRY RUN - Would delete dashboards: ${dashboard_names}"
        fi
    fi
}

# Function to delete CloudWatch alarms
delete_alarms() {
    print_status "Deleting CloudWatch alarms..."
    
    local alarms=($(aws cloudwatch describe-alarms --alarm-name-prefix "${PROJECT_NAME}" --query "MetricAlarms[].AlarmName" --output text 2>/dev/null || echo ""))
    
    if [[ ${#alarms[@]} -eq 0 || "${alarms[0]}" == "" ]]; then
        print_debug "No alarms found to delete"
        return 0
    fi
    
    for alarm in "${alarms[@]}"; do
        if [[ "${alarm}" != "" ]]; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                if aws cloudwatch delete-alarms --alarm-names "${alarm}" >/dev/null 2>&1; then
                    print_status "Deleted alarm: ${alarm}"
                else
                    print_warning "Failed to delete alarm: ${alarm}"
                fi
            else
                print_status "DRY RUN - Would delete alarm: ${alarm}"
            fi
        fi
    done
}

# Function to delete anomaly detectors
delete_anomaly_detectors() {
    print_status "Deleting CloudWatch anomaly detectors..."
    
    local detectors=(
        "Business/Metrics:HourlyRevenue:Environment=production,BusinessUnit=ecommerce"
        "Business/Metrics:APIResponseTime:Environment=production,Service=api-gateway"
        "Business/Metrics:ErrorRate:Environment=production,Service=api-gateway"
        "Infrastructure/Health:OverallInfrastructureHealth:Environment=production"
    )
    
    for detector_config in "${detectors[@]}"; do
        IFS=':' read -r namespace metric_name dimensions <<< "${detector_config}"
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            # Try to delete the anomaly detector
            if aws cloudwatch delete-anomaly-detector \
                --namespace "${namespace}" \
                --metric-name "${metric_name}" \
                --stat "Average" >/dev/null 2>&1; then
                print_status "Deleted anomaly detector: ${metric_name}"
            else
                print_debug "Anomaly detector not found or already deleted: ${metric_name}"
            fi
        else
            print_status "DRY RUN - Would delete anomaly detector: ${metric_name}"
        fi
    done
}

# Function to delete EventBridge rules
delete_eventbridge_rules() {
    print_status "Deleting EventBridge rules..."
    
    local rules=($(aws events list-rules --name-prefix "${PROJECT_NAME}" --query "Rules[].Name" --output text 2>/dev/null || echo ""))
    
    if [[ ${#rules[@]} -eq 0 || "${rules[0]}" == "" ]]; then
        print_debug "No EventBridge rules found to delete"
        return 0
    fi
    
    for rule in "${rules[@]}"; do
        if [[ "${rule}" != "" ]]; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                # Remove targets first
                if aws events remove-targets --rule "${rule}" --ids "1" >/dev/null 2>&1; then
                    print_debug "Removed targets from rule: ${rule}"
                fi
                
                # Delete the rule
                if aws events delete-rule --name "${rule}" >/dev/null 2>&1; then
                    print_status "Deleted EventBridge rule: ${rule}"
                else
                    print_warning "Failed to delete EventBridge rule: ${rule}"
                fi
            else
                print_status "DRY RUN - Would delete EventBridge rule: ${rule}"
            fi
        fi
    done
}

# Function to delete Lambda functions
delete_lambda_functions() {
    print_status "Deleting Lambda functions..."
    
    local functions=($(aws lambda list-functions --query "Functions[?contains(FunctionName, '${PROJECT_NAME}')].FunctionName" --output text 2>/dev/null || echo ""))
    
    if [[ ${#functions[@]} -eq 0 || "${functions[0]}" == "" ]]; then
        print_debug "No Lambda functions found to delete"
        return 0
    fi
    
    for function in "${functions[@]}"; do
        if [[ "${function}" != "" ]]; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                if aws lambda delete-function --function-name "${function}" >/dev/null 2>&1; then
                    print_status "Deleted Lambda function: ${function}"
                else
                    print_warning "Failed to delete Lambda function: ${function}"
                fi
            else
                print_status "DRY RUN - Would delete Lambda function: ${function}"
            fi
        fi
    done
}

# Function to delete SNS topics
delete_sns_topics() {
    print_status "Deleting SNS topics..."
    
    local topics=($(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text 2>/dev/null || echo ""))
    
    if [[ ${#topics[@]} -eq 0 || "${topics[0]}" == "" ]]; then
        print_debug "No SNS topics found to delete"
        return 0
    fi
    
    for topic in "${topics[@]}"; do
        if [[ "${topic}" != "" ]]; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                if aws sns delete-topic --topic-arn "${topic}" >/dev/null 2>&1; then
                    local topic_name=$(echo "${topic}" | awk -F':' '{print $NF}')
                    print_status "Deleted SNS topic: ${topic_name}"
                else
                    print_warning "Failed to delete SNS topic: ${topic}"
                fi
            else
                local topic_name=$(echo "${topic}" | awk -F':' '{print $NF}')
                print_status "DRY RUN - Would delete SNS topic: ${topic_name}"
            fi
        fi
    done
}

# Function to delete IAM role
delete_iam_role() {
    print_status "Deleting IAM role..."
    
    if ! aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        print_debug "IAM role not found: ${LAMBDA_ROLE_NAME}"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Detach managed policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/CloudWatchFullAccess"
            "arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess"
            "arn:aws:iam::aws:policy/AmazonElastiCacheReadOnlyAccess"
        )
        
        for policy in "${policies[@]}"; do
            if aws iam detach-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-arn "${policy}" >/dev/null 2>&1; then
                print_debug "Detached policy: ${policy}"
            fi
        done
        
        # Delete the role
        if aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
            print_status "Deleted IAM role: ${LAMBDA_ROLE_NAME}"
        else
            print_warning "Failed to delete IAM role: ${LAMBDA_ROLE_NAME}"
        fi
    else
        print_status "DRY RUN - Would delete IAM role: ${LAMBDA_ROLE_NAME}"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    print_status "Cleaning up temporary files..."
    
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        if [[ "${DRY_RUN}" == "false" ]]; then
            rm -rf "${TEMP_DIR}"
            print_status "Removed temporary directory: ${TEMP_DIR}"
        else
            print_status "DRY RUN - Would remove temporary directory: ${TEMP_DIR}"
        fi
    fi
    
    # Clean up other temporary files
    local temp_patterns=(
        "/tmp/advanced-monitoring-deploy-*.log"
        "/tmp/advanced-monitoring-destroy-*.log"
        "/tmp/business-*.py"
        "/tmp/infrastructure-*.py"
        "/tmp/cost-*.py"
        "/tmp/*-dashboard.json"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "${pattern}" > /dev/null 2>&1; then
            if [[ "${DRY_RUN}" == "false" ]]; then
                rm -f ${pattern}
                print_debug "Cleaned up temporary files: ${pattern}"
            else
                print_status "DRY RUN - Would clean up temporary files: ${pattern}"
            fi
        fi
    done
}

# Function to verify cleanup
verify_cleanup() {
    print_status "Verifying cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining Lambda functions
    local functions=($(aws lambda list-functions --query "Functions[?contains(FunctionName, '${PROJECT_NAME}')].FunctionName" --output text 2>/dev/null || echo ""))
    if [[ ${#functions[@]} -gt 0 && "${functions[0]}" != "" ]]; then
        print_warning "Remaining Lambda functions: ${functions[*]}"
        remaining_resources=$((remaining_resources + ${#functions[@]}))
    fi
    
    # Check for remaining SNS topics
    local topics=($(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text 2>/dev/null || echo ""))
    if [[ ${#topics[@]} -gt 0 && "${topics[0]}" != "" ]]; then
        print_warning "Remaining SNS topics: ${#topics[@]}"
        remaining_resources=$((remaining_resources + ${#topics[@]}))
    fi
    
    # Check for remaining dashboards
    local dashboards=($(aws cloudwatch list-dashboards --dashboard-name-prefix "${DASHBOARD_PREFIX}" --query "DashboardEntries[].DashboardName" --output text 2>/dev/null || echo ""))
    if [[ ${#dashboards[@]} -gt 0 && "${dashboards[0]}" != "" ]]; then
        print_warning "Remaining dashboards: ${dashboards[*]}"
        remaining_resources=$((remaining_resources + ${#dashboards[@]}))
    fi
    
    # Check for remaining IAM role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        print_warning "IAM role still exists: ${LAMBDA_ROLE_NAME}"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        print_status "✅ Cleanup verification passed - no resources remaining"
    else
        print_warning "⚠️  Cleanup verification found ${remaining_resources} remaining resources"
        print_warning "You may need to manually delete these resources"
    fi
}

# Function to display cleanup summary
display_summary() {
    print_status "Cleanup completed!"
    echo
    echo "=== Cleanup Summary ==="
    echo "Project Name: ${PROJECT_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo
    echo "=== Resources Removed ==="
    echo "• Lambda Functions (business-metrics, infrastructure-health, cost-monitoring)"
    echo "• SNS Topics (critical, warning, info alerts)"
    echo "• EventBridge Rules (scheduling rules)"
    echo "• CloudWatch Dashboards (Infrastructure, Business, Executive, Operations)"
    echo "• CloudWatch Alarms (health monitoring)"
    echo "• CloudWatch Anomaly Detectors"
    echo "• IAM Role (Lambda execution role)"
    echo "• Temporary Files and Directories"
    echo
    echo "=== Notes ==="
    echo "• Custom metrics data will be retained in CloudWatch"
    echo "• CloudWatch Logs groups may still exist (deleted automatically after retention period)"
    echo "• Any custom configurations or manual changes are not affected"
    echo
    echo "Cleanup log saved to: ${LOG_FILE}"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        print_error "Cleanup failed with exit code ${exit_code}"
        print_error "Check the log file: ${LOG_FILE}"
        print_error "Some resources may still exist and require manual cleanup"
    fi
}

# Function to display help
show_help() {
    echo "Advanced Multi-Service Monitoring Dashboards - Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --dry-run       Show what would be deleted without making changes"
    echo "  -v, --verbose       Enable verbose output"
    echo "  -f, --force         Skip confirmation prompts"
    echo "  -y, --yes           Auto-confirm all prompts"
    echo "  -r, --region REGION Override AWS region"
    echo "  -p, --project NAME  Specify project name to cleanup"
    echo
    echo "EXAMPLES:"
    echo "  $0                  Interactive cleanup with confirmations"
    echo "  $0 --dry-run        Show what would be deleted"
    echo "  $0 --yes            Auto-confirm all deletions"
    echo "  $0 --project advanced-monitoring-abc123  Cleanup specific project"
    echo
    echo "SAFETY FEATURES:"
    echo "  - Confirmation prompts for destructive actions"
    echo "  - Dry-run mode to preview changes"
    echo "  - Detailed logging of all operations"
    echo "  - Verification of cleanup completion"
    echo
    echo "For more information, see the recipe documentation."
}

# Main execution function
main() {
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
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set up trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Start cleanup
    print_status "Starting Advanced Multi-Service Monitoring Dashboards cleanup..."
    print_status "Log file: ${LOG_FILE}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute cleanup steps
    validate_aws_credentials
    load_environment
    
    # List resources and confirm
    if list_resources; then
        echo
        if [[ "${DRY_RUN}" == "false" ]]; then
            confirm_action "This will permanently delete all monitoring resources for project '${PROJECT_NAME}'"
        fi
        
        # Execute cleanup in reverse order of creation
        delete_dashboards
        delete_alarms
        delete_anomaly_detectors
        delete_eventbridge_rules
        delete_lambda_functions
        delete_sns_topics
        delete_iam_role
        cleanup_temp_files
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            # Wait a moment for AWS eventual consistency
            sleep 5
            verify_cleanup
            display_summary
        else
            print_status "DRY RUN completed - no resources were deleted"
        fi
    fi
    
    print_status "Cleanup script completed successfully!"
}

# Execute main function
main "$@"