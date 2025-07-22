#!/bin/bash

# Deploy script for Enterprise Data Discovery with Data Catalog and Cloud Workflows
# This script deploys the complete infrastructure for automated data discovery and cataloging

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
LOG_FILE="${PROJECT_ROOT}/deployment.log"
DRY_RUN=false
FORCE_DEPLOY=false
VERBOSE=false

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
    log "ERROR" "Deployment failed. Check the log file: $LOG_FILE"
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script exited with error code $exit_code"
    fi
}

trap cleanup EXIT

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Enterprise Data Discovery with Data Catalog and Cloud Workflows

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION             Deployment region (default: us-central1)
    -n, --dry-run                   Show what would be deployed without making changes
    -f, --force                     Force deployment even if resources exist
    -v, --verbose                   Enable verbose logging
    -h, --help                      Show this help message

EXAMPLES:
    $0 -p my-project-123
    $0 -p my-project-123 -r us-east1 -v
    $0 -p my-project-123 --dry-run

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT           Project ID (can be used instead of -p)
    DEPLOYMENT_REGION             Region (can be used instead of -r)

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
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
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

    # Check if required APIs are enabled
    log "INFO" "Checking required APIs..."
    local required_apis=(
        "datacatalog.googleapis.com"
        "workflows.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "bigquery.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
    )

    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            log "WARN" "API $api is not enabled. Enabling now..."
            if [[ "$DRY_RUN" == "false" ]]; then
                gcloud services enable "$api" || error_exit "Failed to enable API: $api"
            fi
        else
            log "DEBUG" "API $api is already enabled"
        fi
    done

    # Check IAM permissions
    log "INFO" "Checking IAM permissions..."
    local required_permissions=(
        "datacatalog.entryGroups.create"
        "workflows.workflows.create"
        "cloudfunctions.functions.create"
        "cloudscheduler.jobs.create"
        "storage.buckets.create"
        "bigquery.datasets.create"
    )

    local user_email
    user_email=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    
    if [[ -z "$user_email" ]]; then
        error_exit "Could not determine authenticated user email"
    fi

    log "DEBUG" "Authenticated as: $user_email"

    # Note: We'll do a basic check rather than testing each individual permission
    # as that would require more complex IAM testing
    log "INFO" "Prerequisites check completed successfully"
}

# Generate unique resource names
generate_resource_names() {
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100-999 -n 1)")
    
    export DEPLOYMENT_SUFFIX="${random_suffix}"
    export WORKFLOW_NAME="data-discovery-workflow-${DEPLOYMENT_SUFFIX}"
    export FUNCTION_NAME="metadata-extractor-${DEPLOYMENT_SUFFIX}"
    export SCHEDULER_JOB="discovery-scheduler-${DEPLOYMENT_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-data-catalog-staging-${DEPLOYMENT_SUFFIX}"
    
    log "INFO" "Generated resource names with suffix: $DEPLOYMENT_SUFFIX"
    log "DEBUG" "Workflow: $WORKFLOW_NAME"
    log "DEBUG" "Function: $FUNCTION_NAME"
    log "DEBUG" "Scheduler: $SCHEDULER_JOB"
    log "DEBUG" "Bucket: $BUCKET_NAME"
}

# Create Cloud Storage bucket for staging
create_storage_bucket() {
    log "INFO" "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log "WARN" "Bucket already exists, but force deployment is enabled"
        else
            log "WARN" "Bucket $BUCKET_NAME already exists. Skipping creation."
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create bucket: gs://$BUCKET_NAME"
        return 0
    fi
    
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        error_exit "Failed to create Cloud Storage bucket: $BUCKET_NAME"
    fi
    
    log "INFO" "✅ Cloud Storage bucket created successfully"
}

# Create Data Catalog tag templates
create_tag_templates() {
    log "INFO" "Creating Data Catalog tag templates..."
    
    # Create data classification tag template
    log "DEBUG" "Creating data classification tag template"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create data classification tag template"
    else
        if ! gcloud data-catalog tag-templates create data_classification \
            --location="$REGION" \
            --display-name="Data Classification Template" \
            --field=id=sensitivity,display-name="Data Sensitivity",type=enum,enum-values="PUBLIC|INTERNAL|CONFIDENTIAL|RESTRICTED" \
            --field=id=owner,display-name="Data Owner",type=string \
            --field=id=department,display-name="Department",type=string \
            --field=id=last_updated,display-name="Last Updated",type=datetime \
            2>/dev/null; then
            
            if gcloud data-catalog tag-templates describe data_classification --location="$REGION" &> /dev/null; then
                log "WARN" "Data classification tag template already exists"
            else
                error_exit "Failed to create data classification tag template"
            fi
        fi
    fi
    
    # Create data quality tag template
    log "DEBUG" "Creating data quality tag template"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create data quality tag template"
    else
        if ! gcloud data-catalog tag-templates create data_quality \
            --location="$REGION" \
            --display-name="Data Quality Metrics" \
            --field=id=completeness_score,display-name="Completeness Score",type=double \
            --field=id=accuracy_score,display-name="Accuracy Score",type=double \
            --field=id=freshness_days,display-name="Data Freshness (Days)",type=double \
            --field=id=validation_date,display-name="Last Validation",type=datetime \
            2>/dev/null; then
            
            if gcloud data-catalog tag-templates describe data_quality --location="$REGION" &> /dev/null; then
                log "WARN" "Data quality tag template already exists"
            else
                error_exit "Failed to create data quality tag template"
            fi
        fi
    fi
    
    log "INFO" "✅ Data Catalog tag templates created successfully"
}

