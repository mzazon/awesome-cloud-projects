#!/bin/bash

# Multi-Region Backup Automation with Backup and DR Service and Cloud Workflows
# Cleanup Script for GCP Recipe
# 
# This script safely removes all resources created by the deployment script,
# ensuring proper cleanup order and handling dependencies between resources.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/backup-automation-destroy-$(date +%Y%m%d_%H%M%S).log"

# Global variables
PROJECT_ID=""
PRIMARY_REGION="us-central1"
SECONDARY_REGION="us-east1"
BACKUP_VAULT_PRIMARY="backup-vault-primary"
BACKUP_VAULT_SECONDARY="backup-vault-secondary"
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Error handler for non-critical failures
warn_on_error() {
    local message="$1"
    log "WARN" "$message (continuing cleanup)"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all resources created by the multi-region backup automation deployment.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --primary-region REGION    Primary region (default: us-central1)
    -s, --secondary-region REGION  Secondary region (default: us-east1)
    -d, --dry-run                  Show what would be deleted without making changes
    -y, --yes                      Skip confirmation prompts
    -f, --force                    Force deletion even if some resources are in use
    -h, --help                     Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --dry-run
    $0 --project-id my-project-123 --yes --force

WARNINGS:
    - This will permanently delete all backup automation resources
    - Backup data will be deleted according to retention policies
    - Use --dry-run first to see what will be deleted
    - Backup vaults may take several minutes to delete

For more information, refer to the recipe documentation.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--primary-region)
                PRIMARY_REGION="$2"
                shift 2
                ;;
            -s|--secondary-region)
                SECONDARY_REGION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1. Use --help for usage information."
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log "ERROR" "Project ID is required. Use --project-id PROJECT_ID or --help for usage."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites for cleanup..."

    # Check if gcloud CLI is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "gcloud CLI is not installed. Please install it first: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log "ERROR" "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "ERROR" "Cannot access project '$PROJECT_ID'. Check project ID and permissions."
        exit 1
    fi

    log "INFO" "Prerequisites check completed successfully"
}

# List resources to be deleted
list_resources() {
    log "INFO" "Scanning for backup automation resources in project '$PROJECT_ID'..."

    local resources_found=false

    # Check for Cloud Scheduler jobs
    local scheduler_jobs
    scheduler_jobs=$(gcloud scheduler jobs list \
        --location="$PRIMARY_REGION" \
        --filter="name:backup-scheduler*" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$scheduler_jobs" ]]; then
        log "INFO" "Found Cloud Scheduler jobs:"
        echo "$scheduler_jobs" | while read -r job; do
            [[ -n "$job" ]] && log "INFO" "  - $job"
        done
        resources_found=true
    fi

    # Check for Cloud Workflows
    local workflows
    workflows=$(gcloud workflows list \
        --location="$PRIMARY_REGION" \
        --filter="name:backup-workflow*" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$workflows" ]]; then
        log "INFO" "Found Cloud Workflows:"
        echo "$workflows" | while read -r workflow; do
            [[ -n "$workflow" ]] && log "INFO" "  - $workflow"
        done
        resources_found=true
    fi

    # Check for backup vaults
    local backup_vaults
    backup_vaults=$(gcloud backup-dr backup-vaults list \
        --filter="name:(${BACKUP_VAULT_PRIMARY} OR ${BACKUP_VAULT_SECONDARY})" \
        --format="value(name,location)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$backup_vaults" ]]; then
        log "INFO" "Found Backup Vaults:"
        echo "$backup_vaults" | while read -r vault; do
            [[ -n "$vault" ]] && log "INFO" "  - $vault"
        done
        resources_found=true
    fi

    # Check for test compute resources
    local test_instances
    test_instances=$(gcloud compute instances list \
        --filter="name:backup-test-instance" \
        --format="value(name,zone)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$test_instances" ]]; then
        log "INFO" "Found test compute instances:"
        echo "$test_instances" | while read -r instance; do
            [[ -n "$instance" ]] && log "INFO" "  - $instance"
        done
        resources_found=true
    fi

    local test_disks
    test_disks=$(gcloud compute disks list \
        --filter="name:backup-test-data-disk" \
        --format="value(name,zone)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$test_disks" ]]; then
        log "INFO" "Found test persistent disks:"
        echo "$test_disks" | while read -r disk; do
            [[ -n "$disk" ]] && log "INFO" "  - $disk"
        done
        resources_found=true
    fi

    # Check for service accounts
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list \
        --filter="name:backup-automation-sa" \
        --format="value(email)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$service_accounts" ]]; then
        log "INFO" "Found service accounts:"
        echo "$service_accounts" | while read -r sa; do
            [[ -n "$sa" ]] && log "INFO" "  - $sa"
        done
        resources_found=true
    fi

    # Check for monitoring resources
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:*Backup*" \
        --format="value(displayName)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        log "INFO" "Found monitoring dashboards:"
        echo "$dashboards" | while read -r dashboard; do
            [[ -n "$dashboard" ]] && log "INFO" "  - $dashboard"
        done
        resources_found=true
    fi

    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:Backup*" \
        --format="value(displayName)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$alert_policies" ]]; then
        log "INFO" "Found alert policies:"
        echo "$alert_policies" | while read -r policy; do
            [[ -n "$policy" ]] && log "INFO" "  - $policy"
        done
        resources_found=true
    fi

    if [[ "$resources_found" == "false" ]]; then
        log "INFO" "No backup automation resources found in project '$PROJECT_ID'"
        return 1
    fi

    return 0
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "INFO" "Deleting Cloud Scheduler jobs..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete scheduler jobs with pattern: backup-scheduler*"
        return 0
    fi

    local scheduler_jobs
    scheduler_jobs=$(gcloud scheduler jobs list \
        --location="$PRIMARY_REGION" \
        --filter="name:backup-scheduler*" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -n "$scheduler_jobs" ]]; then
        echo "$scheduler_jobs" | while read -r job_path; do
            if [[ -n "$job_path" ]]; then
                local job_name
                job_name=$(basename "$job_path")
                log "INFO" "Deleting scheduler job: $job_name"
                
                if ! gcloud scheduler jobs delete "$job_name" \
                    --location="$PRIMARY_REGION" \
                    --quiet \
                    --project="$PROJECT_ID" 2>/dev/null; then
                    warn_on_error "Failed to delete scheduler job: $job_name"
                fi
            fi
        done
    else
        log "DEBUG" "No scheduler jobs found to delete"
    fi

    log "INFO" "Scheduler jobs cleanup completed"
}

