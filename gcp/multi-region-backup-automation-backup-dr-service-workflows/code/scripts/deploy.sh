#!/bin/bash

# Multi-Region Backup Automation with Backup and DR Service and Cloud Workflows
# Deployment Script for GCP Recipe
# 
# This script automates the deployment of a comprehensive backup and disaster recovery
# system using Google Cloud's Backup and DR Service orchestrated by Cloud Workflows.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/backup-automation-deploy-$(date +%Y%m%d_%H%M%S).log"
readonly REQUIRED_APIS=(
    "compute.googleapis.com"
    "backupdr.googleapis.com"
    "workflows.googleapis.com"
    "cloudscheduler.googleapis.com"
    "monitoring.googleapis.com"
)

# Global variables
PROJECT_ID=""
PRIMARY_REGION="us-central1"
SECONDARY_REGION="us-east1"
BACKUP_VAULT_PRIMARY="backup-vault-primary"
BACKUP_VAULT_SECONDARY="backup-vault-secondary"
RANDOM_SUFFIX=""
WORKFLOW_NAME=""
SCHEDULER_JOB=""
SA_EMAIL=""
DRY_RUN=false
SKIP_CONFIRMATION=false

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
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
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check log file: $LOG_FILE"
    exit 1
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy multi-region backup automation infrastructure on Google Cloud Platform.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --primary-region REGION    Primary region (default: us-central1)
    -s, --secondary-region REGION  Secondary region (default: us-east1)
    -d, --dry-run                  Show what would be deployed without making changes
    -y, --yes                      Skip confirmation prompts
    -h, --help                     Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --primary-region us-west1 --secondary-region us-east1
    $0 --project-id my-project-123 --dry-run

For more information, refer to the recipe documentation.
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
            -r|--primary-region)
                PRIMARY_REGION="$2"
                shift 2
                ;;
            -s|--secondary-region)
                SECONDARY_REGION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        error_exit "Project ID is required. Use --project-id PROJECT_ID or --help for usage."
    fi

    # Generate random suffix for unique resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    WORKFLOW_NAME="backup-workflow-${RANDOM_SUFFIX}"
    SCHEDULER_JOB="backup-scheduler-${RANDOM_SUFFIX}"
    SA_EMAIL="backup-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Check if gcloud CLI is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first: https://cloud.google.com/sdk/docs/install"
    fi

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi

    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Cannot access project '$PROJECT_ID'. Check project ID and permissions."
    fi

    # Check if regions are valid
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION"; do
        if ! gcloud compute regions describe "$region" &> /dev/null; then
            error_exit "Invalid region: $region"
        fi
    done

    # Check if OpenSSL is available for random generation
    if ! command -v openssl &> /dev/null; then
        log "WARN" "OpenSSL not found. Using timestamp for random suffix."
    fi

    log "INFO" "Prerequisites check completed successfully"
}

# Enable required APIs
enable_apis() {
    log "INFO" "Enabling required Google Cloud APIs..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return 0
    fi

    local api_status
    for api in "${REQUIRED_APIS[@]}"; do
        log "DEBUG" "Checking API: $api"
        api_status=$(gcloud services list --enabled --filter="name:$api" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -z "$api_status" ]]; then
            log "INFO" "Enabling API: $api"
            if ! gcloud services enable "$api" --project="$PROJECT_ID"; then
                error_exit "Failed to enable API: $api"
            fi
        else
            log "DEBUG" "API already enabled: $api"
        fi
    done

    # Wait for APIs to be fully enabled
    log "INFO" "Waiting for APIs to be fully available..."
    sleep 30

    log "INFO" "APIs enabled successfully"
}