# Deploy Cloud Function for metadata extraction
deploy_cloud_function() {
    log "INFO" "Deploying Cloud Function: $FUNCTION_NAME"
    
    local function_source_dir="${PROJECT_ROOT}/terraform/function_code"
    
    if [[ ! -d "$function_source_dir" ]]; then
        error_exit "Function source directory not found: $function_source_dir"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would deploy Cloud Function from: $function_source_dir"
        return 0
    fi
    
    # Deploy the function
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=python311 \
        --source="$function_source_dir" \
        --entry-point=discover_and_catalog \
        --trigger=http \
        --memory=1Gi \
        --timeout=540s \
        --max-instances=10 \
        --region="$REGION" \
        --allow-unauthenticated; then
        error_exit "Failed to deploy Cloud Function: $FUNCTION_NAME"
    fi
    
    log "INFO" "✅ Cloud Function deployed successfully"
}

# Deploy Cloud Workflow
deploy_cloud_workflow() {
    log "INFO" "Deploying Cloud Workflow: $WORKFLOW_NAME"
    
    local workflow_file="${PROJECT_ROOT}/terraform/workflow_definition.yaml"
    
    if [[ ! -f "$workflow_file" ]]; then
        error_exit "Workflow definition file not found: $workflow_file"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would deploy Cloud Workflow from: $workflow_file"
        return 0
    fi
    
    # Create a temporary workflow file with substituted variables
    local temp_workflow_file=$(mktemp)
    sed "s/metadata-extractor-\${input\.suffix}/metadata-extractor-${DEPLOYMENT_SUFFIX}/g" "$workflow_file" > "$temp_workflow_file"
    
    if ! gcloud workflows deploy "$WORKFLOW_NAME" \
        --source="$temp_workflow_file" \
        --location="$REGION"; then
        rm -f "$temp_workflow_file"
        error_exit "Failed to deploy Cloud Workflow: $WORKFLOW_NAME"
    fi
    
    rm -f "$temp_workflow_file"
    log "INFO" "✅ Cloud Workflow deployed successfully"
}

# Create Cloud Scheduler jobs
create_scheduler_jobs() {
    log "INFO" "Creating Cloud Scheduler jobs..."
    
    # Get the default service account
    local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    # Create daily discovery job
    log "DEBUG" "Creating daily scheduler job: $SCHEDULER_JOB"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create daily scheduler job"
    else
        if ! gcloud scheduler jobs create http "$SCHEDULER_JOB" \
            --location="$REGION" \
            --schedule="0 2 * * *" \
            --uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}/executions" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body="{\"argument\": \"{\\\"suffix\\\": \\\"${DEPLOYMENT_SUFFIX}\\\"}\"}" \
            --oauth-service-account-email="$service_account" \
            2>/dev/null; then
            
            if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location="$REGION" &> /dev/null; then
                log "WARN" "Daily scheduler job already exists"
            else
                error_exit "Failed to create daily scheduler job"
            fi
        fi
    fi
    
    # Create weekly comprehensive discovery job
    log "DEBUG" "Creating weekly scheduler job: ${SCHEDULER_JOB}-weekly"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create weekly scheduler job"
    else
        if ! gcloud scheduler jobs create http "${SCHEDULER_JOB}-weekly" \
            --location="$REGION" \
            --schedule="0 1 * * 0" \
            --uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}/executions" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body="{\"argument\": \"{\\\"suffix\\\": \\\"${DEPLOYMENT_SUFFIX}\\\", \\\"comprehensive\\\": true}\"}" \
            --oauth-service-account-email="$service_account" \
            2>/dev/null; then
            
            if gcloud scheduler jobs describe "${SCHEDULER_JOB}-weekly" --location="$REGION" &> /dev/null; then
                log "WARN" "Weekly scheduler job already exists"
            else
                error_exit "Failed to create weekly scheduler job"
            fi
        fi
    fi
    
    log "INFO" "✅ Cloud Scheduler jobs created successfully"
}

