#!/bin/bash

# Real-Time Behavioral Analytics with Cloud Run Worker Pools and Cloud Firestore
# Cleanup Script for GCP
# 
# This script removes all resources created by the behavioral analytics deployment:
# - Cloud Run Worker Pools
# - Pub/Sub topics and subscriptions
# - Firestore data (with confirmation)
# - Service accounts and IAM bindings
# - Artifact Registry repositories
# - Container images

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        echo "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found."
        echo "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed!"
}

# Function to detect existing resources
detect_resources() {
    log_info "Detecting existing resources..."
    
    # Get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No active Google Cloud project set."
        echo "Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Get current region
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    
    # Find worker pools related to behavioral analytics
    WORKER_POOLS=()
    if command_exists gcloud && gcloud run workers list --region="$REGION" --format="value(metadata.name)" 2>/dev/null | grep -i behavioral; then
        while IFS= read -r pool; do
            if [[ -n "$pool" ]]; then
                WORKER_POOLS+=("$pool")
            fi
        done < <(gcloud run workers list --region="$REGION" --format="value(metadata.name)" 2>/dev/null | grep -i behavioral || true)
    fi
    
    # Find Pub/Sub topics related to behavioral analytics
    PUBSUB_TOPICS=()
    if gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(user-events|behavioral)" | sed 's|.*topics/||'; then
        while IFS= read -r topic; do
            if [[ -n "$topic" ]]; then
                PUBSUB_TOPICS+=("$topic")
            fi
        done < <(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(user-events|behavioral)" | sed 's|.*topics/||' || true)
    fi
    
    # Find Pub/Sub subscriptions related to behavioral analytics
    PUBSUB_SUBSCRIPTIONS=()
    if gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep -E "(analytics-processor|behavioral)" | sed 's|.*subscriptions/||'; then
        while IFS= read -r subscription; do
            if [[ -n "$subscription" ]]; then
                PUBSUB_SUBSCRIPTIONS+=("$subscription")
            fi
        done < <(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep -E "(analytics-processor|behavioral)" | sed 's|.*subscriptions/||' || true)
    fi
    
    # Find service accounts related to behavioral analytics
    SERVICE_ACCOUNTS=()
    if gcloud iam service-accounts list --format="value(email)" 2>/dev/null | grep -E "(analytics-processor|behavioral)"; then
        while IFS= read -r sa; do
            if [[ -n "$sa" ]]; then
                SERVICE_ACCOUNTS+=("$sa")
            fi
        done < <(gcloud iam service-accounts list --format="value(email)" 2>/dev/null | grep -E "(analytics-processor|behavioral)" || true)
    fi
    
    # Find Artifact Registry repositories related to behavioral analytics
    ARTIFACT_REPOS=()
    if gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null | grep -E "(behavioral-analytics)" | sed 's|.*repositories/||'; then
        while IFS= read -r repo; do
            if [[ -n "$repo" ]]; then
                ARTIFACT_REPOS+=("$repo")
            fi
        done < <(gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null | grep -E "(behavioral-analytics)" | sed 's|.*repositories/||' || true)
    fi
    
    # Find Firestore databases
    FIRESTORE_DATABASES=()
    if gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -E "(behavioral-analytics)" | sed 's|.*databases/||'; then
        while IFS= read -r db; do
            if [[ -n "$db" ]]; then
                FIRESTORE_DATABASES+=("$db")
            fi
        done < <(gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -E "(behavioral-analytics)" | sed 's|.*databases/||' || true)
    fi
    
    # Summary of detected resources
    echo ""
    log_info "=== DETECTED RESOURCES ==="
    echo "Worker Pools (${#WORKER_POOLS[@]}): ${WORKER_POOLS[*]:-None}"
    echo "Pub/Sub Topics (${#PUBSUB_TOPICS[@]}): ${PUBSUB_TOPICS[*]:-None}"
    echo "Pub/Sub Subscriptions (${#PUBSUB_SUBSCRIPTIONS[@]}): ${PUBSUB_SUBSCRIPTIONS[*]:-None}"
    echo "Service Accounts (${#SERVICE_ACCOUNTS[@]}): ${SERVICE_ACCOUNTS[*]:-None}"
    echo "Artifact Repositories (${#ARTIFACT_REPOS[@]}): ${ARTIFACT_REPOS[*]:-None}"
    echo "Firestore Databases (${#FIRESTORE_DATABASES[@]}): ${FIRESTORE_DATABASES[*]:-None}"
    echo ""
}

# Function to confirm destruction
confirm_destruction() {
    local total_resources=$((${#WORKER_POOLS[@]} + ${#PUBSUB_TOPICS[@]} + ${#PUBSUB_SUBSCRIPTIONS[@]} + ${#SERVICE_ACCOUNTS[@]} + ${#ARTIFACT_REPOS[@]}))
    
    if [[ $total_resources -eq 0 ]]; then
        log_warning "No behavioral analytics resources found to delete."
        
        # Check for manually specified resources
        read -p "Do you want to specify resource names manually? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled. No resources to remove."
            exit 0
        fi
        
        # Manual resource specification
        read -p "Enter worker pool name (or press Enter to skip): " manual_worker_pool
        read -p "Enter Pub/Sub topic name (or press Enter to skip): " manual_topic
        read -p "Enter Pub/Sub subscription name (or press Enter to skip): " manual_subscription
        read -p "Enter service account email (or press Enter to skip): " manual_service_account
        read -p "Enter Artifact Registry repository name (or press Enter to skip): " manual_repo
        
        [[ -n "$manual_worker_pool" ]] && WORKER_POOLS=("$manual_worker_pool")
        [[ -n "$manual_topic" ]] && PUBSUB_TOPICS=("$manual_topic")
        [[ -n "$manual_subscription" ]] && PUBSUB_SUBSCRIPTIONS=("$manual_subscription")
        [[ -n "$manual_service_account" ]] && SERVICE_ACCOUNTS=("$manual_service_account")
        [[ -n "$manual_repo" ]] && ARTIFACT_REPOS=("$manual_repo")
        
        total_resources=$((${#WORKER_POOLS[@]} + ${#PUBSUB_TOPICS[@]} + ${#PUBSUB_SUBSCRIPTIONS[@]} + ${#SERVICE_ACCOUNTS[@]} + ${#ARTIFACT_REPOS[@]}))
        
        if [[ $total_resources -eq 0 ]]; then
            log_info "No resources specified. Exiting."
            exit 0
        fi
    fi
    
    log_warning "This will permanently delete the following resources:"
    echo ""
    [[ ${#WORKER_POOLS[@]} -gt 0 ]] && echo "  🔴 Cloud Run Worker Pools: ${WORKER_POOLS[*]}"
    [[ ${#PUBSUB_TOPICS[@]} -gt 0 ]] && echo "  🔴 Pub/Sub Topics: ${PUBSUB_TOPICS[*]}"
    [[ ${#PUBSUB_SUBSCRIPTIONS[@]} -gt 0 ]] && echo "  🔴 Pub/Sub Subscriptions: ${PUBSUB_SUBSCRIPTIONS[*]}"
    [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]] && echo "  🔴 Service Accounts: ${SERVICE_ACCOUNTS[*]}"
    [[ ${#ARTIFACT_REPOS[@]} -gt 0 ]] && echo "  🔴 Artifact Registry Repositories: ${ARTIFACT_REPOS[*]}"
    [[ ${#FIRESTORE_DATABASES[@]} -gt 0 ]] && echo "  ⚠️  Firestore Databases: ${FIRESTORE_DATABASES[*]} (data will be preserved unless explicitly deleted)"
    echo ""
    
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with resource cleanup..."
}

# Function to delete Cloud Run Worker Pools
delete_worker_pools() {
    if [[ ${#WORKER_POOLS[@]} -eq 0 ]]; then
        log_info "No worker pools to delete."
        return 0
    fi
    
    log_info "Deleting Cloud Run Worker Pools..."
    
    for pool in "${WORKER_POOLS[@]}"; do
        log_info "Deleting worker pool: $pool"
        
        if gcloud run workers delete "$pool" \
            --region="$REGION" \
            --quiet 2>/dev/null; then
            log_success "✓ Worker pool '$pool' deleted"
        else
            log_error "✗ Failed to delete worker pool '$pool'"
        fi
    done
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    # Delete subscriptions first (they depend on topics)
    if [[ ${#PUBSUB_SUBSCRIPTIONS[@]} -gt 0 ]]; then
        log_info "Deleting Pub/Sub subscriptions..."
        
        for subscription in "${PUBSUB_SUBSCRIPTIONS[@]}"; do
            log_info "Deleting subscription: $subscription"
            
            if gcloud pubsub subscriptions delete "$subscription" --quiet 2>/dev/null; then
                log_success "✓ Subscription '$subscription' deleted"
            else
                log_error "✗ Failed to delete subscription '$subscription'"
            fi
        done
    fi
    
    # Delete topics
    if [[ ${#PUBSUB_TOPICS[@]} -gt 0 ]]; then
        log_info "Deleting Pub/Sub topics..."
        
        for topic in "${PUBSUB_TOPICS[@]}"; do
            log_info "Deleting topic: $topic"
            
            if gcloud pubsub topics delete "$topic" --quiet 2>/dev/null; then
                log_success "✓ Topic '$topic' deleted"
            else
                log_error "✗ Failed to delete topic '$topic'"
            fi
        done
    fi
    
    if [[ ${#PUBSUB_TOPICS[@]} -eq 0 && ${#PUBSUB_SUBSCRIPTIONS[@]} -eq 0 ]]; then
        log_info "No Pub/Sub resources to delete."
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        log_info "No service accounts to delete."
        return 0
    fi
    
    log_info "Deleting service accounts..."
    
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        log_info "Deleting service account: $sa"
        
        # Remove IAM policy bindings first
        local roles=("roles/pubsub.subscriber" "roles/datastore.user" "roles/monitoring.metricWriter")
        
        for role in "${roles[@]}"; do
            if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa" \
                --role="$role" \
                --quiet 2>/dev/null; then
                log_success "  ✓ Removed role '$role' from '$sa'"
            fi
        done
        
        # Delete the service account
        if gcloud iam service-accounts delete "$sa" --quiet 2>/dev/null; then
            log_success "✓ Service account '$sa' deleted"
        else
            log_error "✗ Failed to delete service account '$sa'"
        fi
    done
}

# Function to delete Artifact Registry repositories
delete_artifact_repositories() {
    if [[ ${#ARTIFACT_REPOS[@]} -eq 0 ]]; then
        log_info "No Artifact Registry repositories to delete."
        return 0
    fi
    
    log_info "Deleting Artifact Registry repositories..."
    
    for repo in "${ARTIFACT_REPOS[@]}"; do
        log_info "Deleting repository: $repo"
        
        if gcloud artifacts repositories delete "$repo" \
            --location="$REGION" \
            --quiet 2>/dev/null; then
            log_success "✓ Repository '$repo' deleted"
        else
            log_error "✗ Failed to delete repository '$repo'"
        fi
    done
}

# Function to handle Firestore data cleanup
handle_firestore_cleanup() {
    if [[ ${#FIRESTORE_DATABASES[@]} -eq 0 ]]; then
        log_info "No Firestore databases detected."
        return 0
    fi
    
    log_warning "Firestore database cleanup options:"
    echo ""
    echo "  1. Keep database and data (recommended for production)"
    echo "  2. Delete collections only (preserves database structure)"
    echo "  3. Delete entire database (⚠️  IRREVERSIBLE)"
    echo "  4. Skip Firestore cleanup"
    echo ""
    
    read -p "Choose an option (1-4): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            log_info "Keeping Firestore database and data intact."
            ;;
        2)
            log_warning "Deleting Firestore collections..."
            for db in "${FIRESTORE_DATABASES[@]}"; do
                delete_firestore_collections "$db"
            done
            ;;
        3)
            log_error "⚠️  WARNING: This will delete the entire Firestore database!"
            read -p "Type 'DELETE DATABASE' to confirm: " -r
            if [[ "$REPLY" == "DELETE DATABASE" ]]; then
                for db in "${FIRESTORE_DATABASES[@]}"; do
                    delete_firestore_database "$db"
                done
            else
                log_info "Database deletion cancelled."
            fi
            ;;
        4)
            log_info "Skipping Firestore cleanup."
            ;;
        *)
            log_info "Invalid option. Skipping Firestore cleanup."
            ;;
    esac
}

# Function to delete Firestore collections
delete_firestore_collections() {
    local database="$1"
    log_info "Deleting collections from database: $database"
    
    local collections=("user_events" "analytics_aggregates")
    
    for collection in "${collections[@]}"; do
        log_info "Deleting collection: $collection"
        
        if gcloud firestore collections delete "$collection" \
            --database="$database" \
            --recursive \
            --quiet 2>/dev/null; then
            log_success "✓ Collection '$collection' deleted"
        else
            log_warning "Collection '$collection' may not exist or failed to delete"
        fi
    done
}

# Function to delete Firestore database
delete_firestore_database() {
    local database="$1"
    log_info "Deleting Firestore database: $database"
    
    if gcloud firestore databases delete "$database" --quiet 2>/dev/null; then
        log_success "✓ Database '$database' deleted"
    else
        log_error "✗ Failed to delete database '$database'"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "generate_events.py"
        "test_queries.py"
        "dashboard-config.json"
        "firestore.indexes.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "✓ Removed local file: $file"
        fi
    done
    
    # Remove any temporary directories created during deployment
    if [[ -d "behavioral-processor" ]]; then
        rm -rf "behavioral-processor"
        log_success "✓ Removed temporary directory: behavioral-processor"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_errors=0
    
    # Check worker pools
    for pool in "${WORKER_POOLS[@]}"; do
        if gcloud run workers describe "$pool" --region="$REGION" >/dev/null 2>&1; then
            log_error "✗ Worker pool '$pool' still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check Pub/Sub topics
    for topic in "${PUBSUB_TOPICS[@]}"; do
        if gcloud pubsub topics describe "$topic" >/dev/null 2>&1; then
            log_error "✗ Pub/Sub topic '$topic' still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check subscriptions
    for subscription in "${PUBSUB_SUBSCRIPTIONS[@]}"; do
        if gcloud pubsub subscriptions describe "$subscription" >/dev/null 2>&1; then
            log_error "✗ Pub/Sub subscription '$subscription' still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check service accounts
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        if gcloud iam service-accounts describe "$sa" >/dev/null 2>&1; then
            log_error "✗ Service account '$sa' still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check repositories
    for repo in "${ARTIFACT_REPOS[@]}"; do
        if gcloud artifacts repositories describe "$repo" --location="$REGION" >/dev/null 2>&1; then
            log_error "✗ Artifact Registry repository '$repo' still exists"
            ((cleanup_errors++))
        fi
    done
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "✓ All resources cleaned up successfully!"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
    
    return $cleanup_errors
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "=== CLEANUP SUMMARY ==="
    echo ""
    echo "🧹 Behavioral Analytics System Cleanup Completed"
    echo ""
    echo "📋 Resources Processed:"
    echo "   Project ID: $PROJECT_ID"
    echo "   Region: $REGION"
    [[ ${#WORKER_POOLS[@]} -gt 0 ]] && echo "   Worker Pools Deleted: ${#WORKER_POOLS[@]}"
    [[ ${#PUBSUB_TOPICS[@]} -gt 0 ]] && echo "   Pub/Sub Topics Deleted: ${#PUBSUB_TOPICS[@]}"
    [[ ${#PUBSUB_SUBSCRIPTIONS[@]} -gt 0 ]] && echo "   Pub/Sub Subscriptions Deleted: ${#PUBSUB_SUBSCRIPTIONS[@]}"
    [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]] && echo "   Service Accounts Deleted: ${#SERVICE_ACCOUNTS[@]}"
    [[ ${#ARTIFACT_REPOS[@]} -gt 0 ]] && echo "   Artifact Repositories Deleted: ${#ARTIFACT_REPOS[@]}"
    echo ""
    echo "💡 Next Steps:"
    echo "   1. Verify no unexpected charges in Cloud Billing"
    echo "   2. Check Cloud Console to confirm resource removal"
    echo "   3. Review any remaining Firestore data if preserved"
    echo ""
    echo "📚 Documentation:"
    echo "   - Cloud Run: https://cloud.google.com/run/docs"
    echo "   - Pub/Sub: https://cloud.google.com/pubsub/docs"
    echo "   - Firestore: https://cloud.google.com/firestore/docs"
    echo ""
}

# Main execution function
main() {
    log_info "Starting cleanup of Real-Time Behavioral Analytics System..."
    echo ""
    
    # Execute cleanup steps
    check_prerequisites
    detect_resources
    confirm_destruction
    
    echo ""
    log_info "Beginning resource deletion..."
    
    # Delete resources in proper order (dependencies first)
    delete_worker_pools
    delete_pubsub_resources
    delete_service_accounts
    delete_artifact_repositories
    handle_firestore_cleanup
    cleanup_local_files
    
    echo ""
    verify_cleanup
    
    echo ""
    display_cleanup_summary
    
    log_success "Cleanup completed! 🧹"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted! Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"