# Create service account for backup automation
create_service_account() {
    log "INFO" "Creating service account for backup automation..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create service account: backup-automation-sa"
        log "INFO" "[DRY RUN] Would assign roles: roles/backupdr.admin, roles/workflows.invoker"
        return 0
    fi

    # Check if service account already exists
    if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &> /dev/null; then
        log "WARN" "Service account already exists: $SA_EMAIL"
    else
        log "INFO" "Creating service account: backup-automation-sa"
        if ! gcloud iam service-accounts create backup-automation-sa \
            --display-name="Backup Automation Service Account" \
            --description="Service account for multi-region backup automation" \
            --project="$PROJECT_ID"; then
            error_exit "Failed to create service account"
        fi
    fi

    # Grant necessary permissions
    local roles=("roles/backupdr.admin" "roles/workflows.invoker")
    for role in "${roles[@]}"; do
        log "INFO" "Granting role $role to service account"
        if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SA_EMAIL" \
            --role="$role" &> /dev/null; then
            error_exit "Failed to grant role $role to service account"
        fi
    done

    log "INFO" "Service account created and configured successfully"
}

# Create multi-region backup vaults
create_backup_vaults() {
    log "INFO" "Creating multi-region backup vaults..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create backup vault: $BACKUP_VAULT_PRIMARY in $PRIMARY_REGION"
        log "INFO" "[DRY RUN] Would create backup vault: $BACKUP_VAULT_SECONDARY in $SECONDARY_REGION"
        return 0
    fi

    # Create primary backup vault
    log "INFO" "Creating primary backup vault in $PRIMARY_REGION"
    if ! gcloud backup-dr backup-vaults create "$BACKUP_VAULT_PRIMARY" \
        --location="$PRIMARY_REGION" \
        --backup-minimum-enforced-retention-duration=30d \
        --description="Primary backup vault for multi-region automation" \
        --project="$PROJECT_ID"; then
        error_exit "Failed to create primary backup vault"
    fi

    # Create secondary backup vault
    log "INFO" "Creating secondary backup vault in $SECONDARY_REGION"
    if ! gcloud backup-dr backup-vaults create "$BACKUP_VAULT_SECONDARY" \
        --location="$SECONDARY_REGION" \
        --backup-minimum-enforced-retention-duration=30d \
        --description="Secondary backup vault for disaster recovery" \
        --project="$PROJECT_ID"; then
        error_exit "Failed to create secondary backup vault"
    fi

    # Verify backup vaults are created
    log "INFO" "Verifying backup vault creation..."
    sleep 60 # Wait for vaults to be fully created

    local vault_count=0
    vault_count=$(gcloud backup-dr backup-vaults list \
        --filter="name:(${BACKUP_VAULT_PRIMARY} OR ${BACKUP_VAULT_SECONDARY})" \
        --format="value(name)" \
        --project="$PROJECT_ID" | wc -l)

    if [[ "$vault_count" -lt 2 ]]; then
        error_exit "Failed to verify backup vault creation"
    fi

    log "INFO" "Backup vaults created successfully"
}

# Create sample compute instance for testing
create_test_instance() {
    log "INFO" "Creating sample compute instance for backup testing..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create test instance: backup-test-instance"
        log "INFO" "[DRY RUN] Would create additional disk: backup-test-data-disk"
        return 0
    fi

    local zone="${PRIMARY_REGION}-a"
    local instance_name="backup-test-instance"
    local disk_name="backup-test-data-disk"

    # Check if instance already exists
    if gcloud compute instances describe "$instance_name" --zone="$zone" --project="$PROJECT_ID" &> /dev/null; then
        log "WARN" "Test instance already exists: $instance_name"
        return 0
    fi

    # Create compute instance
    log "INFO" "Creating test compute instance: $instance_name"
    if ! gcloud compute instances create "$instance_name" \
        --zone="$zone" \
        --machine-type=e2-medium \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-standard \
        --labels=backup-policy=critical,environment=production \
        --metadata=backup-schedule=daily \
        --project="$PROJECT_ID"; then
        error_exit "Failed to create test instance"
    fi

    # Create additional persistent disk
    log "INFO" "Creating additional persistent disk: $disk_name"
    if ! gcloud compute disks create "$disk_name" \
        --zone="$zone" \
        --size=10GB \
        --type=pd-standard \
        --project="$PROJECT_ID"; then
        error_exit "Failed to create test disk"
    fi

    # Attach disk to instance
    log "INFO" "Attaching disk to test instance"
    if ! gcloud compute instances attach-disk "$instance_name" \
        --zone="$zone" \
        --disk="$disk_name" \
        --project="$PROJECT_ID"; then
        error_exit "Failed to attach disk to instance"
    fi

    log "INFO" "Test instance and disk created successfully"
}

