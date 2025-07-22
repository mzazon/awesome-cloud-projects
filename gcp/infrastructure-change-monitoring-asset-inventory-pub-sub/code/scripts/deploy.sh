#!/bin/bash

# Infrastructure Change Monitoring with Cloud Asset Inventory and Pub/Sub - Deploy Script
# This script deploys the complete infrastructure change monitoring solution

set -e  # Exit on any error

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID=""
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
DRY_RUN="${DRY_RUN:-false}"

# Resource names with unique suffix
RANDOM_SUFFIX=$(openssl rand -hex 3)
TOPIC_NAME="infrastructure-changes-${RANDOM_SUFFIX}"
SUBSCRIPTION_NAME="infrastructure-changes-sub-${RANDOM_SUFFIX}"
FUNCTION_NAME="process-asset-changes-${RANDOM_SUFFIX}"
DATASET_NAME="infrastructure_audit_${RANDOM_SUFFIX}"
FEED_NAME="infrastructure-feed-${RANDOM_SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Unable to verify billing status. Please ensure billing is enabled for project $PROJECT_ID"
    fi
    
    # Check required tools
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudasset.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would enable API: $api"
        else
            gcloud services enable "$api" --project="$PROJECT_ID"
        fi
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "Required APIs enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Pub/Sub topic: $TOPIC_NAME"
        log_info "[DRY RUN] Would create Pub/Sub subscription: $SUBSCRIPTION_NAME"
        return
    fi
    
    # Create topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Pub/Sub topic $TOPIC_NAME already exists"
    else
        gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"
        log_success "Created Pub/Sub topic: $TOPIC_NAME"
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Pub/Sub subscription $SUBSCRIPTION_NAME already exists"
    else
        gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
            --topic="$TOPIC_NAME" \
            --ack-deadline=60 \
            --project="$PROJECT_ID"
        log_success "Created Pub/Sub subscription: $SUBSCRIPTION_NAME"
    fi
}

# Function to create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and table..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create BigQuery dataset: $DATASET_NAME"
        log_info "[DRY RUN] Would create BigQuery table: asset_changes"
        return
    fi
    
    # Create dataset
    if bq ls -d "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        log_warning "BigQuery dataset $DATASET_NAME already exists"
    else
        bq mk --location="$REGION" "$DATASET_NAME"
        log_success "Created BigQuery dataset: $DATASET_NAME"
    fi
    
    # Create table
    if bq ls "$PROJECT_ID:$DATASET_NAME.asset_changes" &>/dev/null; then
        log_warning "BigQuery table asset_changes already exists"
    else
        bq mk --table "$PROJECT_ID:$DATASET_NAME.asset_changes" \
        timestamp:TIMESTAMP,asset_name:STRING,asset_type:STRING,change_type:STRING,prior_state:STRING,current_state:STRING,project_id:STRING,location:STRING,change_time:TIMESTAMP,ancestors:STRING
        log_success "Created BigQuery table: asset_changes"
    fi
}

