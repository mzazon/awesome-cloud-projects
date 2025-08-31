#!/bin/bash

# Automated Service Lifecycle with VPC Lattice and EventBridge - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# including Lambda functions, EventBridge resources, VPC Lattice components, and IAM roles

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
readonly LOG_FILE="/tmp/service-lifecycle-destroy-${TIMESTAMP}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-service-lifecycle}"
readonly AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"
readonly DRY_RUN="${DRY_RUN:-false}"
readonly FORCE="${FORCE:-false}"
readonly VERBOSE="${VERBOSE:-false}"

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_info "Check log file: ${LOG_FILE}"
    log_info "Some resources may still exist and require manual cleanup"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Safely remove all automated service lifecycle management infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deleted without making changes
    -f, --force            Skip confirmation prompts (use with caution)
    -v, --verbose          Enable verbose output
    -r, --region REGION    AWS region (default: ${AWS_REGION})
    -n, --name NAME        Deployment name prefix (default: ${DEPLOYMENT_NAME})
    -s, --suffix SUFFIX    Resource suffix for targeted cleanup

ENVIRONMENT VARIABLES:
    AWS_REGION             AWS region containing resources
    DEPLOYMENT_NAME        Prefix used for resource names
    DRY_RUN               Set to 'true' for dry run
    FORCE                 Set to 'true' to skip confirmations
    VERBOSE               Set to 'true' for verbose output

EXAMPLES:
    ${SCRIPT_NAME}                          # Interactive cleanup
    ${SCRIPT_NAME} --dry-run               # Preview what would be deleted
    ${SCRIPT_NAME} --force                 # Delete without confirmations
    ${SCRIPT_NAME} --suffix abc123         # Clean up specific deployment

WARNING:
    This script will permanently delete AWS resources. Use --dry-run first
    to preview what will be deleted.

EOF
}

# Parse command line arguments
parse_args() {
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
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -n|--name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            -s|--suffix)
                RESOURCE_SUFFIX="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites validation
check_prerequisites() {
    log_info "Validating prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    # Validate region
    if ! aws ec2 describe-regions --region-names "${AWS_REGION}" &> /dev/null; then
        log_error "Invalid AWS region: ${AWS_REGION}"
        exit 1
    fi

    log_success "Prerequisites validation completed"
}

