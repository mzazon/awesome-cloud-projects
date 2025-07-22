#!/bin/bash

# AWS IoT FleetWise and Timestream Vehicle Telemetry Analytics Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Global variables for cleanup tracking
RESOURCES_TO_CLEANUP=()
FAILED_CLEANUPS=()

# Add resource to cleanup list
add_cleanup_resource() {
    RESOURCES_TO_CLEANUP+=("$1")
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load configuration from deployment
load_configuration() {
    if [[ -f "deployment_config.env" ]]; then
        log_info "Loading configuration from deployment_config.env..."
        source deployment_config.env
        log_success "Configuration loaded successfully"
    else
        log_warning "deployment_config.env not found. Using environment variables or defaults."
        
        # Set defaults if not provided
        export AWS_REGION="${AWS_REGION:-us-east-1}"
        export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
        
        # Try to infer resource names if possible
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            log_warning "RANDOM_SUFFIX not set. Manual cleanup may be required."
            log_warning "Please provide resource names manually or use --force to clean all matching resources."
        fi
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        log_warning "Force mode enabled. Skipping confirmation prompts."
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - IoT FleetWise Campaign: ${CAMPAIGN_NAME:-TelemetryCampaign-*}"
    echo "  - IoT FleetWise Fleet: ${FLEET_NAME:-vehicle-fleet-*}"
    echo "  - IoT FleetWise Vehicle: ${VEHICLE_NAME:-vehicle-001-*}"
    echo "  - IoT FleetWise Decoder Manifest: StandardDecoder"
    echo "  - IoT FleetWise Model Manifest: StandardVehicleModel"
    echo "  - IoT FleetWise Signal Catalog: VehicleSignalCatalog"
    echo "  - Timestream Database: ${TIMESTREAM_DB:-telemetry_db_*}"
    echo "  - Timestream Table: ${TIMESTREAM_TABLE:-vehicle_metrics}"
    echo "  - S3 Bucket: ${S3_BUCKET:-fleetwise-data-*}"
    echo "  - IAM Role: ${IAM_ROLE_NAME:-FleetWiseServiceRole-*}"
    echo "  - Grafana Workspace: ${GRAFANA_WORKSPACE_NAME:-FleetTelemetry-*}"
    echo "  - IoT Thing: ${VEHICLE_NAME:-vehicle-001-*}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
}

# Safe resource deletion with retries
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="$3"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if eval "$delete_command" 2>/dev/null; then
            log_success "Deleted $resource_type: $resource_name"
            return 0
        else
            ((retry_count++))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Failed to delete $resource_type: $resource_name (attempt $retry_count/$max_retries). Retrying in 5 seconds..."
                sleep 5
            else
                log_error "Failed to delete $resource_type: $resource_name after $max_retries attempts"
                FAILED_CLEANUPS+=("$resource_type: $resource_name")
                return 1
            fi
        fi
    done
}

# Wait for resource to be in deletable state
wait_for_resource_state() {
    local check_command="$1"
    local expected_state="$2"
    local resource_name="$3"
    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=10
    
    log_info "Waiting for $resource_name to reach state: $expected_state..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$check_command" 2>/dev/null | grep -q "$expected_state"; then
            log_success "$resource_name is ready for deletion"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [[ $((elapsed % 60)) -eq 0 ]]; then
            log_info "Still waiting for $resource_name... (${elapsed}s elapsed)"
        fi
    done
    
    log_warning "Timeout waiting for $resource_name to reach deletable state"
    return 1
}

# Parse command line arguments
FORCE_DESTROY=false
DRY_RUN=false
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DESTROY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force             Force cleanup without confirmation prompts"
            echo "  --dry-run           Show what would be deleted without actually deleting"
            echo "  --yes               Skip confirmation prompt"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main cleanup function
