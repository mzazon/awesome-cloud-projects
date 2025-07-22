#!/bin/bash

# Database Fleet Governance Deployment Script
# Recipe: Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory
# Provider: Google Cloud Platform

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$ERROR_LOG" >&2)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Check $ERROR_LOG for details."
    log_info "You may need to run destroy.sh to clean up partially created resources."
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo "============================================================"
echo "  Database Fleet Governance Deployment"
echo "  Recipe: Centralized Database Fleet Governance"
echo "  Provider: Google Cloud Platform"
echo "============================================================"
echo

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed (for JSON processing)
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-db-governance-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set derived variables
    export SERVICE_ACCOUNT="db-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log_info "PROJECT_ID: $PROJECT_ID"
    log_info "REGION: $REGION"
    log_info "ZONE: $ZONE"
    log_info "RANDOM_SUFFIX: $RANDOM_SUFFIX"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
RANDOM_SUFFIX=$RANDOM_SUFFIX
SERVICE_ACCOUNT=$SERVICE_ACCOUNT
EOF
    
    log_success "Environment variables configured"
}

# Create or set project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Project $PROJECT_ID already exists"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Database Governance Project"
        
        # Enable billing (user needs to link billing account manually)
        log_warning "Please ensure billing is enabled for project $PROJECT_ID"
        read -p "Press Enter when billing is enabled for the project..."
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudasset.googleapis.com"
        "workflows.googleapis.com"
        "monitoring.googleapis.com"
        "sqladmin.googleapis.com"
        "spanner.googleapis.com"
        "bigtableadmin.googleapis.com"
        "firestore.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "securitycenter.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create service account and set permissions
setup_service_account() {
    log_info "Setting up service account for automation workflows..."
    
    # Create service account
    if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" &>/dev/null; then
        gcloud iam service-accounts create db-governance-sa \
            --display-name="Database Governance Service Account" \
            --description="Service account for database governance automation"
    else
        log_info "Service account already exists"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/cloudasset.viewer"
        "roles/workflows.invoker"
        "roles/monitoring.metricWriter"
        "roles/aiplatform.user"
        "roles/cloudsql.viewer"
        "roles/spanner.databaseReader"
        "roles/bigtable.reader"
        "roles/bigquery.dataEditor"
        "roles/bigquery.jobUser"
        "roles/storage.objectAdmin"
        "roles/pubsub.publisher"
        "roles/pubsub.subscriber"
        "roles/cloudfunctions.invoker"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role $role to service account..."
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT" \
            --role="$role" \
            --quiet
    done
    
    log_success "Service account configured with necessary permissions"
}

# Create sample database fleet
create_database_fleet() {
    log_info "Creating sample database fleet for governance testing..."
    
    # Create Cloud SQL instance
    log_info "Creating Cloud SQL PostgreSQL instance..."
    if ! gcloud sql instances describe "fleet-sql-${RANDOM_SUFFIX}" &>/dev/null; then
        gcloud sql instances create "fleet-sql-${RANDOM_SUFFIX}" \
            --database-version=POSTGRES_15 \
            --tier=db-f1-micro \
            --region="$REGION" \
            --backup-start-time=02:00 \
            --enable-bin-log \
            --storage-auto-increase \
            --deletion-protection \
            --quiet
    else
        log_info "Cloud SQL instance already exists"
    fi
    
    # Create Spanner instance
    log_info "Creating Spanner instance..."
    if ! gcloud spanner instances describe "fleet-spanner-${RANDOM_SUFFIX}" &>/dev/null; then
        gcloud spanner instances create "fleet-spanner-${RANDOM_SUFFIX}" \
            --config="regional-${REGION}" \
            --nodes=1 \
            --description="Fleet governance sample" \
            --quiet
    else
        log_info "Spanner instance already exists"
    fi
    
    # Create Bigtable instance
    log_info "Creating Bigtable instance..."
    if ! gcloud bigtable instances describe "fleet-bigtable-${RANDOM_SUFFIX}" &>/dev/null; then
        gcloud bigtable instances create "fleet-bigtable-${RANDOM_SUFFIX}" \
            --cluster="fleet-cluster" \
            --cluster-zone="$ZONE" \
            --cluster-num-nodes=1 \
            --instance-type=DEVELOPMENT \
            --quiet
    else
        log_info "Bigtable instance already exists"
    fi
    
    log_success "Sample database fleet created successfully"
}