# Function to create Cloud Function
create_cloud_function() {
    log_info "Creating Cloud Function for asset change processing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud Function: $FUNCTION_NAME"
        return
    fi
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create function code
    cat > main.py << 'EOF'
import base64
import json
import logging
import os
from datetime import datetime
from google.cloud import bigquery
from google.cloud import monitoring_v3

def process_asset_change(event, context):
    """Process asset change events from Cloud Asset Inventory."""
    
    # Initialize clients
    bq_client = bigquery.Client()
    monitoring_client = monitoring_v3.MetricServiceClient()
    
    # Decode Pub/Sub message
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    
    # Skip welcome messages
    if pubsub_message.startswith('Welcome'):
        logging.info('Received welcome message, skipping processing')
        return
    
    try:
        # Parse JSON message
        change_data = json.loads(pubsub_message)
        
        # Extract asset information
        asset = change_data.get('asset', {})
        prior_asset = change_data.get('priorAsset', {})
        
        # Determine change type
        change_type = 'DELETED' if prior_asset and not asset else \
                     'CREATED' if asset and not prior_asset else \
                     'UPDATED'
        
        # Prepare BigQuery row
        row = {
            'timestamp': datetime.utcnow().isoformat(),
            'asset_name': asset.get('name', '') if asset else prior_asset.get('name', ''),
            'asset_type': asset.get('assetType', '') if asset else prior_asset.get('assetType', ''),
            'change_type': change_type,
            'prior_state': json.dumps(prior_asset.get('resource', {}).get('data', {})),
            'current_state': json.dumps(asset.get('resource', {}).get('data', {})),
            'project_id': context.resource.split('/')[-1] if hasattr(context, 'resource') else '',
            'location': asset.get('resource', {}).get('location', '') if asset else '',
            'change_time': change_data.get('window', {}).get('startTime', ''),
            'ancestors': ','.join(asset.get('ancestors', [])) if asset else ''
        }
        
        # Insert into BigQuery
        table_ref = bq_client.dataset(os.environ['DATASET_NAME']).table('asset_changes')
        errors = bq_client.insert_rows_json(table_ref, [row])
        
        if errors:
            logging.error(f'BigQuery insert errors: {errors}')
        else:
            logging.info(f'Successfully processed {change_type} for {row["asset_name"]}')
            
        # Send custom metric to Cloud Monitoring
        project_name = f"projects/{os.environ['PROJECT_ID']}"
        series = monitoring_v3.TimeSeries()
        series.metric.type = 'custom.googleapis.com/infrastructure/changes'
        series.metric.labels['change_type'] = change_type
        series.metric.labels['asset_type'] = row['asset_type']
        
        now = datetime.utcnow()
        interval = monitoring_v3.TimeInterval()
        interval.end_time.seconds = int(now.timestamp())
        interval.end_time.nanos = int((now.timestamp() % 1) * 10**9)
        
        point = monitoring_v3.Point()
        point.interval = interval
        point.value.int64_value = 1
        series.points = [point]
        
        series.resource.type = 'global'
        series.resource.labels['project_id'] = os.environ['PROJECT_ID']
        
        monitoring_client.create_time_series(
            name=project_name, 
            time_series=[series]
        )
        
    except Exception as e:
        logging.error(f'Error processing asset change: {str(e)}')
        raise
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.13.0
google-cloud-monitoring==2.16.0
EOF
    
    # Deploy function
    if gcloud functions describe "$FUNCTION_NAME" --project="$PROJECT_ID" --region="$REGION" &>/dev/null; then
        log_warning "Cloud Function $FUNCTION_NAME already exists"
    else
        gcloud functions deploy "$FUNCTION_NAME" \
            --runtime python39 \
            --trigger-topic "$TOPIC_NAME" \
            --entry-point process_asset_change \
            --memory 256MB \
            --timeout 60s \
            --region="$REGION" \
            --set-env-vars PROJECT_ID="$PROJECT_ID",DATASET_NAME="$DATASET_NAME" \
            --project="$PROJECT_ID"
        log_success "Created Cloud Function: $FUNCTION_NAME"
    fi
    
    # Configure IAM permissions
    local function_sa
    function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(serviceAccountEmail)")
    
    # Grant BigQuery permissions
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$function_sa" \
        --role="roles/bigquery.dataEditor" \
        --quiet
    
    # Grant Monitoring permissions
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$function_sa" \
        --role="roles/monitoring.metricWriter" \
        --quiet
    
    log_success "Configured IAM permissions for Cloud Function"
    
    # Cleanup temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$temp_dir"
}

