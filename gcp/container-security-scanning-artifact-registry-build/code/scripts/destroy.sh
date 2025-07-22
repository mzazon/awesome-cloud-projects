#!/bin/bash

# Container Security Scanning with Artifact Registry and Cloud Build - Cleanup Script
# This script safely removes all resources created by the deployment script
# including GKE cluster, Binary Authorization resources, KMS keys, and Artifact Registry

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/secure-container-deployment"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Cleanup function for script interruption
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup failed. Some resources may still exist."
        log_info "Check the Google Cloud Console for any remaining resources."
    fi
    exit $exit_code
}
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Container Security Scanning Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -z, --zone ZONE              Deployment zone (default: us-central1-a)
    -n, --name-suffix SUFFIX     Resource name suffix (must match deployment)
    --force                      Force deletion without prompting (dangerous)
    --skip-confirmation          Skip confirmation prompts
    --dry-run                    Show what would be deleted without executing
    -h, --help                   Show this help message

EXAMPLES:
    $0 --project-id my-project --name-suffix abc123
    $0 --project-id my-project --force
    DRY_RUN=true $0 --project-id my-project

SAFETY:
    - This script will DELETE resources and cannot be undone
    - Use --dry-run first to see what will be deleted
    - Backup any important data before running
    - Consider using --skip-confirmation for automation

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
            -n|--name-suffix)
                NAME_SUFFIX="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Validate project ID
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            log_error "Project ID not specified and no default project configured."
            log_error "Use --project-id option or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
        log_info "Using default project: $PROJECT_ID"
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="${2:-Executing command}"
    local ignore_errors="${3:-false}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] $description"
        log_info "[DRY RUN] Command: $cmd"
        return 0
    else
        log_info "$description"
        if [ "$ignore_errors" = true ]; then
            eval "$cmd" || {
                log_warning "Command failed but continuing: $cmd"
                return 0
            }
        else
            eval "$cmd"
        fi
    fi
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would prompt: $message"
        return 0
    fi
    
    echo -n -e "${YELLOW}$message (y/N): ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Set default values and resource names
set_defaults() {
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    
    # If name suffix not provided, try to discover it
    if [ -z "${NAME_SUFFIX:-}" ]; then
        log_info "Name suffix not provided. Attempting to discover resources..."
        discover_resources
    fi
    
    # Resource names
    REPO_NAME="secure-app-${NAME_SUFFIX}"
    CLUSTER_NAME="security-cluster-${NAME_SUFFIX}"
    SERVICE_ACCOUNT_NAME="security-scanner-${NAME_SUFFIX}"
    KEYRING_NAME="security-keyring"
    KEY_NAME="security-signing-key"
    ATTESTOR_NAME="security-attestor"
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Zone: $ZONE"
    log_info "  Repository: $REPO_NAME"
    log_info "  Cluster: $CLUSTER_NAME"
    log_info "  Service Account: $SERVICE_ACCOUNT_NAME"
}

