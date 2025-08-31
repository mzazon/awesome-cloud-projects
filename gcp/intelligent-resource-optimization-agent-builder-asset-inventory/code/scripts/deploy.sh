#!/bin/bash

# =============================================================================
# Intelligent Resource Optimization with Agent Builder and Asset Inventory
# Deployment Script for GCP
# =============================================================================

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
}

# Configuration variables with defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${PROJECT_ID:-resource-optimization-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Resource naming with random suffix for uniqueness
RANDOM_SUFFIX=$(openssl rand -hex 3)
DATASET_NAME="asset_optimization_${RANDOM_SUFFIX}"
BUCKET_NAME="resource-optimizer-${RANDOM_SUFFIX}"
JOB_NAME="asset-export-${RANDOM_SUFFIX}"
FUNCTION_NAME="asset-export-trigger-${RANDOM_SUFFIX}"
SERVICE_ACCOUNT_NAME="asset-export-scheduler"

# Required APIs
REQUIRED_APIS=(
    "cloudasset.googleapis.com"
    "bigquery.googleapis.com"
    "aiplatform.googleapis.com"
    "cloudscheduler.googleapis.com"
    "storage.googleapis.com"
    "cloudfunctions.googleapis.com"
)

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Intelligent Resource Optimization with Agent Builder and Asset Inventory

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (default: resource-optimization-\$(date +%s))
    -r, --region REGION           GCP Region (default: us-central1)
    -z, --zone ZONE              GCP Zone (default: us-central1-a)
    -d, --dry-run                Show what would be deployed without executing
    -y, --yes                    Skip confirmation prompts
    -h, --help                   Display this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                   GCP Project ID
    REGION                      GCP Region
    ZONE                        GCP Zone
    SKIP_CONFIRMATION           Skip confirmation prompts (true/false)
    DRY_RUN                     Dry run mode (true/false)

EXAMPLES:
    $0                          # Deploy with default settings
    $0 -p my-project -r us-west1 # Deploy to specific project and region
    $0 -d                       # Dry run to see what would be deployed
    $0 -y                       # Skip confirmation prompts

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
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK with Cloud Storage components."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if organization exists (required for asset inventory)
    if ! gcloud organizations list --format="value(name)" | grep -q .; then
        warning "No organization found. Asset inventory requires organization-level permissions."
        warning "This deployment may fail if you don't have organization-level access."
    fi
    
    success "Prerequisites check completed"
}

# Validate project and set configuration
validate_project() {
    log "Validating project configuration..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set default project
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    # Check billing account
    if ! gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" | grep -q .; then
        error "Project '$PROJECT_ID' does not have billing enabled."
        exit 1
    fi
    
    success "Project validation completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would enable API: $api"
        else
            log "Enabling API: $api"
            gcloud services enable "$api" --quiet
        fi
    done
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "API enablement completed"
}

# Create BigQuery dataset and storage bucket
create_data_infrastructure() {
    log "Creating data infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create BigQuery dataset: $DATASET_NAME"
        log "[DRY RUN] Would create storage bucket: gs://$BUCKET_NAME"
        return
    fi
    
    # Create BigQuery dataset
    log "Creating BigQuery dataset: $DATASET_NAME"
    bq mk --location="$REGION" \
        --description="Asset inventory for cost optimization" \
        "${PROJECT_ID}:${DATASET_NAME}" || {
        error "Failed to create BigQuery dataset"
        exit 1
    }
    
    # Create storage bucket
    log "Creating storage bucket: gs://$BUCKET_NAME"
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME" || {
        error "Failed to create storage bucket"
        exit 1
    }
    
    success "Data infrastructure created"
}

# Export asset inventory to BigQuery
export_asset_inventory() {
    log "Exporting asset inventory to BigQuery..."
    
    # Get organization ID
    local org_id
    org_id=$(gcloud organizations list --format="value(name)" | head -n1 | cut -d'/' -f2)
    
    if [[ -z "$org_id" ]]; then
        error "No organization found. Asset inventory export requires organization-level permissions."
        exit 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would export asset inventory for organization: $org_id"
        return
    fi
    
    log "Exporting asset inventory for organization: $org_id"
    gcloud asset export \
        --organization="$org_id" \
        --content-type=resource \
        --bigquery-table="projects/${PROJECT_ID}/datasets/${DATASET_NAME}/tables/asset_inventory" \
        --output-bigquery-force \
        --asset-types="compute.googleapis.com/Instance,compute.googleapis.com/Disk,storage.googleapis.com/Bucket,container.googleapis.com/Cluster,sqladmin.googleapis.com/Instance" || {
        error "Failed to export asset inventory"
        exit 1
    }
    
    log "Waiting for asset export to complete..."
    sleep 60
    
    success "Asset inventory export completed"
}