# Discover existing resources
discover_resources() {
    log_info "Discovering existing resources..."

    # Initialize arrays for discovered resources
    declare -g -a SERVICE_NETWORKS=()
    declare -g -a EVENTBRIDGE_BUSES=()
    declare -g -a LAMBDA_FUNCTIONS=()
    declare -g -a IAM_ROLES=()
    declare -g -a LOG_GROUPS=()
    declare -g -a DASHBOARDS=()
    declare -g -a EVENTBRIDGE_RULES=()

    # Discover VPC Lattice service networks
    local networks=$(aws vpc-lattice list-service-networks \
        --region "${AWS_REGION}" \
        --query "items[?contains(name, '${DEPLOYMENT_NAME}')].{name:name,id:id}" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "${networks}" != "[]" ]]; then
        while IFS= read -r network; do
            SERVICE_NETWORKS+=("${network}")
        done < <(echo "${networks}" | jq -r '.[] | "\(.name)|\(.id)"')
    fi

    # Discover EventBridge custom buses
    local buses=$(aws events list-event-buses \
        --region "${AWS_REGION}" \
        --name-prefix "${DEPLOYMENT_NAME}" \
        --query "EventBuses[?contains(Name, '${DEPLOYMENT_NAME}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${buses}" ]]; then
        IFS=$'\t' read -ra EVENTBRIDGE_BUSES <<< "${buses}"
    fi

    # Discover Lambda functions
    local functions=$(aws lambda list-functions \
        --region "${AWS_REGION}" \
        --query "Functions[?contains(FunctionName, '${DEPLOYMENT_NAME}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        IFS=$'\t' read -ra LAMBDA_FUNCTIONS <<< "${functions}"
    fi

    # Discover IAM roles
    local roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${DEPLOYMENT_NAME}')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${roles}" ]]; then
        IFS=$'\t' read -ra IAM_ROLES <<< "${roles}"
    fi

    # Discover CloudWatch log groups
    local logs=$(aws logs describe-log-groups \
        --region "${AWS_REGION}" \
        --log-group-name-prefix "/aws/vpclattice/${DEPLOYMENT_NAME}" \
        --query "logGroups[].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${logs}" ]]; then
        IFS=$'\t' read -ra LOG_GROUPS <<< "${logs}"
    fi

    # Discover CloudWatch dashboards
    local dash_names=$(aws cloudwatch list-dashboards \
        --region "${AWS_REGION}" \
        --query "DashboardEntries[?contains(DashboardName, '${DEPLOYMENT_NAME}')].DashboardName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${dash_names}" ]]; then
        IFS=$'\t' read -ra DASHBOARDS <<< "${dash_names}"
    fi

    # Discover EventBridge rules
    local rules=$(aws events list-rules \
        --region "${AWS_REGION}" \
        --name-prefix "${DEPLOYMENT_NAME}" \
        --query "Rules[?contains(Name, '${DEPLOYMENT_NAME}') || contains(Name, 'health-monitoring-rule') || contains(Name, 'scheduled-health-check')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${rules}" ]]; then
        IFS=$'\t' read -ra EVENTBRIDGE_RULES <<< "${rules}"
    fi

    # Display discovered resources
    log_info "Resource discovery completed:"
    log_info "  Service Networks: ${#SERVICE_NETWORKS[@]}"
    log_info "  EventBridge Buses: ${#EVENTBRIDGE_BUSES[@]}"
    log_info "  Lambda Functions: ${#LAMBDA_FUNCTIONS[@]}"
    log_info "  IAM Roles: ${#IAM_ROLES[@]}"
    log_info "  Log Groups: ${#LOG_GROUPS[@]}"
    log_info "  Dashboards: ${#DASHBOARDS[@]}"
    log_info "  EventBridge Rules: ${#EVENTBRIDGE_RULES[@]}"

    if [[ "${VERBOSE}" == "true" ]]; then
        [[ ${#SERVICE_NETWORKS[@]} -gt 0 ]] && log_info "Service Networks: ${SERVICE_NETWORKS[*]}"
        [[ ${#EVENTBRIDGE_BUSES[@]} -gt 0 ]] && log_info "EventBridge Buses: ${EVENTBRIDGE_BUSES[*]}"
        [[ ${#LAMBDA_FUNCTIONS[@]} -gt 0 ]] && log_info "Lambda Functions: ${LAMBDA_FUNCTIONS[*]}"
        [[ ${#IAM_ROLES[@]} -gt 0 ]] && log_info "IAM Roles: ${IAM_ROLES[*]}"
        [[ ${#LOG_GROUPS[@]} -gt 0 ]] && log_info "Log Groups: ${LOG_GROUPS[*]}"
        [[ ${#DASHBOARDS[@]} -gt 0 ]] && log_info "Dashboards: ${DASHBOARDS[*]}"
        [[ ${#EVENTBRIDGE_RULES[@]} -gt 0 ]] && log_info "EventBridge Rules: ${EVENTBRIDGE_RULES[*]}"
    fi
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    local total_resources=$((${#SERVICE_NETWORKS[@]} + ${#EVENTBRIDGE_BUSES[@]} + ${#LAMBDA_FUNCTIONS[@]} + ${#IAM_ROLES[@]} + ${#LOG_GROUPS[@]} + ${#DASHBOARDS[@]} + ${#EVENTBRIDGE_RULES[@]}))
    
    if [[ ${total_resources} -eq 0 ]]; then
        log_info "No resources found to delete"
        exit 0
    fi

    log_warning "This will permanently delete ${total_resources} AWS resources"
    log_warning "This action cannot be undone!"
    
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r response
    
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove CloudWatch dashboards
remove_dashboards() {
    if [[ ${#DASHBOARDS[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing CloudWatch dashboards..."

    for dashboard in "${DASHBOARDS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete dashboard: ${dashboard}"
            continue
        fi

        aws cloudwatch delete-dashboards \
            --dashboard-names "${dashboard}" \
            --region "${AWS_REGION}" || {
            log_warning "Failed to delete dashboard: ${dashboard}"
            continue
        }

        log_success "Deleted dashboard: ${dashboard}"
    done
}

# Remove EventBridge rules and targets
remove_eventbridge_rules() {
    if [[ ${#EVENTBRIDGE_RULES[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing EventBridge rules..."

    for rule in "${EVENTBRIDGE_RULES[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete EventBridge rule: ${rule}"
            continue
        fi

        # Get rule targets first
        local targets=$(aws events list-targets-by-rule \
            --rule "${rule}" \
            --region "${AWS_REGION}" \
            --query "Targets[].Id" \
            --output text 2>/dev/null || echo "")

        # Remove targets if they exist
        if [[ -n "${targets}" ]]; then
            aws events remove-targets \
                --rule "${rule}" \
                --ids ${targets} \
                --region "${AWS_REGION}" || {
                log_warning "Failed to remove targets from rule: ${rule}"
            }
        fi

        # Check if rule belongs to custom event bus
        local event_bus=""
        for bus in "${EVENTBRIDGE_BUSES[@]}"; do
            if aws events list-targets-by-rule \
                --event-bus-name "${bus}" \
                --rule "${rule}" \
                --region "${AWS_REGION}" &>/dev/null; then
                event_bus="--event-bus-name ${bus}"
                break
            fi
        done

        # Delete the rule
        aws events delete-rule \
            ${event_bus} \
            --name "${rule}" \
            --region "${AWS_REGION}" || {
            log_warning "Failed to delete rule: ${rule}"
            continue
        }

        log_success "Deleted EventBridge rule: ${rule}"
    done
}

# Remove EventBridge custom buses
remove_eventbridge_buses() {
    if [[ ${#EVENTBRIDGE_BUSES[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing EventBridge custom buses..."

    for bus in "${EVENTBRIDGE_BUSES[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete EventBridge bus: ${bus}"
            continue
        fi

        aws events delete-event-bus \
            --name "${bus}" \
            --region "${AWS_REGION}" || {
            log_warning "Failed to delete EventBridge bus: ${bus}"
            continue
        }

        log_success "Deleted EventBridge bus: ${bus}"
    done
}

# Remove Lambda functions
remove_lambda_functions() {
    if [[ ${#LAMBDA_FUNCTIONS[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing Lambda functions..."

    for function in "${LAMBDA_FUNCTIONS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete Lambda function: ${function}"
            continue
        fi

        aws lambda delete-function \
            --function-name "${function}" \
            --region "${AWS_REGION}" || {
            log_warning "Failed to delete Lambda function: ${function}"
            continue
        }

        log_success "Deleted Lambda function: ${function}"
    done
}

# Remove VPC Lattice service networks
remove_service_networks() {
    if [[ ${#SERVICE_NETWORKS[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing VPC Lattice service networks..."

    for network_info in "${SERVICE_NETWORKS[@]}"; do
        IFS='|' read -r network_name network_id <<< "${network_info}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete service network: ${network_name} (${network_id})"
            continue
        fi

        # Delete access log subscriptions first
        local access_logs=$(aws vpc-lattice list-access-log-subscriptions \
            --resource-identifier "${network_id}" \
            --region "${AWS_REGION}" \
            --query "items[].id" \
            --output text 2>/dev/null || echo "")

        if [[ -n "${access_logs}" ]]; then
            for log_id in ${access_logs}; do
                aws vpc-lattice delete-access-log-subscription \
                    --access-log-subscription-identifier "${log_id}" \
                    --region "${AWS_REGION}" || {
                    log_warning "Failed to delete access log subscription: ${log_id}"
                }
            done
        fi

        # Delete the service network
        aws vpc-lattice delete-service-network \
            --service-network-identifier "${network_id}" \
            --region "${AWS_REGION}" || {
            log_warning "Failed to delete service network: ${network_name}"
            continue
        }

        log_success "Deleted service network: ${network_name}"
    done
}

# Remove CloudWatch log groups
remove_log_groups() {
    if [[ ${#LOG_GROUPS[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing CloudWatch log groups..."

    for log_group in "${LOG_GROUPS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete log group: ${log_group}"
            continue
        fi

        aws logs delete-log-group \
            --log-group-name "${log_group}" \
            --region "${AWS_REGION}" || {
            log_warning "Failed to delete log group: ${log_group}"
            continue
        }

        log_success "Deleted log group: ${log_group}"
    done
}

# Remove IAM roles
remove_iam_roles() {
    if [[ ${#IAM_ROLES[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Removing IAM roles..."

    for role in "${IAM_ROLES[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete IAM role: ${role}"
            continue
        fi

        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "${role}" \
            --query "AttachedPolicies[].PolicyArn" \
            --output text 2>/dev/null || echo "")

        if [[ -n "${attached_policies}" ]]; then
            for policy_arn in ${attached_policies}; do
                aws iam detach-role-policy \
                    --role-name "${role}" \
                    --policy-arn "${policy_arn}" || {
                    log_warning "Failed to detach policy ${policy_arn} from role ${role}"
                }
            done
        fi

        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "${role}" \
            --query "PolicyNames" \
            --output text 2>/dev/null || echo "")

        if [[ -n "${inline_policies}" ]]; then
            for policy_name in ${inline_policies}; do
                aws iam delete-role-policy \
                    --role-name "${role}" \
                    --policy-name "${policy_name}" || {
                    log_warning "Failed to delete inline policy ${policy_name} from role ${role}"
                }
            done
        fi

        # Delete the role
        aws iam delete-role \
            --role-name "${role}" || {
            log_warning "Failed to delete IAM role: ${role}"
            continue
        }

        log_success "Deleted IAM role: ${role}"
    done
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."

    # Remove any temporary Lambda code files
    local temp_patterns=(
        "/tmp/service-lifecycle-lambda-*"
        "/tmp/service-lifecycle-deployment-*.json"
    )

    for pattern in "${temp_patterns[@]}"; do
        for file in ${pattern}; do
            if [[ -e "${file}" ]]; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY RUN] Would remove temporary file: ${file}"
                else
                    rm -rf "${file}"
                    log_success "Removed temporary file: ${file}"
                fi
            fi
        done
    done
}

# Main cleanup function
main() {
    log_info "Starting automated service lifecycle cleanup..."
    log_info "Deployment name: ${DEPLOYMENT_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Dry run: ${DRY_RUN}"
    log_info "Force: ${FORCE}"
    log_info "Log file: ${LOG_FILE}"

    # Execute cleanup steps
    check_prerequisites
    discover_resources
    confirm_deletion

    # Remove resources in reverse order of dependencies
    remove_dashboards
    remove_eventbridge_rules
    remove_eventbridge_buses
    remove_lambda_functions
    remove_service_networks
    remove_log_groups
    remove_iam_roles
    cleanup_temp_files

    log_success "Cleanup completed successfully!"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "This was a dry run. No resources were actually deleted."
    else
        log_info "All discovered resources have been removed."
    fi
    
    log_info "Check log file for details: ${LOG_FILE}"
}

# Parse arguments and run main function
parse_args "$@"
main