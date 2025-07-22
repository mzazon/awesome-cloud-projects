#!/bin/bash

# AWS IoT Device Management Cleanup Script
# This script safely removes all resources created by the deployment script
# Recipe: IoT Device Lifecycle Management

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deployment-config.env"

# Check if running in dry-run mode
DRY_RUN=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Show what would be deleted without actually deleting"
            echo "  --yes, -y         Skip confirmation prompts"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load deployment configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "Please run the deploy script first or provide the configuration manually."
        exit 1
    fi
    
    log "Loading deployment configuration..."
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=("AWS_REGION" "FLEET_NAME" "THING_TYPE_NAME" "THING_GROUP_NAME" "POLICY_NAME" "RANDOM_SUFFIX")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in configuration"
            exit 1
        fi
    done
    
    info "Configuration loaded successfully"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    warn "⚠️  WARNING: This will permanently delete all IoT Device Management resources!"
    warn "Resources to be deleted:"
    warn "  - Thing Type: $THING_TYPE_NAME"
    warn "  - Thing Group: $THING_GROUP_NAME"
    warn "  - IoT Policy: $POLICY_NAME"
    warn "  - Dynamic Thing Groups: outdated-firmware-${RANDOM_SUFFIX}, building-a-sensors-${RANDOM_SUFFIX}"
    warn "  - IoT Jobs: firmware-update-${RANDOM_SUFFIX}"
    warn "  - Fleet Metrics: ConnectedDevices-${RANDOM_SUFFIX}, FirmwareVersions-${RANDOM_SUFFIX}"
    warn "  - CloudWatch Log Group: /aws/iot/device-management-${RANDOM_SUFFIX}"
    warn "  - All IoT Things and Certificates"
    warn ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
}

# Delete IoT Jobs and Fleet Metrics
delete_jobs_and_metrics() {
    log "Deleting IoT jobs and fleet metrics..."
    
    # Cancel and delete IoT job
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would cancel and delete job: firmware-update-${RANDOM_SUFFIX}"
    else
        # Check if job exists before trying to cancel
        if aws iot describe-job --job-id "firmware-update-${RANDOM_SUFFIX}" &> /dev/null; then
            aws iot cancel-job --job-id "firmware-update-${RANDOM_SUFFIX}" || true
            
            # Wait a moment for job cancellation
            sleep 2
            
            aws iot delete-job --job-id "firmware-update-${RANDOM_SUFFIX}" || true
            info "Deleted IoT job: firmware-update-${RANDOM_SUFFIX} ✅"
        else
            info "Job firmware-update-${RANDOM_SUFFIX} not found, skipping"
        fi
    fi
    
    # Delete fleet metrics
    local metrics=("ConnectedDevices-${RANDOM_SUFFIX}" "FirmwareVersions-${RANDOM_SUFFIX}")
    for metric in "${metrics[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would delete fleet metric: $metric"
        else
            if aws iot describe-fleet-metric --metric-name "$metric" &> /dev/null; then
                aws iot delete-fleet-metric --metric-name "$metric"
                info "Deleted fleet metric: $metric ✅"
            else
                info "Fleet metric $metric not found, skipping"
            fi
        fi
    done
    
    log "Jobs and metrics cleanup completed ✅"
}