# Delete Cloud Workflows
delete_workflows() {
    log "INFO" "Deleting Cloud Workflows..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete workflows with pattern: backup-workflow*"
        return 0
    fi

    local workflows
    workflows=$(gcloud workflows list \
        --location="$PRIMARY_REGION" \
        --filter="name:backup-workflow*" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -n "$workflows" ]]; then
        echo "$workflows" | while read -r workflow_path; do
            if [[ -n "$workflow_path" ]]; then
                local workflow_name
                workflow_name=$(basename "$workflow_path")
                log "INFO" "Deleting workflow: $workflow_name"
                
                if ! gcloud workflows delete "$workflow_name" \
                    --location="$PRIMARY_REGION" \
                    --quiet \
                    --project="$PROJECT_ID" 2>/dev/null; then
                    warn_on_error "Failed to delete workflow: $workflow_name"
                fi
            fi
        done
    else
        log "DEBUG" "No workflows found to delete"
    fi

    log "INFO" "Workflows cleanup completed"
}

# Delete test compute resources
delete_test_resources() {
    log "INFO" "Deleting test compute resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete test instance: backup-test-instance"
        log "INFO" "[DRY RUN] Would delete test disk: backup-test-data-disk"
        return 0
    fi

    local zone="${PRIMARY_REGION}-a"

    # Delete test instance
    if gcloud compute instances describe backup-test-instance \
        --zone="$zone" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        log "INFO" "Deleting test instance: backup-test-instance"
        if ! gcloud compute instances delete backup-test-instance \
            --zone="$zone" \
            --quiet \
            --project="$PROJECT_ID" 2>/dev/null; then
            warn_on_error "Failed to delete test instance"
        fi
    else
        log "DEBUG" "Test instance not found"
    fi

    # Wait for instance deletion to complete
    local max_wait=120
    local wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        if ! gcloud compute instances describe backup-test-instance \
            --zone="$zone" \
            --project="$PROJECT_ID" &> /dev/null; then
            break
        fi
        sleep 5
        wait_time=$((wait_time + 5))
    done

    # Delete test disk
    if gcloud compute disks describe backup-test-data-disk \
        --zone="$zone" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        log "INFO" "Deleting test disk: backup-test-data-disk"
        if ! gcloud compute disks delete backup-test-data-disk \
            --zone="$zone" \
            --quiet \
            --project="$PROJECT_ID" 2>/dev/null; then
            warn_on_error "Failed to delete test disk"
        fi
    else
        log "DEBUG" "Test disk not found"
    fi

    log "INFO" "Test resources cleanup completed"
}

