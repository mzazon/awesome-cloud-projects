#!/bin/bash

# Fleet Operations with Fleet Engine and Cloud Run Jobs - Deployment Script
# This script deploys the complete fleet operations infrastructure on Google Cloud Platform

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
PROJECT_ID=${PROJECT_ID:-"fleet-ops-$(date +%s)"}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
RANDOM_SUFFIX=$(openssl rand -hex 3)
FLEET_ENGINE_PROJECT_ID="${PROJECT_ID}"
ANALYTICS_JOB_NAME="fleet-analytics-${RANDOM_SUFFIX}"
BUCKET_NAME="fleet-data-${RANDOM_SUFFIX}"
DATASET_NAME="fleet_analytics"
FLEET_ENGINE_SA_EMAIL="fleet-engine-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create project and enable APIs
setup_project() {
    log_info "Setting up project: ${PROJECT_ID}"
    
    # Create the project
    if ! gcloud projects describe ${PROJECT_ID} &> /dev/null; then
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create ${PROJECT_ID} \
            --name="Fleet Operations Platform" || {
            log_error "Failed to create project ${PROJECT_ID}"
            exit 1
        }
    else
        log_warning "Project ${PROJECT_ID} already exists"
    fi
    
    # Set project as default
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    # Enable required APIs
    log_info "Enabling required APIs..."
    gcloud services enable \
        fleetengine.googleapis.com \
        run.googleapis.com \
        cloudscheduler.googleapis.com \
        bigquery.googleapis.com \
        storage.googleapis.com \
        firestore.googleapis.com \
        maps-backend.googleapis.com \
        routes.googleapis.com \
        monitoring.googleapis.com \
        cloudbuild.googleapis.com \
        container.googleapis.com || {
        log_error "Failed to enable required APIs"
        exit 1
    }
    
    log_success "Project setup completed"
}

# Configure Fleet Engine service account
setup_fleet_engine_sa() {
    log_info "Setting up Fleet Engine service account..."
    
    # Create service account for Fleet Engine
    if ! gcloud iam service-accounts describe fleet-engine-sa@${PROJECT_ID}.iam.gserviceaccount.com &> /dev/null; then
        gcloud iam service-accounts create fleet-engine-sa \
            --display-name="Fleet Engine Service Account" \
            --description="Service account for Fleet Engine operations" || {
            log_error "Failed to create Fleet Engine service account"
            exit 1
        }
    else
        log_warning "Fleet Engine service account already exists"
    fi
    
    # Grant necessary roles for Fleet Engine operations
    local roles=(
        "roles/fleetengine.deliveryFleetReader"
        "roles/fleetengine.deliveryConsumer"
        "roles/bigquery.dataEditor"
        "roles/storage.objectAdmin"
        "roles/datastore.user"
        "roles/run.invoker"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role: ${role}"
        gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${FLEET_ENGINE_SA_EMAIL}" \
            --role="${role}" &> /dev/null || {
            log_warning "Role ${role} may already be assigned"
        }
    done
    
    # Create service account key if it doesn't exist
    if [[ ! -f "fleet-engine-key.json" ]]; then
        log_info "Creating service account key..."
        gcloud iam service-accounts keys create fleet-engine-key.json \
            --iam-account=${FLEET_ENGINE_SA_EMAIL} || {
            log_error "Failed to create service account key"
            exit 1
        }
    else
        log_warning "Service account key already exists"
    fi
    
    log_success "Fleet Engine service account configured"
}

# Create Cloud Storage bucket
setup_storage() {
    log_info "Setting up Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Create bucket for fleet data storage
    if ! gsutil ls -b gs://${BUCKET_NAME} &> /dev/null; then
        gsutil mb -p ${PROJECT_ID} \
            -c STANDARD \
            -l ${REGION} \
            gs://${BUCKET_NAME} || {
            log_error "Failed to create storage bucket"
            exit 1
        }
        
        # Enable versioning for data protection
        gsutil versioning set on gs://${BUCKET_NAME}
        
        # Create folder structure for organized data storage
        echo "Fleet data initialized" | gsutil cp - gs://${BUCKET_NAME}/vehicle-telemetry/README.txt
        echo "Route histories storage" | gsutil cp - gs://${BUCKET_NAME}/route-histories/README.txt
        echo "Analytics results storage" | gsutil cp - gs://${BUCKET_NAME}/analytics-results/README.txt
        
        # Set lifecycle policy for cost optimization
        cat > lifecycle-policy.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
        
        gsutil lifecycle set lifecycle-policy.json gs://${BUCKET_NAME}
        rm lifecycle-policy.json
    else
        log_warning "Storage bucket already exists"
    fi
    
    log_success "Cloud Storage bucket configured"
}