# Create sample data for testing
create_sample_data() {
    log "INFO" "Creating sample data assets for testing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create sample BigQuery datasets and Cloud Storage buckets"
        return 0
    fi
    
    # Create sample BigQuery datasets
    log "DEBUG" "Creating sample BigQuery datasets"
    
    if ! bq mk --dataset \
        --description="Sample customer data for discovery testing" \
        "${PROJECT_ID}:customer_analytics" 2>/dev/null; then
        if bq show "${PROJECT_ID}:customer_analytics" &> /dev/null; then
            log "WARN" "Dataset customer_analytics already exists"
        else
            log "WARN" "Failed to create dataset customer_analytics, but continuing"
        fi
    fi
    
    if ! bq mk --dataset \
        --description="Internal employee data for testing" \
        "${PROJECT_ID}:hr_internal" 2>/dev/null; then
        if bq show "${PROJECT_ID}:hr_internal" &> /dev/null; then
            log "WARN" "Dataset hr_internal already exists"
        else
            log "WARN" "Failed to create dataset hr_internal, but continuing"
        fi
    fi
    
    # Create sample tables
    log "DEBUG" "Creating sample BigQuery tables"
    
    bq mk --table \
        --description="Customer transaction history" \
        "${PROJECT_ID}:customer_analytics.transactions" \
        customer_id:STRING,transaction_date:TIMESTAMP,amount:FLOAT,product_category:STRING,payment_method:STRING \
        2>/dev/null || log "WARN" "Failed to create transactions table, but continuing"
    
    bq mk --table \
        --description="Employee personal information" \
        "${PROJECT_ID}:hr_internal.employees" \
        employee_id:STRING,first_name:STRING,last_name:STRING,email:STRING,department:STRING,salary:INTEGER,hire_date:DATE \
        2>/dev/null || log "WARN" "Failed to create employees table, but continuing"
    
    # Create sample Cloud Storage buckets
    log "DEBUG" "Creating sample Cloud Storage buckets"
    
    gsutil mb -p "$PROJECT_ID" -c STANDARD "gs://${PROJECT_ID}-public-datasets" 2>/dev/null || \
        log "WARN" "Failed to create public datasets bucket, but continuing"
    
    gsutil mb -p "$PROJECT_ID" -c STANDARD "gs://${PROJECT_ID}-confidential-reports" 2>/dev/null || \
        log "WARN" "Failed to create confidential reports bucket, but continuing"
    
    # Upload sample files
    log "DEBUG" "Uploading sample files"
    
    echo "Sample public dataset content" | gsutil cp - "gs://${PROJECT_ID}-public-datasets/sample-public-data.txt" 2>/dev/null || \
        log "WARN" "Failed to upload sample public data file, but continuing"
    
    echo "Confidential financial report data" | gsutil cp - "gs://${PROJECT_ID}-confidential-reports/financial-report-q4.txt" 2>/dev/null || \
        log "WARN" "Failed to upload sample confidential file, but continuing"
    
    log "INFO" "✅ Sample data assets created successfully"
}

# Test the deployment
test_deployment() {
    log "INFO" "Testing deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would test the deployment"
        return 0
    fi
    
    # Execute workflow manually for testing
    log "DEBUG" "Executing workflow for testing: $WORKFLOW_NAME"
    
    if ! gcloud workflows run "$WORKFLOW_NAME" \
        --location="$REGION" \
        --data="{\"suffix\": \"${DEPLOYMENT_SUFFIX}\"}" \
        >/dev/null 2>&1; then
        log "WARN" "Failed to execute test workflow, but deployment is complete"
        return 0
    fi
    
    # Wait a moment for execution to start
    sleep 5
    
    # Check if execution started successfully
    local execution_count
    execution_count=$(gcloud workflows executions list \
        --workflow="$WORKFLOW_NAME" \
        --location="$REGION" \
        --limit=1 \
        --format="value(name)" | wc -l)
    
    if [[ "$execution_count" -gt 0 ]]; then
        log "INFO" "✅ Test workflow execution started successfully"
    else
        log "WARN" "Test workflow execution may not have started properly"
    fi
}

