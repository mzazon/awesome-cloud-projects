#!/bin/bash

# Destroy script for Enterprise Data Discovery with Data Catalog and Cloud Workflows
# This script safely removes all infrastructure components created by the deploy script

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_ROOT}/cleanup.log"
DRY_RUN=false
FORCE_CLEANUP=false
VERBOSE=false
KEEP_SAMPLE_DATA=false

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            else
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Cleanup failed. Check the log file: $LOG_FILE"
    exit 1
}

# Cleanup on exit
cleanup_handler() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script exited with error code $exit_code"
    fi
}

trap cleanup_handler EXIT

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Enterprise Data Discovery infrastructure and clean up resources

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION             Deployment region (default: us-central1)
    -s, --suffix SUFFIX             Deployment suffix to identify specific deployment
    -n, --dry-run                   Show what would be deleted without making changes
    -f, --force                     Force cleanup without confirmation prompts
    -k, --keep-sample-data          Keep sample BigQuery datasets and Storage buckets
    -v, --verbose                   Enable verbose logging
    -h, --help                      Show this help message

EXAMPLES:
    $0 -p my-project-123 -s abc123
    $0 -p my-project-123 --dry-run
    $0 -p my-project-123 -s abc123 --keep-sample-data -v

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT           Project ID (can be used instead of -p)
    DEPLOYMENT_REGION             Region (can be used instead of -r)
    DEPLOYMENT_SUFFIX             Deployment suffix (can be used instead of -s)

EOF
}

# Parse command line arguments
parse_arguments() {
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
            -s|--suffix)
                DEPLOYMENT_SUFFIX="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -k|--keep-sample-data)
                KEEP_SAMPLE_DATA=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use -h for help."
                ;;
        esac
    done

    # Set defaults from environment or hardcoded values
    PROJECT_ID="${PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
    REGION="${REGION:-${DEPLOYMENT_REGION:-us-central1}}"
    DEPLOYMENT_SUFFIX="${DEPLOYMENT_SUFFIX:-}"

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        error_exit "Project ID is required. Use -p PROJECT_ID or set GOOGLE_CLOUD_PROJECT environment variable."
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' does not exist or is not accessible."
    fi

    # Set project context
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project context"
    log "INFO" "Using project: $PROJECT_ID"

    log "INFO" "Prerequisites check completed successfully"
}

# Load deployment info if available
load_deployment_info() {
    local deployment_info_file="${PROJECT_ROOT}/deployment-info.txt"
    
    if [[ -f "$deployment_info_file" ]]; then
        log "INFO" "Loading deployment information from: $deployment_info_file"
        
        # Source the deployment info file safely
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] || [[ -z "$key" ]] && continue
            
            # Export the variable
            export "$key"="$value"
            log "DEBUG" "Loaded: $key=$value"
        done < "$deployment_info_file"
        
        # Use loaded values if not provided via command line
        DEPLOYMENT_SUFFIX="${DEPLOYMENT_SUFFIX:-${DEPLOYMENT_SUFFIX:-}}"
        
        log "INFO" "Deployment information loaded successfully"
    else
        log "WARN" "Deployment info file not found. Using command line parameters only."
    fi
}

# Generate resource names based on suffix
generate_resource_names() {
    if [[ -z "$DEPLOYMENT_SUFFIX" ]]; then
        log "WARN" "No deployment suffix provided. Will attempt to find resources by pattern."
        # Set empty names to search for patterns later
        export WORKFLOW_NAME=""
        export FUNCTION_NAME=""
        export SCHEDULER_JOB=""
        export BUCKET_NAME=""
    else
        export WORKFLOW_NAME="data-discovery-workflow-${DEPLOYMENT_SUFFIX}"
        export FUNCTION_NAME="metadata-extractor-${DEPLOYMENT_SUFFIX}"
        export SCHEDULER_JOB="discovery-scheduler-${DEPLOYMENT_SUFFIX}"
        export BUCKET_NAME="${PROJECT_ID}-data-catalog-staging-${DEPLOYMENT_SUFFIX}"
        
        log "INFO" "Using deployment suffix: $DEPLOYMENT_SUFFIX"
        log "DEBUG" "Workflow: $WORKFLOW_NAME"
        log "DEBUG" "Function: $FUNCTION_NAME"
        log "DEBUG" "Scheduler: $SCHEDULER_JOB"
        log "DEBUG" "Bucket: $BUCKET_NAME"
    fi
}

