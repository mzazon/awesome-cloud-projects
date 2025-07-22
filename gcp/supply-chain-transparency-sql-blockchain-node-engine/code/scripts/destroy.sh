#!/bin/bash

# Supply Chain Transparency with Cloud SQL and Blockchain Node Engine - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail

# Color codes for output formatting
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

# Configuration variables with defaults
PROJECT_ID=${PROJECT_ID:-""}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
FORCE_DELETE=${FORCE_DELETE:-false}
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Resource name variables
DB_INSTANCE_NAME=${DB_INSTANCE_NAME:-""}
BLOCKCHAIN_NODE_NAME=${BLOCKCHAIN_NODE_NAME:-""}

# Function to load deployment state
load_deployment_state() {
    local state_file="deployment-state.env"
    
    if [ -f "$state_file" ]; then
        log_info "Loading deployment state from $state_file"
        # shellcheck source=/dev/null
        source "$state_file"
        log_success "Deployment state loaded"
    else
        log_warning "Deployment state file not found. Manual configuration required."
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project and resources
validate_configuration() {
    log_info "Validating configuration..."
    
    # Ensure project ID is set
    if [ -z "$PROJECT_ID" ]; then
        log_error "PROJECT_ID is not set. Please set it manually or ensure deployment-state.env exists."
        log_info "You can set it with: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set project
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Configuration validated"
}

# Function to discover resources if not provided
discover_resources() {
    log_info "Discovering supply chain transparency resources..."
    
    # Discover Cloud SQL instances if not specified
    if [ -z "$DB_INSTANCE_NAME" ]; then
        log_info "Discovering Cloud SQL instances..."
        local instances
        instances=$(gcloud sql instances list --format="value(name)" --filter="name~supply-chain-db")
        if [ -n "$instances" ]; then
            DB_INSTANCE_NAME=$(echo "$instances" | head -n1)
            log_info "Found Cloud SQL instance: $DB_INSTANCE_NAME"
        fi
    fi
    
    # Discover Blockchain Node Engine instances if not specified
    if [ -z "$BLOCKCHAIN_NODE_NAME" ]; then
        log_info "Discovering Blockchain Node Engine instances..."
        local nodes
        nodes=$(gcloud blockchain-node-engine nodes list --location="$REGION" --format="value(name)" --filter="name~supply-chain-node" 2>/dev/null || echo "")
        if [ -n "$nodes" ]; then
            BLOCKCHAIN_NODE_NAME=$(echo "$nodes" | head -n1 | cut -d'/' -f6)
            log_info "Found blockchain node: $BLOCKCHAIN_NODE_NAME"
        fi
    fi
    
    log_success "Resource discovery completed"
}

# Function to list resources to be deleted
list_resources_to_delete() {
    echo
    log_info "Resources that will be deleted:"
    echo
    
    # Cloud Functions
    local functions
    functions=$(gcloud functions list --format="value(name)" --filter="name~(processSupplyChainEvent OR supplyChainIngestion)" 2>/dev/null || echo "")
    if [ -n "$functions" ]; then
        echo "Cloud Functions:"
        echo "$functions" | sed 's/^/  • /'
        echo
    fi
    
    # Pub/Sub Topics and Subscriptions
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~(supply-chain-events OR blockchain-verification)" 2>/dev/null || echo "")
    if [ -n "$topics" ]; then
        echo "Pub/Sub Topics:"
        echo "$topics" | sed 's/^/  • /'
    fi
    
    local subscriptions
    subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" --filter="name~(process-supply-events OR process-blockchain-verification)" 2>/dev/null || echo "")
    if [ -n "$subscriptions" ]; then
        echo "Pub/Sub Subscriptions:"
        echo "$subscriptions" | sed 's/^/  • /'
        echo
    fi
    
    # Blockchain Node
    if [ -n "$BLOCKCHAIN_NODE_NAME" ] && gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" &>/dev/null; then
        echo "Blockchain Node Engine:"
        echo "  • $BLOCKCHAIN_NODE_NAME"
        echo
    fi
    
    # Cloud SQL Instance
    if [ -n "$DB_INSTANCE_NAME" ] && gcloud sql instances describe "$DB_INSTANCE_NAME" &>/dev/null; then
        echo "Cloud SQL Instance:"
        echo "  • $DB_INSTANCE_NAME"
        echo
    fi
    
    # Service Account
    if gcloud iam service-accounts describe "supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        echo "Service Account:"
        echo "  • supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com"
        echo
    fi
    
    # KMS Resources
    if gcloud kms keyrings describe blockchain-keyring --location="$REGION" &>/dev/null; then
        echo "KMS Resources:"
        echo "  • blockchain-keyring (keyring)"
        echo "  • blockchain-key (key - will be scheduled for deletion)"
        echo
    fi
}

# Function to estimate cost savings
show_cost_savings() {
    log_info "Estimated monthly cost savings after cleanup:"
    echo "  • Cloud SQL PostgreSQL: ~\$150-200"
    echo "  • Blockchain Node Engine: ~\$100-150" 
    echo "  • Cloud Functions: ~\$5-20"
    echo "  • Pub/Sub messaging: ~\$5-15"
    echo "  • Cloud KMS: ~\$1-5"
    echo "  • Other services: ~\$10-30"
    echo "  • Total savings: ~\$270-420/month"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = "true" ] || [ "$FORCE_DELETE" = "true" ]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete all supply chain transparency infrastructure!"
    echo
    list_resources_to_delete
    show_cost_savings
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed with deletion? (type 'DELETE' to confirm): " -r
    echo
    if [ "$REPLY" != "DELETE" ]; then
        log_info "Deletion cancelled by user."
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would delete Cloud Functions"
        return 0
    fi
    
    local functions=("processSupplyChainEvent" "supplyChainIngestion")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" &>/dev/null; then
            log_info "Deleting function: $func"
            gcloud functions delete "$func" --quiet || log_warning "Failed to delete function: $func"
        else
            log_info "Function not found: $func"
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would delete Pub/Sub topics and subscriptions"
        return 0
    fi
    
    # Delete subscriptions first
    local subscriptions=("process-supply-events" "process-blockchain-verification")
    for sub in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe "$sub" &>/dev/null; then
            log_info "Deleting subscription: $sub"
            gcloud pubsub subscriptions delete "$sub" --quiet || log_warning "Failed to delete subscription: $sub"
        else
            log_info "Subscription not found: $sub"
        fi
    done
    
    # Delete topics
    local topics=("supply-chain-events" "blockchain-verification")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &>/dev/null; then
            log_info "Deleting topic: $topic"
            gcloud pubsub topics delete "$topic" --quiet || log_warning "Failed to delete topic: $topic"
        else
            log_info "Topic not found: $topic"
        fi
    done
    
    log_success "Pub/Sub resources cleanup completed"
}

