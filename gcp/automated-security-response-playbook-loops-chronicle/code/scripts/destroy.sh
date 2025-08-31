#!/bin/bash

# Automated Security Response with Playbook Loops and Chronicle - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Display script header
echo "================================================"
echo "Chronicle SOAR Security Automation Cleanup"
echo "================================================"
echo ""

# Check if running in interactive mode
if [[ -t 0 ]]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
SECURITY_TOPIC="${SECURITY_TOPIC:-}"
RESPONSE_TOPIC="${RESPONSE_TOPIC:-}"
SA_NAME="${SA_NAME:-security-automation-sa}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Get current project if not specified
    if [[ -z "${PROJECT_ID}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "${PROJECT_ID}" ]]; then
            error "No project ID specified and no default project configured."
            error "Set PROJECT_ID environment variable or use --project-id option."
            exit 1
        fi
        log "Using current project: ${PROJECT_ID}"
    fi
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error "Project ${PROJECT_ID} does not exist or is not accessible."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to discover resources if not specified
discover_resources() {
    log "Discovering security automation resources..."
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    # Discover Pub/Sub topics if not specified
    if [[ -z "${SECURITY_TOPIC}" ]] || [[ -z "${RESPONSE_TOPIC}" ]]; then
        log "Searching for security automation Pub/Sub topics..."
        
        local topics
        topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null || true)
        
        if [[ -z "${SECURITY_TOPIC}" ]]; then
            SECURITY_TOPIC=$(echo "${topics}" | grep "security-events" | head -n1 | sed 's|projects/.*/topics/||')
        fi
        
        if [[ -z "${RESPONSE_TOPIC}" ]]; then
            RESPONSE_TOPIC=$(echo "${topics}" | grep "response-actions" | head -n1 | sed 's|projects/.*/topics/||')
        fi
        
        # Extract suffix from topics if found
        if [[ -z "${RANDOM_SUFFIX}" ]] && [[ -n "${SECURITY_TOPIC}" ]]; then
            RANDOM_SUFFIX=$(echo "${SECURITY_TOPIC}" | sed 's/security-events-//')
        fi
    fi
    
    log "Resource discovery completed:"
    log "  Security Topic: ${SECURITY_TOPIC:-'Not found'}"
    log "  Response Topic: ${RESPONSE_TOPIC:-'Not found'}"
    log "  Random Suffix: ${RANDOM_SUFFIX:-'Not found'}"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log "Force delete enabled, skipping confirmation."
        return 0
    fi
    
    if [[ "${INTERACTIVE}" == "false" ]]; then
        log "Running in non-interactive mode with force delete disabled."
        error "Use --force-delete to proceed with cleanup in non-interactive mode."
        exit 1
    fi
    
    echo ""
    warn "This will delete the following resources in project: ${PROJECT_ID}"
    echo ""
    echo "Cloud Functions:"
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        echo "  • threat-enrichment-${RANDOM_SUFFIX}"
        echo "  • automated-response-${RANDOM_SUFFIX}"
    else
        echo "  • All security automation functions (if any)"
    fi
    echo ""
    echo "Pub/Sub Topics:"
    [[ -n "${SECURITY_TOPIC}" ]] && echo "  • ${SECURITY_TOPIC}"
    [[ -n "${RESPONSE_TOPIC}" ]] && echo "  • ${RESPONSE_TOPIC}"
    echo ""
    echo "Service Account:"
    echo "  • ${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "Security Command Center:"
    echo "  • Notification configurations (if any)"
    echo ""
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "⚠️  ENTIRE PROJECT: ${PROJECT_ID} (including all other resources)"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo ""
        warn "PROJECT DELETION CONFIRMATION"
        echo "You are about to delete the entire project: ${PROJECT_ID}"
        echo "This action is IRREVERSIBLE and will delete ALL resources in the project."
        echo ""
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "$REPLY" != "${PROJECT_ID}" ]]; then
            error "Project ID mismatch. Cleanup cancelled."
            exit 1
        fi
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Delete specific functions
        local functions=(
            "threat-enrichment-${RANDOM_SUFFIX}"
            "automated-response-${RANDOM_SUFFIX}"
        )
        
        for func in "${functions[@]}"; do
            log "Deleting function: ${func}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                if gcloud functions describe "${func}" --region="${REGION}" &> /dev/null; then
                    if ! gcloud functions delete "${func}" --region="${REGION}" --quiet; then
                        warn "Failed to delete function: ${func}"
                    else
                        success "Deleted function: ${func}"
                    fi
                else
                    warn "Function not found: ${func}"
                fi
            fi
        done
    else
        # Search for all security automation functions
        log "Searching for security automation functions..."
        local functions
        functions=$(gcloud functions list --format="value(name)" --filter="name~'threat-enrichment|automated-response'" 2>/dev/null || true)
        
        if [[ -n "${functions}" ]]; then
            while IFS= read -r func; do
                if [[ -n "${func}" ]]; then
                    log "Deleting discovered function: ${func}"
                    if [[ "${DRY_RUN}" == "false" ]]; then
                        if ! gcloud functions delete "${func}" --region="${REGION}" --quiet; then
                            warn "Failed to delete function: ${func}"
                        else
                            success "Deleted function: ${func}"
                        fi
                    fi
                fi
            done <<< "${functions}"
        else
            log "No security automation functions found"
        fi
    fi
}