# Find resources by pattern if suffix not provided
find_resources_by_pattern() {
    if [[ -n "$DEPLOYMENT_SUFFIX" ]]; then
        return 0  # Skip if suffix is provided
    fi
    
    log "INFO" "Searching for resources by pattern..."
    
    # Find workflows
    local workflows
    workflows=$(gcloud workflows list --location="$REGION" --filter="name:data-discovery-workflow-*" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$workflows" ]]; then
        WORKFLOW_NAME=$(echo "$workflows" | head -n1)
        log "DEBUG" "Found workflow: $WORKFLOW_NAME"
    fi
    
    # Find functions
    local functions
    functions=$(gcloud functions list --region="$REGION" --filter="name:metadata-extractor-*" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$functions" ]]; then
        FUNCTION_NAME=$(echo "$functions" | head -n1)
        log "DEBUG" "Found function: $FUNCTION_NAME"
    fi
    
    # Find scheduler jobs
    local jobs
    jobs=$(gcloud scheduler jobs list --location="$REGION" --filter="name:discovery-scheduler-*" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$jobs" ]]; then
        SCHEDULER_JOB=$(echo "$jobs" | head -n1 | sed 's|.*/||')
        log "DEBUG" "Found scheduler job: $SCHEDULER_JOB"
    fi
    
    # Find staging buckets
    local buckets
    buckets=$(gsutil ls -b | grep "gs://${PROJECT_ID}-data-catalog-staging-" | head -n1 | sed 's|gs://||' | sed 's|/||' 2>/dev/null || echo "")
    if [[ -n "$buckets" ]]; then
        BUCKET_NAME="$buckets"
        log "DEBUG" "Found bucket: $BUCKET_NAME"
    fi
    
    log "INFO" "Resource discovery completed"
}

# Confirm cleanup operation
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    echo -e "${YELLOW}⚠️  WARNING: This will delete the following resources:${NC}"
    echo
    
    if [[ -n "$WORKFLOW_NAME" ]]; then
        echo -e "  • Cloud Workflow: ${RED}$WORKFLOW_NAME${NC}"
    fi
    
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo -e "  • Cloud Function: ${RED}$FUNCTION_NAME${NC}"
    fi
    
    if [[ -n "$SCHEDULER_JOB" ]]; then
        echo -e "  • Scheduler Jobs: ${RED}$SCHEDULER_JOB, ${SCHEDULER_JOB}-weekly${NC}"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo -e "  • Storage Bucket: ${RED}$BUCKET_NAME${NC}"
    fi
    
    echo -e "  • Data Catalog Tag Templates: ${RED}data_classification, data_quality${NC}"
    
    if [[ "$KEEP_SAMPLE_DATA" == "false" ]]; then
        echo -e "  • Sample BigQuery Datasets: ${RED}customer_analytics, hr_internal${NC}"
        echo -e "  • Sample Storage Buckets: ${RED}${PROJECT_ID}-public-datasets, ${PROJECT_ID}-confidential-reports${NC}"
    fi
    
    echo
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "INFO" "Deleting Cloud Scheduler jobs..."
    
    if [[ -z "$SCHEDULER_JOB" ]]; then
        log "WARN" "No scheduler job name found, skipping"
        return 0
    fi
    
    # Delete daily job
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete scheduler job: $SCHEDULER_JOB"
    else
        if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location="$REGION" &> /dev/null; then
            if gcloud scheduler jobs delete "$SCHEDULER_JOB" --location="$REGION" --quiet; then
                log "INFO" "✅ Deleted daily scheduler job: $SCHEDULER_JOB"
            else
                log "WARN" "Failed to delete daily scheduler job: $SCHEDULER_JOB"
            fi
        else
            log "DEBUG" "Daily scheduler job not found: $SCHEDULER_JOB"
        fi
    fi
    
    # Delete weekly job
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete scheduler job: ${SCHEDULER_JOB}-weekly"
    else
        if gcloud scheduler jobs describe "${SCHEDULER_JOB}-weekly" --location="$REGION" &> /dev/null; then
            if gcloud scheduler jobs delete "${SCHEDULER_JOB}-weekly" --location="$REGION" --quiet; then
                log "INFO" "✅ Deleted weekly scheduler job: ${SCHEDULER_JOB}-weekly"
            else
                log "WARN" "Failed to delete weekly scheduler job: ${SCHEDULER_JOB}-weekly"
            fi
        else
            log "DEBUG" "Weekly scheduler job not found: ${SCHEDULER_JOB}-weekly"
        fi
    fi
}

# Delete Cloud Workflow
delete_cloud_workflow() {
    log "INFO" "Deleting Cloud Workflow..."
    
    if [[ -z "$WORKFLOW_NAME" ]]; then
        log "WARN" "No workflow name found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete workflow: $WORKFLOW_NAME"
        return 0
    fi
    
    if gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" &> /dev/null; then
        if gcloud workflows delete "$WORKFLOW_NAME" --location="$REGION" --quiet; then
            log "INFO" "✅ Deleted Cloud Workflow: $WORKFLOW_NAME"
        else
            log "WARN" "Failed to delete Cloud Workflow: $WORKFLOW_NAME"
        fi
    else
        log "DEBUG" "Cloud Workflow not found: $WORKFLOW_NAME"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log "INFO" "Deleting Cloud Function..."
    
    if [[ -z "$FUNCTION_NAME" ]]; then
        log "WARN" "No function name found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete function: $FUNCTION_NAME"
        return 0
    fi
    
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 &> /dev/null; then
        if gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --gen2 --quiet; then
            log "INFO" "✅ Deleted Cloud Function: $FUNCTION_NAME"
        else
            log "WARN" "Failed to delete Cloud Function: $FUNCTION_NAME"
        fi
    else
        log "DEBUG" "Cloud Function not found: $FUNCTION_NAME"
    fi
}

# Delete Data Catalog tag templates
delete_tag_templates() {
    log "INFO" "Deleting Data Catalog tag templates..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete tag templates: data_classification, data_quality"
        return 0
    fi
    
    # Delete data_quality template
    if gcloud data-catalog tag-templates describe data_quality --location="$REGION" &> /dev/null; then
        if gcloud data-catalog tag-templates delete data_quality --location="$REGION" --quiet; then
            log "INFO" "✅ Deleted tag template: data_quality"
        else
            log "WARN" "Failed to delete tag template: data_quality"
        fi
    else
        log "DEBUG" "Tag template not found: data_quality"
    fi
    
    # Delete data_classification template
    if gcloud data-catalog tag-templates describe data_classification --location="$REGION" &> /dev/null; then
        if gcloud data-catalog tag-templates delete data_classification --location="$REGION" --quiet; then
            log "INFO" "✅ Deleted tag template: data_classification"
        else
            log "WARN" "Failed to delete tag template: data_classification"
        fi
    else
        log "DEBUG" "Tag template not found: data_classification"
    fi
}

# Delete staging bucket
delete_staging_bucket() {
    log "INFO" "Deleting staging bucket..."
    
    if [[ -z "$BUCKET_NAME" ]]; then
        log "WARN" "No staging bucket name found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete bucket: $BUCKET_NAME"
        return 0
    fi
    
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        if gsutil rm -r "gs://$BUCKET_NAME"; then
            log "INFO" "✅ Deleted staging bucket: $BUCKET_NAME"
        else
            log "WARN" "Failed to delete staging bucket: $BUCKET_NAME"
        fi
    else
        log "DEBUG" "Staging bucket not found: $BUCKET_NAME"
    fi
}

# Delete sample data
delete_sample_data() {
    if [[ "$KEEP_SAMPLE_DATA" == "true" ]]; then
        log "INFO" "Keeping sample data as requested"
        return 0
    fi
    
    log "INFO" "Deleting sample data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete sample BigQuery datasets and Storage buckets"
        return 0
    fi
    
    # Delete BigQuery datasets
    log "DEBUG" "Deleting sample BigQuery datasets"
    
    if bq show "${PROJECT_ID}:hr_internal" &> /dev/null; then
        if bq rm -r -f "${PROJECT_ID}:hr_internal"; then
            log "INFO" "✅ Deleted BigQuery dataset: hr_internal"
        else
            log "WARN" "Failed to delete BigQuery dataset: hr_internal"
        fi
    else
        log "DEBUG" "BigQuery dataset not found: hr_internal"
    fi
    
    if bq show "${PROJECT_ID}:customer_analytics" &> /dev/null; then
        if bq rm -r -f "${PROJECT_ID}:customer_analytics"; then
            log "INFO" "✅ Deleted BigQuery dataset: customer_analytics"
        else
            log "WARN" "Failed to delete BigQuery dataset: customer_analytics"
        fi
    else
        log "DEBUG" "BigQuery dataset not found: customer_analytics"
    fi
    
    # Delete sample Cloud Storage buckets
    log "DEBUG" "Deleting sample Cloud Storage buckets"
    
    if gsutil ls -b "gs://${PROJECT_ID}-confidential-reports" &> /dev/null; then
        if gsutil rm -r "gs://${PROJECT_ID}-confidential-reports"; then
            log "INFO" "✅ Deleted sample bucket: ${PROJECT_ID}-confidential-reports"
        else
            log "WARN" "Failed to delete sample bucket: ${PROJECT_ID}-confidential-reports"
        fi
    else
        log "DEBUG" "Sample bucket not found: ${PROJECT_ID}-confidential-reports"
    fi
    
    if gsutil ls -b "gs://${PROJECT_ID}-public-datasets" &> /dev/null; then
        if gsutil rm -r "gs://${PROJECT_ID}-public-datasets"; then
            log "INFO" "✅ Deleted sample bucket: ${PROJECT_ID}-public-datasets"
        else
            log "WARN" "Failed to delete sample bucket: ${PROJECT_ID}-public-datasets"
        fi
    else
        log "DEBUG" "Sample bucket not found: ${PROJECT_ID}-public-datasets"
    fi
}

# Clean up deployment info file
cleanup_deployment_info() {
    local deployment_info_file="${PROJECT_ROOT}/deployment-info.txt"
    
    if [[ -f "$deployment_info_file" ]] && [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Removing deployment info file: $deployment_info_file"
        rm -f "$deployment_info_file"
        log "INFO" "✅ Deployment info file removed"
    fi
}

# Print cleanup summary
print_summary() {
    log "INFO" "🧹 Cleanup completed successfully!"
    echo
    echo -e "${GREEN}=== CLEANUP SUMMARY ===${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "Region: ${BLUE}$REGION${NC}"
    
    if [[ -n "$DEPLOYMENT_SUFFIX" ]]; then
        echo -e "Deployment Suffix: ${BLUE}$DEPLOYMENT_SUFFIX${NC}"
    fi
    
    echo
    echo -e "${GREEN}=== RESOURCES CLEANED UP ===${NC}"
    echo -e "✅ Cloud Scheduler jobs removed"
    echo -e "✅ Cloud Workflow removed"
    echo -e "✅ Cloud Function removed"
    echo -e "✅ Data Catalog tag templates removed"
    echo -e "✅ Staging bucket removed"
    
    if [[ "$KEEP_SAMPLE_DATA" == "false" ]]; then
        echo -e "✅ Sample data removed"
    else
        echo -e "ℹ️  Sample data preserved"
    fi
    
    echo
    echo -e "${GREEN}=== VERIFICATION ===${NC}"
    echo "You can verify cleanup by checking:"
    echo "• Cloud Console Workflows: https://console.cloud.google.com/workflows?project=$PROJECT_ID"
    echo "• Cloud Console Functions: https://console.cloud.google.com/functions?project=$PROJECT_ID"
    echo "• Cloud Console Scheduler: https://console.cloud.google.com/cloudscheduler?project=$PROJECT_ID"
    echo "• Data Catalog: https://console.cloud.google.com/datacatalog?project=$PROJECT_ID"
    echo
    echo -e "${YELLOW}Note: Some Data Catalog entries may persist as they reference external data sources${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}🧹 Enterprise Data Discovery Cleanup Script${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
    
    # Initialize log file
    echo "# Enterprise Data Discovery Cleanup Log" > "$LOG_FILE"
    echo "# Started: $(date)" >> "$LOG_FILE"
    echo >> "$LOG_FILE"
    
    log "INFO" "Starting cleanup process..."
    
    # Parse arguments and check prerequisites
    parse_arguments "$@"
    check_prerequisites
    
    # Load deployment info and generate resource names
    load_deployment_info
    generate_resource_names
    find_resources_by_pattern
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "🔍 DRY RUN MODE - No actual resources will be deleted"
        echo
    fi
    
    # Confirm cleanup operation
    confirm_cleanup
    
    # Perform cleanup in reverse order of creation
    delete_scheduler_jobs
    delete_cloud_workflow
    delete_cloud_function
    delete_tag_templates
    delete_staging_bucket
    delete_sample_data
    cleanup_deployment_info
    
    if [[ "$DRY_RUN" == "false" ]]; then
        print_summary
    else
        log "INFO" "🔍 DRY RUN completed - no resources were actually deleted"
        echo
        echo -e "${YELLOW}To perform actual cleanup, run without --dry-run flag${NC}"
    fi
    
    log "INFO" "Cleanup process completed successfully"
}

# Run main function with all arguments
main "$@"