# Function to create Asset Inventory feed
create_asset_feed() {
    log_info "Creating Cloud Asset Inventory feed..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Asset feed: $FEED_NAME"
        return
    fi
    
    # Check if feed already exists
    if gcloud asset feeds list --project="$PROJECT_ID" --format="value(name)" | grep -q "$FEED_NAME"; then
        log_warning "Asset feed $FEED_NAME already exists"
    else
        gcloud asset feeds create "$FEED_NAME" \
            --project="$PROJECT_ID" \
            --pubsub-topic="projects/$PROJECT_ID/topics/$TOPIC_NAME" \
            --content-type=RESOURCE \
            --asset-types=".*"
        log_success "Created Asset feed: $FEED_NAME"
    fi
}

# Function to create monitoring alert policy
create_alert_policy() {
    log_info "Creating Cloud Monitoring alert policy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create alert policy for critical infrastructure changes"
        return
    fi
    
    # Create temporary alert policy file
    local temp_policy=$(mktemp)
    cat > "$temp_policy" << EOF
{
  "displayName": "Critical Infrastructure Changes - $RANDOM_SUFFIX",
  "conditions": [
    {
      "displayName": "High Change Rate",
      "conditionThreshold": {
        "filter": "resource.type=\"global\" AND metric.type=\"custom.googleapis.com/infrastructure/changes\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": "10",
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true
}
EOF
    
    # Create alert policy
    gcloud alpha monitoring policies create --policy-from-file="$temp_policy" --project="$PROJECT_ID"
    log_success "Created alert policy for infrastructure change monitoring"
    
    # Cleanup
    rm -f "$temp_policy"
}

# Function to save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    local config_file="$SCRIPT_DIR/../.deployment_config"
    cat > "$config_file" << EOF
# Deployment configuration for Infrastructure Change Monitoring
# Generated on $(date)
PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
TOPIC_NAME="$TOPIC_NAME"
SUBSCRIPTION_NAME="$SUBSCRIPTION_NAME"
FUNCTION_NAME="$FUNCTION_NAME"
DATASET_NAME="$DATASET_NAME"
FEED_NAME="$FEED_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log_success "Deployment configuration saved to $config_file"
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Infrastructure Change Monitoring deployment completed!"
    echo
    echo "===== DEPLOYMENT SUMMARY ====="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "BigQuery Dataset: $DATASET_NAME"
    echo "Asset Feed: $FEED_NAME"
    echo
    echo "===== NEXT STEPS ====="
    echo "1. Asset feed may take up to 10 minutes to become active"
    echo "2. Create test resources to verify change detection:"
    echo "   gcloud compute addresses create test-address --region=$REGION"
    echo "3. Query BigQuery for changes:"
    echo "   bq query \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_NAME.asset_changes\\\` LIMIT 10\""
    echo "4. Monitor Cloud Function logs:"
    echo "   gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo
    echo "===== ESTIMATED COSTS ====="
    echo "• Pub/Sub: ~$1-5/month (based on message volume)"
    echo "• Cloud Functions: ~$1-10/month (based on invocations)"
    echo "• BigQuery: ~$5-20/month (based on data storage and queries)"
    echo "• Cloud Asset Inventory: No additional cost"
    echo "• Cloud Monitoring: ~$1-5/month (based on metrics)"
    echo
    echo "Total estimated cost: $20-50/month for moderate usage"
    echo
    echo "To clean up resources, run: ./destroy.sh"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --project-id PROJECT_ID    Override project ID"
    echo "  --region REGION           Override region (default: us-central1)"
    echo "  --zone ZONE              Override zone (default: us-central1-a)"
    echo "  --dry-run                Simulate deployment without creating resources"
    echo "  --help                   Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID               Google Cloud project ID"
    echo "  REGION                   Google Cloud region"
    echo "  ZONE                     Google Cloud zone"
    echo "  DRY_RUN                  Set to 'true' for dry run mode"
}

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
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting Infrastructure Change Monitoring deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    enable_apis
    create_pubsub_resources
    create_bigquery_resources
    create_cloud_function
    create_asset_feed
    create_alert_policy
    
    if [[ "$DRY_RUN" != "true" ]]; then
        save_deployment_config
        display_summary
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Execute main function
main "$@"