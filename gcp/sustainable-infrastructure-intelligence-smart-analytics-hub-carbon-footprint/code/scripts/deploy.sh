#!/bin/bash

# Deploy script for Sustainable Infrastructure Intelligence with Smart Analytics Hub and Cloud Carbon Footprint
# This script deploys the complete solution for carbon footprint monitoring and analytics

set -euo pipefail

# Colors for output
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

# Exit handler
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        log_error "Deployment failed. Some resources may have been created."
        log_info "Run ./destroy.sh to clean up any partially created resources."
    fi
}
trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed"
        log_info "Install with: gcloud components install bq"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Cloud Storage CLI (gsutil) is not installed"
        log_info "Install with: gcloud components install gsutil"
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Project configuration
    export PROJECT_ID="${PROJECT_ID:-sustainability-intel-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Resource names
    export DATASET_NAME="${DATASET_NAME:-carbon_intelligence}"
    export BUCKET_NAME="${BUCKET_NAME:-carbon-reports-${RANDOM_SUFFIX}}"
    export TOPIC_NAME="${TOPIC_NAME:-carbon-alerts}"
    export FUNCTION_NAME="${FUNCTION_NAME:-carbon-processor}"
    
    # Get billing account (use first available if not specified)
    if [ -z "${BILLING_ACCOUNT_ID:-}" ]; then
        export BILLING_ACCOUNT_ID=$(gcloud billing accounts list --filter="open=true" --format="value(name)" | head -1)
        if [ -z "$BILLING_ACCOUNT_ID" ]; then
            log_error "No active billing account found"
            log_info "Please set BILLING_ACCOUNT_ID environment variable or enable billing"
            exit 1
        fi
    fi
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "Billing Account: $BILLING_ACCOUNT_ID"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    
    log_success "Environment variables configured"
}

# Create and configure project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Sustainability Intelligence"
        
        # Link billing account
        log_info "Linking billing account..."
        gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
    else
        log_info "Using existing project: $PROJECT_ID"
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquerydatatransfer.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "cloudscheduler.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

# Create BigQuery dataset and carbon footprint export
setup_bigquery() {
    log_info "Setting up BigQuery dataset and carbon footprint export..."
    
    # Create BigQuery dataset
    log_info "Creating BigQuery dataset: $DATASET_NAME"
    bq mk --dataset \
        --description="Carbon footprint intelligence and analytics" \
        --location="$REGION" \
        "${PROJECT_ID}:${DATASET_NAME}" || true
    
    # Wait for dataset creation
    sleep 10
    
    # Note: Carbon Footprint data transfer setup requires manual configuration
    # as it involves billing account access and may require organization-level permissions
    log_warning "Carbon Footprint data export requires manual setup:"
    log_info "1. Go to BigQuery Data Transfer Service in the Console"
    log_info "2. Create a new transfer for 'Carbon Footprint'"
    log_info "3. Configure with billing account: $BILLING_ACCOUNT_ID"
    log_info "4. Set destination dataset to: $DATASET_NAME"
    
    log_success "BigQuery dataset created successfully"
}

# Create Cloud Storage bucket
setup_storage() {
    log_info "Creating Cloud Storage bucket for reports..."
    
    # Create storage bucket
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME" || {
        log_warning "Bucket creation failed, it may already exist"
    }
    
    # Enable versioning
    gsutil versioning set on "gs://$BUCKET_NAME"
    
    # Set appropriate IAM permissions
    gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME" 2>/dev/null || true
    
    log_success "Storage bucket created: $BUCKET_NAME"
}

# Create Pub/Sub topic and subscription
setup_pubsub() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    gcloud pubsub topics create "$TOPIC_NAME" || {
        log_warning "Topic creation failed, it may already exist"
    }
    
    # Create subscription
    gcloud pubsub subscriptions create "carbon-alerts-sub" \
        --topic="$TOPIC_NAME" || {
        log_warning "Subscription creation failed, it may already exist"
    }
    
    log_success "Pub/Sub resources created successfully"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Create temporary directory for function source
    local temp_dir=$(mktemp -d)
    local original_dir=$(pwd)
    
    # Deploy data processing function
    log_info "Deploying data processing function..."
    mkdir -p "$temp_dir/carbon-processor"
    cd "$temp_dir/carbon-processor"
    
    # Create main.py for data processing function
    cat > main.py << 'EOF'
import os
import json
from google.cloud import bigquery
from google.cloud import pubsub_v1
import pandas as pd
from datetime import datetime, timedelta

