#!/bin/bash

# Destroy script for Database Performance Optimization with AlloyDB Omni and Hyperdisk Extreme
# This script safely removes all infrastructure created by the deployment script

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_ROOT}/destroy-$(date +%Y%m%d-%H%M%S).log"
readonly CONFIG_FILE="${PROJECT_ROOT}/deployment-config.json"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Resource variables (will be loaded from config or command line)
INSTANCE_NAME=""
DISK_NAME=""
FUNCTION_NAME=""
DATABASE_NAME=""
DEPLOYMENT_ID=""

# Resources to delete (will be populated from config or discovery)
RESOURCES_TO_DELETE=()

# Print usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Destroy AlloyDB Omni with Hyperdisk Extreme infrastructure.

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required if no config file)
    -r, --region REGION           GCP Region (default: us-central1)
    -z, --zone ZONE               GCP Zone (default: us-central1-a)
    -i, --instance-name NAME      VM instance name to delete
    -D, --disk-name NAME          Disk name to delete
    -f, --function-name NAME      Cloud Function name to delete
    -c, --config-file FILE        Deployment config file (default: ./deployment-config.json)
    -y, --yes                     Skip confirmation prompts
    -d, --dry-run                 Show what would be deleted without executing
    --force                       Force deletion even if resources are not found in config
    -h, --help                    Show this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                    GCP Project ID
    REGION                        GCP Region
    ZONE                          GCP Zone
    SKIP_CONFIRMATION             Skip confirmation prompts (true/false)
    DRY_RUN                       Dry run mode (true/false)
    FORCE_DELETE                  Force deletion mode (true/false)

EXAMPLES:
    $SCRIPT_NAME --project-id my-project
    $SCRIPT_NAME -c /path/to/config.json --yes
    $SCRIPT_NAME --instance-name alloydb-vm-abc123 --disk-name hyperdisk-extreme-abc123
    $SCRIPT_NAME --dry-run --config-file ./deployment-config.json
    $SCRIPT_NAME --force --project-id my-project

NOTES:
    • Script will attempt to load configuration from deployment-config.json first
    • If no config file is found, you must specify resource names manually
    • Use --force to delete resources even if they're not in the config file
    • Dry-run mode shows what would be deleted without actually deleting anything

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
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -i|--instance-name)
                INSTANCE_NAME="$2"
                shift 2
                ;;
            -D|--disk-name)
                DISK_NAME="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -c|--config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            --force)
                FORCE_DELETE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load configuration from deployment config file
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Found deployment config file: $CONFIG_FILE"
        
        if command -v jq &> /dev/null; then
            # Extract configuration using jq
            PROJECT_ID="${PROJECT_ID:-$(jq -r '.project_id // empty' "$CONFIG_FILE")}"
            REGION="${REGION:-$(jq -r '.region // empty' "$CONFIG_FILE")}"
            ZONE="${ZONE:-$(jq -r '.zone // empty' "$CONFIG_FILE")}"
            INSTANCE_NAME="${INSTANCE_NAME:-$(jq -r '.instance_name // empty' "$CONFIG_FILE")}"
            DISK_NAME="${DISK_NAME:-$(jq -r '.disk_name // empty' "$CONFIG_FILE")}"
            FUNCTION_NAME="${FUNCTION_NAME:-$(jq -r '.function_name // empty' "$CONFIG_FILE")}"
            DATABASE_NAME="$(jq -r '.database_name // empty' "$CONFIG_FILE")"
            DEPLOYMENT_ID="$(jq -r '.deployment_id // empty' "$CONFIG_FILE")"
            
            # Load created resources list
            local resources
            resources=$(jq -r '.created_resources[]? // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ -n "$resources" ]]; then
                while IFS= read -r resource; do
                    [[ -n "$resource" ]] && RESOURCES_TO_DELETE+=("$resource")
                done <<< "$resources"
            fi
            
            log_success "Configuration loaded from $CONFIG_FILE"
        else
            log_warning "jq not found, attempting to parse config manually"
            # Basic parsing without jq (less reliable)
            PROJECT_ID="${PROJECT_ID:-$(grep -o '"project_id":[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 2>/dev/null || echo "")}"
            INSTANCE_NAME="${INSTANCE_NAME:-$(grep -o '"instance_name":[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 2>/dev/null || echo "")}"
            DISK_NAME="${DISK_NAME:-$(grep -o '"disk_name":[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 2>/dev/null || echo "")}"
            FUNCTION_NAME="${FUNCTION_NAME:-$(grep -o '"function_name":[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 2>/dev/null || echo "")}"
        fi
    else
        log_warning "No deployment config file found at: $CONFIG_FILE"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            log_info "Use --force to proceed without config file, or specify resource names manually"
        fi
    fi
}

