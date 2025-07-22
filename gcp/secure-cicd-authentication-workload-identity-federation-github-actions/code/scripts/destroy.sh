#!/bin/bash

# Destroy script for Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions
# This script removes all resources created by the deploy.sh script

set -euo pipefail

# ANSI color codes for output formatting
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

# Error handling
handle_error() {
    log_warning "An error occurred on line $1. Continuing with cleanup..."
    # Don't exit on errors during cleanup to ensure all resources are attempted to be removed
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions resources

OPTIONS:
    -p, --project-id PROJECT_ID      Google Cloud Project ID (required)
    -r, --region REGION              Deployment region (default: us-central1)
    -h, --help                       Show this help message
    --dry-run                        Show what would be destroyed without making changes
    --force                          Skip confirmation prompts
    --delete-project                 Delete the entire project (DESTRUCTIVE)
    --list-resources                 List all WIF-related resources without deleting

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT             Alternative way to set project ID

EXAMPLES:
    $0 --project-id my-project
    $0 -p my-project --region us-west1
    $0 --project-id my-project --list-resources
    $0 --project-id my-project --delete-project --force

EOF
}

# Default values
PROJECT_ID=""
REGION="us-central1"
DRY_RUN=false
FORCE=false
DELETE_PROJECT=false
LIST_RESOURCES=false

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --list-resources)
            LIST_RESOURCES=true
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

# Check for environment variables if not provided via CLI
PROJECT_ID=${PROJECT_ID:-$GOOGLE_CLOUD_PROJECT}

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
    show_help
    exit 1
fi

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access to it."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local suppress_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log_info "$description"
    
    if [[ "$suppress_errors" == "true" ]]; then
        eval "$cmd" 2>/dev/null || log_warning "Command failed but continuing: $cmd"
    else
        eval "$cmd"
    fi
}