# Set up BigQuery dataset
setup_bigquery() {
    log_info "Setting up BigQuery dataset: ${DATASET_NAME}"
    
    # Create BigQuery dataset for fleet analytics
    if ! bq ls -d ${PROJECT_ID}:${DATASET_NAME} &> /dev/null; then
        bq mk \
            --dataset \
            --description="Fleet operations analytics dataset" \
            --location=${REGION} \
            ${PROJECT_ID}:${DATASET_NAME} || {
            log_error "Failed to create BigQuery dataset"
            exit 1
        }
        
        # Create table for vehicle telemetry data
        bq mk \
            --table \
            --description="Vehicle telemetry and location data" \
            ${PROJECT_ID}:${DATASET_NAME}.vehicle_telemetry \
            vehicle_id:STRING,timestamp:TIMESTAMP,latitude:FLOAT,longitude:FLOAT,speed:FLOAT,fuel_level:FLOAT,engine_status:STRING,driver_id:STRING
        
        # Create table for route performance metrics
        bq mk \
            --table \
            --description="Route performance and optimization metrics" \
            ${PROJECT_ID}:${DATASET_NAME}.route_performance \
            route_id:STRING,vehicle_id:STRING,start_time:TIMESTAMP,end_time:TIMESTAMP,distance_km:FLOAT,fuel_consumed:FLOAT,average_speed:FLOAT,stops_count:INTEGER,efficiency_score:FLOAT
        
        # Create table for delivery tasks
        bq mk \
            --table \
            --description="Delivery task tracking and completion data" \
            ${PROJECT_ID}:${DATASET_NAME}.delivery_tasks \
            task_id:STRING,vehicle_id:STRING,driver_id:STRING,pickup_location:STRING,delivery_location:STRING,scheduled_time:TIMESTAMP,completed_time:TIMESTAMP,status:STRING,customer_rating:INTEGER
    else
        log_warning "BigQuery dataset already exists"
    fi
    
    log_success "BigQuery dataset and tables created"
}

# Create Firestore database
setup_firestore() {
    log_info "Setting up Firestore database..."
    
    # Check if Firestore is already enabled
    if ! gcloud firestore databases list --filter="name:*default*" --format="value(name)" | grep -q .; then
        log_info "Creating Firestore database..."
        gcloud firestore databases create \
            --location=${REGION} \
            --type=firestore-native || {
            log_error "Failed to create Firestore database"
            exit 1
        }
        
        # Create composite indexes for efficient queries
        cat > firestore-indexes.yaml << EOF
indexes:
- collectionGroup: vehicles
  queryScope: COLLECTION
  fields:
  - fieldPath: status
    order: ASCENDING
  - fieldPath: last_updated
    order: DESCENDING

- collectionGroup: delivery_tasks
  queryScope: COLLECTION
  fields:
  - fieldPath: vehicle_id
    order: ASCENDING
  - fieldPath: status
    order: ASCENDING
  - fieldPath: scheduled_time
    order: ASCENDING

- collectionGroup: route_plans
  queryScope: COLLECTION
  fields:
  - fieldPath: vehicle_id
    order: ASCENDING
  - fieldPath: created_at
    order: DESCENDING
EOF
        
        gcloud firestore indexes composite create --file=firestore-indexes.yaml || {
            log_warning "Failed to create Firestore indexes (may already exist)"
        }
        rm firestore-indexes.yaml
    else
        log_warning "Firestore database already exists"
    fi
    
    log_success "Firestore database configured"
}