# Remove device certificates and policies
remove_certificates() {
    log "Removing device certificates and policies..."
    
    local devices=("temp-sensor-01" "temp-sensor-02" "temp-sensor-03" "temp-sensor-04")
    
    for device in "${devices[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would remove certificates for device: $device"
            continue
        fi
        
        # Check if thing exists
        if ! aws iot describe-thing --thing-name "$device" &> /dev/null; then
            info "Device $device not found, skipping certificate cleanup"
            continue
        fi
        
        # Get certificate ARNs for the device
        local cert_arns
        cert_arns=$(aws iot list-thing-principals --thing-name "$device" \
            --query 'principals[]' --output text 2>/dev/null || echo "")
        
        if [[ -n "$cert_arns" ]]; then
            for cert_arn in $cert_arns; do
                # Detach policy from certificate
                aws iot detach-policy \
                    --policy-name "$POLICY_NAME" \
                    --target "$cert_arn" 2>/dev/null || true
                
                # Detach certificate from thing
                aws iot detach-thing-principal \
                    --thing-name "$device" \
                    --principal "$cert_arn" 2>/dev/null || true
                
                # Get certificate ID and deactivate
                local cert_id
                cert_id=$(echo "$cert_arn" | cut -d'/' -f2)
                
                aws iot update-certificate \
                    --certificate-id "$cert_id" \
                    --new-status INACTIVE 2>/dev/null || true
                
                # Delete certificate
                aws iot delete-certificate \
                    --certificate-id "$cert_id" 2>/dev/null || true
                
                info "Deleted certificate for device: $device ✅"
            done
        else
            info "No certificates found for device: $device"
        fi
    done
    
    log "Certificate cleanup completed ✅"
}

# Remove thing groups and dynamic groups
remove_thing_groups() {
    log "Removing thing groups..."
    
    local devices=("temp-sensor-01" "temp-sensor-02" "temp-sensor-03" "temp-sensor-04")
    
    # Remove devices from static group
    for device in "${devices[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would remove device from group: $device"
            continue
        fi
        
        # Check if thing exists and is in group
        if aws iot describe-thing --thing-name "$device" &> /dev/null; then
            aws iot remove-thing-from-thing-group \
                --thing-name "$device" \
                --thing-group-name "$THING_GROUP_NAME" 2>/dev/null || true
            info "Removed device from group: $device ✅"
        fi
    done
    
    # Delete dynamic thing groups
    local dynamic_groups=("outdated-firmware-${RANDOM_SUFFIX}" "building-a-sensors-${RANDOM_SUFFIX}")
    for group in "${dynamic_groups[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would delete dynamic group: $group"
        else
            if aws iot describe-thing-group --thing-group-name "$group" &> /dev/null; then
                aws iot delete-dynamic-thing-group --thing-group-name "$group"
                info "Deleted dynamic group: $group ✅"
            else
                info "Dynamic group $group not found, skipping"
            fi
        fi
    done
    
    # Delete static thing group
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete static group: $THING_GROUP_NAME"
    else
        if aws iot describe-thing-group --thing-group-name "$THING_GROUP_NAME" &> /dev/null; then
            aws iot delete-thing-group --thing-group-name "$THING_GROUP_NAME"
            info "Deleted static group: $THING_GROUP_NAME ✅"
        else
            info "Static group $THING_GROUP_NAME not found, skipping"
        fi
    fi
    
    log "Thing groups cleanup completed ✅"
}

# Remove IoT things and policies
remove_things_and_policies() {
    log "Removing IoT things and policies..."
    
    local devices=("temp-sensor-01" "temp-sensor-02" "temp-sensor-03" "temp-sensor-04")
    
    # Delete IoT things
    for device in "${devices[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would delete thing: $device"
        else
            if aws iot describe-thing --thing-name "$device" &> /dev/null; then
                aws iot delete-thing --thing-name "$device"
                info "Deleted thing: $device ✅"
            else
                info "Thing $device not found, skipping"
            fi
        fi
    done
    
    # Delete thing type
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete thing type: $THING_TYPE_NAME"
    else
        if aws iot describe-thing-type --thing-type-name "$THING_TYPE_NAME" &> /dev/null; then
            aws iot delete-thing-type --thing-type-name "$THING_TYPE_NAME"
            info "Deleted thing type: $THING_TYPE_NAME ✅"
        else
            info "Thing type $THING_TYPE_NAME not found, skipping"
        fi
    fi
    
    # Delete IoT policy
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete IoT policy: $POLICY_NAME"
    else
        if aws iot get-policy --policy-name "$POLICY_NAME" &> /dev/null; then
            aws iot delete-policy --policy-name "$POLICY_NAME"
            info "Deleted IoT policy: $POLICY_NAME ✅"
        else
            info "IoT policy $POLICY_NAME not found, skipping"
        fi
    fi
    
    log "Things and policies cleanup completed ✅"
}