# Discover resources if not loaded from config
discover_resources() {
    log_info "Discovering AlloyDB Omni resources..."
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is required. Use --project-id or ensure it's in the config file."
        exit 1
    fi
    
    # Set gcloud project
    gcloud config set project "$PROJECT_ID" &> /dev/null
    
    # Discover VM instances with alloydb-omni tag if not specified
    if [[ -z "$INSTANCE_NAME" ]]; then
        log_info "Searching for AlloyDB Omni instances..."
        local instances
        instances=$(gcloud compute instances list --filter="tags.items:alloydb-omni" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$instances" ]]; then
            # Take the first match
            INSTANCE_NAME=$(echo "$instances" | head -n1)
            log_info "Found AlloyDB Omni instance: $INSTANCE_NAME"
        fi
    fi
    
    # Discover Hyperdisk Extreme disks if not specified
    if [[ -z "$DISK_NAME" ]]; then
        log_info "Searching for Hyperdisk Extreme volumes..."
        local disks
        disks=$(gcloud compute disks list --filter="type:hyperdisk-extreme AND name~hyperdisk-extreme" --format="value(name)" --zones="$ZONE" 2>/dev/null || echo "")
        if [[ -n "$disks" ]]; then
            # Take the first match
            DISK_NAME=$(echo "$disks" | head -n1)
            log_info "Found Hyperdisk Extreme disk: $DISK_NAME"
        fi
    fi
    
    # Discover Cloud Functions if not specified
    if [[ -z "$FUNCTION_NAME" ]]; then
        log_info "Searching for performance scaling functions..."
        local functions
        functions=$(gcloud functions list --filter="name~perf-scaler" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$functions" ]]; then
            # Take the first match (extract just the function name)
            FUNCTION_NAME=$(echo "$functions" | head -n1 | sed 's|.*/||')
            log_info "Found Cloud Function: $FUNCTION_NAME"
        fi
    fi
    
    # Build resources list if not loaded from config
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        [[ -n "$INSTANCE_NAME" ]] && RESOURCES_TO_DELETE+=("instance:$INSTANCE_NAME")
        [[ -n "$DISK_NAME" ]] && RESOURCES_TO_DELETE+=("disk:$DISK_NAME")
        [[ -n "$FUNCTION_NAME" ]] && RESOURCES_TO_DELETE+=("function:$FUNCTION_NAME")
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check gcloud authentication
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 2>/dev/null || echo "")
    if [[ -z "$active_account" ]]; then
        log_error "No active gcloud authentication found. Run 'gcloud auth login' first."
        exit 1
    fi
    log_info "Using authenticated account: $active_account"
    
    # Validate PROJECT_ID
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is required. Use --project-id or ensure it's in the config file."
        exit 1
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Display destruction plan
show_destruction_plan() {
    cat << EOF

${RED}=== AlloyDB Omni Destruction Plan ===${NC}

Project ID:         $PROJECT_ID
Region:             $REGION
Zone:               $ZONE
Config File:        $CONFIG_FILE
Log File:           $LOG_FILE
Deployment ID:      ${DEPLOYMENT_ID:-"Unknown"}

${RED}Resources to be deleted:${NC}
EOF

    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        echo "• No resources found to delete"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            echo ""
            echo "${YELLOW}Use --force to discover and delete resources, or specify them manually${NC}"
        fi
    else
        for resource in "${RESOURCES_TO_DELETE[@]}"; do
            IFS=':' read -r type name <<< "$resource"
            case "$type" in
                "instance")
                    echo "• VM Instance: $name (c3-highmem-8)"
                    ;;
                "disk")
                    echo "• Hyperdisk Extreme: $name (500GB, 100K IOPS)"
                    ;;
                "function")
                    echo "• Cloud Function: $name"
                    ;;
                "dashboard")
                    echo "• Monitoring Dashboard: $name"
                    ;;
                "alert")
                    echo "• Alert Policy: $name"
                    ;;
                *)
                    echo "• Unknown resource type: $type:$name"
                    ;;
            esac
        done
    fi
    
    # Additional cleanup
    cat << EOF

