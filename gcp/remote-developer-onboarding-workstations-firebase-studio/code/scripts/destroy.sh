#!/bin/bash

# Destroy script for Remote Developer Onboarding with Cloud Workstations and Firebase Studio
# This script safely removes all infrastructure created by the deploy script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Help function
show_help() {
    cat << EOF
Destroy Remote Developer Onboarding Infrastructure

Usage: $0 [OPTIONS]

Options:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -c, --cluster-name NAME       Workstation cluster name (default: developer-workstations)
    --config-name NAME           Workstation config name (required if non-default)
    --repo-name NAME             Source repository name (required if non-default)
    --keep-repo                  Keep the source repository (don't delete)
    --keep-iam                   Keep custom IAM roles (don't delete)
    --force                      Skip confirmation prompts
    --dry-run                    Show what would be destroyed without making changes
    -h, --help                   Show this help message

Examples:
    $0 --project-id my-dev-project
    $0 --project-id my-dev-project --force
    $0 --project-id my-dev-project --keep-repo --keep-iam
    $0 --project-id my-dev-project --dry-run

EOF
}

# Default values
PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="developer-workstations"
CONFIG_NAME=""
REPO_NAME=""
KEEP_REPO=false
KEEP_IAM=false
FORCE=false
DRY_RUN=false

# Parse command line arguments
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
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --config-name)
            CONFIG_NAME="$2"
            shift 2
            ;;
        --repo-name)
            REPO_NAME="$2"
            shift 2
            ;;
        --keep-repo)
            KEEP_REPO=true
            shift
            ;;
        --keep-iam)
            KEEP_IAM=true
            shift
            ;;
        --force)
            FORCE=true
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
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    error "Project ID is required. Use --project-id or -p option."
fi

log "Starting destruction with the following configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Config Name: ${CONFIG_NAME:-'auto-detect'}"
echo "  Repository Name: ${REPO_NAME:-'auto-detect'}"
echo "  Keep Repository: $KEEP_REPO"
echo "  Keep IAM Roles: $KEEP_IAM"
echo "  Force Mode: $FORCE"
echo "  Dry Run: $DRY_RUN"
echo ""

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project '$PROJECT_ID' does not exist or is not accessible."
    fi
    
    success "Prerequisites check completed"
}

# Configure gcloud settings
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would set project: $PROJECT_ID"
        log "[DRY RUN] Would set region: $REGION"
        return
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    success "gcloud configuration updated"
}