# Clean up logging resources
cleanup_logging() {
    log "Cleaning up logging resources..."
    
    # Delete CloudWatch log group
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would delete log group: /aws/iot/device-management-${RANDOM_SUFFIX}"
    else
        if aws logs describe-log-groups \
            --log-group-name-prefix "/aws/iot/device-management-${RANDOM_SUFFIX}" \
            --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "device-management"; then
            aws logs delete-log-group \
                --log-group-name "/aws/iot/device-management-${RANDOM_SUFFIX}"
            info "Deleted log group: /aws/iot/device-management-${RANDOM_SUFFIX} ✅"
        else
            info "Log group /aws/iot/device-management-${RANDOM_SUFFIX} not found, skipping"
        fi
    fi
    
    log "Logging cleanup completed ✅"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "$SCRIPT_DIR/deployment-config.env"
        "$SCRIPT_DIR/device-list.txt"
        "$SCRIPT_DIR/certificate-ids.txt"
        "device-policy.json"
        "firmware-update-job.json"
        "shadow-update.json"
        "shadow-output.json"
        "retrieved-shadow.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ -f "$file" ]]; then
                info "[DRY-RUN] Would delete local file: $file"
            fi
        else
            if [[ -f "$file" ]]; then
                rm -f "$file"
                info "Deleted local file: $file ✅"
            fi
        fi
    done
    
    log "Local files cleanup completed ✅"
}

# Validation function
validate_cleanup() {
    log "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would validate cleanup"
        return
    fi
    
    local cleanup_issues=0
    
    # Check if thing group still exists
    if aws iot describe-thing-group --thing-group-name "$THING_GROUP_NAME" &> /dev/null; then
        warn "Thing group still exists: $THING_GROUP_NAME"
        ((cleanup_issues++))
    fi
    
    # Check if thing type still exists
    if aws iot describe-thing-type --thing-type-name "$THING_TYPE_NAME" &> /dev/null; then
        warn "Thing type still exists: $THING_TYPE_NAME"
        ((cleanup_issues++))
    fi
    
    # Check if policy still exists
    if aws iot get-policy --policy-name "$POLICY_NAME" &> /dev/null; then
        warn "IoT policy still exists: $POLICY_NAME"
        ((cleanup_issues++))
    fi
    
    # Check devices
    local devices=("temp-sensor-01" "temp-sensor-02" "temp-sensor-03" "temp-sensor-04")
    for device in "${devices[@]}"; do
        if aws iot describe-thing --thing-name "$device" &> /dev/null; then
            warn "Device still exists: $device"
            ((cleanup_issues++))
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Cleanup validation passed ✅"
    else
        warn "Cleanup validation found $cleanup_issues issues"
    fi
}

# Main cleanup function
main() {
    log "Starting AWS IoT Device Management cleanup..."
    
    # Load configuration
    load_config
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm destruction
    confirm_destruction
    
    # Perform cleanup in correct order
    delete_jobs_and_metrics
    remove_certificates
    remove_thing_groups
    remove_things_and_policies
    cleanup_logging
    cleanup_local_files
    
    # Validate cleanup
    validate_cleanup
    
    log "Cleanup completed successfully! ✅"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "All AWS IoT Device Management resources have been removed"
        info "Configuration files have been cleaned up"
    else
        info "Dry-run completed - no resources were actually deleted"
    fi
}

# Error handling
handle_error() {
    error "An error occurred during cleanup on line $1"
    error "You may need to manually clean up remaining resources"
    exit 1
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Run main function
main "$@"