${RED}Additional cleanup actions:${NC}
• Stop and remove AlloyDB Omni container
• Unmount Hyperdisk Extreme volume
• Remove monitoring dashboards and alert policies
• Clean up local configuration files

${YELLOW}Warning:${NC} This action cannot be undone!
${YELLOW}Note:${NC} All data in the AlloyDB Omni database will be permanently lost!

EOF
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo -e "${RED}⚠️  WARNING: This will permanently delete all AlloyDB Omni resources! ⚠️${NC}"
    echo -n "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: "
    read -r response
    if [[ "$response" == "DELETE" ]]; then
        return 0
    else
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        log_info "[DRY-RUN] Command: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "$description completed"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "$description failed (ignoring error)"
            return 0
        else
            log_error "$description failed"
            return 1
        fi
    fi
}

# Stop AlloyDB Omni container and unmount disk
cleanup_vm_instance() {
    if [[ -z "$INSTANCE_NAME" ]]; then
        log_warning "No VM instance name provided, skipping container cleanup"
        return 0
    fi
    
    log_info "Cleaning up AlloyDB Omni container and unmounting disk..."
    
    # Check if instance exists and is running
    local instance_status
    instance_status=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$instance_status" == "NOT_FOUND" ]]; then
        log_warning "Instance $INSTANCE_NAME not found, skipping container cleanup"
        return 0
    fi
    
    if [[ "$instance_status" == "RUNNING" ]]; then
        local cleanup_cmd="gcloud compute ssh '$INSTANCE_NAME' \\
            --zone='$ZONE' \\
            --command='
              echo \"Stopping AlloyDB Omni container...\"
              sudo docker stop alloydb-omni 2>/dev/null || echo \"Container already stopped\"
              sudo docker rm alloydb-omni 2>/dev/null || echo \"Container already removed\"
              
              echo \"Unmounting Hyperdisk Extreme...\"
              sudo umount /var/lib/alloydb 2>/dev/null || echo \"Disk already unmounted\"
              
              echo \"Removing fstab entry...\"
              sudo sed -i '/google-alloydb-data/d' /etc/fstab 2>/dev/null || echo \"No fstab entry found\"
              
              echo \"Container and disk cleanup completed\"
            '"
        
        execute_cmd "$cleanup_cmd" "Cleaning up AlloyDB Omni container" "true"
    else
        log_info "Instance $INSTANCE_NAME is not running, skipping container cleanup"
    fi
}

# Delete VM instance
delete_vm_instance() {
    if [[ -z "$INSTANCE_NAME" ]]; then
        log_warning "No VM instance name provided, skipping"
        return 0
    fi
    
    log_info "Deleting VM instance..."
    
    # Check if instance exists
    if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &> /dev/null; then
        log_warning "Instance $INSTANCE_NAME not found, skipping"
        return 0
    fi
    
    local cmd="gcloud compute instances delete '$INSTANCE_NAME' \\
        --zone='$ZONE' \\
        --quiet"
    
    execute_cmd "$cmd" "Deleting VM instance: $INSTANCE_NAME"
}

# Delete Hyperdisk Extreme volume
delete_hyperdisk() {
    if [[ -z "$DISK_NAME" ]]; then
        log_warning "No disk name provided, skipping"
        return 0
    fi
    
    log_info "Deleting Hyperdisk Extreme volume..."
    
    # Check if disk exists
    if ! gcloud compute disks describe "$DISK_NAME" --zone="$ZONE" &> /dev/null; then
        log_warning "Disk $DISK_NAME not found, skipping"
        return 0
    fi
    
    local cmd="gcloud compute disks delete '$DISK_NAME' \\
        --zone='$ZONE' \\
        --quiet"
    
    execute_cmd "$cmd" "Deleting Hyperdisk Extreme volume: $DISK_NAME"
}

