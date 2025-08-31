#!/bin/bash

# GCP Real-Time Voice Support Agent with ADK and Live API - Cleanup Script
# This script safely removes all resources created by the deployment script.

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="voice_agent_destroy_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Script metadata
SCRIPT_VERSION="1.0"
DESTROY_START_TIME=$(date)

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  GCP Voice Support Agent Cleanup Script v${SCRIPT_VERSION}${NC}"
echo -e "${BLUE}  Recipe: Real-Time Voice Support Agent with ADK and Live API${NC}"
echo -e "${BLUE}  Started: ${DESTROY_START_TIME}${NC}"
echo -e "${BLUE}================================================================${NC}"

# Configuration variables
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    print_step "Validating prerequisites for cleanup..."
    
    local prerequisites_met=true
    
    # Check for gcloud CLI
    if ! command_exists gcloud; then
        print_error "Google Cloud CLI (gcloud) is not installed"
        prerequisites_met=false
    else
        print_status "Google Cloud CLI found"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found"
        print_error "Run: gcloud auth login"
        prerequisites_met=false
    else
        local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
        print_status "Authenticated as: ${active_account}"
    fi
    
    if [ "$prerequisites_met" = false ]; then
        print_error "Prerequisites validation failed. Please address the issues above."
        exit 1
    fi
    
    print_status "Prerequisites validation completed successfully"
}

# Function to discover deployed resources
discover_resources() {
    print_step "Discovering deployed voice agent resources..."
    
    # Try to find resources from deployment artifacts
    local project_id=""
    local function_name=""
    local service_account=""
    local region=""
    
    # Check for deployment summary files
    local summary_files=(voice_agent_deployment_summary_*.json)
    if [ -f "${summary_files[0]}" ]; then
        print_status "Found deployment summary file: ${summary_files[0]}"
        project_id=$(jq -r '.deployment_info.project_id // empty' "${summary_files[0]}" 2>/dev/null || echo "")
        function_name=$(jq -r '.deployment_info.function_name // empty' "${summary_files[0]}" 2>/dev/null || echo "")
        service_account=$(jq -r '.deployment_info.service_account // empty' "${summary_files[0]}" 2>/dev/null || echo "")
        region=$(jq -r '.deployment_info.region // empty' "${summary_files[0]}" 2>/dev/null || echo "")
    fi
    
    # Check for environment files
    if [ -z "$project_id" ] && [ -f ".voice_agent_project_id" ]; then
        project_id=$(cat .voice_agent_project_id)
        print_status "Found project ID from artifact: ${project_id}"
    fi
    
    if [ -z "$function_name" ] && [ -f ".voice_agent_function_name" ]; then
        function_name=$(cat .voice_agent_function_name)
        print_status "Found function name from artifact: ${function_name}"
    fi
    
    # Try to detect from current gcloud configuration
    if [ -z "$project_id" ]; then
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -n "$project_id" ]; then
            print_warning "Using current gcloud project: ${project_id}"
        fi
    fi
    
    if [ -z "$region" ]; then
        region=$(gcloud config get-value functions/region 2>/dev/null || echo "us-central1")
        print_status "Using region: ${region}"
    fi
    
    # Interactive discovery if resources not found
    if [ -z "$project_id" ] && [ "$SKIP_CONFIRMATION" = "false" ]; then
        echo
        print_warning "Could not automatically discover voice agent resources"
        echo "Please provide the following information:"
        echo
        read -p "Project ID (voice-support-*): " project_id
        read -p "Function Name (voice-agent-*): " function_name
        read -p "Service Account (voice-agent-sa-*): " service_account
        read -p "Region [us-central1]: " region
        region=${region:-us-central1}
    fi
    
    # Export discovered resources
    export DISCOVERED_PROJECT_ID="$project_id"
    export DISCOVERED_FUNCTION_NAME="$function_name"
    export DISCOVERED_SERVICE_ACCOUNT="$service_account"
    export DISCOVERED_REGION="$region"
    
    # Validate we have minimum required information
    if [ -z "$project_id" ]; then
        print_error "Project ID is required for cleanup"
        return 1
    fi
    
    print_status "Resource discovery completed"
    print_status "Project ID: ${project_id}"
    print_status "Function Name: ${function_name:-'not specified'}"
    print_status "Service Account: ${service_account:-'not specified'}"
    print_status "Region: ${region}"
}