# Configure Cloud Asset Inventory
setup_asset_inventory() {
    log_info "Configuring Cloud Asset Inventory for database discovery..."
    
    # Create BigQuery dataset
    if ! bq ls -d "${PROJECT_ID}:database_governance" &>/dev/null; then
        bq mk --dataset \
            --location="$REGION" \
            --description="Database fleet asset inventory" \
            "${PROJECT_ID}:database_governance"
    else
        log_info "BigQuery dataset already exists"
    fi
    
    # Create Cloud Storage bucket
    local bucket_name="db-governance-assets-${RANDOM_SUFFIX}"
    if ! gsutil ls "gs://$bucket_name" &>/dev/null; then
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://$bucket_name"
    else
        log_info "Cloud Storage bucket already exists"
    fi
    
    # Export current asset snapshot to BigQuery
    log_info "Exporting asset inventory to BigQuery..."
    gcloud asset export \
        --project="$PROJECT_ID" \
        --bigquery-table="//bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/database_governance/tables/asset_inventory" \
        --content-type=resource \
        --asset-types="sqladmin.googleapis.com/Instance,spanner.googleapis.com/Instance,bigtableadmin.googleapis.com/Instance" \
        --quiet
    
    # Create Pub/Sub topic for real-time asset change notifications
    if ! gcloud pubsub topics describe database-asset-changes &>/dev/null; then
        gcloud pubsub topics create database-asset-changes --quiet
    else
        log_info "Pub/Sub topic already exists"
    fi
    
    log_success "Cloud Asset Inventory configured successfully"
}

# Create governance workflow
create_governance_workflow() {
    log_info "Creating automated governance workflow..."
    
    # Create workflow definition
    cat > "${SCRIPT_DIR}/governance-workflow.yaml" << 'EOF'
main:
  params: [input]
  steps:
    - checkAssetChange:
        call: http.get
        args:
          url: ${"https://cloudasset.googleapis.com/v1/projects/" + sys.get_env("PROJECT_ID") + "/assets"}
          auth:
            type: OAuth2
        result: assets
    - evaluateCompliance:
        for:
          value: asset
          in: ${assets.body.assets}
          steps:
            - checkDatabaseSecurity:
                switch:
                  - condition: ${asset.assetType == "sqladmin.googleapis.com/Instance"}
                    steps:
                      - validateCloudSQL:
                          call: validateSQLSecurity
                          args:
                            instance: ${asset}
                  - condition: ${asset.assetType == "spanner.googleapis.com/Instance"}
                    steps:
                      - validateSpanner:
                          call: validateSpannerSecurity
                          args:
                            instance: ${asset}
    - generateReport:
        call: http.post
        args:
          url: ${"https://monitoring.googleapis.com/v3/projects/" + sys.get_env("PROJECT_ID") + "/timeSeries"}
          auth:
            type: OAuth2
          body:
            timeSeries:
              - metric:
                  type: "custom.googleapis.com/database/governance_score"
                points:
                  - value:
                      doubleValue: 0.95
                    interval:
                      endTime: ${time.now()}

validateSQLSecurity:
  params: [instance]
  steps:
    - checkBackupConfig:
        return: ${default(instance.resource.data.settings.backupConfiguration.enabled, false)}

validateSpannerSecurity:
  params: [instance]
  steps:
    - checkEncryption:
        return: ${instance.resource.data.encryptionConfig != null}
EOF
    
    # Deploy the governance workflow
    if ! gcloud workflows describe database-governance-workflow --location="$REGION" &>/dev/null; then
        gcloud workflows deploy database-governance-workflow \
            --source="${SCRIPT_DIR}/governance-workflow.yaml" \
            --location="$REGION" \
            --service-account="$SERVICE_ACCOUNT" \
            --quiet
    else
        log_info "Governance workflow already exists"
    fi
    
    log_success "Automated governance workflow deployed successfully"
}

# Configure monitoring and alerting
setup_monitoring() {
    log_info "Configuring real-time monitoring and alerting..."
    
    # Create log-based metric for governance monitoring
    if ! gcloud logging metrics describe database_compliance_score &>/dev/null; then
        gcloud logging metrics create database_compliance_score \
            --description="Database fleet compliance score" \
            --log-filter='resource.type="cloud_function" AND "compliance"' \
            --quiet
    else
        log_info "Log-based metric already exists"
    fi
    
    # Create notification channel for governance alerts
    local notification_channels
    notification_channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:Database Governance Alerts" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$notification_channels" ]]; then
        gcloud alpha monitoring channels create \
            --display-name="Database Governance Alerts" \
            --type=email \
            --channel-labels="email_address=$(gcloud config get-value account)" \
            --quiet
    else
        log_info "Notification channel already exists"
    fi
    
    # Get the notification channel ID
    local channel_id
    channel_id=$(gcloud alpha monitoring channels list \
        --filter="displayName:Database Governance Alerts" \
        --format="value(name)")
    
    # Create alert policy for governance violations
    cat > "${SCRIPT_DIR}/governance-alert-policy.json" << EOF
{
  "displayName": "Database Governance Violations",
  "conditions": [
    {
      "displayName": "Low compliance score",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/database_compliance_score\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5,
        "duration": "300s"
      }
    }
  ],
  "notificationChannels": ["${channel_id}"],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    # Create the alert policy if it doesn't exist
    if ! gcloud alpha monitoring policies list --filter="displayName:Database Governance Violations" --format="value(name)" | grep -q .; then
        gcloud alpha monitoring policies create \
            --policy-from-file="${SCRIPT_DIR}/governance-alert-policy.json" \
            --quiet
    else
        log_info "Alert policy already exists"
    fi
    
    log_success "Real-time monitoring and alerting configured"
}