# Create workflow definition
create_workflow() {
    log "INFO" "Creating Cloud Workflow for backup orchestration..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create workflow: $WORKFLOW_NAME"
        return 0
    fi

    # Create workflow definition file
    local workflow_file="/tmp/backup-workflow-${RANDOM_SUFFIX}.yaml"
    cat > "$workflow_file" << EOF
main:
  params: [args]
  steps:
    - init:
        assign:
          - project_id: \${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
          - primary_region: "${PRIMARY_REGION}"
          - secondary_region: "${SECONDARY_REGION}"
          - backup_vault_primary: "${BACKUP_VAULT_PRIMARY}"
          - backup_vault_secondary: "${BACKUP_VAULT_SECONDARY}"
    
    - create_primary_backup:
        call: create_backup
        args:
          project_id: \${project_id}
          region: \${primary_region}
          backup_vault: \${backup_vault_primary}
          instance_name: "backup-test-instance"
        result: primary_backup_result
    
    - create_secondary_backup:
        call: create_cross_region_backup
        args:
          project_id: \${project_id}
          source_region: \${primary_region}
          target_region: \${secondary_region}
          backup_vault: \${backup_vault_secondary}
          source_backup: \${primary_backup_result.backup_id}
        result: secondary_backup_result
    
    - log_results:
        call: sys.log
        args:
          data: \${"Primary backup: " + primary_backup_result.backup_id + ", Secondary backup: " + secondary_backup_result.backup_id}
          severity: "INFO"
    
    - return_results:
        return:
          primary_backup: \${primary_backup_result}
          secondary_backup: \${secondary_backup_result}
          status: "SUCCESS"

create_backup:
  params: [project_id, region, backup_vault, instance_name]
  steps:
    - create_backup_plan:
        call: http.post
        args:
          url: \${"https://backupdr.googleapis.com/v1/projects/" + project_id + "/locations/" + region + "/backupPlans"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            backupPlanId: \${"plan-" + instance_name + "-" + string(int(sys.now()))}
            backupPlan:
              description: "Automated backup plan for instance"
              backupVault: \${"projects/" + project_id + "/locations/" + region + "/backupVaults/" + backup_vault}
              resourceType: "compute.googleapis.com/Instance"
        result: backup_plan_response
    
    - return_backup_info:
        return:
          backup_id: \${backup_plan_response.body.name}
          status: "CREATED"

create_cross_region_backup:
  params: [project_id, source_region, target_region, backup_vault, source_backup]
  steps:
    - copy_backup:
        call: http.post
        args:
          url: \${"https://backupdr.googleapis.com/v1/" + source_backup + ":copy"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            destinationBackupVault: \${"projects/" + project_id + "/locations/" + target_region + "/backupVaults/" + backup_vault}
        result: copy_response
    
    - return_copy_info:
        return:
          backup_id: \${copy_response.body.name}
          status: "COPIED"
EOF

    # Deploy the workflow
    log "INFO" "Deploying workflow: $WORKFLOW_NAME"
    if ! gcloud workflows deploy "$WORKFLOW_NAME" \
        --source="$workflow_file" \
        --location="$PRIMARY_REGION" \
        --service-account="$SA_EMAIL" \
        --project="$PROJECT_ID"; then
        error_exit "Failed to deploy workflow"
    fi

    # Clean up temporary file
    rm -f "$workflow_file"

    log "INFO" "Workflow deployed successfully"
}

# Create Cloud Scheduler jobs
create_scheduler_jobs() {
    log "INFO" "Creating Cloud Scheduler jobs for automated execution..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create scheduler job: $SCHEDULER_JOB"
        log "INFO" "[DRY RUN] Would create validation job: $SCHEDULER_JOB-validation"
        return 0
    fi

    local workflow_uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${PRIMARY_REGION}/workflows/${WORKFLOW_NAME}/executions"

    # Create daily backup scheduler job
    log "INFO" "Creating daily backup scheduler job"
    if ! gcloud scheduler jobs create http "$SCHEDULER_JOB" \
        --location="$PRIMARY_REGION" \
        --schedule="0 2 * * *" \
        --time-zone="America/New_York" \
        --uri="$workflow_uri" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --oauth-service-account-email="$SA_EMAIL" \
        --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
        --message-body='{"argument": "{\"backup_type\": \"scheduled\"}"}' \
        --project="$PROJECT_ID"; then
        error_exit "Failed to create scheduler job"
    fi

    # Create weekly validation scheduler job
    log "INFO" "Creating weekly validation scheduler job"
    if ! gcloud scheduler jobs create http "${SCHEDULER_JOB}-validation" \
        --location="$PRIMARY_REGION" \
        --schedule="0 3 * * 0" \
        --time-zone="America/New_York" \
        --uri="$workflow_uri" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --oauth-service-account-email="$SA_EMAIL" \
        --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
        --message-body='{"argument": "{\"backup_type\": \"validation\"}"}' \
        --project="$PROJECT_ID"; then
        error_exit "Failed to create validation scheduler job"
    fi

    log "INFO" "Scheduler jobs created successfully"
}

# Configure monitoring and alerting
configure_monitoring() {
    log "INFO" "Configuring Cloud Monitoring and alerting..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create alert policy for backup failures"
        log "INFO" "[DRY RUN] Would create monitoring dashboard"
        return 0
    fi

    # Create alert policy file
    local alert_policy_file="/tmp/backup-alert-policy-${RANDOM_SUFFIX}.yaml"
    cat > "$alert_policy_file" << EOF
displayName: "Backup Workflow Failures"
documentation:
  content: "Alert when backup workflows fail execution"
  mimeType: "text/markdown"
conditions:
  - displayName: "Workflow execution failure"
    conditionThreshold:
      filter: 'resource.type="workflows.googleapis.com/Workflow"'
      comparison: COMPARISON_GT
      thresholdValue: 0
      duration: "60s"
      aggregations:
        - alignmentPeriod: "300s"
          perSeriesAligner: ALIGN_RATE
          crossSeriesReducer: REDUCE_SUM
combiner: OR
enabled: true
notificationChannels: []
alertStrategy:
  autoClose: "604800s"
EOF

    # Create alert policy
    log "INFO" "Creating alert policy for backup failures"
    if ! gcloud alpha monitoring policies create \
        --policy-from-file="$alert_policy_file" \
        --project="$PROJECT_ID"; then
        log "WARN" "Failed to create alert policy (non-critical)"
    fi

    # Create dashboard configuration
    local dashboard_file="/tmp/backup-dashboard-${RANDOM_SUFFIX}.json"
    cat > "$dashboard_file" << EOF
{
  "displayName": "Multi-Region Backup Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Backup Workflow Executions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"workflows.googleapis.com/Workflow\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM"
                    }
                  }
                }
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Executions per second",
              "scale": "LINEAR"
            }
          }
        }
      }
    ]
  }
}
EOF

    # Create monitoring dashboard
    log "INFO" "Creating monitoring dashboard"
    if ! gcloud monitoring dashboards create \
        --config-from-file="$dashboard_file" \
        --project="$PROJECT_ID"; then
        log "WARN" "Failed to create monitoring dashboard (non-critical)"
    fi

    # Clean up temporary files
    rm -f "$alert_policy_file" "$dashboard_file"

    log "INFO" "Monitoring configuration completed"
}