# Function to list all resources to be deleted
list_resources_for_deletion() {
    print_step "Scanning for voice agent resources to delete..."
    
    local project_id="$DISCOVERED_PROJECT_ID"
    local region="$DISCOVERED_REGION"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would scan for resources in project ${project_id}"
        return 0
    fi
    
    # Set project context
    gcloud config set project "$project_id" 2>/dev/null || true
    
    echo
    echo -e "${YELLOW}Resources found for deletion:${NC}"
    echo "----------------------------------------"
    
    # List Cloud Functions
    print_status "Scanning Cloud Functions..."
    local functions=$(gcloud functions list --regions="$region" --format="value(name)" --filter="name~voice-agent" 2>/dev/null || echo "")
    if [ -n "$functions" ]; then
        echo "Cloud Functions:"
        echo "$functions" | sed 's/^/  - /'
    else
        echo "  No voice agent Cloud Functions found"
    fi
    
    # List Service Accounts
    print_status "Scanning Service Accounts..."
    local service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email~voice-agent-sa" 2>/dev/null || echo "")
    if [ -n "$service_accounts" ]; then
        echo "Service Accounts:"
        echo "$service_accounts" | sed 's/^/  - /'
    else
        echo "  No voice agent Service Accounts found"
    fi
    
    # List IAM Policy Bindings (this is more complex to list specifically)
    print_status "IAM policy bindings will be removed for discovered service accounts"
    
    # Check for Cloud Storage buckets (if any were created)
    local buckets=$(gsutil ls -p "$project_id" 2>/dev/null | grep -E "(voice-agent|voice-support)" || echo "")
    if [ -n "$buckets" ]; then
        echo "Cloud Storage Buckets:"
        echo "$buckets" | sed 's/^/  - /'
    fi
    
    # Check project deletion eligibility
    echo
    print_warning "Project Deletion:"
    if [[ "$project_id" =~ ^voice-support- ]]; then
        echo "  - Project ${project_id} appears to be created by this recipe"
        echo "  - Will be marked for deletion (billing account will be unlinked)"
        export DELETE_PROJECT="true"
    else
        echo "  - Project ${project_id} does not match expected naming pattern"
        echo "  - Project will NOT be deleted (only resources within it)"
        export DELETE_PROJECT="false"
    fi
    
    echo "----------------------------------------"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = "true" ]; then
        print_warning "Skipping confirmation due to --skip-confirmation flag"
        return 0
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    echo
    echo -e "${RED}WARNING: This will permanently delete the resources listed above.${NC}"
    echo -e "${RED}This action cannot be undone.${NC}"
    echo
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        echo -e "${RED}The entire project ${DISCOVERED_PROJECT_ID} will be deleted!${NC}"
        echo
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        print_warning "Deletion cancelled by user"
        exit 0
    fi
    
    print_warning "Proceeding with resource deletion..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    print_step "Deleting Cloud Functions..."
    
    local project_id="$DISCOVERED_PROJECT_ID"
    local region="$DISCOVERED_REGION"
    local function_name="$DISCOVERED_FUNCTION_NAME"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would delete Cloud Functions"
        return 0
    fi
    
    # Delete specific function if known
    if [ -n "$function_name" ]; then
        print_status "Deleting function: ${function_name}"
        if gcloud functions delete "$function_name" --region="$region" --quiet 2>/dev/null; then
            print_status "✅ Function ${function_name} deleted successfully"
        else
            print_warning "Function ${function_name} not found or already deleted"
        fi
    fi
    
    # Delete any other voice agent functions
    local functions=$(gcloud functions list --regions="$region" --format="value(name)" --filter="name~voice-agent" 2>/dev/null || echo "")
    if [ -n "$functions" ]; then
        while IFS= read -r func; do
            if [ -n "$func" ] && [ "$func" != "$function_name" ]; then
                print_status "Deleting function: ${func}"
                if gcloud functions delete "$func" --region="$region" --quiet 2>/dev/null; then
                    print_status "✅ Function ${func} deleted successfully"
                else
                    print_warning "Failed to delete function ${func}"
                fi
            fi
        done <<< "$functions"
    fi
    
    print_status "Cloud Functions cleanup completed"
}