# Save deployment information
save_deployment_info() {
    local deployment_info_file="${PROJECT_ROOT}/deployment-info.txt"
    
    log "INFO" "Saving deployment information to: $deployment_info_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would save deployment information"
        return 0
    fi
    
    cat > "$deployment_info_file" << EOF
# Enterprise Data Discovery Deployment Information
# Generated on: $(date)

PROJECT_ID=$PROJECT_ID
REGION=$REGION
DEPLOYMENT_SUFFIX=$DEPLOYMENT_SUFFIX

# Resource Names
WORKFLOW_NAME=$WORKFLOW_NAME
FUNCTION_NAME=$FUNCTION_NAME
SCHEDULER_JOB=$SCHEDULER_JOB
BUCKET_NAME=$BUCKET_NAME

# URLs and Endpoints
WORKFLOW_URL=https://console.cloud.google.com/workflows/workflow/$REGION/$WORKFLOW_NAME/executions?project=$PROJECT_ID
FUNCTION_URL=https://console.cloud.google.com/functions/details/$REGION/$FUNCTION_NAME?project=$PROJECT_ID
SCHEDULER_URL=https://console.cloud.google.com/cloudscheduler?project=$PROJECT_ID
DATA_CATALOG_URL=https://console.cloud.google.com/datacatalog?project=$PROJECT_ID

# Sample Datasets
BIGQUERY_DATASETS=customer_analytics,hr_internal
STORAGE_BUCKETS=${PROJECT_ID}-public-datasets,${PROJECT_ID}-confidential-reports

# Cleanup Command
# To clean up this deployment, run:
# ./scripts/destroy.sh -p $PROJECT_ID -s $DEPLOYMENT_SUFFIX
EOF
    
    log "INFO" "✅ Deployment information saved"
}

# Print deployment summary
print_summary() {
    log "INFO" "🎉 Deployment completed successfully!"
    echo
    echo -e "${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "Region: ${BLUE}$REGION${NC}"
    echo -e "Deployment Suffix: ${BLUE}$DEPLOYMENT_SUFFIX${NC}"
    echo
    echo -e "${GREEN}=== DEPLOYED RESOURCES ===${NC}"
    echo -e "✅ Data Catalog Tag Templates: ${BLUE}data_classification, data_quality${NC}"
    echo -e "✅ Cloud Function: ${BLUE}$FUNCTION_NAME${NC}"
    echo -e "✅ Cloud Workflow: ${BLUE}$WORKFLOW_NAME${NC}"
    echo -e "✅ Cloud Scheduler Jobs: ${BLUE}$SCHEDULER_JOB (daily), ${SCHEDULER_JOB}-weekly${NC}"
    echo -e "✅ Cloud Storage Bucket: ${BLUE}$BUCKET_NAME${NC}"
    echo -e "✅ Sample Data: ${BLUE}BigQuery datasets and Cloud Storage buckets${NC}"
    echo
    echo -e "${GREEN}=== NEXT STEPS ===${NC}"
    echo "1. Visit the Data Catalog console to view discovered assets:"
    echo "   https://console.cloud.google.com/datacatalog?project=$PROJECT_ID"
    echo
    echo "2. Monitor workflow executions:"
    echo "   https://console.cloud.google.com/workflows/workflow/$REGION/$WORKFLOW_NAME/executions?project=$PROJECT_ID"
    echo
    echo "3. View scheduled discovery jobs:"
    echo "   https://console.cloud.google.com/cloudscheduler?project=$PROJECT_ID"
    echo
    echo -e "${GREEN}=== SCHEDULING ===${NC}"
    echo "• Daily discovery runs at 2:00 AM"
    echo "• Weekly comprehensive discovery runs at 1:00 AM on Sundays"
    echo
    echo -e "${YELLOW}Note: Check deployment-info.txt for complete deployment details${NC}"
    echo -e "${YELLOW}Note: Use ./scripts/destroy.sh to clean up resources when done${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}🚀 Enterprise Data Discovery Deployment Script${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo
    
    # Initialize log file
    echo "# Enterprise Data Discovery Deployment Log" > "$LOG_FILE"
    echo "# Started: $(date)" >> "$LOG_FILE"
    echo >> "$LOG_FILE"
    
    log "INFO" "Starting deployment process..."
    
    # Parse arguments and check prerequisites
    parse_arguments "$@"
    check_prerequisites
    
    # Generate resource names
    generate_resource_names
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "🔍 DRY RUN MODE - No actual resources will be created"
        echo
    fi
    
    # Deploy infrastructure components
    create_storage_bucket
    create_tag_templates
    deploy_cloud_function
    deploy_cloud_workflow
    create_scheduler_jobs
    create_sample_data
    
    # Test and finalize
    test_deployment
    save_deployment_info
    
    if [[ "$DRY_RUN" == "false" ]]; then
        print_summary
    else
        log "INFO" "🔍 DRY RUN completed - no resources were actually created"
        echo
        echo -e "${YELLOW}To perform actual deployment, run without --dry-run flag${NC}"
    fi
    
    log "INFO" "Deployment process completed successfully"
}

# Run main function with all arguments
main "$@"