def process_carbon_data(event, context):
    """Process carbon footprint data and generate insights"""
    
    client = bigquery.Client()
    project_id = os.environ['GCP_PROJECT']
    dataset_id = os.environ['DATASET_NAME']
    
    # Query recent carbon emissions data
    query = f"""
    SELECT 
        month,
        project_id,
        service,
        region,
        location_based_carbon_emissions_kgCO2e,
        market_based_carbon_emissions_kgCO2e,
        carbon_model_version
    FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
    WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
    ORDER BY month DESC, location_based_carbon_emissions_kgCO2e DESC
    """
    
    try:
        results = client.query(query).to_dataframe()
        
        if not results.empty:
            # Calculate trends and anomalies
            monthly_totals = results.groupby('month')['location_based_carbon_emissions_kgCO2e'].sum()
            
            # Detect significant increases (>20% month-over-month)
            if len(monthly_totals) >= 2:
                latest_month = monthly_totals.iloc[0]
                previous_month = monthly_totals.iloc[1]
                increase_pct = ((latest_month - previous_month) / previous_month) * 100
                
                if increase_pct > 20:
                    # Publish alert for significant increase
                    publisher = pubsub_v1.PublisherClient()
                    topic_path = publisher.topic_path(project_id, os.environ['TOPIC_NAME'])
                    
                    alert_data = {
                        'type': 'carbon_increase_alert',
                        'increase_percentage': increase_pct,
                        'latest_emissions': float(latest_month),
                        'timestamp': datetime.now().isoformat()
                    }
                    
                    publisher.publish(topic_path, json.dumps(alert_data).encode('utf-8'))
            
            # Create aggregated views for Smart Analytics Hub
            create_analytical_views(client, project_id, dataset_id)
            
        return {'status': 'success', 'processed_rows': len(results)}
    except Exception as e:
        print(f"Error processing carbon data: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def create_analytical_views(client, project_id, dataset_id):
    """Create analytical views for Smart Analytics Hub sharing"""
    
    # Monthly emissions trend view
    monthly_view_query = f"""
    CREATE OR REPLACE VIEW `{project_id}.{dataset_id}.monthly_emissions_trend` AS
    SELECT 
        month,
        SUM(location_based_carbon_emissions_kgCO2e) as total_location_emissions,
        SUM(market_based_carbon_emissions_kgCO2e) as total_market_emissions,
        COUNT(DISTINCT project_id) as active_projects,
        COUNT(DISTINCT service) as active_services
    FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
    GROUP BY month
    ORDER BY month DESC
    """
    
    # Service-level emissions view
    service_view_query = f"""
    CREATE OR REPLACE VIEW `{project_id}.{dataset_id}.service_emissions_analysis` AS
    SELECT 
        service,
        region,
        AVG(location_based_carbon_emissions_kgCO2e) as avg_monthly_emissions,
        MAX(location_based_carbon_emissions_kgCO2e) as peak_emissions,
        COUNT(*) as measurement_count,
        STDDEV(location_based_carbon_emissions_kgCO2e) as emissions_variability
    FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
    WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    GROUP BY service, region
    HAVING avg_monthly_emissions > 0
    ORDER BY avg_monthly_emissions DESC
    """
    
    try:
        client.query(monthly_view_query)
        client.query(service_view_query)
    except Exception as e:
        print(f"Error creating views: {str(e)}")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-bigquery>=3.0.0
google-cloud-pubsub>=2.0.0
pandas>=1.5.0
EOF
    
    # Deploy the function
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python39 \
        --trigger-topic "$TOPIC_NAME" \
        --source . \
        --entry-point process_carbon_data \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME},TOPIC_NAME=${TOPIC_NAME}" \
        --region="$REGION" \
        --quiet || {
        log_error "Failed to deploy data processing function"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    }
    
    cd "$original_dir"
    
    # Deploy recommendations engine function
    log_info "Deploying recommendations engine function..."
    mkdir -p "$temp_dir/recommendations-engine"
    cd "$temp_dir/recommendations-engine"
    
    # Create main.py for recommendations function
    cat > main.py << 'EOF'
import os
import json
from google.cloud import bigquery
from google.cloud import storage
from datetime import datetime, timedelta
import pandas as pd