# Function to delete Blockchain Node Engine
delete_blockchain_node() {
    log_info "Deleting Blockchain Node Engine..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would delete blockchain node: $BLOCKCHAIN_NODE_NAME"
        return 0
    fi
    
    if [ -z "$BLOCKCHAIN_NODE_NAME" ]; then
        log_info "No blockchain node name specified, skipping"
        return 0
    fi
    
    if gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" &>/dev/null; then
        log_info "Deleting blockchain node: $BLOCKCHAIN_NODE_NAME (this may take several minutes)"
        gcloud blockchain-node-engine nodes delete "$BLOCKCHAIN_NODE_NAME" \
            --location="$REGION" \
            --quiet || log_warning "Failed to delete blockchain node: $BLOCKCHAIN_NODE_NAME"
        log_success "Blockchain node deletion initiated"
    else
        log_info "Blockchain node not found or not accessible: $BLOCKCHAIN_NODE_NAME"
    fi
}

# Function to delete Cloud SQL instance
delete_cloud_sql() {
    log_info "Deleting Cloud SQL instance..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would delete Cloud SQL instance: $DB_INSTANCE_NAME"
        return 0
    fi
    
    if [ -z "$DB_INSTANCE_NAME" ]; then
        log_info "No Cloud SQL instance name specified, skipping"
        return 0
    fi
    
    if gcloud sql instances describe "$DB_INSTANCE_NAME" &>/dev/null; then
        # Check if deletion protection is enabled
        local deletion_protection
        deletion_protection=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(settings.deletionProtectionEnabled)" 2>/dev/null || echo "false")
        
        if [ "$deletion_protection" = "True" ]; then
            log_warning "Deletion protection is enabled. Disabling it first..."
            gcloud sql instances patch "$DB_INSTANCE_NAME" --no-deletion-protection --quiet
            log_info "Deletion protection disabled"
        fi
        
        log_info "Deleting Cloud SQL instance: $DB_INSTANCE_NAME (this may take several minutes)"
        gcloud sql instances delete "$DB_INSTANCE_NAME" --quiet || log_warning "Failed to delete Cloud SQL instance: $DB_INSTANCE_NAME"
        log_success "Cloud SQL instance deletion initiated"
    else
        log_info "Cloud SQL instance not found: $DB_INSTANCE_NAME"
    fi
}