# Create service account and IAM roles
create_service_account() {
    log "Creating service account and configuring IAM..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create service account: $SERVICE_ACCOUNT_NAME"
        log "[DRY RUN] Would assign IAM roles"
        return
    fi
    
    # Create service account
    log "Creating service account: $SERVICE_ACCOUNT_NAME"
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Asset Export Scheduler" \
        --description="Service account for automated asset exports" || {
        warning "Service account may already exist"
    }
    
    # Grant necessary permissions
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log "Granting Cloud Asset Viewer role"
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$sa_email" \
        --role="roles/cloudasset.viewer" --quiet
    
    log "Granting BigQuery Data Editor role"
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$sa_email" \
        --role="roles/bigquery.dataEditor" --quiet
    
    log "Granting Cloud Functions Invoker role"
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$sa_email" \
        --role="roles/cloudfunctions.invoker" --quiet
    
    success "Service account and IAM configuration completed"
}

# Deploy Cloud Function for asset export
deploy_cloud_function() {
    log "Deploying Cloud Function for asset export..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy Cloud Function: $FUNCTION_NAME"
        return
    fi
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create function code
    cat > "$temp_dir/main.py" << 'EOF'
import functions_framework
from google.cloud import asset_v1
import json
import os

@functions_framework.http
def trigger_asset_export(request):
    """HTTP Cloud Function to trigger asset export."""
    try:
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return {'error': 'Invalid request format'}, 400
        
        organization_id = request_json.get('organization_id')
        project_id = request_json.get('project_id')
        dataset_name = request_json.get('dataset_name')
        
        if not all([organization_id, project_id, dataset_name]):
            return {'error': 'Missing required parameters'}, 400
        
        client = asset_v1.AssetServiceClient()
        parent = f"organizations/{organization_id}"
        
        output_config = asset_v1.OutputConfig()
        output_config.bigquery_destination.dataset = f"projects/{project_id}/datasets/{dataset_name}"
        output_config.bigquery_destination.table = "asset_inventory"
        output_config.bigquery_destination.force = True
        
        operation = client.export_assets(
            request={
                "parent": parent,
                "output_config": output_config,
                "content_type": asset_v1.ContentType.RESOURCE,
                "asset_types": [
                    "compute.googleapis.com/Instance",
                    "compute.googleapis.com/Disk", 
                    "storage.googleapis.com/Bucket",
                    "container.googleapis.com/Cluster",
                    "sqladmin.googleapis.com/Instance"
                ]
            }
        )
        
        return {
            'status': 'success',
            'operation': operation.name,
            'message': f'Export operation started for organization {organization_id}'
        }
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Create requirements.txt
    cat > "$temp_dir/requirements.txt" << 'EOF'
google-cloud-asset==3.24.0
functions-framework==3.5.0
EOF
    
    # Deploy function
    log "Deploying Cloud Function to trigger asset exports"
    gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=python311 \
        --region="$REGION" \
        --source="$temp_dir" \
        --entry-point=trigger_asset_export \
        --trigger=http \
        --allow-unauthenticated \
        --memory=256MB \
        --timeout=540s || {
        error "Failed to deploy Cloud Function"
        rm -rf "$temp_dir"
        exit 1
    }
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    success "Cloud Function deployment completed"
}