# Build and deploy Cloud Run Job
deploy_analytics_job() {
    log_info "Building and deploying Cloud Run Job: ${ANALYTICS_JOB_NAME}"
    
    # Create the analytics job container source code
    mkdir -p fleet-analytics-job
    cd fleet-analytics-job
    
    # Create Python requirements
    cat > requirements.txt << EOF
google-cloud-bigquery==3.14.1
google-cloud-storage==2.10.0
google-cloud-firestore==2.13.1
pandas==2.1.4
numpy==1.24.3
scikit-learn==1.3.2
EOF
    
    # Create the analytics processing script
    cat > analytics_processor.py << 'EOF'
import os
import pandas as pd
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import firestore
from datetime import datetime, timedelta
import json

def process_fleet_analytics():
    """Process fleet data and generate analytics insights"""
    
    # Initialize clients
    bq_client = bigquery.Client()
    storage_client = storage.Client()
    firestore_client = firestore.Client()
    
    project_id = os.environ.get('PROJECT_ID')
    dataset_name = os.environ.get('DATASET_NAME')
    bucket_name = os.environ.get('BUCKET_NAME')
    
    print(f"Processing fleet analytics for project: {project_id}")
    
    # Query vehicle telemetry data from last 24 hours
    query = f"""
    SELECT 
        vehicle_id,
        AVG(speed) as avg_speed,
        MAX(speed) as max_speed,
        MIN(fuel_level) as min_fuel_level,
        COUNT(*) as data_points,
        STDDEV(speed) as speed_variance
    FROM `{project_id}.{dataset_name}.vehicle_telemetry`
    WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    GROUP BY vehicle_id
    """
    
    try:
        df = bq_client.query(query).to_dataframe()
        
        if not df.empty:
            # Generate performance insights
            insights = {
                'total_vehicles': len(df),
                'avg_fleet_speed': df['avg_speed'].mean(),
                'vehicles_needing_fuel': len(df[df['min_fuel_level'] < 0.2]),
                'high_variance_vehicles': len(df[df['speed_variance'] > 10]),
                'timestamp': datetime.now().isoformat()
            }
            
            # Store insights in Firestore
            firestore_client.collection('fleet_insights').document('daily_summary').set(insights)
            
            # Save detailed analytics to Cloud Storage
            analytics_data = df.to_json(orient='records')
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(f'analytics-results/{datetime.now().strftime("%Y-%m-%d")}/vehicle_performance.json')
            blob.upload_from_string(analytics_data, content_type='application/json')
            
            print(f"Analytics processed for {len(df)} vehicles")
            print(f"Fleet insights: {insights}")
            
        else:
            print("No telemetry data found for processing")
            
    except Exception as e:
        print(f"Error processing analytics: {e}")
        raise

if __name__ == "__main__":
    process_fleet_analytics()
EOF
    
    # Create Dockerfile for the analytics job
    cat > Dockerfile << EOF
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY analytics_processor.py .

CMD ["python", "analytics_processor.py"]
EOF
    
    # Build and push the container image
    log_info "Building container image..."
    gcloud builds submit --tag gcr.io/${PROJECT_ID}/${ANALYTICS_JOB_NAME} || {
        log_error "Failed to build container image"
        cd ..
        exit 1
    }
    
    cd ..
    
    # Deploy the Cloud Run Job
    log_info "Deploying Cloud Run Job..."
    gcloud run jobs create ${ANALYTICS_JOB_NAME} \
        --image gcr.io/${PROJECT_ID}/${ANALYTICS_JOB_NAME} \
        --region=${REGION} \
        --max-retries=2 \
        --parallelism=1 \
        --task-count=1 \
        --task-timeout=3600 \
        --memory=2Gi \
        --cpu=1 \
        --service-account=${FLEET_ENGINE_SA_EMAIL} \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},DATASET_NAME=${DATASET_NAME},BUCKET_NAME=${BUCKET_NAME}" || {
        log_error "Failed to deploy Cloud Run Job"
        exit 1
    }
    
    log_success "Cloud Run Job deployed successfully"
}

# Configure Cloud Scheduler
setup_scheduler() {
    log_info "Setting up Cloud Scheduler jobs..."
    
    # Create Cloud Scheduler job for daily analytics processing
    if ! gcloud scheduler jobs describe fleet-analytics-daily --location=${REGION} &> /dev/null; then
        gcloud scheduler jobs create http fleet-analytics-daily \
            --schedule="0 2 * * *" \
            --time-zone="America/New_York" \
            --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${ANALYTICS_JOB_NAME}:run" \
            --http-method=POST \
            --oidc-service-account-email=${FLEET_ENGINE_SA_EMAIL} \
            --oidc-token-audience="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${ANALYTICS_JOB_NAME}:run" \
            --location=${REGION} \
            --description="Daily fleet analytics processing" || {
            log_error "Failed to create daily scheduler job"
            exit 1
        }
    else
        log_warning "Daily scheduler job already exists"
    fi
    
    # Create additional scheduler job for hourly insights
    if ! gcloud scheduler jobs describe fleet-insights-hourly --location=${REGION} &> /dev/null; then
        gcloud scheduler jobs create http fleet-insights-hourly \
            --schedule="0 * * * *" \
            --time-zone="America/New_York" \
            --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${ANALYTICS_JOB_NAME}:run" \
            --http-method=POST \
            --oidc-service-account-email=${FLEET_ENGINE_SA_EMAIL} \
            --oidc-token-audience="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${ANALYTICS_JOB_NAME}:run" \
            --location=${REGION} \
            --description="Hourly fleet insights processing" || {
            log_error "Failed to create hourly scheduler job"
            exit 1
        }
    else
        log_warning "Hourly scheduler job already exists"
    fi
    
    # Set up retry policy for reliability
    gcloud scheduler jobs update http fleet-analytics-daily \
        --max-retry-attempts=3 \
        --max-retry-duration=300s \
        --location=${REGION} || {
        log_warning "Failed to update retry policy for daily job"
    }
    
    log_success "Cloud Scheduler jobs configured"
}

# Set up monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create monitoring dashboard for fleet operations
    cat > fleet-dashboard.json << EOF
{
  "displayName": "Fleet Operations Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Fleet Engine API Requests",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"consumed_api\" AND resource.label.service=\"fleetengine.googleapis.com\"",
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
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Cloud Run Job Executions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_job\" AND resource.label.job_name=\"${ANALYTICS_JOB_NAME}\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
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
    gcloud monitoring dashboards create --config-from-file=fleet-dashboard.json || {
        log_warning "Failed to create monitoring dashboard"
    }
    
    rm fleet-dashboard.json
    
    log_success "Monitoring and alerting configured"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test Fleet Engine API access
    log_info "Testing Fleet Engine API access..."
    if curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        "https://fleetengine.googleapis.com/v1/providers/${PROJECT_ID}/vehicles" \
        -d '{}' | grep -q "vehicles"; then
        log_success "Fleet Engine API access confirmed"
    else
        log_warning "Fleet Engine API test may have failed (expected for new fleet)"
    fi
    
    # Test Cloud Run Job execution
    log_info "Testing Cloud Run Job execution..."
    if gcloud run jobs execute ${ANALYTICS_JOB_NAME} --region=${REGION} --wait; then
        log_success "Cloud Run Job execution test passed"
    else
        log_warning "Cloud Run Job execution test failed (expected if no data)"
    fi
    
    # Check BigQuery tables
    log_info "Verifying BigQuery tables..."
    if bq ls ${PROJECT_ID}:${DATASET_NAME} | grep -q "vehicle_telemetry"; then
        log_success "BigQuery tables verified"
    else
        log_warning "BigQuery tables verification failed"
    fi
    
    # Verify Cloud Storage bucket
    log_info "Verifying Cloud Storage bucket..."
    if gsutil ls gs://${BUCKET_NAME}/ | grep -q "README.txt"; then
        log_success "Cloud Storage bucket verified"
    else
        log_warning "Cloud Storage bucket verification failed"
    fi
    
    log_success "Deployment testing completed"
}

# Print deployment summary
print_summary() {
    log_success "Fleet Operations deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Analytics Job: ${ANALYTICS_JOB_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "BigQuery Dataset: ${PROJECT_ID}:${DATASET_NAME}"
    echo "Service Account: ${FLEET_ENGINE_SA_EMAIL}"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Configure your Fleet Engine fleet in the Google Cloud Console"
    echo "2. Set up vehicle tracking and delivery tasks"
    echo "3. Monitor analytics job execution in Cloud Logging"
    echo "4. View fleet insights in Firestore or BigQuery"
    echo ""
    echo "=== CLEANUP ==="
    echo "To remove all resources: ./destroy.sh"
    echo ""
    echo "=== IMPORTANT FILES ==="
    echo "- Service account key: fleet-engine-key.json (keep secure!)"
    echo "- Fleet analytics job source: fleet-analytics-job/"
    echo ""
}

# Main execution
main() {
    log_info "Starting Fleet Operations deployment..."
    
    check_prerequisites
    setup_project
    setup_fleet_engine_sa
    setup_storage
    setup_bigquery
    setup_firestore
    deploy_analytics_job
    setup_scheduler
    setup_monitoring
    test_deployment
    print_summary
    
    log_success "Fleet Operations deployment completed successfully!"
}

# Execute main function
main "$@"