# Function to delete IAM service account and bindings
delete_service_account() {
    log_info "Deleting IAM service account..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would delete service account and remove IAM bindings"
        return 0
    fi
    
    local service_account="supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$service_account" &>/dev/null; then
        # Remove IAM policy bindings
        local roles=(
            "roles/cloudsql.client"
            "roles/pubsub.editor"
            "roles/cloudfunctions.invoker"
            "roles/cloudkms.cryptoKeyEncrypterDecrypter"
            "roles/blockchain.nodeUser"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding for role: $role"
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$service_account" \
                --role="$role" \
                --quiet 2>/dev/null || log_info "Role binding not found or already removed: $role"
        done
        
        # Delete service account
        log_info "Deleting service account: $service_account"
        gcloud iam service-accounts delete "$service_account" --quiet || log_warning "Failed to delete service account"
        log_success "Service account cleanup completed"
    else
        log_info "Service account not found: $service_account"
    fi
}

# Function to delete KMS resources
delete_kms_resources() {
    log_info "Deleting KMS resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would schedule KMS key for deletion"
        return 0
    fi
    
    # Schedule key for deletion (actual deletion happens after 30 days)
    if gcloud kms keys describe blockchain-key --keyring=blockchain-keyring --location="$REGION" &>/dev/null; then
        log_info "Scheduling KMS key for deletion (30-day delay)..."
        
        # Get all key versions and schedule them for destruction
        local versions
        versions=$(gcloud kms keys versions list --key=blockchain-key --keyring=blockchain-keyring --location="$REGION" --format="value(name)")
        
        if [ -n "$versions" ]; then
            for version in $versions; do
                local version_number
                version_number=$(basename "$version")
                log_info "Scheduling key version $version_number for destruction..."
                gcloud kms keys versions destroy "$version_number" \
                    --key=blockchain-key \
                    --keyring=blockchain-keyring \
                    --location="$REGION" \
                    --quiet 2>/dev/null || log_info "Key version already destroyed or not destroyable: $version_number"
            done
        fi
        
        log_warning "KMS key scheduled for deletion in 30 days (Google Cloud policy)"
    else
        log_info "KMS key not found: blockchain-key"
    fi
    
    # Note: KMS keyrings cannot be deleted, they remain but incur no cost when empty
    if gcloud kms keyrings describe blockchain-keyring --location="$REGION" &>/dev/null; then
        log_info "KMS keyring 'blockchain-keyring' will remain (cannot be deleted, but incurs no cost when empty)"
    fi
    
    log_success "KMS resources cleanup completed"
}

# Function to clean up temporary files
cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return 0
    fi
    
    # Remove Cloud SQL proxy if downloaded
    if [ -f "cloud_sql_proxy" ]; then
        rm -f cloud_sql_proxy
        log_info "Removed cloud_sql_proxy binary"
    fi
    
    # Remove schema file if exists
    if [ -f "schema.sql" ]; then
        rm -f schema.sql
        log_info "Removed schema.sql file"
    fi
    
    # List deployment state file for manual removal
    if [ -f "deployment-state.env" ]; then
        log_warning "deployment-state.env contains sensitive information."
        log_warning "Consider removing it manually: rm deployment-state.env"
    fi
    
    # List log files for cleanup consideration
    local log_files
    log_files=$(find . -name "deployment-*.log" 2>/dev/null || echo "")
    if [ -n "$log_files" ]; then
        log_info "Deployment log files found:"
        echo "$log_files" | sed 's/^/  • /'
        log_info "Consider removing old log files if no longer needed"
    fi
    
    log_success "Temporary files cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local issues_found=false
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" --filter="name~(processSupplyChainEvent OR supplyChainIngestion)" 2>/dev/null || echo "")
    if [ -n "$remaining_functions" ]; then
        log_warning "Some Cloud Functions still exist:"
        echo "$remaining_functions" | sed 's/^/  • /'
        issues_found=true
    fi
    
    # Check Pub/Sub topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~(supply-chain-events OR blockchain-verification)" 2>/dev/null || echo "")
    if [ -n "$remaining_topics" ]; then
        log_warning "Some Pub/Sub topics still exist:"
        echo "$remaining_topics" | sed 's/^/  • /'
        issues_found=true
    fi
    
    # Check Cloud SQL instance
    if [ -n "$DB_INSTANCE_NAME" ] && gcloud sql instances describe "$DB_INSTANCE_NAME" &>/dev/null; then
        local sql_state
        sql_state=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(state)")
        log_warning "Cloud SQL instance still exists (state: $sql_state)"
        log_info "Large instances may take several minutes to delete completely"
        issues_found=true
    fi
    
    # Check blockchain node
    if [ -n "$BLOCKCHAIN_NODE_NAME" ] && gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" &>/dev/null; then
        local node_state
        node_state=$(gcloud blockchain-node-engine nodes describe "$BLOCKCHAIN_NODE_NAME" --location="$REGION" --format="value(state)" 2>/dev/null || echo "unknown")
        log_warning "Blockchain node still exists (state: $node_state)"
        log_info "Blockchain nodes may take 15-30 minutes to delete completely"
        issues_found=true
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_warning "Service account still exists: supply-chain-sa@${PROJECT_ID}.iam.gserviceaccount.com"
        issues_found=true
    fi
    
    if [ "$issues_found" = "false" ]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may still be in the process of deletion"
        log_info "Large resources like Cloud SQL and Blockchain nodes can take several minutes to fully delete"
        log_info "Check the Google Cloud Console to monitor deletion progress"
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo
    log_success "=== CLEANUP COMPLETED ==="
    echo
    echo "Deleted Resources:"
    echo "  • Cloud Functions: processSupplyChainEvent, supplyChainIngestion"
    echo "  • Pub/Sub Topics: supply-chain-events, blockchain-verification"
    echo "  • Pub/Sub Subscriptions: process-supply-events, process-blockchain-verification"
    if [ -n "$BLOCKCHAIN_NODE_NAME" ]; then
        echo "  • Blockchain Node: $BLOCKCHAIN_NODE_NAME"
    fi
    if [ -n "$DB_INSTANCE_NAME" ]; then
        echo "  • Cloud SQL Instance: $DB_INSTANCE_NAME"
    fi
    echo "  • Service Account: supply-chain-sa"
    echo "  • KMS Key: blockchain-key (scheduled for deletion in 30 days)"
    echo
    
    echo "Important Notes:"
    echo "  • KMS keyring 'blockchain-keyring' remains (cannot be deleted, no cost when empty)"
    echo "  • KMS key 'blockchain-key' scheduled for deletion in 30 days"
    echo "  • Large resources may take several minutes to fully delete"
    echo "  • Check Google Cloud Console for final deletion confirmation"
    echo
    
    show_cost_savings
    echo
    
    log_info "Cleanup log saved to: cleanup-$(date +%Y%m%d-%H%M%S).log"
}

