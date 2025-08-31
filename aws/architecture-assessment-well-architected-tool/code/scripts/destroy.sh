#!/bin/bash

# AWS Well-Architected Tool Assessment Cleanup Script
# This script removes the workload and cleans up all associated resources

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail  # Exit if any command in a pipeline fails

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Help function
show_help() {
    cat << EOF
AWS Well-Architected Tool Assessment Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -w, --workload-id       Specific workload ID to delete
    -n, --workload-name     Specific workload name to delete
    --force                 Skip confirmation prompts
    --dry-run              Show what would be done without making changes
    -v, --verbose          Enable verbose logging
    --list-workloads       List all workloads and exit

EXAMPLES:
    $0                                         # Delete workload from deployment
    $0 -w "12345678-1234-1234-1234-123456789012"  # Delete specific workload
    $0 -n "sample-web-app-abc123"             # Delete by name
    $0 --dry-run                              # Preview deletions
    $0 --force                                # Skip confirmations
    $0 --list-workloads                       # List all workloads

SAFETY FEATURES:
    - Confirmation prompts before deletion (unless --force is used)
    - Validation of workload existence before deletion
    - Detailed logging of all operations
    - Dry-run mode to preview actions

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -w|--workload-id)
                SPECIFIED_WORKLOAD_ID="$2"
                shift 2
                ;;
            -n|--workload-name)
                SPECIFIED_WORKLOAD_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --list-workloads)
                LIST_WORKLOADS=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisite checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        log_info "Run 'aws configure' to set up credentials."
        exit 1
    fi
    
    # Check Well-Architected Tool permissions
    if ! aws wellarchitected list-workloads --query 'WorkloadSummaries[0]' &> /dev/null; then
        log_error "Insufficient permissions for AWS Well-Architected Tool."
        log_info "Required permissions: wellarchitected:* actions"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# List all workloads
list_workloads() {
    log_info "Listing all Well-Architected workloads..."
    
    local workloads
    workloads=$(aws wellarchitected list-workloads \
        --query 'WorkloadSummaries[].{
            WorkloadId: WorkloadId,
            WorkloadName: WorkloadName,
            Owner: Owner,
            UpdatedAt: UpdatedAt,
            RiskCounts: RiskCounts
        }' --output json)
    
    if [[ $? -eq 0 ]]; then
        local count=$(echo "$workloads" | jq '. | length')
        log_info "Found ${count} workload(s):"
        echo "$workloads" | jq '.'
    else
        log_error "Failed to list workloads"
        exit 1
    fi
}

# Find workload ID from stored files or parameters
find_workload_id() {
    log_info "Determining workload to delete..."
    
    # Priority 1: Command line specified workload ID
    if [[ -n "${SPECIFIED_WORKLOAD_ID:-}" ]]; then
        WORKLOAD_ID="$SPECIFIED_WORKLOAD_ID"
        log_info "Using specified workload ID: ${WORKLOAD_ID}"
        return 0
    fi
    
    # Priority 2: Command line specified workload name
    if [[ -n "${SPECIFIED_WORKLOAD_NAME:-}" ]]; then
        WORKLOAD_ID=$(aws wellarchitected list-workloads \
            --workload-name-prefix "${SPECIFIED_WORKLOAD_NAME}" \
            --query 'WorkloadSummaries[0].WorkloadId' --output text)
        
        if [[ "$WORKLOAD_ID" == "None" || -z "$WORKLOAD_ID" ]]; then
            log_error "No workload found with name: ${SPECIFIED_WORKLOAD_NAME}"
            exit 1
        fi
        
        log_info "Found workload ID ${WORKLOAD_ID} for name: ${SPECIFIED_WORKLOAD_NAME}"
        return 0
    fi
    
    # Priority 3: Stored workload ID from deployment
    if [[ -f "${SCRIPT_DIR}/.workload_id" ]]; then
        WORKLOAD_ID=$(cat "${SCRIPT_DIR}/.workload_id")
        WORKLOAD_NAME=$(cat "${SCRIPT_DIR}/.workload_name" 2>/dev/null || echo "Unknown")
        log_info "Using stored workload ID: ${WORKLOAD_ID} (${WORKLOAD_NAME})"
        return 0
    fi
    
    log_error "No workload specified and no stored workload found."
    log_info "Use -w <workload-id> or -n <workload-name> to specify a workload."
    log_info "Use --list-workloads to see available workloads."
    exit 1
}