# Discover existing resources if name suffix not provided
discover_resources() {
    log_info "Discovering existing resources..."
    
    # Try to find repositories with the pattern
    local repos
    repos=$(gcloud artifacts repositories list --location="$REGION" --format="value(name)" --filter="name:secure-app-*" 2>/dev/null || echo "")
    
    if [ -n "$repos" ]; then
        local repo_name
        repo_name=$(echo "$repos" | head -n1 | sed 's|.*/||')
        NAME_SUFFIX=${repo_name#secure-app-}
        log_info "Discovered name suffix from repository: $NAME_SUFFIX"
        return 0
    fi
    
    # Try to find clusters with the pattern
    local clusters
    clusters=$(gcloud container clusters list --zone="$ZONE" --format="value(name)" --filter="name:security-cluster-*" 2>/dev/null || echo "")
    
    if [ -n "$clusters" ]; then
        local cluster_name
        cluster_name=$(echo "$clusters" | head -n1)
        NAME_SUFFIX=${cluster_name#security-cluster-}
        log_info "Discovered name suffix from cluster: $NAME_SUFFIX"
        return 0
    fi
    
    # Try to find service accounts with the pattern
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email:security-scanner-*" 2>/dev/null || echo "")
    
    if [ -n "$service_accounts" ]; then
        local sa_email
        sa_email=$(echo "$service_accounts" | head -n1)
        local sa_name=${sa_email%@*}
        NAME_SUFFIX=${sa_name#security-scanner-}
        log_info "Discovered name suffix from service account: $NAME_SUFFIX"
        return 0
    fi
    
    log_error "Could not discover resources. Please provide --name-suffix parameter."
    log_error "Check the Google Cloud Console for existing resources and their naming pattern."
    exit 1
}

# Check for existing resources and confirm deletion
check_existing_resources() {
    log_info "Checking for existing resources..."
    
    local resources_found=false
    
    # Check for Artifact Registry repository
    if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log_info "Found Artifact Registry repository: $REPO_NAME"
        resources_found=true
    fi
    
    # Check for GKE cluster
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        log_info "Found GKE cluster: $CLUSTER_NAME"
        resources_found=true
    fi
    
    # Check for service account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" &>/dev/null; then
        log_info "Found service account: $SERVICE_ACCOUNT_NAME"
        resources_found=true
    fi
    
    # Check for Binary Authorization attestor
    if gcloud container binauthz attestors describe "$ATTESTOR_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_info "Found Binary Authorization attestor: $ATTESTOR_NAME"
        resources_found=true
    fi
    
    # Check for KMS keyring
    if gcloud kms keyrings describe "$KEYRING_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log_info "Found KMS keyring: $KEYRING_NAME"
        resources_found=true
    fi
    
    if [ "$resources_found" = false ]; then
        log_warning "No resources found matching the specified pattern."
        log_info "This might mean resources have already been deleted or use different names."
        if ! confirm_action "Continue anyway?"; then
            log_info "Cleanup cancelled."
            exit 0
        fi
    else
        log_warning "The following resources will be PERMANENTLY DELETED:"
        log_warning "This action CANNOT BE UNDONE!"
        echo ""
        if ! confirm_action "Are you sure you want to proceed with deletion?"; then
            log_info "Cleanup cancelled."
            exit 0
        fi
    fi
}

# Wait for operation to complete
wait_for_operation() {
    local operation_name="$1"
    local operation_type="${2:-regional}"
    local max_wait="${3:-300}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would wait for operation: $operation_name"
        return 0
    fi

    log_info "Waiting for operation to complete: $operation_name"
    local count=0
    while [ $count -lt $max_wait ]; do
        local status
        if [ "$operation_type" = "global" ]; then
            status=$(gcloud compute operations describe "$operation_name" --global --format="value(status)" 2>/dev/null || echo "DONE")
        else
            status=$(gcloud compute operations describe "$operation_name" --region="$REGION" --format="value(status)" 2>/dev/null || echo "DONE")
        fi
        
        if [ "$status" = "DONE" ]; then
            log_success "Operation completed: $operation_name"
            return 0
        fi
        
        echo -n "."
        sleep 5
        count=$((count + 5))
    done
    
    log_error "Operation timed out: $operation_name"
    return 1
}

# Remove Kubernetes deployments
remove_k8s_deployments() {
    log_info "Removing Kubernetes deployments..."
    
    # Check if kubectl is available and cluster is accessible
    if command -v kubectl &> /dev/null; then
        # Get cluster credentials first
        execute_command \
            "gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID" \
            "Getting cluster credentials" \
            true
        
        # Remove deployments
        execute_command \
            "kubectl delete deployment --all --timeout=60s" \
            "Removing all deployments" \
            true
        
        # Remove services
        execute_command \
            "kubectl delete service --all --timeout=60s" \
            "Removing all services" \
            true
        
        # Remove pods (should be handled by deployments, but just in case)
        execute_command \
            "kubectl delete pods --all --timeout=60s" \
            "Removing any remaining pods" \
            true
    else
        log_warning "kubectl not available. Skipping Kubernetes resource cleanup."
        log_info "Kubernetes resources will be deleted when the cluster is removed."
    fi
    
    log_success "Kubernetes resources cleanup completed"
}

# Remove GKE cluster
remove_gke_cluster() {
    log_info "Removing GKE cluster..."
    
    execute_command \
        "gcloud container clusters delete $CLUSTER_NAME \
            --zone=$ZONE \
            --project=$PROJECT_ID \
            --quiet" \
        "Deleting GKE cluster (this may take several minutes)"
    
    log_success "GKE cluster removed"
}

# Remove Binary Authorization resources
remove_binauthz_resources() {
    log_info "Removing Binary Authorization resources..."
    
    # Delete attestor
    execute_command \
        "gcloud container binauthz attestors delete $ATTESTOR_NAME \
            --project=$PROJECT_ID \
            --quiet" \
        "Deleting Binary Authorization attestor" \
        true
    
    # Delete Container Analysis note
    if [ "$DRY_RUN" != true ]; then
        local access_token
        access_token=$(gcloud auth print-access-token)
        
        curl -X DELETE \
            -H "Authorization: Bearer $access_token" \
            "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/security-attestor-note" \
            --fail --silent --show-error || {
            log_warning "Failed to delete Container Analysis note (may not exist)"
        }
        log_success "Container Analysis note deleted"
    else
        log_info "[DRY RUN] Would delete Container Analysis note via API"
    fi
    
    # Reset Binary Authorization policy to default
    execute_command \
        "gcloud container binauthz policy import /dev/stdin --project=$PROJECT_ID <<< '{\"defaultAdmissionRule\":{\"enforcementMode\":\"ALWAYS_ALLOW\"}}'" \
        "Resetting Binary Authorization policy to default" \
        true
    
    log_success "Binary Authorization resources removed"
}

# Remove KMS resources
remove_kms_resources() {
    log_info "Removing KMS resources..."
    
    # Disable and schedule destruction of key versions
    execute_command \
        "gcloud kms keys versions disable 1 \
            --key=$KEY_NAME \
            --keyring=$KEYRING_NAME \
            --location=$REGION \
            --project=$PROJECT_ID" \
        "Disabling KMS key version" \
        true
    
    execute_command \
        "gcloud kms keys versions destroy 1 \
            --key=$KEY_NAME \
            --keyring=$KEYRING_NAME \
            --location=$REGION \
            --project=$PROJECT_ID \
            --quiet" \
        "Scheduling KMS key version for destruction" \
        true
    
    log_warning "KMS key scheduled for destruction (cannot be immediately deleted)"
    log_info "The key will be automatically destroyed after the retention period"
    log_success "KMS resources cleanup initiated"
}

# Remove Artifact Registry repository
remove_artifact_registry() {
    log_info "Removing Artifact Registry repository..."
    
    execute_command \
        "gcloud artifacts repositories delete $REPO_NAME \
            --location=$REGION \
            --project=$PROJECT_ID \
            --quiet" \
        "Deleting Artifact Registry repository"
    
    log_success "Artifact Registry repository removed"
}

# Remove service account and IAM bindings
remove_service_account() {
    log_info "Removing service account and IAM bindings..."
    
    # Remove IAM policy bindings
    local roles=(
        "roles/binaryauthorization.attestorsAdmin"
        "roles/containeranalysis.notes.editor"
        "roles/cloudkms.cryptoKeyVersions.useToSign"
        "roles/cloudkms.viewer"
    )
    
    for role in "${roles[@]}"; do
        execute_command \
            "gcloud projects remove-iam-policy-binding $PROJECT_ID \
                --member='serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com' \
                --role='$role'" \
            "Removing IAM binding: $role" \
            true
    done
    
    # Remove service account token creator binding
    local cloud_build_sa="${PROJECT_ID}@cloudbuild.gserviceaccount.com"
    execute_command \
        "gcloud iam service-accounts remove-iam-policy-binding \
            ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
            --member='serviceAccount:${cloud_build_sa}' \
            --role='roles/iam.serviceAccountTokenCreator' \
            --project=$PROJECT_ID" \
        "Removing Cloud Build service account binding" \
        true
    
    # Delete service account
    execute_command \
        "gcloud iam service-accounts delete \
            ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
            --project=$PROJECT_ID \
            --quiet" \
        "Deleting service account"
    
    log_success "Service account and IAM bindings removed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    execute_command \
        "rm -rf $TEMP_DIR" \
        "Removing temporary directory" \
        true
    
    # Remove any kubectl context for the deleted cluster
    if command -v kubectl &> /dev/null; then
        execute_command \
            "kubectl config delete-context gke_${PROJECT_ID}_${ZONE}_${CLUSTER_NAME}" \
            "Removing kubectl context" \
            true
        
        execute_command \
            "kubectl config delete-cluster gke_${PROJECT_ID}_${ZONE}_${CLUSTER_NAME}" \
            "Removing kubectl cluster" \
            true
    fi
    
    log_success "Local files cleaned up"
}

# Display cleanup summary
display_cleanup_summary() {
    log_success "Container Security Scanning resources cleanup completed!"
    
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Resources Removed:"
    echo "  • Artifact Registry Repository: $REPO_NAME"
    echo "  • GKE Cluster: $CLUSTER_NAME"
    echo "  • Service Account: $SERVICE_ACCOUNT_NAME"
    echo "  • Binary Authorization Attestor: $ATTESTOR_NAME"
    echo "  • KMS Key (scheduled for destruction): $KEY_NAME"
    echo "  • Container Analysis Note: security-attestor-note"
    echo "  • IAM Policy Bindings"
    echo "  • Local temporary files"
    echo ""
    echo "Notes:"
    echo "  • KMS keys cannot be immediately deleted and are scheduled for destruction"
    echo "  • Binary Authorization policy has been reset to default (ALWAYS_ALLOW)"
    echo "  • Check the billing console for any charges from deleted resources"
    echo ""
    echo "Verification Commands:"
    echo "  • Check for remaining resources:"
    echo "    gcloud artifacts repositories list --location=$REGION"
    echo "    gcloud container clusters list --zone=$ZONE"
    echo "    gcloud iam service-accounts list --filter=\"email:*security-scanner*\""
    echo "    gcloud container binauthz attestors list"
    echo ""
}

# Main cleanup function
main() {
    log_info "Starting Container Security Scanning cleanup..."
    
    # Parse arguments
    parse_args "$@"
    
    # Set defaults and validate
    set_defaults
    check_prerequisites
    
    # Show dry-run banner
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
        echo ""
    fi
    
    # Check existing resources and confirm
    check_existing_resources
    
    # Execute cleanup steps in safe order
    remove_k8s_deployments
    remove_gke_cluster
    remove_binauthz_resources
    remove_kms_resources
    remove_artifact_registry
    remove_service_account
    cleanup_local_files
    
    # Display results
    if [ "$DRY_RUN" != true ]; then
        display_cleanup_summary
    else
        log_info "DRY RUN completed - review the commands above"
    fi
    
    log_success "Cleanup script completed successfully!"
}

# Run main function with all arguments
main "$@"