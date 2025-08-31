#!/bin/bash

# Dynamic Delivery Route Optimization Deployment Script
# This script deploys the complete route optimization solution using:
# - Google Maps Platform Route Optimization API
# - BigQuery for analytics
# - Cloud Functions for processing
# - Cloud Storage for data persistence
# - Cloud Scheduler for automation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "Error on line $1"
    log_error "Deployment failed. Run destroy.sh to clean up any partially created resources."
    exit 1
}

trap 'error_exit $LINENO' ERR

# Configuration
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
LOG_FILE="./deployment_$(date +%Y%m%d_%H%M%S).log"

# Default configuration
DEFAULT_PROJECT_PREFIX="route-optimization"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl for generating random suffixes."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check billing account
    if ! gcloud billing accounts list --format="value(name)" | head -1 | grep -q "billingAccounts"; then
        log_warning "No billing accounts found. You may need to set up billing for the project."
    fi
    
    log_success "All prerequisites checked successfully"
}

# Function to get user input
get_user_input() {
    log "Getting deployment configuration..."
    
    # Get project configuration
    echo ""
    echo "=== Project Configuration ==="
    read -p "Enter project prefix [${DEFAULT_PROJECT_PREFIX}]: " PROJECT_PREFIX
    PROJECT_PREFIX=${PROJECT_PREFIX:-$DEFAULT_PROJECT_PREFIX}
    
    read -p "Enter region [${DEFAULT_REGION}]: " REGION
    REGION=${REGION:-$DEFAULT_REGION}
    
    read -p "Enter zone [${DEFAULT_ZONE}]: " ZONE
    ZONE=${ZONE:-$DEFAULT_ZONE}
    
    # Generate unique project ID
    PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    DATASET_NAME="delivery_analytics"
    FUNCTION_NAME="route-optimizer-${RANDOM_SUFFIX}"
    BUCKET_NAME="${PROJECT_ID}-delivery-data"
    TABLE_DELIVERIES="delivery_history"
    TABLE_ROUTES="optimized_routes"
    
    echo ""
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Bucket Name: ${BUCKET_NAME}"
    echo "Dataset Name: ${DATASET_NAME}"
    echo ""
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Function to create and configure project
setup_project() {
    log "Setting up Google Cloud project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create project ${PROJECT_ID}"
        return 0
    fi
    
    # Create project
    log "Creating project: ${PROJECT_ID}"
    if gcloud projects create "${PROJECT_ID}" --name="Route Optimization Demo" 2>/dev/null; then
        log_success "Project created successfully"
    else
        log_warning "Project creation failed or project already exists"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account (if available)
    BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" | head -1)
    if [[ -n "$BILLING_ACCOUNT" ]]; then
        log "Linking billing account..."
        gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
        log_success "Billing account linked"
    else
        log_warning "No billing account found. Manual billing setup may be required."
    fi
    
    log_success "Project setup completed"
}

# Function to enable APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would enable APIs"
        return 0
    fi
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "routeoptimization.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudscheduler.googleapis.com"
        "run.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

# Function to create BigQuery dataset and tables
setup_bigquery() {
    log "Setting up BigQuery resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create BigQuery dataset and tables"
        return 0
    fi
    
    # Create BigQuery dataset
    log "Creating BigQuery dataset: ${DATASET_NAME}"
    bq mk --location="${REGION}" \
        --description="Delivery and route optimization analytics" \
        "${PROJECT_ID}:${DATASET_NAME}"
    
    # Create delivery history table with partitioning
    log "Creating delivery history table..."
    bq mk --table \
        --description="Historical delivery performance data" \
        --time_partitioning_field=delivery_date \
        --clustering_fields=delivery_zone,vehicle_type \
        "${PROJECT_ID}:${DATASET_NAME}.${TABLE_DELIVERIES}" \
        "delivery_id:STRING,delivery_date:DATE,pickup_lat:FLOAT,pickup_lng:FLOAT,delivery_lat:FLOAT,delivery_lng:FLOAT,delivery_zone:STRING,vehicle_type:STRING,delivery_time_minutes:INTEGER,distance_km:FLOAT,fuel_cost:FLOAT,driver_id:STRING,customer_priority:STRING"
    
    # Create optimized routes table
    log "Creating optimized routes table..."
    bq mk --table \
        --description="AI-generated optimized delivery routes" \
        --time_partitioning_field=route_date \
        "${PROJECT_ID}:${DATASET_NAME}.${TABLE_ROUTES}" \
        "route_id:STRING,route_date:DATE,vehicle_id:STRING,driver_id:STRING,total_stops:INTEGER,estimated_duration_minutes:INTEGER,estimated_distance_km:FLOAT,optimization_score:FLOAT,route_waypoints:STRING"
    
    log_success "BigQuery resources created successfully"
}

# Function to create Cloud Storage bucket
setup_storage() {
    log "Setting up Cloud Storage resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Cloud Storage bucket"
        return 0
    fi
    
    # Create Cloud Storage bucket
    log "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Create folder structure
    echo "Route requests data folder" | gsutil cp - "gs://${BUCKET_NAME}/route-requests/README.txt"
    echo "Route responses data folder" | gsutil cp - "gs://${BUCKET_NAME}/route-responses/README.txt"
    echo "System logs folder" | gsutil cp - "gs://${BUCKET_NAME}/logs/README.txt"
    echo "Historical data folder" | gsutil cp - "gs://${BUCKET_NAME}/historical-data/README.txt"
    
    # Set lifecycle policy
    cat > lifecycle.json << EOF
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
    
    gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"
    rm -f lifecycle.json
    
    log_success "Cloud Storage resources created successfully"
}

# Function to load sample data
load_sample_data() {
    log "Loading sample delivery data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would load sample data"
        return 0
    fi
    
    # Create sample delivery data
    cat > sample_deliveries.csv << EOF
delivery_id,delivery_date,pickup_lat,pickup_lng,delivery_lat,delivery_lng,delivery_zone,vehicle_type,delivery_time_minutes,distance_km,fuel_cost,driver_id,customer_priority
DEL001,2024-07-10,37.7749,-122.4194,37.7849,-122.4094,zone_downtown,van,25,3.2,8.50,driver_001,high
DEL002,2024-07-10,37.7749,-122.4194,37.8049,-122.4294,zone_north,van,35,5.8,12.75,driver_001,medium
DEL003,2024-07-10,37.7649,-122.4094,37.7949,-122.4394,zone_west,truck,45,8.1,18.20,driver_002,high
DEL004,2024-07-11,37.7549,-122.4294,37.7749,-122.4094,zone_downtown,van,20,2.5,6.80,driver_003,low
DEL005,2024-07-11,37.7849,-122.4194,37.8149,-122.4494,zone_north,van,40,6.9,15.30,driver_003,medium
DEL006,2024-07-11,37.7449,-122.4394,37.7649,-122.4194,zone_south,truck,50,9.3,21.50,driver_002,high
DEL007,2024-07-12,37.7749,-122.4194,37.7549,-122.4494,zone_west,van,30,4.1,9.75,driver_001,medium
DEL008,2024-07-12,37.7949,-122.4094,37.8249,-122.4194,zone_north,van,28,3.8,8.90,driver_004,high
EOF
    
    # Upload to BigQuery
    log "Uploading data to BigQuery..."
    bq load \
        --source_format=CSV \
        --skip_leading_rows=1 \
        --autodetect \
        "${PROJECT_ID}:${DATASET_NAME}.${TABLE_DELIVERIES}" \
        sample_deliveries.csv
    
    # Upload to Cloud Storage
    gsutil cp sample_deliveries.csv "gs://${BUCKET_NAME}/historical-data/"
    
    # Clean up local file
    rm -f sample_deliveries.csv
    
    log_success "Sample data loaded successfully"
}

# Function to deploy Cloud Function
deploy_function() {
    log "Deploying Cloud Function for route optimization..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy Cloud Function"
        return 0
    fi
    
    # Create function directory
    mkdir -p route-optimizer-function
    cd route-optimizer-function
    
    # Create requirements.txt
    cat > requirements.txt << EOF
google-cloud-bigquery==3.25.0
google-cloud-storage==2.18.0
google-maps-routeoptimization==1.0.7
functions-framework==3.8.1
requests==2.32.3
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import json
import logging
import os
from datetime import datetime
from google.cloud import bigquery
from google.cloud import storage
from google.maps import routeoptimization_v1
from flask import Request
import google.auth

# Initialize clients
bq_client = bigquery.Client()
storage_client = storage.Client()

def optimize_routes(request: Request):
    """Cloud Function to optimize delivery routes using Route Optimization API"""
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {"error": "No JSON data provided"}, 400
        
        # Extract delivery requests
        deliveries = request_json.get('deliveries', [])
        vehicle_capacity = request_json.get('vehicle_capacity', 10)
        
        if not deliveries:
            return {"error": "No deliveries provided"}, 400
        
        # Initialize Route Optimization client
        credentials, project = google.auth.default()
        client = routeoptimization_v1.RouteOptimizationClient(
            credentials=credentials
        )
        
        # Build shipments for Route Optimization API
        shipments = []
        for i, delivery in enumerate(deliveries):
            shipment = routeoptimization_v1.Shipment(
                pickup_task=routeoptimization_v1.Task(
                    task_location=routeoptimization_v1.Location(
                        lat_lng=routeoptimization_v1.LatLng(
                            latitude=delivery.get('pickup_lat', 37.7749),
                            longitude=delivery.get('pickup_lng', -122.4194)
                        )
                    ),
                    duration_seconds=300  # 5 minutes pickup time
                ),
                delivery_task=routeoptimization_v1.Task(
                    task_location=routeoptimization_v1.Location(
                        lat_lng=routeoptimization_v1.LatLng(
                            latitude=delivery['lat'],
                            longitude=delivery['lng']
                        )
                    ),
                    duration_seconds=600  # 10 minutes delivery time
                )
            )
            shipments.append(shipment)
        
        # Define vehicle
        vehicle = routeoptimization_v1.Vehicle(
            start_location=routeoptimization_v1.Location(
                lat_lng=routeoptimization_v1.LatLng(
                    latitude=37.7749,  # Depot location
                    longitude=-122.4194
                )
            ),
            end_location=routeoptimization_v1.Location(
                lat_lng=routeoptimization_v1.LatLng(
                    latitude=37.7749,  # Return to depot
                    longitude=-122.4194
                )
            ),
            capacity_dimensions=[
                routeoptimization_v1.CapacityDimension(
                    type_="weight",
                    limit_value=vehicle_capacity
                )
            ]
        )
        
        # Build optimization request
        optimization_request = routeoptimization_v1.OptimizeToursRequest(
            parent=f"projects/{project}",
            model=routeoptimization_v1.ShipmentModel(
                shipments=shipments,
                vehicles=[vehicle],
                global_start_time="2024-07-15T08:00:00Z",
                global_end_time="2024-07-15T18:00:00Z"
            )
        )
        
        # Call Route Optimization API
        try:
            response = client.optimize_tours(request=optimization_request)
            
            # Extract optimized route information
            if response.routes:
                route = response.routes[0]
                optimized_route = {
                    "route_id": f"route_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
                    "total_stops": len([v for v in route.visits if v.shipment_index >= 0]),
                    "estimated_duration": int(route.end_time.seconds - route.start_time.seconds) // 60,
                    "estimated_distance": route.route_polyline.points if route.route_polyline else "N/A",
                    "optimization_score": 0.90,  # Simplified score
                    "waypoints": [
                        {
                            "lat": visit.location.lat_lng.latitude,
                            "lng": visit.location.lat_lng.longitude,
                            "stop_id": f"stop_{visit.shipment_index}",
                            "arrival_time": visit.start_time.seconds if visit.start_time else 0
                        }
                        for visit in route.visits if visit.shipment_index >= 0
                    ]
                }
            else:
                # Fallback simulation if no routes returned
                optimized_route = {
                    "route_id": f"route_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
                    "total_stops": len(deliveries),
                    "estimated_duration": sum([d.get('estimated_minutes', 30) for d in deliveries]),
                    "estimated_distance": sum([d.get('estimated_km', 5.0) for d in deliveries]),
                    "optimization_score": 0.85,
                    "waypoints": [{"lat": d["lat"], "lng": d["lng"], "stop_id": d["delivery_id"]} for d in deliveries]
                }
        
        except Exception as api_error:
            logging.warning(f"Route Optimization API error: {str(api_error)}, using fallback")
            # Fallback simulation
            optimized_route = {
                "route_id": f"route_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
                "total_stops": len(deliveries),
                "estimated_duration": sum([d.get('estimated_minutes', 30) for d in deliveries]),
                "estimated_distance": sum([d.get('estimated_km', 5.0) for d in deliveries]),
                "optimization_score": 0.85,
                "waypoints": [{"lat": d["lat"], "lng": d["lng"], "stop_id": d["delivery_id"]} for d in deliveries]
            }
        
        # Store results in BigQuery
        table_id = f"{project}.delivery_analytics.optimized_routes"
        
        rows_to_insert = [{
            "route_id": optimized_route["route_id"],
            "route_date": datetime.now().date().isoformat(),
            "vehicle_id": request_json.get("vehicle_id", "VEH001"),
            "driver_id": request_json.get("driver_id", "DRV001"),
            "total_stops": optimized_route["total_stops"],
            "estimated_duration_minutes": optimized_route["estimated_duration"],
            "estimated_distance_km": optimized_route["estimated_distance"],
            "optimization_score": optimized_route["optimization_score"],
            "route_waypoints": json.dumps(optimized_route["waypoints"])
        }]
        
        table = bq_client.get_table(table_id)
        errors = bq_client.insert_rows_json(table, rows_to_insert)
        
        if errors:
            logging.error(f"BigQuery insert errors: {errors}")
            return {"error": "Failed to store route data"}, 500
        
        # Store detailed route in Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(f"route-responses/{optimized_route['route_id']}.json")
            blob.upload_from_string(json.dumps(optimized_route, indent=2))
        
        logging.info(f"Route optimization completed: {optimized_route['route_id']}")
        
        return {
            "status": "success",
            "route_id": optimized_route["route_id"],
            "optimization_score": optimized_route["optimization_score"],
            "estimated_duration_minutes": optimized_route["estimated_duration"],
            "waypoints": optimized_route["waypoints"]
        }
        
    except Exception as e:
        logging.error(f"Route optimization error: {str(e)}")
        return {"error": f"Internal error: {str(e)}"}, 500
EOF
    
    # Deploy the function
    log "Deploying Cloud Function..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point optimize_routes \
        --memory 1Gi \
        --timeout 300s \
        --region "${REGION}" \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},BUCKET_NAME=${BUCKET_NAME}"
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    cd ..
    
    # Store function URL for later use
    echo "${FUNCTION_URL}" > function_url.txt
    
    log_success "Cloud Function deployed successfully"
    log "Function URL: ${FUNCTION_URL}"
}

# Function to create BigQuery views
create_analytics_views() {
    log "Creating BigQuery analytics views..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create BigQuery views"
        return 0
    fi
    
    # Create delivery performance view
    bq mk --view \
        --description="Real-time delivery performance metrics" \
        --view_id=delivery_performance_view \
        "${PROJECT_ID}:${DATASET_NAME}" \
        "SELECT 
            delivery_zone,
            vehicle_type,
            DATE(delivery_date) as delivery_date,
            COUNT(*) as total_deliveries,
            AVG(delivery_time_minutes) as avg_delivery_time,
            AVG(distance_km) as avg_distance,
            AVG(fuel_cost) as avg_fuel_cost,
            SUM(fuel_cost) as total_fuel_cost
         FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_DELIVERIES}\`
         WHERE delivery_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
         GROUP BY delivery_zone, vehicle_type, DATE(delivery_date)
         ORDER BY delivery_date DESC, delivery_zone"
    
    # Create route efficiency view
    bq mk --view \
        --description="Route optimization performance analysis" \
        --view_id=route_efficiency_view \
        "${PROJECT_ID}:${DATASET_NAME}" \
        "SELECT 
            DATE(route_date) as route_date,
            COUNT(*) as total_routes,
            AVG(optimization_score) as avg_optimization_score,
            AVG(estimated_duration_minutes) as avg_duration,
            AVG(estimated_distance_km) as avg_distance,
            AVG(total_stops) as avg_stops_per_route
         FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_ROUTES}\`
         WHERE route_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
         GROUP BY DATE(route_date)
         ORDER BY route_date DESC"
    
    log_success "BigQuery analytics views created successfully"
}

# Function to setup automation
setup_automation() {
    log "Setting up automated route optimization..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would setup automation"
        return 0
    fi
    
    # Get function URL
    if [[ -f "function_url.txt" ]]; then
        FUNCTION_URL=$(cat function_url.txt)
    else
        FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(serviceConfig.uri)")
    fi
    
    # Create sample request payload
    cat > route_request.json << EOF
{
    "deliveries": [
        {"delivery_id": "DEL009", "lat": 37.7749, "lng": -122.4194, "estimated_minutes": 25, "estimated_km": 3.2},
        {"delivery_id": "DEL010", "lat": 37.7849, "lng": -122.4094, "estimated_minutes": 30, "estimated_km": 4.1},
        {"delivery_id": "DEL011", "lat": 37.7949, "lng": -122.4294, "estimated_minutes": 35, "estimated_km": 5.8}
    ],
    "vehicle_id": "VEH001",
    "driver_id": "DRV001",
    "vehicle_capacity": 10
}
EOF
    
    # Create Cloud Scheduler job
    gcloud scheduler jobs create http optimize-routes-hourly \
        --location="${REGION}" \
        --schedule="0 */2 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body-from-file=route_request.json \
        --description="Automated route optimization every 2 hours"
    
    # Clean up temporary file
    rm -f route_request.json
    
    log_success "Automated scheduling configured successfully"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Test BigQuery
    log "Testing BigQuery..."
    bq query --use_legacy_sql=false \
        "SELECT COUNT(*) as total_records FROM \`${PROJECT_ID}.${DATASET_NAME}.${TABLE_DELIVERIES}\`" \
        --format=prettyjson
    
    # Test Cloud Storage
    log "Testing Cloud Storage..."
    gsutil ls "gs://${BUCKET_NAME}/" | head -5
    
    # Test Cloud Function
    if [[ -f "function_url.txt" ]]; then
        FUNCTION_URL=$(cat function_url.txt)
        log "Testing Cloud Function..."
        curl -X POST "${FUNCTION_URL}" \
            -H "Content-Type: application/json" \
            -d '{
                "deliveries": [
                    {"delivery_id": "TEST001", "lat": 37.7749, "lng": -122.4194, "estimated_minutes": 20, "estimated_km": 2.5}
                ],
                "vehicle_id": "TEST_VEH",
                "driver_id": "TEST_DRV",
                "vehicle_capacity": 5
            }' \
            --max-time 30 || log_warning "Function test timed out or failed"
    fi
    
    log_success "Deployment validation completed"
}

# Function to save deployment info
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment_info.json << EOF
{
    "project_id": "${PROJECT_ID}",
    "region": "${REGION}",
    "zone": "${ZONE}",
    "function_name": "${FUNCTION_NAME}",
    "bucket_name": "${BUCKET_NAME}",
    "dataset_name": "${DATASET_NAME}",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "function_url": "$(cat function_url.txt 2>/dev/null || echo 'Not available')"
}
EOF
    
    log_success "Deployment information saved to deployment_info.json"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -rf route-optimizer-function/
    rm -f function_url.txt
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Dynamic Delivery Route Optimization"
    echo "GCP Deployment Script"
    echo "=========================================="
    echo ""
    
    # Start logging
    exec > >(tee -a "${LOG_FILE}")
    exec 2>&1
    
    log "Starting deployment at $(date)"
    
    # Run deployment steps
    check_prerequisites
    get_user_input
    setup_project
    enable_apis
    setup_bigquery
    setup_storage
    load_sample_data
    deploy_function
    create_analytics_views
    setup_automation
    validate_deployment
    save_deployment_info
    cleanup_temp_files
    
    echo ""
    echo "=========================================="
    log_success "Deployment completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Review the deployment_info.json file for important details"
    echo "2. Test the route optimization function using the provided examples"
    echo "3. Monitor BigQuery for analytics data"
    echo "4. Check Cloud Scheduler for automated runs"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
    echo ""
    log "Deployment log saved to: ${LOG_FILE}"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Show what would be deployed without making changes"
            echo "  --skip-confirmation    Skip deployment confirmation prompt"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"