def generate_recommendations(request):
    """Generate sustainability recommendations based on carbon data analysis"""
    
    client = bigquery.Client()
    storage_client = storage.Client()
    
    project_id = os.environ['GCP_PROJECT']
    dataset_id = os.environ['DATASET_NAME']
    bucket_name = os.environ['BUCKET_NAME']
    
    # Analyze emissions patterns for recommendations
    query = f"""
    WITH emissions_analysis AS (
        SELECT 
            service,
            region,
            project_id,
            AVG(location_based_carbon_emissions_kgCO2e) as avg_emissions,
            MAX(location_based_carbon_emissions_kgCO2e) as peak_emissions,
            STDDEV(location_based_carbon_emissions_kgCO2e) as emissions_variance
        FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
        WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
        GROUP BY service, region, project_id
    )
    SELECT 
        service,
        region,
        project_id,
        avg_emissions,
        peak_emissions,
        emissions_variance,
        CASE 
            WHEN emissions_variance > avg_emissions * 0.5 THEN 'HIGH_VARIABILITY'
            WHEN avg_emissions > 100 THEN 'HIGH_EMISSIONS'
            WHEN region NOT IN ('us-central1', 'europe-west1') THEN 'CARBON_INTENSIVE_REGION'
            ELSE 'OPTIMIZED'
        END as recommendation_category
    FROM emissions_analysis
    WHERE avg_emissions > 0
    ORDER BY avg_emissions DESC
    """
    
    try:
        results = client.query(query).to_dataframe()
        
        recommendations = []
        
        for _, row in results.iterrows():
            if row['recommendation_category'] == 'HIGH_VARIABILITY':
                recommendations.append({
                    'type': 'Resource Optimization',
                    'priority': 'High',
                    'service': row['service'],
                    'region': row['region'],
                    'project': row['project_id'],
                    'description': f'High emissions variability detected. Consider implementing auto-scaling or scheduled resources.',
                    'potential_reduction': f"{row['emissions_variance']:.2f} kgCO2e/month",
                    'actions': [
                        'Enable auto-scaling for variable workloads',
                        'Schedule non-critical resources during low-carbon periods',
                        'Consider preemptible instances for batch workloads'
                    ]
                })
            elif row['recommendation_category'] == 'HIGH_EMISSIONS':
                recommendations.append({
                    'type': 'Service Migration',
                    'priority': 'Medium',
                    'service': row['service'],
                    'region': row['region'],
                    'project': row['project_id'],
                    'description': f'High carbon emissions from {row["service"]}. Consider green alternatives.',
                    'potential_reduction': f"{row['avg_emissions'] * 0.3:.2f} kgCO2e/month",
                    'actions': [
                        'Evaluate serverless alternatives',
                        'Optimize resource allocation and utilization',
                        'Consider regional migration to lower-carbon regions'
                    ]
                })
            elif row['recommendation_category'] == 'CARBON_INTENSIVE_REGION':
                recommendations.append({
                    'type': 'Regional Migration',
                    'priority': 'Medium',
                    'service': row['service'],
                    'region': row['region'],
                    'project': row['project_id'],
                    'description': f'Consider migrating to lower-carbon regions like us-central1 or europe-west1.',
                    'potential_reduction': f"{row['avg_emissions'] * 0.4:.2f} kgCO2e/month",
                    'actions': [
                        'Plan migration to Google Cloud carbon-free regions',
                        'Evaluate performance impact of regional change',
                        'Implement gradual migration strategy'
                    ]
                })
        
        # Generate report
        report = {
            'generated_at': datetime.now().isoformat(),
            'total_recommendations': len(recommendations),
            'recommendations': recommendations,
            'summary': {
                'high_priority': len([r for r in recommendations if r['priority'] == 'High']),
                'medium_priority': len([r for r in recommendations if r['priority'] == 'Medium']),
                'total_potential_reduction': sum([float(r['potential_reduction'].split()[0]) for r in recommendations])
            }
        }
        
        # Save report to Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob_name = f"sustainability_recommendations_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(report, indent=2))
        
        return {
            'status': 'success', 
            'recommendations_generated': len(recommendations), 
            'report_location': f"gs://{bucket_name}/{blob_name}"
        }
    except Exception as e:
        return {'status': 'error', 'message': str(e)}
EOF
    
    # Create requirements.txt for recommendations function
    cat > requirements.txt << 'EOF'
google-cloud-bigquery>=3.0.0
google-cloud-storage>=2.0.0
pandas>=1.5.0
EOF
    
    # Deploy recommendations function
    gcloud functions deploy "recommendations-engine" \
        --runtime python39 \
        --trigger-http \
        --source . \
        --entry-point generate_recommendations \
        --memory 512MB \
        --timeout 120s \
        --set-env-vars "DATASET_NAME=${DATASET_NAME},BUCKET_NAME=${BUCKET_NAME}" \
        --region="$REGION" \
        --allow-unauthenticated \
        --quiet || {
        log_error "Failed to deploy recommendations engine function"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    }
    
    cd "$original_dir"
    rm -rf "$temp_dir"
    
    log_success "Cloud Functions deployed successfully"
}