# Function to delete service accounts and IAM bindings
delete_service_accounts() {
    print_step "Deleting Service Accounts and IAM bindings..."
    
    local project_id="$DISCOVERED_PROJECT_ID"
    local service_account="$DISCOVERED_SERVICE_ACCOUNT"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would delete Service Accounts and IAM bindings"
        return 0
    fi
    
    # Get all voice agent service accounts
    local service_accounts=()
    if [ -n "$service_account" ]; then
        service_accounts+=("${service_account}@${project_id}.iam.gserviceaccount.com")
    fi
    
    # Add any other discovered service accounts
    while IFS= read -r sa; do
        if [ -n "$sa" ] && [[ "$sa" =~ voice-agent-sa ]]; then
            service_accounts+=("$sa")
        fi
    done <<< "$(gcloud iam service-accounts list --format="value(email)" --filter="email~voice-agent-sa" 2>/dev/null || echo "")"
    
    # Delete IAM policy bindings and service accounts
    for sa in "${service_accounts[@]}"; do
        if [ -n "$sa" ]; then
            print_status "Processing service account: ${sa}"
            
            # Remove IAM policy bindings
            local roles=(
                "roles/aiplatform.user"
                "roles/cloudfunctions.invoker"
                "roles/logging.logWriter"
                "roles/monitoring.metricWriter"
            )
            
            for role in "${roles[@]}"; do
                print_status "Removing role ${role} from ${sa}"
                if gcloud projects remove-iam-policy-binding "$project_id" \
                    --member="serviceAccount:${sa}" \
                    --role="$role" --quiet 2>/dev/null; then
                    print_status "✅ Role ${role} removed"
                else
                    print_warning "Role ${role} not found or already removed"
                fi
            done
            
            # Delete service account
            print_status "Deleting service account: ${sa}"
            if gcloud iam service-accounts delete "$sa" --quiet 2>/dev/null; then
                print_status "✅ Service account ${sa} deleted successfully"
            else
                print_warning "Service account ${sa} not found or already deleted"
            fi
        fi
    done
    
    print_status "Service Accounts cleanup completed"
}

# Function to delete Cloud Storage resources
delete_storage_resources() {
    print_step "Cleaning up Cloud Storage resources..."
    
    local project_id="$DISCOVERED_PROJECT_ID"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would delete Cloud Storage resources"
        return 0
    fi
    
    # Check for voice agent related buckets
    local buckets=$(gsutil ls -p "$project_id" 2>/dev/null | grep -E "(voice-agent|voice-support)" || echo "")
    
    if [ -n "$buckets" ]; then
        while IFS= read -r bucket; do
            if [ -n "$bucket" ]; then
                print_status "Deleting bucket: ${bucket}"
                if gsutil -m rm -r "$bucket" 2>/dev/null; then
                    print_status "✅ Bucket ${bucket} deleted successfully"
                else
                    print_warning "Failed to delete bucket ${bucket} or already deleted"
                fi
            fi
        done <<< "$buckets"
    else
        print_status "No voice agent Cloud Storage buckets found"
    fi
    
    print_status "Cloud Storage cleanup completed"
}