# Test workflow execution
test_workflow() {
    log "INFO" "Testing workflow execution..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute workflow: $WORKFLOW_NAME"
        return 0
    fi

    # Execute workflow manually
    log "INFO" "Executing backup workflow manually"
    local execution_id
    execution_id=$(gcloud workflows run "$WORKFLOW_NAME" \
        --location="$PRIMARY_REGION" \
        --data='{"backup_type": "manual_test"}' \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -n "$execution_id" ]]; then
        log "INFO" "Workflow execution started: $execution_id"
        
        # Wait for execution to complete
        local max_wait=300 # 5 minutes
        local wait_time=0
        local status=""
        
        while [[ $wait_time -lt $max_wait ]]; do
            status=$(gcloud workflows executions describe "$execution_id" \
                --workflow="$WORKFLOW_NAME" \
                --location="$PRIMARY_REGION" \
                --format="value(state)" \
                --project="$PROJECT_ID" 2>/dev/null || echo "UNKNOWN")
            
            if [[ "$status" == "SUCCEEDED" ]]; then
                log "INFO" "Workflow execution completed successfully"
                break
            elif [[ "$status" == "FAILED" || "$status" == "CANCELLED" ]]; then
                log "WARN" "Workflow execution failed with status: $status"
                break
            fi
            
            sleep 10
            wait_time=$((wait_time + 10))
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            log "WARN" "Workflow execution timed out after $max_wait seconds"
        fi
    else
        log "WARN" "Failed to start workflow execution"
    fi
}