# Set up Smart Analytics Hub
setup_analytics_hub() {
    log_info "Setting up Smart Analytics Hub data sharing..."
    
    # Create data exchange for sustainability analytics
    bq mk --data_exchange \
        --location="$REGION" \
        --display_name="Sustainability Analytics Exchange" \
        --description="Shared carbon footprint and sustainability metrics" \
        sustainability_exchange || {
        log_warning "Data exchange creation failed, it may already exist"
    }
    
    # Note: Creating listings requires data to exist
    log_warning "Analytics Hub listing creation will be available after carbon footprint data is populated"
    log_info "Run this command after data is available:"
    log_info "bq mk --listing --location=$REGION --data_exchange=sustainability_exchange --display_name='Monthly Carbon Emissions Trends' --description='Monthly aggregated carbon emissions' --source_dataset=${PROJECT_ID}:${DATASET_NAME}.monthly_emissions_trend monthly_emissions_listing"
    
    log_success "Smart Analytics Hub exchange created"
}

# Create scheduled jobs
setup_scheduler() {
    log_info "Creating scheduled jobs for automated analysis..."
    
    # Get the recommendations function URL
    local recommendations_url=$(gcloud functions describe recommendations-engine --region="$REGION" --format="value(httpsTrigger.url)")
    
    # Create scheduled job for weekly recommendations
    gcloud scheduler jobs create http recommendations-weekly \
        --schedule="0 9 * * 1" \
        --uri="$recommendations_url" \
        --http-method=POST \
        --time-zone="America/New_York" \
        --location="$REGION" || {
        log_warning "Weekly recommendations job creation failed, it may already exist"
    }
    
    # Create scheduled job for monthly data processing
    gcloud scheduler jobs create pubsub data-processing-monthly \
        --schedule="0 6 15 * *" \
        --topic="$TOPIC_NAME" \
        --message-body='{"trigger":"monthly_processing"}' \
        --time-zone="America/New_York" \
        --location="$REGION" || {
        log_warning "Monthly data processing job creation failed, it may already exist"
    }
    
    log_success "Scheduled jobs created successfully"
}

# Set up service account for Looker Studio
setup_looker_service_account() {
    log_info "Setting up service account for Looker Studio access..."
    
    # Create service account
    gcloud iam service-accounts create looker-studio-sa \
        --display-name="Looker Studio Service Account" \
        --description="Service account for Looker Studio dashboard access" || {
        log_warning "Service account creation failed, it may already exist"
    }
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:looker-studio-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/bigquery.dataViewer" --quiet
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:looker-studio-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/bigquery.jobUser" --quiet
    
    log_success "Looker Studio service account configured"
}

# Print deployment summary
print_summary() {
    log_success "Deployment completed successfully!"
    echo
    log_info "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "BigQuery Dataset: $DATASET_NAME"
    echo "Storage Bucket: $BUCKET_NAME"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "Data Processing Function: $FUNCTION_NAME"
    echo "Recommendations Function: recommendations-engine"
    echo
    log_info "=== NEXT STEPS ==="
    echo "1. Configure Carbon Footprint data export manually in BigQuery Data Transfer Service"
    echo "2. Connect Looker Studio to BigQuery dataset using service account: looker-studio-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "3. Wait for carbon footprint data to populate (monthly exports on 15th)"
    echo "4. Create Analytics Hub listings after data is available"
    echo
    log_info "=== MANUAL CONFIGURATION REQUIRED ==="
    echo "• Carbon Footprint Export: Go to BigQuery > Data Transfer Service"
    echo "• Billing Account ID: $BILLING_ACCOUNT_ID"
    echo "• Destination Dataset: $DATASET_NAME"
    echo
    log_info "=== USEFUL COMMANDS ==="
    echo "• Test recommendations: gcloud functions call recommendations-engine --region=$REGION"
    echo "• View logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "• Check scheduled jobs: gcloud scheduler jobs list --location=$REGION"
    echo
    log_warning "Remember to run ./destroy.sh to clean up resources when done testing"
}

# Main deployment function
main() {
    log_info "Starting deployment of Sustainable Infrastructure Intelligence solution..."
    echo
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_bigquery
    setup_storage
    setup_pubsub
    deploy_functions
    setup_analytics_hub
    setup_scheduler
    setup_looker_service_account
    
    echo
    print_summary
}

# Run main function
main "$@"