# Main cleanup function
main() {
    echo "Supply Chain Transparency Cleanup Script"
    echo "========================================"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --db-instance)
                DB_INSTANCE_NAME="$2"
                shift 2
                ;;
            --blockchain-node)
                BLOCKCHAIN_NODE_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --project-id ID         Google Cloud Project ID"
                echo "  --region REGION         Deployment region (default: us-central1)"
                echo "  --db-instance NAME      Cloud SQL instance name"
                echo "  --blockchain-node NAME  Blockchain node name"
                echo "  --force                 Force deletion without confirmation"
                echo "  --dry-run               Show what would be deleted without removing resources"
                echo "  --skip-confirmation     Skip deletion confirmation"
                echo "  --help                  Show this help message"
                echo
                echo "Environment Variables:"
                echo "  PROJECT_ID              Google Cloud Project ID"
                echo "  REGION                  Deployment region"
                echo "  DB_INSTANCE_NAME        Cloud SQL instance name"
                echo "  BLOCKCHAIN_NODE_NAME    Blockchain node name"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Redirect output to log file
    exec > >(tee "cleanup-$(date +%Y%m%d-%H%M%S).log")
    exec 2>&1
    
    # Execute cleanup steps
    load_deployment_state
    check_prerequisites
    validate_configuration
    discover_resources
    confirm_deletion
    delete_cloud_functions
    delete_pubsub_resources
    delete_blockchain_node
    delete_cloud_sql
    delete_service_account
    delete_kms_resources
    cleanup_temporary_files
    verify_deletion
    show_cleanup_summary
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry run completed. No resources were actually deleted."
    else
        log_success "Cleanup completed successfully!"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi