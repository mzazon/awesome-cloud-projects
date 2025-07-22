#!/bin/bash

# Multi-Cloud Resource Discovery with Cloud Location Finder and Pub/Sub - Deployment Script
# This script deploys the complete infrastructure for multi-cloud resource discovery
# using Google Cloud Location Finder, Pub/Sub, Cloud Functions, and monitoring services.

set -euo pipefail

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Command: $BASH_COMMAND"
    log_error "Run './destroy.sh' to clean up any partially created resources"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="multi-cloud-discovery"
REQUIRED_APIS=(
    "cloudlocationfinder.googleapis.com"
    "pubsub.googleapis.com"
    "cloudfunctions.googleapis.com"
    "cloudscheduler.googleapis.com"
    "storage.googleapis.com"
    "monitoring.googleapis.com"
)

# Display banner
echo -e "${BLUE}"
echo "======================================================================="
echo "  Multi-Cloud Resource Discovery Deployment Script"
echo "  Provider: Google Cloud Platform"
echo "  Recipe: multi-cloud-resource-discovery-location-finder-pub-sub"
echo "======================================================================="
echo -e "${NC}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Google Cloud CLI version: $GCLOUD_VERSION"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_info "Active account: $ACTIVE_ACCOUNT"
    
    # Check for required utilities
    for cmd in curl openssl date; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required utility '$cmd' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
        log_info "Generated PROJECT_ID: $PROJECT_ID"
    else
        log_info "Using existing PROJECT_ID: $PROJECT_ID"
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique identifiers
    export TOPIC_NAME="location-discovery-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="process-locations-${RANDOM_SUFFIX}"
    export BUCKET_NAME="location-reports-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB="location-sync-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
TOPIC_NAME=${TOPIC_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
SCHEDULER_JOB=${SCHEDULER_JOB}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Resource names:"
    log_info "  - Project: $PROJECT_ID"
    log_info "  - Region: $REGION"
    log_info "  - Pub/Sub Topic: $TOPIC_NAME"
    log_info "  - Cloud Function: $FUNCTION_NAME"
    log_info "  - Storage Bucket: $BUCKET_NAME"
    log_info "  - Scheduler Job: $SCHEDULER_JOB"
}

# Function to create or use existing project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Using existing project: $PROJECT_ID"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Multi-Cloud Resource Discovery"
        
        # Wait for project creation to propagate
        sleep 10
    fi
    
    # Set the project as active
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Check if billing is enabled (required for API enablement)
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Billing is not enabled for project $PROJECT_ID"
        log_warning "Please enable billing for the project to continue"
        log_warning "You can do this via the Cloud Console or gcloud CLI"
        read -p "Press Enter after enabling billing, or Ctrl+C to exit..."
    fi
    
    log_success "Project setup completed: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling API: $api"
        gcloud services enable "$api" --project="$PROJECT_ID"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic for location data
    gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"
    log_success "Created Pub/Sub topic: $TOPIC_NAME"
    
    # Create subscription for Cloud Function processing
    gcloud pubsub subscriptions create "${TOPIC_NAME}-sub" \
        --topic="$TOPIC_NAME" \
        --ack-deadline=300 \
        --message-retention-duration=7d \
        --project="$PROJECT_ID"
    
    log_success "Created Pub/Sub subscription with 5-minute ack deadline"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for location reports..."
    
    # Create Cloud Storage bucket for location reports
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME"
    
    # Enable versioning for report history tracking
    gsutil versioning set on "gs://$BUCKET_NAME"
    
    # Create folder structure for organized storage
    echo "" | gsutil cp - "gs://$BUCKET_NAME/reports/.gitkeep"
    echo "" | gsutil cp - "gs://$BUCKET_NAME/raw-data/.gitkeep"
    echo "" | gsutil cp - "gs://$BUCKET_NAME/recommendations/.gitkeep"
    
    log_success "Cloud Storage bucket created: $BUCKET_NAME"
    log_success "Folder structure initialized for location data organization"
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for location data processing..."
    
    # Create temporary function source directory
    FUNCTION_DIR=$(mktemp -d)
    cd "$FUNCTION_DIR"
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
google-cloud-monitoring==2.16.0
requests==2.31.0
functions-framework==3.4.0
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import json
import logging
import os
from datetime import datetime
from typing import Dict, List, Any
import requests
from google.cloud import storage
from google.cloud import monitoring_v3
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
BUCKET_NAME = os.environ.get('BUCKET_NAME')
PROJECT_ID = os.environ.get('PROJECT_ID')