# Auto-detect resources if not specified
auto_detect_resources() {
    log "Auto-detecting resources in project..."
    
    # Detect workstation configurations if not specified
    if [[ -z "$CONFIG_NAME" ]]; then
        local configs
        configs=$(gcloud beta workstations configs list \
            --cluster="$CLUSTER_NAME" \
            --region="$REGION" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$configs" ]]; then
            CONFIG_NAME=$(echo "$configs" | head -1 | sed 's|.*/||')
            log "Auto-detected workstation config: $CONFIG_NAME"
        else
            warning "No workstation configurations found in cluster $CLUSTER_NAME"
        fi
    fi
    
    # Detect source repositories if not specified
    if [[ -z "$REPO_NAME" ]]; then
        local repos
        repos=$(gcloud source repos list \
            --format="value(name)" \
            --filter="name~team-templates" 2>/dev/null || echo "")
        
        if [[ -n "$repos" ]]; then
            REPO_NAME=$(echo "$repos" | head -1)
            log "Auto-detected source repository: $REPO_NAME"
        else
            warning "No team template repositories found"
        fi
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    echo ""
    warning "This will permanently delete the following resources:"
    echo "  • All workstation instances in cluster: $CLUSTER_NAME"
    
    if [[ -n "$CONFIG_NAME" ]]; then
        echo "  • Workstation configuration: $CONFIG_NAME"
    fi
    
    echo "  • Workstation cluster: $CLUSTER_NAME"
    
    if [[ "$KEEP_REPO" == "false" && -n "$REPO_NAME" ]]; then
        echo "  • Source repository: $REPO_NAME (and all code)"
    fi
    
    if [[ "$KEEP_IAM" == "false" ]]; then
        echo "  • Custom IAM role: workstationDeveloper"
    fi
    
    echo "  • Budget alerts and monitoring dashboards"
    echo "  • Local files: onboard-developer.sh"
    echo ""
    
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Delete workstation instances
delete_workstation_instances() {
    log "Deleting workstation instances..."
    
    if [[ -z "$CONFIG_NAME" ]]; then
        warning "No workstation configuration specified, skipping instance deletion"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete all workstation instances in config: $CONFIG_NAME"
        return
    fi
    
    # Get list of workstation instances
    local instances
    instances=$(gcloud beta workstations list \
        --cluster="$CLUSTER_NAME" \
        --config="$CONFIG_NAME" \
        --region="$REGION" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$instances" ]]; then
        log "No workstation instances found to delete"
        return
    fi
    
    log "Found workstation instances to delete:"
    echo "$instances" | sed 's/^/  • /'
    
    # Delete each instance
    for instance in $instances; do
        local instance_name
        instance_name=$(echo "$instance" | sed 's|.*/||')
        
        log "Deleting workstation instance: $instance_name"
        
        if gcloud beta workstations delete "$instance_name" \
            --cluster="$CLUSTER_NAME" \
            --config="$CONFIG_NAME" \
            --region="$REGION" \
            --quiet; then
            success "Deleted workstation instance: $instance_name"
        else
            warning "Failed to delete workstation instance: $instance_name"
        fi
    done
    
    # Wait for all instances to be deleted
    log "Waiting for workstation instances to be fully deleted..."
    local max_attempts=20
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local remaining_instances
        remaining_instances=$(gcloud beta workstations list \
            --cluster="$CLUSTER_NAME" \
            --config="$CONFIG_NAME" \
            --region="$REGION" \
            --format="value(name)" 2>/dev/null | wc -l)
        
        if [[ $remaining_instances -eq 0 ]]; then
            success "All workstation instances deleted"
            return
        fi
        
        log "Waiting for $remaining_instances instances to be deleted... (attempt $attempt/$max_attempts)"
        sleep 15
        ((attempt++))
    done
    
    warning "Some workstation instances may still be deleting"
}

# Delete workstation configuration
delete_workstation_config() {
    log "Deleting workstation configuration..."
    
    if [[ -z "$CONFIG_NAME" ]]; then
        warning "No workstation configuration specified, skipping"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete workstation config: $CONFIG_NAME"
        return
    fi
    
    if ! gcloud beta workstations configs describe "$CONFIG_NAME" \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" &> /dev/null; then
        log "Workstation configuration '$CONFIG_NAME' not found, skipping"
        return
    fi
    
    if gcloud beta workstations configs delete "$CONFIG_NAME" \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" \
        --quiet; then
        success "Deleted workstation configuration: $CONFIG_NAME"
    else
        error "Failed to delete workstation configuration: $CONFIG_NAME"
    fi
}

# Delete workstation cluster
delete_workstation_cluster() {
    log "Deleting workstation cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete workstation cluster: $CLUSTER_NAME"
        return
    fi
    
    if ! gcloud beta workstations clusters describe "$CLUSTER_NAME" \
        --region="$REGION" &> /dev/null; then
        log "Workstation cluster '$CLUSTER_NAME' not found, skipping"
        return
    fi
    
    log "Deleting workstation cluster (this may take several minutes)..."
    
    if gcloud beta workstations clusters delete "$CLUSTER_NAME" \
        --region="$REGION" \
        --quiet; then
        success "Deleted workstation cluster: $CLUSTER_NAME"
    else
        error "Failed to delete workstation cluster: $CLUSTER_NAME"
    fi
    
    # Wait for cluster deletion to complete
    log "Waiting for cluster deletion to complete..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ! gcloud beta workstations clusters describe "$CLUSTER_NAME" \
            --region="$REGION" &> /dev/null; then
            success "Workstation cluster fully deleted"
            return
        fi
        
        log "Cluster still deleting... (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    warning "Cluster deletion may still be in progress"
}

# Delete source repository
delete_source_repository() {
    if [[ "$KEEP_REPO" == "true" ]]; then
        log "Keeping source repository as requested"
        return
    fi
    
    log "Deleting source repository..."
    
    if [[ -z "$REPO_NAME" ]]; then
        warning "No source repository specified, skipping"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete source repository: $REPO_NAME"
        return
    fi
    
    if ! gcloud source repos describe "$REPO_NAME" \
        --project="$PROJECT_ID" &> /dev/null; then
        log "Source repository '$REPO_NAME' not found, skipping"
        return
    fi
    
    warning "This will permanently delete all code in repository: $REPO_NAME"
    
    if [[ "$FORCE" == "false" ]]; then
        read -p "Are you sure you want to delete the repository? [y/N]: " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Repository deletion skipped"
            return
        fi
    fi
    
    if gcloud source repos delete "$REPO_NAME" \
        --project="$PROJECT_ID" \
        --quiet; then
        success "Deleted source repository: $REPO_NAME"
    else
        warning "Failed to delete source repository: $REPO_NAME"
    fi
}

# Delete IAM roles
delete_iam_roles() {
    if [[ "$KEEP_IAM" == "true" ]]; then
        log "Keeping IAM roles as requested"
        return
    fi
    
    log "Deleting custom IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete IAM role: workstationDeveloper"
        return
    fi
    
    if ! gcloud iam roles describe workstationDeveloper \
        --project="$PROJECT_ID" &> /dev/null; then
        log "Custom IAM role 'workstationDeveloper' not found, skipping"
        return
    fi
    
    if gcloud iam roles delete workstationDeveloper \
        --project="$PROJECT_ID" \
        --quiet; then
        success "Deleted custom IAM role: workstationDeveloper"
    else
        warning "Failed to delete custom IAM role: workstationDeveloper"
    fi
}

# Delete budget alerts
delete_budget_alerts() {
    log "Deleting budget alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete budget alerts for project"
        return
    fi
    
    # Get billing account
    local billing_account
    billing_account=$(gcloud beta billing accounts list \
        --format="value(name)" \
        --filter="open=true" | head -1)
    
    if [[ -z "$billing_account" ]]; then
        warning "No active billing account found, skipping budget deletion"
        return
    fi
    
    # Find budgets for this project
    local budgets
    budgets=$(gcloud beta billing budgets list \
        --billing-account="$billing_account" \
        --format="value(name)" \
        --filter="displayName~'Developer Workstations Budget - $PROJECT_ID'" 2>/dev/null || echo "")
    
    if [[ -z "$budgets" ]]; then
        log "No budget alerts found for this project"
        return
    fi
    
    # Delete each budget
    for budget in $budgets; do
        local budget_name
        budget_name=$(echo "$budget" | sed 's|.*/||')
        
        log "Deleting budget alert: $budget_name"
        
        if gcloud beta billing budgets delete "$budget_name" \
            --billing-account="$billing_account" \
            --quiet; then
            success "Deleted budget alert: $budget_name"
        else
            warning "Failed to delete budget alert: $budget_name"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete local files: onboard-developer.sh, repository clone"
        return
    fi
    
    local files_to_delete=(
        "onboard-developer.sh"
        "$REPO_NAME"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -e "$file" ]]; then
            log "Deleting local file/directory: $file"
            rm -rf "$file"
            success "Deleted: $file"
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check workstation cluster
    if gcloud beta workstations clusters describe "$CLUSTER_NAME" \
        --region="$REGION" &> /dev/null; then
        cleanup_issues+=("Workstation cluster '$CLUSTER_NAME' still exists")
    fi
    
    # Check source repository (if it should be deleted)
    if [[ "$KEEP_REPO" == "false" && -n "$REPO_NAME" ]]; then
        if gcloud source repos describe "$REPO_NAME" \
            --project="$PROJECT_ID" &> /dev/null; then
            cleanup_issues+=("Source repository '$REPO_NAME' still exists")
        fi
    fi
    
    # Check IAM role (if it should be deleted)
    if [[ "$KEEP_IAM" == "false" ]]; then
        if gcloud iam roles describe workstationDeveloper \
            --project="$PROJECT_ID" &> /dev/null; then
            cleanup_issues+=("Custom IAM role 'workstationDeveloper' still exists")
        fi
    fi
    
    if [[ ${#cleanup_issues[@]} -gt 0 ]]; then
        warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            echo "  • $issue"
        done
        echo ""
        warning "Manual cleanup may be required for remaining resources"
    else
        success "All targeted resources have been successfully removed"
    fi
}

# Main destruction function
main() {
    log "🗑️  Starting Remote Developer Onboarding Infrastructure Destruction"
    echo ""
    
    check_prerequisites
    configure_gcloud
    auto_detect_resources
    confirm_destruction
    
    delete_workstation_instances
    delete_workstation_config
    delete_workstation_cluster
    delete_source_repository
    delete_iam_roles
    delete_budget_alerts
    cleanup_local_files
    
    verify_cleanup
    
    echo ""
    success "🎉 Destruction completed!"
    echo ""
    echo "📋 Destruction Summary:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Workstation Cluster: $CLUSTER_NAME (deleted)"
    
    if [[ -n "$CONFIG_NAME" ]]; then
        echo "  Workstation Config: $CONFIG_NAME (deleted)"
    fi
    
    if [[ "$KEEP_REPO" == "false" && -n "$REPO_NAME" ]]; then
        echo "  Source Repository: $REPO_NAME (deleted)"
    elif [[ -n "$REPO_NAME" ]]; then
        echo "  Source Repository: $REPO_NAME (preserved)"
    fi
    
    if [[ "$KEEP_IAM" == "false" ]]; then
        echo "  Custom IAM Role: workstationDeveloper (deleted)"
    else
        echo "  Custom IAM Role: workstationDeveloper (preserved)"
    fi
    
    echo "  Budget Alerts: deleted"
    echo "  Local Files: cleaned up"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "This was a dry run. No actual resources were deleted."
    else
        echo "💡 Note: APIs remain enabled. Disable them manually if no longer needed:"
        echo "   gcloud services disable workstations.googleapis.com"
        echo "   gcloud services disable sourcerepo.googleapis.com"
        echo "   # ... and other APIs as needed"
    fi
    echo ""
}

# Run main function
main "$@"