# Validate workload exists
validate_workload() {
    log_info "Validating workload exists..."
    
    local workload_info
    workload_info=$(aws wellarchitected get-workload \
        --workload-id "${WORKLOAD_ID}" \
        --query '{
            WorkloadName: Workload.WorkloadName,
            Environment: Workload.Environment,
            UpdatedAt: Workload.UpdatedAt,
            RiskCounts: Workload.RiskCounts
        }' --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        WORKLOAD_NAME=$(echo "$workload_info" | jq -r '.WorkloadName')
        log_success "Workload validation passed"
        log_info "Workload details:"
        echo "$workload_info" | jq '.'
    else
        log_error "Workload not found or inaccessible: ${WORKLOAD_ID}"
        exit 1
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This will permanently delete the following workload:"
    echo "  - ID: ${WORKLOAD_ID}"
    echo "  - Name: ${WORKLOAD_NAME}"
    echo
    echo "This action will:"
    echo "  ✗ Remove all assessment data and progress"
    echo "  ✗ Delete improvement recommendations"
    echo "  ✗ Remove milestone snapshots"
    echo "  ✗ Cannot be undone"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed deletion"
}

# Export assessment data (backup)
backup_assessment_data() {
    log_info "Creating assessment data backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create assessment backup"
        return 0
    fi
    
    local backup_dir="${SCRIPT_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup workload details
    aws wellarchitected get-workload \
        --workload-id "${WORKLOAD_ID}" \
        --output json > "${backup_dir}/workload.json"
    
    # Backup lens review
    aws wellarchitected get-lens-review \
        --workload-id "${WORKLOAD_ID}" \
        --lens-alias "wellarchitected" \
        --output json > "${backup_dir}/lens_review.json" 2>/dev/null || true
    
    # Backup improvement recommendations
    aws wellarchitected list-lens-review-improvements \
        --workload-id "${WORKLOAD_ID}" \
        --lens-alias "wellarchitected" \
        --output json > "${backup_dir}/improvements.json" 2>/dev/null || true
    
    # Backup answers for each pillar
    local pillars=("operationalExcellence" "security" "reliability" "performance" "costOptimization" "sustainability")
    for pillar in "${pillars[@]}"; do
        aws wellarchitected list-answers \
            --workload-id "${WORKLOAD_ID}" \
            --lens-alias "wellarchitected" \
            --pillar-id "$pillar" \
            --output json > "${backup_dir}/answers_${pillar}.json" 2>/dev/null || true
    done
    
    log_success "Assessment data backed up to: ${backup_dir}"
    echo "Backup directory: ${backup_dir}" > "${SCRIPT_DIR}/.last_backup"
}

# Delete workload
delete_workload() {
    log_info "Deleting Well-Architected workload..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete workload: ${WORKLOAD_ID}"
        return 0
    fi
    
    # Delete the workload
    if aws wellarchitected delete-workload --workload-id "${WORKLOAD_ID}"; then
        log_success "Workload deleted successfully"
    else
        log_error "Failed to delete workload"
        exit 1
    fi
}

# Verify deletion
verify_deletion() {
    log_info "Verifying workload deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify workload deletion"
        return 0
    fi
    
    # Wait a moment for deletion to propagate
    sleep 2
    
    # Try to get the workload (should fail)
    if aws wellarchitected get-workload --workload-id "${WORKLOAD_ID}" &> /dev/null; then
        log_error "Workload still exists after deletion attempt"
        exit 1
    else
        log_success "Workload deletion verified"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove stored workload information
    rm -f "${SCRIPT_DIR}/.workload_id"
    rm -f "${SCRIPT_DIR}/.workload_name"
    
    # Clean up environment variables
    unset WORKLOAD_ID WORKLOAD_NAME AWS_REGION AWS_ACCOUNT_ID 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Main cleanup function
main() {
    log_info "Starting AWS Well-Architected Tool cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    parse_arguments "$@"
    check_prerequisites
    
    # Handle list workloads option
    if [[ "${LIST_WORKLOADS:-false}" == "true" ]]; then
        list_workloads
        exit 0
    fi
    
    find_workload_id
    validate_workload
    confirm_deletion
    backup_assessment_data
    delete_workload
    verify_deletion
    cleanup_local_files
    
    log_success "Cleanup completed successfully!"
    
    cat << EOF

🧹 AWS Well-Architected Tool Cleanup Complete!

Actions Performed:
  ✅ Workload deleted: ${WORKLOAD_NAME} (${WORKLOAD_ID})
  ✅ Assessment data backed up
  ✅ Local files cleaned up

Backup Information:
  📁 Assessment data has been preserved in the backup directory
  📝 Check ${SCRIPT_DIR}/.last_backup for backup location

Resources Removed:
  - Well-Architected workload and all assessment data
  - Improvement recommendations and milestones
  - Local tracking files

Note: Well-Architected Tool assessments do not incur charges,
but backups are stored locally for your reference.

EOF
}

# Execute main function with all arguments
main "$@"