# Function to clean up local artifacts
cleanup_local_artifacts() {
    print_step "Cleaning up local deployment artifacts..."
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would clean up local artifacts"
        return 0
    fi
    
    # Remove deployment artifacts
    local artifacts=(
        ".voice_agent_project_id"
        ".voice_agent_function_name"
        ".voice_agent_function_url"
        ".voice_agent_work_dir"
        "voice_agent_deployment_summary_*.json"
        "voice_agent_deploy_*.log"
        "voice_test.html"
    )
    
    for artifact in "${artifacts[@]}"; do
        if ls $artifact 1> /dev/null 2>&1; then
            print_status "Removing: ${artifact}"
            rm -f $artifact
        fi
    done
    
    # Clean up working directory if it exists
    if [ -f ".voice_agent_work_dir" ]; then
        local work_dir=$(cat .voice_agent_work_dir)
        if [ -d "$work_dir" ]; then
            print_status "Removing working directory: ${work_dir}"
            rm -rf "$work_dir"
        fi
        rm -f .voice_agent_work_dir
    fi
    
    # Clean up any voice-support-agent directories
    for dir in voice-support-agent-*; do
        if [ -d "$dir" ]; then
            print_status "Removing directory: ${dir}"
            rm -rf "$dir"
        fi
    done
    
    print_status "Local artifacts cleanup completed"
}

# Function to handle project deletion
delete_project() {
    print_step "Handling project deletion..."
    
    local project_id="$DISCOVERED_PROJECT_ID"
    
    if [ "$DELETE_PROJECT" != "true" ]; then
        print_status "Project deletion not requested, skipping"
        return 0
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would delete project ${project_id}"
        return 0
    fi
    
    print_warning "Marking project ${project_id} for deletion..."
    
    # Note: Project deletion is a two-step process in GCP
    # First, we shut down the project, then it's automatically deleted after 30 days
    if gcloud projects delete "$project_id" --quiet 2>/dev/null; then
        print_status "✅ Project ${project_id} marked for deletion"
        print_status "The project will be permanently deleted in 30 days"
        print_status "To restore: gcloud projects undelete ${project_id}"
    else
        print_warning "Failed to delete project ${project_id}"
        print_warning "You may need to delete it manually from the console"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    print_step "Verifying cleanup completion..."
    
    local project_id="$DISCOVERED_PROJECT_ID"
    local region="$DISCOVERED_REGION"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would verify cleanup"
        return 0
    fi
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        print_status "Project marked for deletion, skipping resource verification"
        return 0
    fi
    
    # Set project context for verification
    gcloud config set project "$project_id" 2>/dev/null || true
    
    # Check for remaining Cloud Functions
    local remaining_functions=$(gcloud functions list --regions="$region" --format="value(name)" --filter="name~voice-agent" 2>/dev/null || echo "")
    if [ -n "$remaining_functions" ]; then
        print_warning "Some Cloud Functions may still exist:"
        echo "$remaining_functions" | sed 's/^/  - /'
    else
        print_status "✅ No voice agent Cloud Functions found"
    fi
    
    # Check for remaining Service Accounts
    local remaining_sa=$(gcloud iam service-accounts list --format="value(email)" --filter="email~voice-agent-sa" 2>/dev/null || echo "")
    if [ -n "$remaining_sa" ]; then
        print_warning "Some Service Accounts may still exist:"
        echo "$remaining_sa" | sed 's/^/  - /'
    else
        print_status "✅ No voice agent Service Accounts found"
    fi
    
    print_status "Cleanup verification completed"
}