main() {
    log_info "Starting AWS IoT FleetWise and Timestream cleanup..."
    
    check_prerequisites
    load_configuration
    
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        confirm_destruction
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - Would delete the following resources:"
        echo "  - Campaign: ${CAMPAIGN_NAME:-TelemetryCampaign-*}"
        echo "  - Fleet: ${FLEET_NAME:-vehicle-fleet-*}"
        echo "  - Vehicle: ${VEHICLE_NAME:-vehicle-001-*}"
        echo "  - Decoder Manifest: StandardDecoder"
        echo "  - Model Manifest: StandardVehicleModel"
        echo "  - Signal Catalog: VehicleSignalCatalog"
        echo "  - Timestream Database: ${TIMESTREAM_DB:-telemetry_db_*}"
        echo "  - S3 Bucket: ${S3_BUCKET:-fleetwise-data-*}"
        echo "  - IAM Role: ${IAM_ROLE_NAME:-FleetWiseServiceRole-*}"
        echo "  - Grafana Workspace: ${GRAFANA_WORKSPACE_NAME:-FleetTelemetry-*}"
        return 0
    fi
    
    # Step 1: Stop and delete campaign
    log_info "Step 1: Stopping and deleting data collection campaign..."
    if [[ -n "${CAMPAIGN_NAME:-}" ]]; then
        # Suspend campaign first
        if aws iotfleetwise get-campaign --name "$CAMPAIGN_NAME" &>/dev/null; then
            aws iotfleetwise update-campaign --name "$CAMPAIGN_NAME" --action SUSPEND 2>/dev/null || true
            sleep 5
            
            safe_delete "Campaign" \
                "aws iotfleetwise delete-campaign --name '$CAMPAIGN_NAME'" \
                "$CAMPAIGN_NAME"
        else
            log_warning "Campaign $CAMPAIGN_NAME not found or already deleted"
        fi
    else
        log_warning "Campaign name not specified, skipping campaign cleanup"
    fi
    
    # Step 2: Remove vehicles and fleet
    log_info "Step 2: Removing vehicles and fleet..."
    if [[ -n "${VEHICLE_NAME:-}" && -n "${FLEET_NAME:-}" ]]; then
        # Disassociate vehicle from fleet
        if aws iotfleetwise get-vehicle --vehicle-name "$VEHICLE_NAME" &>/dev/null; then
            aws iotfleetwise disassociate-vehicle-fleet \
                --vehicle-name "$VEHICLE_NAME" \
                --fleet-id "$FLEET_NAME" 2>/dev/null || true
            
            safe_delete "Vehicle" \
                "aws iotfleetwise delete-vehicle --vehicle-name '$VEHICLE_NAME'" \
                "$VEHICLE_NAME"
        else
            log_warning "Vehicle $VEHICLE_NAME not found or already deleted"
        fi
        
        # Delete fleet
        if aws iotfleetwise get-fleet --fleet-id "$FLEET_NAME" &>/dev/null; then
            safe_delete "Fleet" \
                "aws iotfleetwise delete-fleet --fleet-id '$FLEET_NAME'" \
                "$FLEET_NAME"
        else
            log_warning "Fleet $FLEET_NAME not found or already deleted"
        fi
        
        # Delete IoT thing
        if [[ -n "${VEHICLE_NAME:-}" ]]; then
            if aws iot describe-thing --thing-name "$VEHICLE_NAME" --region "$AWS_REGION" &>/dev/null; then
                safe_delete "IoT Thing" \
                    "aws iot delete-thing --thing-name '$VEHICLE_NAME' --region '$AWS_REGION'" \
                    "$VEHICLE_NAME"
            else
                log_warning "IoT Thing $VEHICLE_NAME not found or already deleted"
            fi
        fi
    else
        log_warning "Vehicle or fleet name not specified, skipping vehicle/fleet cleanup"
    fi
    
    # Step 3: Delete decoder and model manifests
    log_info "Step 3: Deleting decoder and model manifests..."
    
    # Deactivate and delete decoder manifest
    if aws iotfleetwise get-decoder-manifest --name "StandardDecoder" &>/dev/null; then
        aws iotfleetwise update-decoder-manifest \
            --name "StandardDecoder" \
            --status "INACTIVE" 2>/dev/null || true
        
        # Wait for deactivation
        wait_for_resource_state \
            "aws iotfleetwise get-decoder-manifest --name 'StandardDecoder' --query 'status'" \
            "INACTIVE" \
            "StandardDecoder" || true
        
        safe_delete "Decoder Manifest" \
            "aws iotfleetwise delete-decoder-manifest --name 'StandardDecoder'" \
            "StandardDecoder"
    else
        log_warning "Decoder manifest StandardDecoder not found or already deleted"
    fi
    
    # Deactivate and delete model manifest
    if aws iotfleetwise get-model-manifest --name "StandardVehicleModel" &>/dev/null; then
        aws iotfleetwise update-model-manifest \
            --name "StandardVehicleModel" \
            --status "INACTIVE" 2>/dev/null || true
        
        # Wait for deactivation
        wait_for_resource_state \
            "aws iotfleetwise get-model-manifest --name 'StandardVehicleModel' --query 'status'" \
            "INACTIVE" \
            "StandardVehicleModel" || true
        
        safe_delete "Model Manifest" \
            "aws iotfleetwise delete-model-manifest --name 'StandardVehicleModel'" \
            "StandardVehicleModel"
    else
        log_warning "Model manifest StandardVehicleModel not found or already deleted"
    fi
    
    # Step 4: Delete signal catalog
    log_info "Step 4: Deleting signal catalog..."
    if aws iotfleetwise get-signal-catalog --name "VehicleSignalCatalog" &>/dev/null; then
        safe_delete "Signal Catalog" \
            "aws iotfleetwise delete-signal-catalog --name 'VehicleSignalCatalog'" \
            "VehicleSignalCatalog"
    else
        log_warning "Signal catalog VehicleSignalCatalog not found or already deleted"
    fi
    
    # Step 5: Delete Timestream resources
    log_info "Step 5: Deleting Timestream resources..."
    if [[ -n "${TIMESTREAM_DB:-}" && -n "${TIMESTREAM_TABLE:-}" ]]; then
        # Delete table first
        if aws timestream-write describe-table \
            --database-name "$TIMESTREAM_DB" \
            --table-name "$TIMESTREAM_TABLE" \
            --region "$AWS_REGION" &>/dev/null; then
            safe_delete "Timestream Table" \
                "aws timestream-write delete-table --database-name '$TIMESTREAM_DB' --table-name '$TIMESTREAM_TABLE' --region '$AWS_REGION'" \
                "$TIMESTREAM_TABLE"
        else
            log_warning "Timestream table $TIMESTREAM_TABLE not found or already deleted"
        fi
        
        # Delete database
        if aws timestream-write describe-database \
            --database-name "$TIMESTREAM_DB" \
            --region "$AWS_REGION" &>/dev/null; then
            safe_delete "Timestream Database" \
                "aws timestream-write delete-database --database-name '$TIMESTREAM_DB' --region '$AWS_REGION'" \
                "$TIMESTREAM_DB"
        else
            log_warning "Timestream database $TIMESTREAM_DB not found or already deleted"
        fi
    else
        log_warning "Timestream database or table name not specified, skipping Timestream cleanup"
    fi
    
    # Step 6: Delete Grafana workspace
    log_info "Step 6: Deleting Grafana workspace..."
    if [[ -n "${GRAFANA_WORKSPACE_NAME:-}" ]]; then
        WORKSPACE_ID=$(aws grafana list-workspaces \
            --query "workspaces[?name=='$GRAFANA_WORKSPACE_NAME'].id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$WORKSPACE_ID" && "$WORKSPACE_ID" != "None" ]]; then
            safe_delete "Grafana Workspace" \
                "aws grafana delete-workspace --workspace-id '$WORKSPACE_ID'" \
                "$GRAFANA_WORKSPACE_NAME"
        else
            log_warning "Grafana workspace $GRAFANA_WORKSPACE_NAME not found or already deleted"
        fi
    else
        log_warning "Grafana workspace name not specified, skipping Grafana cleanup"
    fi
    
    # Step 7: Delete S3 bucket
    log_info "Step 7: Deleting S3 bucket..."
    if [[ -n "${S3_BUCKET:-}" ]]; then
        if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
            # Delete all objects first
            aws s3 rm s3://"$S3_BUCKET" --recursive 2>/dev/null || true
            
            # Delete all versions if versioning is enabled
            aws s3api delete-objects \
                --bucket "$S3_BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$S3_BUCKET" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            
            # Delete delete markers
            aws s3api delete-objects \
                --bucket "$S3_BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$S3_BUCKET" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            
            safe_delete "S3 Bucket" \
                "aws s3 rb s3://'$S3_BUCKET' --force" \
                "$S3_BUCKET"
        else
            log_warning "S3 bucket $S3_BUCKET not found or already deleted"
        fi
    else
        log_warning "S3 bucket name not specified, skipping S3 cleanup"
    fi
    
    # Step 8: Delete IAM role
    log_info "Step 8: Deleting IAM role..."
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
            # Delete attached policies first
            aws iam delete-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-name TimestreamWritePolicy 2>/dev/null || true
            
            safe_delete "IAM Role" \
                "aws iam delete-role --role-name '$IAM_ROLE_NAME'" \
                "$IAM_ROLE_NAME"
        else
            log_warning "IAM role $IAM_ROLE_NAME not found or already deleted"
        fi
    else
        log_warning "IAM role name not specified, skipping IAM cleanup"
    fi
    
    # Step 9: Clean up local files
    log_info "Step 9: Cleaning up local files..."
    local files_to_remove=(
        "deployment_config.env"
        "fleetwise-trust-policy.json"
        "signal-catalog.json"
        "model-manifest.json"
        "decoder-manifest.json"
        "campaign.json"
        "timestream-policy.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed local file: $file"
        fi
    done
    
    # Display cleanup summary
    echo ""
    log_success "Cleanup completed!"
    
    if [[ ${#FAILED_CLEANUPS[@]} -gt 0 ]]; then
        echo ""
        log_warning "The following resources could not be deleted:"
        for failure in "${FAILED_CLEANUPS[@]}"; do
            echo "  - $failure"
        done
        echo ""
        log_warning "Please check these resources manually in the AWS Console."
        echo "Some resources may have dependencies that need to be resolved first."
    else
        echo ""
        log_success "All resources have been successfully cleaned up!"
    fi
    
    echo ""
    echo "==================== CLEANUP SUMMARY ===================="
    echo "✅ Campaign and fleet resources removed"
    echo "✅ Signal catalog and manifests deleted"
    echo "✅ Timestream database and table deleted"
    echo "✅ S3 bucket and contents removed"
    echo "✅ IAM role and policies deleted"
    echo "✅ Grafana workspace removed"
    echo "✅ Local configuration files cleaned up"
    echo "============================================================"
    
    if [[ ${#FAILED_CLEANUPS[@]} -eq 0 ]]; then
        log_success "All AWS IoT FleetWise and Timestream resources have been successfully removed."
    else
        log_warning "Cleanup completed with ${#FAILED_CLEANUPS[@]} failures. Please review manually."
        exit 1
    fi
}

# Run main function
main "$@"