# Create optimization analysis views
create_analysis_views() {
    log "Creating optimization analysis views..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create BigQuery views for optimization analysis"
        return
    fi
    
    # Create resource optimization analysis view
    log "Creating resource optimization analysis view"
    bq query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.resource_optimization_analysis\` AS
    SELECT 
      name,
      asset_type,
      JSON_EXTRACT_SCALAR(resource.data, '$.location') as location,
      JSON_EXTRACT_SCALAR(resource.data, '$.project') as project,
      DATE_DIFF(CURRENT_DATE(), DATE(update_time), DAY) as age_days,
      JSON_EXTRACT_SCALAR(resource.data, '$.status') as status,
      JSON_EXTRACT_SCALAR(resource.data, '$.machineType') as machine_type,
      CASE 
        WHEN asset_type LIKE '%Instance%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'TERMINATED' THEN 'Idle Compute'
        WHEN asset_type LIKE '%Disk%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'READY' AND JSON_EXTRACT_SCALAR(resource.data, '$.users') IS NULL THEN 'Unattached Storage'
        WHEN asset_type LIKE '%Bucket%' THEN 'Storage Analysis Needed'
        ELSE 'Active Resource'
      END as optimization_category,
      CASE
        WHEN DATE_DIFF(CURRENT_DATE(), DATE(update_time), DAY) > 30 AND JSON_EXTRACT_SCALAR(resource.data, '$.status') != 'RUNNING' THEN 90
        WHEN DATE_DIFF(CURRENT_DATE(), DATE(update_time), DAY) > 7 AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'TERMINATED' THEN 70
        WHEN JSON_EXTRACT_SCALAR(resource.data, '$.machineType') LIKE '%n1-%' THEN 60
        ELSE 20
      END as optimization_score
    FROM \`${PROJECT_ID}.${DATASET_NAME}.asset_inventory\`
    WHERE update_time IS NOT NULL" || {
        error "Failed to create resource optimization analysis view"
        exit 1
    }
    
    # Create cost impact summary view
    log "Creating cost impact summary view"
    bq query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.cost_impact_summary\` AS
    SELECT 
      optimization_category,
      COUNT(*) as resource_count,
      AVG(optimization_score) as avg_optimization_score,
      COUNT(*) * AVG(optimization_score) as total_impact_score
    FROM \`${PROJECT_ID}.${DATASET_NAME}.resource_optimization_analysis\`
    GROUP BY optimization_category
    ORDER BY total_impact_score DESC" || {
        error "Failed to create cost impact summary view"
        exit 1
    }
    
    success "Optimization analysis views created"
}

# Create Cloud Scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Cloud Scheduler job: $JOB_NAME"
        return
    fi
    
    # Get organization ID and function URL
    local org_id
    org_id=$(gcloud organizations list --format="value(name)" | head -n1 | cut -d'/' -f2)
    
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --format="value(serviceConfig.uri)")
    
    # Create scheduler job
    log "Creating daily asset export schedule"
    gcloud scheduler jobs create http "$JOB_NAME" \
        --location="$REGION" \
        --schedule="0 2 * * *" \
        --time-zone="America/New_York" \
        --uri="$function_url" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body="{\"organization_id\":\"$org_id\",\"project_id\":\"$PROJECT_ID\",\"dataset_name\":\"$DATASET_NAME\"}" || {
        error "Failed to create Cloud Scheduler job"
        exit 1
    }
    
    success "Cloud Scheduler job created"
}

# Deploy Vertex AI Agent
deploy_vertex_ai_agent() {
    log "Deploying Vertex AI Agent..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy Vertex AI Agent with BigQuery integration"
        return
    fi
    
    # Create temporary directory for agent code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create agent implementation
    cat > "$temp_dir/optimization_agent.py" << EOF
import vertexai
from vertexai import agent_engines
from google.cloud import bigquery
import json

def query_optimization_data(query_type: str = "summary"):
    """Query asset optimization data from BigQuery."""
    client = bigquery.Client()
    
    if query_type == "summary":
        query = f"""
        SELECT optimization_category, resource_count, avg_optimization_score
        FROM \`${PROJECT_ID}.${DATASET_NAME}.cost_impact_summary\`
        ORDER BY total_impact_score DESC
        LIMIT 10
        """
    elif query_type == "high_priority":
        query = f"""
        SELECT name, asset_type, optimization_category, optimization_score
        FROM \`${PROJECT_ID}.${DATASET_NAME}.resource_optimization_analysis\`
        WHERE optimization_score > 70
        ORDER BY optimization_score DESC
        LIMIT 20
        """
    else:
        query = f"""
        SELECT COUNT(*) as total_resources,
               COUNT(CASE WHEN optimization_score > 70 THEN 1 END) as high_priority,
               AVG(optimization_score) as avg_score
        FROM \`${PROJECT_ID}.${DATASET_NAME}.resource_optimization_analysis\`
        """
    
    try:
        results = client.query(query).to_dataframe()
        return results.to_json(orient='records')
    except Exception as e:
        return f"Error querying data: {str(e)}"

# Initialize Vertex AI
vertexai.init(
    project="${PROJECT_ID}",
    location="${REGION}",
    staging_bucket="gs://${BUCKET_NAME}"
)

# Create agent with BigQuery tools
agent = agent_engines.LangchainAgent(
    model="gemini-1.5-pro",
    tools=[query_optimization_data],
    model_kwargs={
        "temperature": 0.2,
        "max_output_tokens": 2000,
        "top_p": 0.95,
    },
)
EOF
    
    # Create requirements file
    cat > "$temp_dir/requirements.txt" << 'EOF'
google-cloud-aiplatform[agent_engines,langchain]
google-cloud-bigquery
pandas
EOF
    
    # Deploy the agent using Python
    cat > "$temp_dir/deploy_agent.py" << EOF
import sys
import vertexai
from vertexai import agent_engines
sys.path.append('.')
from optimization_agent import agent

try:
    remote_agent = agent_engines.create(
        agent,
        requirements=['google-cloud-aiplatform[agent_engines,langchain]', 'google-cloud-bigquery', 'pandas'],
        display_name='resource-optimization-agent'
    )
    print(f'Agent deployed with ID: {remote_agent.resource_name}')
    
    # Save agent resource name
    with open('/tmp/agent_resource_name.txt', 'w') as f:
        f.write(remote_agent.resource_name)
        
except Exception as e:
    print(f'Error deploying agent: {str(e)}')
    sys.exit(1)
EOF
    
    # Execute agent deployment
    cd "$temp_dir"
    python3 deploy_agent.py || {
        error "Failed to deploy Vertex AI Agent"
        rm -rf "$temp_dir"
        exit 1
    }
    cd - > /dev/null
    
    # Copy agent resource name to project directory
    if [[ -f /tmp/agent_resource_name.txt ]]; then
        cp /tmp/agent_resource_name.txt "${SCRIPT_DIR}/../agent_resource_name.txt"
        rm /tmp/agent_resource_name.txt
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    success "Vertex AI Agent deployment completed"
}

# Create optimization metrics table
create_metrics_table() {
    log "Creating optimization metrics table..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create optimization metrics table"
        return
    fi
    
    log "Creating optimization metrics tracking table"
    bq query --use_legacy_sql=false \
    "CREATE OR REPLACE TABLE \`${PROJECT_ID}.${DATASET_NAME}.optimization_metrics\` AS
    SELECT 
      CURRENT_TIMESTAMP() as analysis_time,
      COUNT(*) as total_resources,
      COUNT(CASE WHEN optimization_score > 70 THEN 1 END) as high_priority_optimizations,
      COUNT(CASE WHEN optimization_score BETWEEN 40 AND 70 THEN 1 END) as medium_priority_optimizations,
      AVG(optimization_score) as avg_optimization_score,
      SUM(CASE WHEN optimization_category = 'Idle Compute' THEN 1 ELSE 0 END) as idle_compute_count,
      SUM(CASE WHEN optimization_category = 'Unattached Storage' THEN 1 ELSE 0 END) as unattached_storage_count
    FROM \`${PROJECT_ID}.${DATASET_NAME}.resource_optimization_analysis\`" || {
        error "Failed to create optimization metrics table"
        exit 1
    }
    
    success "Optimization metrics table created"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Created Resources:"
    echo "- BigQuery Dataset: $DATASET_NAME"
    echo "- Storage Bucket: gs://$BUCKET_NAME"
    echo "- Cloud Function: $FUNCTION_NAME"
    echo "- Cloud Scheduler Job: $JOB_NAME"
    echo "- Service Account: $SERVICE_ACCOUNT_NAME"
    echo "- Vertex AI Agent: resource-optimization-agent"
    echo ""
    echo "Next Steps:"
    echo "1. Verify asset inventory data in BigQuery"
    echo "2. Test optimization queries and agent responses"
    echo "3. Review scheduled export job configuration"
    echo "4. Set up monitoring and alerting as needed"
    echo ""
    echo "Access URLs:"
    echo "- BigQuery Console: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    echo "- Cloud Storage: https://console.cloud.google.com/storage/browser/$BUCKET_NAME?project=$PROJECT_ID"
    echo "- Vertex AI Agents: https://console.cloud.google.com/vertex-ai/agents?project=$PROJECT_ID"
    echo ""
}

# Save deployment configuration
save_config() {
    local config_file="${SCRIPT_DIR}/../deployment_config.txt"
    
    cat > "$config_file" << EOF
# Deployment Configuration
# Generated on $(date)

PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
DATASET_NAME=$DATASET_NAME
BUCKET_NAME=$BUCKET_NAME
JOB_NAME=$JOB_NAME
FUNCTION_NAME=$FUNCTION_NAME
SERVICE_ACCOUNT_NAME=$SERVICE_ACCOUNT_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX

# For cleanup script
export PROJECT_ID REGION ZONE DATASET_NAME BUCKET_NAME JOB_NAME FUNCTION_NAME SERVICE_ACCOUNT_NAME
EOF
    
    log "Deployment configuration saved to: $config_file"
}

# Main deployment function
main() {
    echo "=============================================="
    echo "Intelligent Resource Optimization Deployment"
    echo "=============================================="
    echo ""
    
    parse_args "$@"
    
    # Display configuration
    log "Deployment Configuration:"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Confirmation prompt
    if [[ "$SKIP_CONFIRMATION" == "false" && "$DRY_RUN" == "false" ]]; then
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_project
    enable_apis
    create_data_infrastructure
    export_asset_inventory
    create_service_account
    deploy_cloud_function
    create_analysis_views
    create_scheduler_job
    deploy_vertex_ai_agent
    create_metrics_table
    
    if [[ "$DRY_RUN" == "false" ]]; then
        save_config
        display_summary
        success "Deployment completed successfully!"
    else
        log "Dry run completed. No resources were created."
    fi
}

# Cleanup on script exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Some resources may have been created."
        error "Run the destroy.sh script to clean up any partial deployment."
    fi
}

trap cleanup EXIT

# Execute main function
main "$@"