# List all resources related to Workload Identity Federation
list_wif_resources() {
    log_info "Listing Workload Identity Federation resources in project $PROJECT_ID..."
    
    echo ""
    echo "=== WORKLOAD IDENTITY POOLS ==="
    gcloud iam workload-identity-pools list --project="$PROJECT_ID" --location="global" --format="table(name,state,displayName)" 2>/dev/null || log_warning "No workload identity pools found or access denied"
    
    echo ""
    echo "=== SERVICE ACCOUNTS ==="
    gcloud iam service-accounts list --project="$PROJECT_ID" --filter="displayName:*GitHub*" --format="table(email,displayName)" 2>/dev/null || log_warning "No GitHub-related service accounts found"
    
    echo ""
    echo "=== ARTIFACT REGISTRY REPOSITORIES ==="
    gcloud artifacts repositories list --project="$PROJECT_ID" --location="$REGION" --format="table(name,format,description)" 2>/dev/null || log_warning "No artifact repositories found in region $REGION"
    
    echo ""
    echo "=== CLOUD RUN SERVICES ==="
    gcloud run services list --project="$PROJECT_ID" --region="$REGION" --format="table(metadata.name,status.url,status.conditions[0].type)" 2>/dev/null || log_warning "No Cloud Run services found in region $REGION"
    
    echo ""
    echo "=== LOCAL FILES ==="
    if [[ -d "sample-app" ]]; then
        echo "sample-app/ directory exists"
    fi
    if [[ -d ".github/workflows" ]]; then
        echo ".github/workflows/ directory exists"
        ls -la .github/workflows/*.yml 2>/dev/null || echo "No workflow files found"
    fi
}

# Get all workload identity pools
get_workload_identity_pools() {
    gcloud iam workload-identity-pools list \
        --project="$PROJECT_ID" \
        --location="global" \
        --format="value(name)" 2>/dev/null || true
}

# Get all providers for a pool
get_workload_identity_providers() {
    local pool_name="$1"
    local pool_id=$(basename "$pool_name")
    
    gcloud iam workload-identity-pools providers list \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$pool_id" \
        --format="value(name)" 2>/dev/null || true
}

# Get GitHub-related service accounts
get_github_service_accounts() {
    gcloud iam service-accounts list \
        --project="$PROJECT_ID" \
        --filter="displayName:*GitHub*" \
        --format="value(email)" 2>/dev/null || true
}

# Get Artifact Registry repositories
get_artifact_repositories() {
    gcloud artifacts repositories list \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --format="value(name)" 2>/dev/null || true
}

# Get Cloud Run services
get_cloud_run_services() {
    gcloud run services list \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format="value(metadata.name)" 2>/dev/null || true
}

# Remove Cloud Run services
remove_cloud_run_services() {
    log_info "Removing Cloud Run services..."
    
    local services
    services=$(get_cloud_run_services)
    
    if [[ -z "$services" ]]; then
        log_info "No Cloud Run services found to remove"
        return 0
    fi
    
    while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            execute_command \
                "gcloud run services delete '$service' --region='$REGION' --project='$PROJECT_ID' --quiet" \
                "Removing Cloud Run service: $service" \
                true
        fi
    done <<< "$services"
    
    log_success "Cloud Run services removal completed"
}

# Remove Artifact Registry repositories
remove_artifact_repositories() {
    log_info "Removing Artifact Registry repositories..."
    
    local repositories
    repositories=$(get_artifact_repositories)
    
    if [[ -z "$repositories" ]]; then
        log_info "No Artifact Registry repositories found to remove"
        return 0
    fi
    
    while IFS= read -r repo; do
        if [[ -n "$repo" ]]; then
            local repo_name=$(basename "$repo")
            execute_command \
                "gcloud artifacts repositories delete '$repo_name' --location='$REGION' --project='$PROJECT_ID' --quiet" \
                "Removing Artifact Registry repository: $repo_name" \
                true
        fi
    done <<< "$repositories"
    
    log_success "Artifact Registry repositories removal completed"
}

# Remove Workload Identity Federation bindings
remove_wif_bindings() {
    log_info "Removing Workload Identity Federation bindings..."
    
    local service_accounts
    service_accounts=$(get_github_service_accounts)
    
    if [[ -z "$service_accounts" ]]; then
        log_info "No GitHub service accounts found to unbind"
        return 0
    fi
    
    while IFS= read -r sa_email; do
        if [[ -n "$sa_email" ]]; then
            # Get all IAM policy bindings for this service account
            local bindings
            bindings=$(gcloud iam service-accounts get-iam-policy "$sa_email" \
                --project="$PROJECT_ID" \
                --format="json" 2>/dev/null | \
                jq -r '.bindings[]? | select(.role=="roles/iam.workloadIdentityUser") | .members[]?' 2>/dev/null || true)
            
            if [[ -n "$bindings" ]]; then
                while IFS= read -r member; do
                    if [[ -n "$member" && "$member" == principalSet* ]]; then
                        execute_command \
                            "gcloud iam service-accounts remove-iam-policy-binding '$sa_email' \
                                --project='$PROJECT_ID' \
                                --role='roles/iam.workloadIdentityUser' \
                                --member='$member' \
                                --quiet" \
                            "Removing WIF binding for $sa_email: $member" \
                            true
                    fi
                done <<< "$bindings"
            fi
        fi
    done <<< "$service_accounts"
    
    log_success "Workload Identity Federation bindings removal completed"
}

# Remove service accounts
remove_service_accounts() {
    log_info "Removing GitHub-related service accounts..."
    
    local service_accounts
    service_accounts=$(get_github_service_accounts)
    
    if [[ -z "$service_accounts" ]]; then
        log_info "No GitHub service accounts found to remove"
        return 0
    fi
    
    while IFS= read -r sa_email; do
        if [[ -n "$sa_email" ]]; then
            execute_command \
                "gcloud iam service-accounts delete '$sa_email' --project='$PROJECT_ID' --quiet" \
                "Removing service account: $sa_email" \
                true
        fi
    done <<< "$service_accounts"
    
    log_success "Service accounts removal completed"
}

# Remove Workload Identity Federation providers
remove_wif_providers() {
    log_info "Removing Workload Identity Federation providers..."
    
    local pools
    pools=$(get_workload_identity_pools)
    
    if [[ -z "$pools" ]]; then
        log_info "No workload identity pools found"
        return 0
    fi
    
    while IFS= read -r pool; do
        if [[ -n "$pool" ]]; then
            local pool_id=$(basename "$pool")
            local providers
            providers=$(get_workload_identity_providers "$pool")
            
            while IFS= read -r provider; do
                if [[ -n "$provider" ]]; then
                    local provider_id=$(basename "$provider")
                    execute_command \
                        "gcloud iam workload-identity-pools providers delete '$provider_id' \
                            --project='$PROJECT_ID' \
                            --location='global' \
                            --workload-identity-pool='$pool_id' \
                            --quiet" \
                        "Removing WIF provider: $provider_id" \
                        true
                fi
            done <<< "$providers"
        fi
    done <<< "$pools"
    
    log_success "Workload Identity Federation providers removal completed"
}

# Remove Workload Identity Federation pools
remove_wif_pools() {
    log_info "Removing Workload Identity Federation pools..."
    
    local pools
    pools=$(get_workload_identity_pools)
    
    if [[ -z "$pools" ]]; then
        log_info "No workload identity pools found to remove"
        return 0
    fi
    
    while IFS= read -r pool; do
        if [[ -n "$pool" ]]; then
            local pool_id=$(basename "$pool")
            execute_command \
                "gcloud iam workload-identity-pools delete '$pool_id' \
                    --project='$PROJECT_ID' \
                    --location='global' \
                    --quiet" \
                "Removing WIF pool: $pool_id" \
                true
        fi
    done <<< "$pools"
    
    log_success "Workload Identity Federation pools removal completed"
}

# Remove local files
remove_local_files() {
    log_info "Removing local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove local files"
        return 0
    fi
    
    # Remove sample application
    if [[ -d "sample-app" ]]; then
        rm -rf sample-app
        log_info "Removed sample-app directory"
    fi
    
    # Remove GitHub workflows
    if [[ -f ".github/workflows/deploy.yml" ]]; then
        rm -f .github/workflows/deploy.yml
        log_info "Removed .github/workflows/deploy.yml"
        
        # Remove .github directory if empty
        if [[ -d ".github/workflows" ]] && [[ -z "$(ls -A .github/workflows)" ]]; then
            rmdir .github/workflows
            log_info "Removed empty .github/workflows directory"
        fi
        
        if [[ -d ".github" ]] && [[ -z "$(ls -A .github)" ]]; then
            rmdir .github
            log_info "Removed empty .github directory"
        fi
    fi
    
    log_success "Local files removal completed"
}

# Delete entire project
delete_project() {
    log_error "PROJECT DELETION IS DESTRUCTIVE AND IRREVERSIBLE!"
    log_warning "This will delete the entire project '$PROJECT_ID' and ALL resources within it."
    
    if [[ "$FORCE" != "true" ]]; then
        echo ""
        echo -n "Type the project ID '$PROJECT_ID' to confirm deletion: "
        read -r confirmation
        if [[ "$confirmation" != "$PROJECT_ID" ]]; then
            log_info "Project deletion cancelled - confirmation did not match"
            exit 0
        fi
        
        echo -n "Are you absolutely sure you want to delete project '$PROJECT_ID'? (yes/NO): "
        read -r final_confirmation
        if [[ "$final_confirmation" != "yes" ]]; then
            log_info "Project deletion cancelled"
            exit 0
        fi
    fi
    
    execute_command \
        "gcloud projects delete '$PROJECT_ID' --quiet" \
        "Deleting project: $PROJECT_ID"
    
    log_success "Project deletion initiated. It may take several minutes to complete."
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$LIST_RESOURCES" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will remove ALL Workload Identity Federation resources from project: $PROJECT_ID"
    echo ""
    echo -n "Do you want to proceed with the cleanup? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

# Display destruction plan
show_destruction_plan() {
    if [[ "$LIST_RESOURCES" == "true" ]]; then
        return 0
    fi
    
    cat << EOF

${RED}=== DESTRUCTION PLAN ===${NC}
Project ID: ${PROJECT_ID}
Region: ${REGION}

Resources to be removed:
• Cloud Run services (in region $REGION)
• Artifact Registry repositories (in region $REGION)
• Workload Identity Federation bindings
• GitHub-related service accounts
• Workload Identity Federation providers
• Workload Identity Federation pools
• Local sample application files
• Local GitHub workflow files

EOF

    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo -e "${RED}WARNING: The entire project will be DELETED!${NC}"
        echo ""
    fi
}

# Display summary
display_summary() {
    if [[ "$LIST_RESOURCES" == "true" ]]; then
        log_info "Resource listing completed"
        return 0
    fi
    
    cat << EOF

${GREEN}=== CLEANUP COMPLETE ===${NC}

The following resources have been removed from project ${PROJECT_ID}:
• Cloud Run services
• Artifact Registry repositories
• Workload Identity Federation components
• Service accounts
• Local application and workflow files

EOF

    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "Project deletion has been initiated and will complete in the background."
    else
        echo "The Google Cloud project itself has been preserved."
        echo "You may want to disable APIs or perform additional cleanup if needed."
    fi
    
    echo ""
    log_success "Cleanup completed successfully!"
}

# Main execution function
main() {
    log_info "Starting cleanup of Secure CI/CD Authentication with Workload Identity Federation"
    
    check_prerequisites
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &> /dev/null
    
    if [[ "$LIST_RESOURCES" == "true" ]]; then
        list_wif_resources
        return 0
    fi
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
        return 0
    fi
    
    show_destruction_plan
    confirm_destruction
    
    # Execute cleanup steps in reverse order of creation
    remove_cloud_run_services
    remove_artifact_repositories
    remove_wif_bindings
    remove_service_accounts
    remove_wif_providers
    remove_wif_pools
    remove_local_files
    
    display_summary
}

# Execute main function
main "$@"