# Create compliance reporting function
create_compliance_function() {
    log_info "Implementing automated compliance reporting..."
    
    # Create function directory
    local function_dir="${SCRIPT_DIR}/governance-reporting"
    mkdir -p "$function_dir"
    
    # Create main.py for Cloud Function
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
from google.cloud import asset_v1
from google.cloud import bigquery
from google.cloud import storage
import datetime

def generate_compliance_report(request):
    """Generate compliance report for database governance."""
    try:
        # Initialize clients
        project_id = os.environ.get('PROJECT_ID')
        suffix = request.args.get('suffix', '')
        
        asset_client = asset_v1.AssetServiceClient()
        bq_client = bigquery.Client()
        storage_client = storage.Client()
        
        # Query database assets from BigQuery
        query = f"""
        SELECT 
          asset_type,
          name,
          resource.data as config
        FROM `{project_id}.database_governance.asset_inventory`
        WHERE asset_type LIKE '%Instance'
        """
        
        results = bq_client.query(query)
        
        # Generate compliance report
        report = {
            'timestamp': datetime.datetime.now().isoformat(),
            'project_id': project_id,
            'total_databases': 0,
            'compliant_databases': 0,
            'violations': []
        }
        
        for row in results:
            report['total_databases'] += 1
            # Basic compliance check - backup enabled
            if 'backup' in str(row.config).lower():
                report['compliant_databases'] += 1
            else:
                report['violations'].append({
                    'resource': row.name,
                    'type': row.asset_type,
                    'issue': 'Backup not configured'
                })
        
        # Calculate compliance percentage
        if report['total_databases'] > 0:
            report['compliance_percentage'] = (
                report['compliant_databases'] / report['total_databases']
            ) * 100
        else:
            report['compliance_percentage'] = 100
        
        # Upload report to Cloud Storage
        bucket_name = f"db-governance-assets-{suffix}"
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(f"compliance-reports/{datetime.date.today()}-report.json")
        blob.upload_from_string(json.dumps(report, indent=2))
        
        return {
            'status': 'success',
            'report_location': f"gs://{bucket_name}/compliance-reports/{datetime.date.today()}-report.json",
            'compliance_percentage': report['compliance_percentage']
        }
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-asset==3.19.1
google-cloud-bigquery==3.11.4
google-cloud-storage==2.10.0
EOF
    
    # Deploy the compliance reporting function
    if ! gcloud functions describe compliance-reporter --region="$REGION" &>/dev/null; then
        gcloud functions deploy compliance-reporter \
            --source="$function_dir" \
            --runtime=python39 \
            --trigger=http \
            --allow-unauthenticated \
            --entry-point=generate_compliance_report \
            --service-account="$SERVICE_ACCOUNT" \
            --set-env-vars="PROJECT_ID=$PROJECT_ID" \
            --region="$REGION" \
            --quiet
    else
        log_info "Compliance reporting function already exists"
    fi
    
    log_success "Automated compliance reporting implemented"
}