# Delete Cloud Function
delete_cloud_function() {
    if [[ -z "$FUNCTION_NAME" ]]; then
        log_warning "No Cloud Function name provided, skipping"
        return 0
    fi
    
    log_info "Deleting Cloud Function..."
    
    # Check if function exists
    if ! gcloud functions describe "$FUNCTION_NAME" &> /dev/null; then
        log_warning "Function $FUNCTION_NAME not found, skipping"
        return 0
    fi
    
    local cmd="gcloud functions delete '$FUNCTION_NAME' \\
        --quiet"
    
    execute_cmd "$cmd" "Deleting Cloud Function: $FUNCTION_NAME"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # Delete dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list --filter="displayName:'AlloyDB Omni Performance Dashboard'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$dashboards" ]]; then
        while IFS= read -r dashboard_id; do
            [[ -n "$dashboard_id" ]] && execute_cmd "gcloud monitoring dashboards delete '$dashboard_id' --quiet" "Deleting dashboard: $dashboard_id" "true"
        done <<< "$dashboards"
    else
        log_info "No AlloyDB Omni dashboards found"
    fi
    
    # Delete alert policies
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list --filter="displayName:'AlloyDB Omni High CPU Alert'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$alert_policies" ]]; then
        while IFS= read -r policy_id; do
            [[ -n "$policy_id" ]] && execute_cmd "gcloud alpha monitoring policies delete '$policy_id' --quiet" "Deleting alert policy: $policy_id" "true"
        done <<< "$alert_policies"
    else
        log_info "No AlloyDB Omni alert policies found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "$CONFIG_FILE"
        "$PROJECT_ROOT/dashboard-config.json"
        "$PROJECT_ROOT/alert-policy.json"
        "$PROJECT_ROOT/scaling-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ "$DRY_RUN" != "true" ]]; then
                rm -rf "$file"
                log_success "Removed: $file"
            else
                log_info "[DRY-RUN] Would remove: $file"
            fi
        fi
    done
}

# Verify resources are deleted
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Skipping verification in dry-run mode"
        return 0
    fi
    
    local all_deleted=true
    
    # Check VM instance
    if [[ -n "$INSTANCE_NAME" ]]; then
        if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &> /dev/null; then
            log_error "VM instance $INSTANCE_NAME still exists"
            all_deleted=false
        else
            log_success "VM instance $INSTANCE_NAME successfully deleted"
        fi
    fi
    
    # Check disk
    if [[ -n "$DISK_NAME" ]]; then
        if gcloud compute disks describe "$DISK_NAME" --zone="$ZONE" &> /dev/null; then
            log_error "Disk $DISK_NAME still exists"
            all_deleted=false
        else
            log_success "Disk $DISK_NAME successfully deleted"
        fi
    fi
    
    # Check Cloud Function
    if [[ -n "$FUNCTION_NAME" ]]; then
        if gcloud functions describe "$FUNCTION_NAME" &> /dev/null; then
            log_error "Cloud Function $FUNCTION_NAME still exists"
            all_deleted=false
        else
            log_success "Cloud Function $FUNCTION_NAME successfully deleted"
        fi
    fi
    
    if [[ "$all_deleted" == "true" ]]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may not have been deleted completely"
    fi
}

# Display destruction summary
show_destruction_summary() {
    cat << EOF

${GREEN}=== Destruction Completed ===${NC}

${BLUE}Deleted Resources:${NC}
• VM Instance:        ${INSTANCE_NAME:-"None"}
• Hyperdisk Extreme:  ${DISK_NAME:-"None"}
• Cloud Function:     ${FUNCTION_NAME:-"None"}
• Monitoring Resources (dashboards and alerts)
• Local configuration files

${BLUE}Actions Performed:${NC}
• Stopped and removed AlloyDB Omni container
• Unmounted Hyperdisk Extreme volume
• Deleted all cloud resources
• Cleaned up local files

${GREEN}Cleanup completed successfully!${NC}

${YELLOW}Log File:${NC} $LOG_FILE

${BLUE}Note:${NC} All AlloyDB Omni data has been permanently deleted.
If you need to deploy again, use the deploy.sh script.

EOF
}

# Main destruction function
main() {
    log_info "Starting AlloyDB Omni destruction script"
    log_info "Log file: $LOG_FILE"
    
    parse_args "$@"
    load_deployment_config
    validate_prerequisites
    
    # If force mode or no resources found, discover them
    if [[ "$FORCE_DELETE" == "true" ]] || [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        discover_resources
    fi
    
    show_destruction_plan
    confirm_destruction
    
    # Execute destruction steps
    cleanup_vm_instance
    delete_cloud_function
    delete_vm_instance
    delete_hyperdisk
    delete_monitoring_resources
    cleanup_local_files
    verify_deletion
    
    show_destruction_summary
    
    log_success "Destruction completed successfully!"
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"