# Display deployment summary
display_summary() {
    log "INFO" "Deployment Summary"
    log "INFO" "=================="
    log "INFO" "Project ID: $PROJECT_ID"
    log "INFO" "Primary Region: $PRIMARY_REGION"
    log "INFO" "Secondary Region: $SECONDARY_REGION"
    log "INFO" "Backup Vaults: $BACKUP_VAULT_PRIMARY, $BACKUP_VAULT_SECONDARY"
    log "INFO" "Workflow Name: $WORKFLOW_NAME"
    log "INFO" "Scheduler Job: $SCHEDULER_JOB"
    log "INFO" "Service Account: $SA_EMAIL"
    log "INFO" "Log File: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" ""
        log "INFO" "Next Steps:"
        log "INFO" "1. Review the monitoring dashboard in Cloud Console"
        log "INFO" "2. Configure notification channels for alerts"
        log "INFO" "3. Test disaster recovery procedures"
        log "INFO" "4. Review backup policies and retention settings"
        log "INFO" ""
        log "INFO" "To clean up resources, run: ./destroy.sh --project-id $PROJECT_ID"
    fi
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    log "INFO" "This will deploy the following resources in project '$PROJECT_ID':"
    log "INFO" "- Service account with backup permissions"
    log "INFO" "- Backup vaults in $PRIMARY_REGION and $SECONDARY_REGION"
    log "INFO" "- Cloud Workflow for backup orchestration"
    log "INFO" "- Cloud Scheduler jobs for automation"
    log "INFO" "- Monitoring and alerting configuration"
    log "INFO" "- Test compute instance and disk"
    echo

    read -p "Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Deployment cancelled by user"
        exit 0
    fi
}

# Main execution function
main() {
    log "INFO" "Starting multi-region backup automation deployment"
    log "INFO" "Log file: $LOG_FILE"

    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY RUN mode - no changes will be made"
    fi

    check_prerequisites
    confirm_deployment

    # Set gcloud project
    gcloud config set project "$PROJECT_ID" &> /dev/null

    # Execute deployment steps
    enable_apis
    create_service_account
    create_backup_vaults
    create_test_instance
    create_workflow
    create_scheduler_jobs
    configure_monitoring
    
    if [[ "$DRY_RUN" == "false" ]]; then
        test_workflow
    fi

    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Deployment completed successfully!"
    else
        log "INFO" "Dry run completed successfully!"
    fi
}

# Handle script interruption
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"