# Function to generate cleanup summary
generate_cleanup_summary() {
    print_step "Generating cleanup summary..."
    
    local summary_file="voice_agent_cleanup_summary_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$summary_file" << EOF
{
    "cleanup_info": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "script_version": "${SCRIPT_VERSION}",
        "project_id": "${DISCOVERED_PROJECT_ID}",
        "region": "${DISCOVERED_REGION}",
        "function_name": "${DISCOVERED_FUNCTION_NAME}",
        "service_account": "${DISCOVERED_SERVICE_ACCOUNT}",
        "project_deleted": "${DELETE_PROJECT:-false}",
        "dry_run": "${DRY_RUN}"
    },
    "resources_cleaned": [
        "Cloud Functions matching voice-agent pattern",
        "Service Accounts matching voice-agent-sa pattern",
        "IAM role bindings for voice agent service accounts",
        "Cloud Storage buckets matching voice-agent pattern",
        "Local deployment artifacts and working directories"
    ],
    "notes": [
        "If project was deleted, it will be permanently removed in 30 days",
        "Some logs and monitoring data may persist beyond resource deletion",
        "Billing charges should stop within 24 hours of resource deletion"
    ]
}
EOF
    
    print_status "✅ Cleanup summary saved to: ${summary_file}"
    
    # Display summary
    echo
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  CLEANUP COMPLETED SUCCESSFULLY${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo
    if [ "$DELETE_PROJECT" = "true" ]; then
        echo -e "${BLUE}Project ${DISCOVERED_PROJECT_ID} has been marked for deletion${NC}"
        echo -e "${BLUE}It will be permanently deleted in 30 days${NC}"
        echo -e "${BLUE}To restore: gcloud projects undelete ${DISCOVERED_PROJECT_ID}${NC}"
    else
        echo -e "${BLUE}Voice agent resources removed from project ${DISCOVERED_PROJECT_ID}${NC}"
    fi
    echo
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "• Billing charges should stop within 24 hours"
    echo "• Some logs and monitoring data may persist"
    echo "• Check the Google Cloud Console to verify all resources are removed"
    echo
}

# Function to handle errors
handle_error() {
    local line_number=$1
    local exit_code=$2
    print_error "An error occurred on line ${line_number} with exit code ${exit_code}"
    print_error "Check the log file: ${LOG_FILE}"
    print_warning "Some resources may not have been cleaned up properly"
    print_warning "Please check the Google Cloud Console and clean up manually if needed"
    exit "${exit_code}"
}

# Function to handle script interruption
handle_interrupt() {
    print_warning "Cleanup interrupted by user"
    print_warning "Some resources may not have been cleaned up"
    print_warning "Re-run this script to continue cleanup"
    exit 130
}

# Set up error handling
trap 'handle_error ${LINENO} $?' ERR
trap 'handle_interrupt' INT TERM

# Main cleanup function
main() {
    # Validate prerequisites first
    validate_prerequisites
    
    # Discover resources to delete
    discover_resources
    
    # List resources that will be deleted
    list_resources_for_deletion
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup steps
    delete_cloud_functions
    delete_service_accounts
    delete_storage_resources
    cleanup_local_artifacts
    delete_project
    verify_cleanup
    generate_cleanup_summary
    
    print_status "Cleanup completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --project-id)
            DISCOVERED_PROJECT_ID="$2"
            shift 2
            ;;
        --function-name)
            DISCOVERED_FUNCTION_NAME="$2"
            shift 2
            ;;
        --service-account)
            DISCOVERED_SERVICE_ACCOUNT="$2"
            shift 2
            ;;
        --region)
            DISCOVERED_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Show what would be deleted without actually deleting"
            echo "  --force                Force deletion without interactive prompts"
            echo "  --skip-confirmation    Skip confirmation prompts"
            echo "  --project-id TEXT      Specify project ID to clean up"
            echo "  --function-name TEXT   Specify function name to delete"
            echo "  --service-account TEXT Specify service account to delete"
            echo "  --region TEXT          Specify region for resource cleanup"
            echo "  --help                 Show this help message"
            echo
            echo "Examples:"
            echo "  $0                     # Interactive cleanup with resource discovery"
            echo "  $0 --dry-run          # Show what would be deleted"
            echo "  $0 --force            # Skip all confirmations"
            echo "  $0 --project-id voice-support-123 --skip-confirmation"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"