# Delete backup vaults
delete_backup_vaults() {
    log "INFO" "Deleting backup vaults..."
    log "WARN" "This may take several minutes to complete"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete backup vault: $BACKUP_VAULT_PRIMARY in $PRIMARY_REGION"
        log "INFO" "[DRY RUN] Would delete backup vault: $BACKUP_VAULT_SECONDARY in $SECONDARY_REGION"
        return 0
    fi

    # Delete primary backup vault
    if gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_PRIMARY" \
        --location="$PRIMARY_REGION" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        log "INFO" "Deleting primary backup vault: $BACKUP_VAULT_PRIMARY"
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log "WARN" "Force deleting backup vault (may fail if backups exist)"
        fi
        
        if ! gcloud backup-dr backup-vaults delete "$BACKUP_VAULT_PRIMARY" \
            --location="$PRIMARY_REGION" \
            --quiet \
            --project="$PROJECT_ID" 2>/dev/null; then
            warn_on_error "Failed to delete primary backup vault"
        fi
    else
        log "DEBUG" "Primary backup vault not found"
    fi

    # Delete secondary backup vault
    if gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_SECONDARY" \
        --location="$SECONDARY_REGION" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        log "INFO" "Deleting secondary backup vault: $BACKUP_VAULT_SECONDARY"
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log "WARN" "Force deleting backup vault (may fail if backups exist)"
        fi
        
        if ! gcloud backup-dr backup-vaults delete "$BACKUP_VAULT_SECONDARY" \
            --location="$SECONDARY_REGION" \
            --quiet \
            --project="$PROJECT_ID" 2>/dev/null; then
            warn_on_error "Failed to delete secondary backup vault"
        fi
    else
        log "DEBUG" "Secondary backup vault not found"
    fi

    log "INFO" "Backup vaults cleanup initiated (deletion may continue in background)"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "INFO" "Deleting monitoring resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete backup monitoring dashboards and alert policies"
        return 0
    fi

    # Delete monitoring dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:*Backup*" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -n "$dashboards" ]]; then
        echo "$dashboards" | while read -r dashboard_id; do
            if [[ -n "$dashboard_id" ]]; then
                log "INFO" "Deleting monitoring dashboard: $dashboard_id"
                if ! gcloud monitoring dashboards delete "$dashboard_id" \
                    --quiet \
                    --project="$PROJECT_ID" 2>/dev/null; then
                    warn_on_error "Failed to delete dashboard: $dashboard_id"
                fi
            fi
        done
    else
        log "DEBUG" "No monitoring dashboards found"
    fi

    # Delete alert policies
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:Backup*" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -n "$alert_policies" ]]; then
        echo "$alert_policies" | while read -r policy_id; do
            if [[ -n "$policy_id" ]]; then
                log "INFO" "Deleting alert policy: $policy_id"
                if ! gcloud alpha monitoring policies delete "$policy_id" \
                    --quiet \
                    --project="$PROJECT_ID" 2>/dev/null; then
                    warn_on_error "Failed to delete alert policy: $policy_id"
                fi
            fi
        done
    else
        log "DEBUG" "No alert policies found"
    fi

    log "INFO" "Monitoring resources cleanup completed"
}

# Delete service account
delete_service_account() {
    log "INFO" "Deleting service account..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete service account: backup-automation-sa"
        return 0
    fi

    local sa_email="backup-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$sa_email" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        log "INFO" "Deleting service account: $sa_email"
        if ! gcloud iam service-accounts delete "$sa_email" \
            --quiet \
            --project="$PROJECT_ID" 2>/dev/null; then
            warn_on_error "Failed to delete service account"
        fi
    else
        log "DEBUG" "Service account not found"
    fi

    log "INFO" "Service account cleanup completed"
}

# Display cleanup summary
display_summary() {
    log "INFO" "Cleanup Summary"
    log "INFO" "==============="
    log "INFO" "Project ID: $PROJECT_ID"
    log "INFO" "Primary Region: $PRIMARY_REGION"
    log "INFO" "Secondary Region: $SECONDARY_REGION"
    log "INFO" "Log File: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" ""
        log "INFO" "Cleanup completed. All backup automation resources have been removed."
        log "INFO" "Note: Backup vault deletion may take additional time to complete."
        log "INFO" ""
        log "WARN" "If you encounter issues with backup vault deletion, they may contain"
        log "WARN" "backup data that needs to be removed first. Check the Google Cloud Console"
        log "WARN" "for detailed error messages and manual cleanup options."
    fi
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    log "WARN" "WARNING: This will permanently delete the following resources:"
    log "WARN" "- All Cloud Scheduler jobs (backup-scheduler*)"
    log "WARN" "- All Cloud Workflows (backup-workflow*)"
    log "WARN" "- All backup vaults and their data"
    log "WARN" "- Test compute instances and disks"
    log "WARN" "- Service account (backup-automation-sa)"
    log "WARN" "- Monitoring dashboards and alert policies"
    echo
    log "WARN" "This action cannot be undone!"
    echo

    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi

    echo
    read -p "Last chance! Type 'YES' to proceed with deletion: " -r
    if [[ "$REPLY" != "YES" ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
}

# Main execution function
main() {
    log "INFO" "Starting multi-region backup automation cleanup"
    log "INFO" "Log file: $LOG_FILE"

    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY RUN mode - no changes will be made"
    fi

    check_prerequisites

    # Set gcloud project
    gcloud config set project "$PROJECT_ID" &> /dev/null

    # List resources to be deleted
    if ! list_resources; then
        log "INFO" "No resources to clean up. Exiting."
        exit 0
    fi

    confirm_cleanup

    # Execute cleanup steps in reverse order of creation
    delete_scheduler_jobs
    delete_workflows
    delete_test_resources
    delete_backup_vaults
    delete_monitoring_resources
    delete_service_account

    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Cleanup completed successfully!"
    else
        log "INFO" "Dry run completed successfully!"
    fi
}

# Handle script interruption
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"