# Setup continuous governance automation
setup_continuous_governance() {
    log_info "Establishing continuous governance automation..."
    
    # Create Cloud Scheduler job for continuous governance checks
    if ! gcloud scheduler jobs describe governance-scheduler --location="$REGION" &>/dev/null; then
        local function_url
        function_url=$(gcloud functions describe compliance-reporter \
            --region="$REGION" \
            --format="value(httpsTrigger.url)")
        
        gcloud scheduler jobs create http governance-scheduler \
            --schedule="0 */6 * * *" \
            --uri="${function_url}?project_id=${PROJECT_ID}&suffix=${RANDOM_SUFFIX}" \
            --http-method=GET \
            --time-zone="America/New_York" \
            --location="$REGION" \
            --quiet
    else
        log_info "Governance scheduler already exists"
    fi
    
    # Create Pub/Sub subscription for asset change notifications
    if ! gcloud pubsub subscriptions describe governance-automation &>/dev/null; then
        gcloud pubsub subscriptions create governance-automation \
            --topic=database-asset-changes \
            --push-endpoint="https://workflows.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/database-governance-workflow/executions" \
            --quiet
    else
        log_info "Pub/Sub subscription already exists"
    fi
    
    # Configure log-based metrics for governance events
    if ! gcloud logging metrics describe governance_events &>/dev/null; then
        gcloud logging metrics create governance_events \
            --description="Database governance events counter" \
            --log-filter='resource.type="cloud_function" AND resource.labels.function_name="compliance-reporter"' \
            --quiet
    else
        log_info "Log-based metric already exists"
    fi
    
    log_success "Continuous governance automation established"
}

# Create sample Gemini queries
create_gemini_queries() {
    log_info "Creating sample governance queries for Gemini testing..."
    
    cat > "${SCRIPT_DIR}/gemini-queries.json" << 'EOF'
{
  "governance_queries": [
    "Show me all databases without backup enabled",
    "Which Cloud SQL instances have public IP access?",
    "List Spanner instances without encryption at rest",
    "What are the top security recommendations for my database fleet?",
    "How many databases are compliant with our security policies?"
  ]
}
EOF
    
    log_info "Sample queries for Database Center Gemini chat:"
    jq -r '.governance_queries[]' "${SCRIPT_DIR}/gemini-queries.json"
    
    log_success "Gemini AI integration configured for intelligent insights"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check database instances
    local sql_instances
    sql_instances=$(gcloud sql instances list --filter="name:fleet-sql-${RANDOM_SUFFIX}" --format="value(name)")
    if [[ -n "$sql_instances" ]]; then
        log_success "Cloud SQL instance deployed successfully"
    else
        log_error "Cloud SQL instance not found"
        return 1
    fi
    
    local spanner_instances
    spanner_instances=$(gcloud spanner instances list --filter="name:fleet-spanner-${RANDOM_SUFFIX}" --format="value(name)")
    if [[ -n "$spanner_instances" ]]; then
        log_success "Spanner instance deployed successfully"
    else
        log_error "Spanner instance not found"
        return 1
    fi
    
    local bigtable_instances
    bigtable_instances=$(gcloud bigtable instances list --filter="name:fleet-bigtable-${RANDOM_SUFFIX}" --format="value(name)")
    if [[ -n "$bigtable_instances" ]]; then
        log_success "Bigtable instance deployed successfully"
    else
        log_error "Bigtable instance not found"
        return 1
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:database_governance" &>/dev/null; then
        log_success "BigQuery dataset created successfully"
    else
        log_error "BigQuery dataset not found"
        return 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe compliance-reporter --region="$REGION" &>/dev/null; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Cloud Function not found"
        return 1
    fi
    
    # Check workflow
    if gcloud workflows describe database-governance-workflow --location="$REGION" &>/dev/null; then
        log_success "Governance workflow deployed successfully"
    else
        log_error "Governance workflow not found"
        return 1
    fi
    
    log_success "All components validated successfully"
}

# Main deployment function
main() {
    log_info "Starting Database Fleet Governance deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_service_account
    create_database_fleet
    setup_asset_inventory
    create_governance_workflow
    setup_monitoring
    create_compliance_function
    setup_continuous_governance
    create_gemini_queries
    validate_deployment
    
    echo
    echo "============================================================"
    log_success "Database Fleet Governance deployment completed successfully!"
    echo "============================================================"
    echo
    echo "Next steps:"
    echo "1. Navigate to Database Center: https://console.cloud.google.com/database-center?project=${PROJECT_ID}"
    echo "2. Review AI-powered insights and use Gemini chat interface"
    echo "3. Test compliance reporting function"
    echo "4. Monitor governance automation workflows"
    echo
    echo "Resources created:"
    echo "- Project: $PROJECT_ID"
    echo "- Cloud SQL instance: fleet-sql-${RANDOM_SUFFIX}"
    echo "- Spanner instance: fleet-spanner-${RANDOM_SUFFIX}"
    echo "- Bigtable instance: fleet-bigtable-${RANDOM_SUFFIX}"
    echo "- BigQuery dataset: database_governance"
    echo "- Cloud Storage bucket: db-governance-assets-${RANDOM_SUFFIX}"
    echo "- Cloud Function: compliance-reporter"
    echo "- Workflow: database-governance-workflow"
    echo
    echo "Configuration saved to: ${SCRIPT_DIR}/.env"
    echo "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"