# Function to delete Pub/Sub topics
delete_pubsub_topics() {
    log "Deleting Pub/Sub topics..."
    
    local topics_to_delete=()
    
    if [[ -n "${SECURITY_TOPIC}" ]]; then
        topics_to_delete+=("${SECURITY_TOPIC}")
    fi
    
    if [[ -n "${RESPONSE_TOPIC}" ]]; then
        topics_to_delete+=("${RESPONSE_TOPIC}")
    fi
    
    # If no specific topics found, search for security automation topics
    if [[ ${#topics_to_delete[@]} -eq 0 ]]; then
        log "Searching for security automation Pub/Sub topics..."
        local discovered_topics
        discovered_topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~'security-events|response-actions'" 2>/dev/null || true)
        
        while IFS= read -r topic; do
            if [[ -n "${topic}" ]]; then
                topics_to_delete+=("$(echo "${topic}" | sed 's|projects/.*/topics/||')")
            fi
        done <<< "${discovered_topics}"
    fi
    
    # Delete topics
    for topic in "${topics_to_delete[@]}"; do
        if [[ -n "${topic}" ]]; then
            log "Deleting Pub/Sub topic: ${topic}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                if gcloud pubsub topics describe "${topic}" &> /dev/null; then
                    if ! gcloud pubsub topics delete "${topic}" --quiet; then
                        warn "Failed to delete topic: ${topic}"
                    else
                        success "Deleted topic: ${topic}"
                    fi
                else
                    warn "Topic not found: ${topic}"
                fi
            fi
        fi
    done
    
    if [[ ${#topics_to_delete[@]} -eq 0 ]]; then
        log "No Pub/Sub topics to delete"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Cleaning up IAM resources..."
    
    local service_account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if [[ "${DRY_RUN}" == "false" ]]; then
        if gcloud iam service-accounts describe "${service_account}" &> /dev/null; then
            log "Removing IAM policy bindings for service account..."
            
            # List of roles that might have been granted
            local roles=(
                "roles/securitycenter.findings.editor"
                "roles/pubsub.publisher"
                "roles/pubsub.subscriber"
                "roles/cloudfunctions.invoker"
                "roles/compute.instanceAdmin.v1"
                "roles/logging.logWriter"
                "roles/cloudtrace.agent"
            )
            
            for role in "${roles[@]}"; do
                log "Removing role: ${role}"
                if gcloud projects get-iam-policy "${PROJECT_ID}" --format="value(bindings.members)" --filter="bindings.role:${role}" | grep -q "${service_account}"; then
                    if ! gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                        --member="serviceAccount:${service_account}" \
                        --role="${role}" \
                        --quiet; then
                        warn "Failed to remove role: ${role}"
                    fi
                fi
            done
            
            # Delete service account
            log "Deleting service account: ${service_account}"
            if ! gcloud iam service-accounts delete "${service_account}" --quiet; then
                warn "Failed to delete service account: ${service_account}"
            else
                success "Deleted service account: ${service_account}"
            fi
        else
            log "Service account not found: ${service_account}"
        fi
    fi
}

# Function to clean up Security Command Center
cleanup_security_command_center() {
    log "Cleaning up Security Command Center configurations..."
    
    local org_id
    org_id=$(gcloud organizations list --format="value(name)" 2>/dev/null | head -n1)
    
    if [[ -z "${org_id}" ]]; then
        log "No organization found. Skipping Security Command Center cleanup."
        return 0
    fi
    
    log "Found organization: ${org_id}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # List and delete notification configurations
        local notifications
        notifications=$(gcloud scc notifications list --organization="${org_id}" --format="value(name)" 2>/dev/null | grep "scc-automation" || true)
        
        while IFS= read -r notification; do
            if [[ -n "${notification}" ]]; then
                local notification_id
                notification_id=$(echo "${notification}" | sed 's|.*/||')
                log "Deleting SCC notification: ${notification_id}"
                
                if ! gcloud scc notifications delete "${notification_id}" --organization="${org_id}" --quiet; then
                    warn "Failed to delete SCC notification: ${notification_id}"
                else
                    success "Deleted SCC notification: ${notification_id}"
                fi
            fi
        done <<< "${notifications}"
        
        if [[ -z "${notifications}" ]]; then
            log "No Security Command Center notifications found"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "security-functions/"
        "chronicle-playbook-config.json"
        "generate-test-events.py"
    )
    
    for item in "${files_to_remove[@]}"; do
        if [[ -e "${item}" ]]; then
            log "Removing: ${item}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                rm -rf "${item}"
                success "Removed: ${item}"
            fi
        fi
    done
}

# Function to delete entire project
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return 0
    fi
    
    log "Deleting entire project: ${PROJECT_ID}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! gcloud projects delete "${PROJECT_ID}" --quiet; then
            error "Failed to delete project: ${PROJECT_ID}"
            return 1
        else
            success "Project deleted: ${PROJECT_ID}"
            return 0
        fi
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "=============================================="
    echo "           CLEANUP SUMMARY"
    echo "=============================================="
    echo ""
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "Project Deletion:"
        echo "  • Deleted entire project: ${PROJECT_ID}"
    else
        echo "Cleaned up resources in project: ${PROJECT_ID}"
        echo ""
        echo "Resources Removed:"
        echo "  • Cloud Functions (threat enrichment and automated response)"
        echo "  • Pub/Sub topics (security events and response actions)"
        echo "  • Service account and IAM bindings"
        echo "  • Security Command Center notifications"
        echo "  • Local configuration files"
    fi
    
    echo ""
    echo "Manual Cleanup Required:"
    echo "  • Chronicle SOAR playbooks (must be removed from Chronicle console)"
    echo "  • Any custom firewall rules or Cloud Armor policies"
    echo "  • Integration configurations with external ITSM systems"
    echo ""
    
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        echo "Note: The project ${PROJECT_ID} was preserved."
        echo "Delete it manually if no longer needed:"
        echo "  gcloud projects delete ${PROJECT_ID}"
        echo ""
    fi
    
    success "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log "Starting Chronicle SOAR Security Automation cleanup..."
    
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
            --random-suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            --security-topic)
                SECURITY_TOPIC="$2"
                shift 2
                ;;
            --response-topic)
                RESPONSE_TOPIC="$2"
                shift 2
                ;;
            --service-account)
                SA_NAME="$2"
                shift 2
                ;;
            --force-delete)
                FORCE_DELETE="true"
                shift
                ;;
            --delete-project)
                DELETE_PROJECT="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --project-id ID           Google Cloud Project ID"
                echo "  --region REGION          Deployment region (default: us-central1)"
                echo "  --random-suffix SUFFIX   Random suffix used during deployment"
                echo "  --security-topic TOPIC   Security events Pub/Sub topic name"
                echo "  --response-topic TOPIC   Response actions Pub/Sub topic name"
                echo "  --service-account NAME   Service account name (default: security-automation-sa)"
                echo "  --force-delete           Skip confirmation prompts"
                echo "  --delete-project         Delete the entire project"
                echo "  --dry-run               Show what would be deleted without doing it"
                echo "  --help                  Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  PROJECT_ID              Google Cloud Project ID"
                echo "  REGION                  Deployment region"
                echo "  RANDOM_SUFFIX           Random suffix from deployment"
                echo "  SECURITY_TOPIC          Security events topic name"
                echo "  RESPONSE_TOPIC          Response actions topic name"
                echo "  SA_NAME                 Service account name"
                echo "  FORCE_DELETE            Skip confirmations (true/false)"
                echo "  DELETE_PROJECT          Delete entire project (true/false)"
                echo "  DRY_RUN                Dry run mode (true/false)"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "Running in DRY-RUN mode - no resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    confirm_deletion
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        delete_project
    else
        delete_cloud_functions
        delete_pubsub_topics
        cleanup_security_command_center
        delete_iam_resources
        cleanup_local_files
    fi
    
    display_summary
}

# Set trap for cleanup on script exit
trap 'echo ""; warn "Cleanup interrupted. Some resources may still exist."' INT TERM

# Run main function
main "$@"