def get_location_data() -> List[Dict[str, Any]]:
    """Fetch location data from Cloud Location Finder API"""
    try:
        # Cloud Location Finder API endpoint
        url = "https://cloudlocationfinder.googleapis.com/v1/locations"
        
        # Make API request for multi-cloud location data
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        locations = data.get('locations', [])
        
        logger.info(f"Retrieved {len(locations)} locations from Cloud Location Finder")
        return locations
    
    except Exception as e:
        logger.error(f"Error fetching location data: {str(e)}")
        return []

def analyze_locations(locations: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Analyze location data for deployment recommendations"""
    analysis = {
        'total_locations': len(locations),
        'providers': {},
        'regions_by_provider': {},
        'low_carbon_regions': [],
        'recommendations': []
    }
    
    for location in locations:
        provider = location.get('cloudProvider', 'unknown')
        region = location.get('regionCode', 'unknown')
        carbon_footprint = location.get('carbonFootprint', {})
        
        # Count providers and regions
        if provider not in analysis['providers']:
            analysis['providers'][provider] = 0
            analysis['regions_by_provider'][provider] = []
        
        analysis['providers'][provider] += 1
        if region not in analysis['regions_by_provider'][provider]:
            analysis['regions_by_provider'][provider].append(region)
        
        # Identify low-carbon regions
        if carbon_footprint.get('carbonIntensity', 1000) < 200:
            analysis['low_carbon_regions'].append({
                'provider': provider,
                'region': region,
                'carbonIntensity': carbon_footprint.get('carbonIntensity')
            })
    
    # Generate deployment recommendations
    analysis['recommendations'] = generate_recommendations(analysis)
    
    return analysis

def generate_recommendations(analysis: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Generate deployment recommendations based on location analysis"""
    recommendations = []
    
    # Recommend low-carbon regions
    if analysis['low_carbon_regions']:
        recommendations.append({
            'type': 'sustainability',
            'priority': 'high',
            'description': f"Deploy to {len(analysis['low_carbon_regions'])} low-carbon regions",
            'regions': analysis['low_carbon_regions'][:3]  # Top 3
        })
    
    # Recommend multi-provider strategy
    if len(analysis['providers']) >= 3:
        recommendations.append({
            'type': 'resilience',
            'priority': 'medium',
            'description': 'Consider multi-provider deployment for resilience',
            'providers': list(analysis['providers'].keys())
        })
    
    return recommendations

def save_to_storage(data: Dict[str, Any], filename: str) -> None:
    """Save analysis data to Cloud Storage"""
    try:
        client = storage.Client()
        bucket = client.bucket(BUCKET_NAME)
        blob = bucket.blob(f"reports/{filename}")
        
        blob.upload_from_string(
            json.dumps(data, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Saved report to gs://{BUCKET_NAME}/reports/{filename}")
    
    except Exception as e:
        logger.error(f"Error saving to storage: {str(e)}")

def create_custom_metric(analysis: Dict[str, Any]) -> None:
    """Create custom monitoring metrics"""
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{PROJECT_ID}"
        
        # Create time series data
        series = monitoring_v3.TimeSeries()
        series.resource.type = "global"
        series.metric.type = "custom.googleapis.com/multicloud/total_locations"
        
        # Add data point
        point = series.points.add()
        point.value.int64_value = analysis['total_locations']
        point.interval.end_time.seconds = int(datetime.now().timestamp())
        
        # Write time series
        client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.info("Custom metric created successfully")
    
    except Exception as e:
        logger.error(f"Error creating custom metric: {str(e)}")

@functions_framework.cloud_event
def process_location_data(cloud_event):
    """Main function to process location discovery messages"""
    try:
        logger.info("Processing location discovery request")
        
        # Fetch location data from Cloud Location Finder
        locations = get_location_data()
        
        if not locations:
            logger.warning("No location data received")
            return
        
        # Analyze location data for recommendations
        analysis = analyze_locations(locations)
        
        # Generate timestamped filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"location_analysis_{timestamp}.json"
        
        # Save analysis to Cloud Storage
        save_to_storage(analysis, filename)
        
        # Create monitoring metrics
        create_custom_metric(analysis)
        
        logger.info(f"Successfully processed {len(locations)} locations")
        logger.info(f"Generated {len(analysis['recommendations'])} recommendations")
        
        return {"status": "success", "locations_processed": len(locations)}
    
    except Exception as e:
        logger.error(f"Error in process_location_data: {str(e)}")
        raise
EOF
    
    # Deploy Cloud Function with environment variables
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python39 \
        --trigger-topic "$TOPIC_NAME" \
        --source . \
        --entry-point process_location_data \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "BUCKET_NAME=$BUCKET_NAME,PROJECT_ID=$PROJECT_ID" \
        --project="$PROJECT_ID" \
        --region="$REGION"
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$FUNCTION_DIR"
    
    log_success "Cloud Function deployed with Pub/Sub trigger and environment variables"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job for automated discovery..."
    
    # Create Cloud Scheduler job for periodic location discovery
    gcloud scheduler jobs create pubsub "$SCHEDULER_JOB" \
        --schedule="0 */6 * * *" \
        --topic="$TOPIC_NAME" \
        --message-body="{\"trigger\":\"scheduled_discovery\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
        --time-zone="UTC" \
        --description="Automated multi-cloud location discovery" \
        --location="$REGION" \
        --project="$PROJECT_ID"
    
    log_success "Cloud Scheduler job created: $SCHEDULER_JOB"
    log_success "Scheduled for every 6 hours"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating Cloud Monitoring dashboard..."
    
    # Create custom dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
{
  "displayName": "Multi-Cloud Location Discovery Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Total Locations Discovered",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/multicloud/total_locations\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Function Execution Count",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the monitoring dashboard
    gcloud monitoring dashboards create \
        --config-from-file=/tmp/dashboard-config.json \
        --project="$PROJECT_ID"
    
    # Clean up temp file
    rm -f /tmp/dashboard-config.json
    
    log_success "Cloud Monitoring dashboard created with location metrics and function performance"
}

# Function to create alert policies
create_alert_policies() {
    log_info "Setting up alert policies for discovery monitoring..."
    
    # Create alert policy for function failures
    cat > /tmp/alert-policy.json << EOF
{
  "displayName": "Location Discovery Function Failures",
  "conditions": [
    {
      "displayName": "Function execution failures",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${FUNCTION_NAME}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": {
          "doubleValue": 5
        },
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    # Create the alert policy
    gcloud alpha monitoring policies create \
        --policy-from-file=/tmp/alert-policy.json \
        --project="$PROJECT_ID"
    
    # Clean up temp file
    rm -f /tmp/alert-policy.json
    
    log_success "Alert policy created with 5-minute threshold and auto-close"
}

# Function to trigger initial discovery
trigger_initial_discovery() {
    log_info "Triggering initial location discovery..."
    
    # Manually trigger the first execution
    gcloud scheduler jobs run "$SCHEDULER_JOB" \
        --location="$REGION" \
        --project="$PROJECT_ID"
    
    # Wait for processing to begin
    sleep 10
    
    # Check function logs
    log_info "Checking function execution logs..."
    gcloud functions logs read "$FUNCTION_NAME" \
        --limit=10 \
        --project="$PROJECT_ID" \
        --region="$REGION" || log_warning "Could not retrieve logs immediately"
    
    log_success "Initial discovery triggered"
}

# Function to display deployment summary
display_summary() {
    echo ""
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log_info "Deployed Resources:"
    log_info "  • Project: $PROJECT_ID"
    log_info "  • Pub/Sub Topic: $TOPIC_NAME"
    log_info "  • Cloud Function: $FUNCTION_NAME"
    log_info "  • Storage Bucket: gs://$BUCKET_NAME"
    log_info "  • Scheduler Job: $SCHEDULER_JOB"
    echo ""
    log_info "Access Points:"
    log_info "  • Cloud Console: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    log_info "  • Cloud Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    log_info "  • Cloud Storage: https://console.cloud.google.com/storage/browser/$BUCKET_NAME?project=$PROJECT_ID"
    log_info "  • Cloud Monitoring: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
    echo ""
    log_info "Next Steps:"
    log_info "  1. Monitor location discovery in Cloud Functions logs"
    log_info "  2. Review generated reports in Cloud Storage"
    log_info "  3. Check monitoring dashboard for metrics"
    log_info "  4. Customize scheduler frequency as needed"
    echo ""
    log_warning "Remember to run './destroy.sh' when you're done to avoid ongoing charges"
    echo ""
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_pubsub_resources
    create_storage_bucket
    deploy_cloud_function
    create_scheduler_job
    create_monitoring_dashboard
    create_alert_policies
    trigger_initial_discovery
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_summary
    log_success "Total deployment time: ${duration} seconds"
}

# Cleanup on script exit
cleanup() {
    if [[ -f "/tmp/dashboard-config.json" ]]; then
        rm -f "/tmp/dashboard-config.json"
    fi
    if [[ -f "/tmp/alert-policy.json" ]]; then
        rm -f "/tmp/alert-policy.json"
    fi
}

trap cleanup EXIT

# Run main function
main "$@"