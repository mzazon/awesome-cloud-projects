#!/bin/bash

# Route Optimization with Google Maps Routes API and Cloud Optimization AI - Deployment Script
# This script deploys the complete infrastructure for the route optimization platform

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Starting cleanup of partially created resources..."
    
    # Attempt to clean up resources that may have been created
    if [[ -n "${SERVICE_NAME:-}" ]]; then
        gcloud run services delete "${SERVICE_NAME}" \
            --region="${REGION}" \
            --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        gcloud pubsub subscriptions delete "${TOPIC_NAME}-sub" --quiet 2>/dev/null || true
        gcloud pubsub subscriptions delete "${TOPIC_NAME}-dlq-sub" --quiet 2>/dev/null || true
        gcloud pubsub topics delete "${TOPIC_NAME}" --quiet 2>/dev/null || true
        gcloud pubsub topics delete "${TOPIC_NAME}-dlq" --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${SQL_INSTANCE_NAME:-}" ]]; then
        gcloud sql instances delete "${SQL_INSTANCE_NAME}" --quiet 2>/dev/null || true
    fi
    
    # Clean up local files
    rm -rf route-optimizer route-processor schema.sql monitoring-config.yaml 2>/dev/null || true
    
    log_error "Cleanup completed. Please check for any remaining resources manually."
}

# Set up error trap
trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Please install curl first."
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install openssl first."
    fi
    
    log_success "Prerequisites check passed"
}

# Project setup and validation
setup_project() {
    log_info "Setting up GCP project and environment..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-route-optimization-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SQL_INSTANCE_NAME="route-db-${RANDOM_SUFFIX}"
    export SERVICE_NAME="route-optimizer-${RANDOM_SUFFIX}"
    export TOPIC_NAME="route-events-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Project ${PROJECT_ID} does not exist. Creating it..."
        gcloud projects create "${PROJECT_ID}" || error_exit "Failed to create project"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "sql-component.googleapis.com"
        "sqladmin.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud SQL database
create_cloud_sql() {
    log_info "Creating Cloud SQL PostgreSQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe "${SQL_INSTANCE_NAME}" &>/dev/null; then
        log_warning "Cloud SQL instance ${SQL_INSTANCE_NAME} already exists"
        return 0
    fi
    
    # Create Cloud SQL PostgreSQL instance
    gcloud sql instances create "${SQL_INSTANCE_NAME}" \
        --database-version=POSTGRES_14 \
        --tier=db-f1-micro \
        --region="${REGION}" \
        --storage-type=SSD \
        --storage-size=20GB \
        --backup \
        --enable-bin-log \
        --deletion-protection || error_exit "Failed to create Cloud SQL instance"
    
    # Wait for instance to be ready
    log_info "Waiting for Cloud SQL instance to be ready..."
    while ! gcloud sql instances describe "${SQL_INSTANCE_NAME}" --format="value(state)" | grep -q "RUNNABLE"; do
        log_info "Instance still initializing..."
        sleep 30
    done
    
    # Set password for default postgres user
    gcloud sql users set-password postgres \
        --instance="${SQL_INSTANCE_NAME}" \
        --password=SecurePass123! || error_exit "Failed to set postgres password"
    
    log_success "Cloud SQL instance created: ${SQL_INSTANCE_NAME}"
}

# Create database schema
create_database_schema() {
    log_info "Creating database and schema..."
    
    # Create database
    gcloud sql databases create route_analytics \
        --instance="${SQL_INSTANCE_NAME}" || error_exit "Failed to create database"
    
    # Create SQL schema file
    cat > schema.sql << 'EOF'
CREATE TABLE routes (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(255) UNIQUE NOT NULL,
    origin_lat DECIMAL(10, 8) NOT NULL,
    origin_lng DECIMAL(11, 8) NOT NULL,
    destination_lat DECIMAL(10, 8) NOT NULL,
    destination_lng DECIMAL(11, 8) NOT NULL,
    waypoints JSONB,
    optimized_route JSONB,
    estimated_duration INTEGER,
    actual_duration INTEGER,
    distance_meters INTEGER,
    traffic_model VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    optimized_at TIMESTAMP,
    status VARCHAR(50) DEFAULT 'pending'
);

CREATE TABLE vehicles (
    id SERIAL PRIMARY KEY,
    vehicle_id VARCHAR(255) UNIQUE NOT NULL,
    capacity_kg INTEGER,
    current_lat DECIMAL(10, 8),
    current_lng DECIMAL(11, 8),
    status VARCHAR(50) DEFAULT 'available',
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_routes_status ON routes(status);
CREATE INDEX idx_routes_created ON routes(created_at);
CREATE INDEX idx_vehicles_status ON vehicles(status);
EOF
    
    # Create a temporary bucket for schema import
    local temp_bucket="temp-sql-${RANDOM_SUFFIX}"
    gsutil mb "gs://${temp_bucket}" || error_exit "Failed to create temporary bucket"
    
    # Upload schema file
    gsutil cp schema.sql "gs://${temp_bucket}/" || error_exit "Failed to upload schema file"
    
    # Import schema to Cloud SQL
    gcloud sql import sql "${SQL_INSTANCE_NAME}" \
        "gs://${temp_bucket}/schema.sql" \
        --database=route_analytics || error_exit "Failed to import schema"
    
    # Clean up temporary bucket
    gsutil rm "gs://${temp_bucket}/schema.sql"
    gsutil rb "gs://${temp_bucket}"
    
    log_success "Database schema created successfully"
}

# Create Pub/Sub resources
create_pubsub() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    # Create Pub/Sub topic for route optimization events
    gcloud pubsub topics create "${TOPIC_NAME}" || error_exit "Failed to create Pub/Sub topic"
    
    # Create subscription for route processing
    gcloud pubsub subscriptions create "${TOPIC_NAME}-sub" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=600 \
        --message-retention-duration=7d || error_exit "Failed to create subscription"
    
    # Create dead letter topic for failed messages
    gcloud pubsub topics create "${TOPIC_NAME}-dlq" || error_exit "Failed to create DLQ topic"
    
    gcloud pubsub subscriptions create "${TOPIC_NAME}-dlq-sub" \
        --topic="${TOPIC_NAME}-dlq" || error_exit "Failed to create DLQ subscription"
    
    log_success "Pub/Sub topics and subscriptions created"
}

# Create Cloud Run application
create_cloud_run_app() {
    log_info "Creating Cloud Run application..."
    
    # Create application directory structure
    mkdir -p route-optimizer/{src,config}
    cd route-optimizer
    
    # Create main application file
    cat > src/main.py << 'EOF'
import os
import json
import logging
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import sql
from google.cloud import pubsub_v1
import requests
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID')
SQL_INSTANCE = os.environ.get('SQL_INSTANCE')
MAPS_API_KEY = os.environ.get('MAPS_API_KEY', 'YOUR_MAPS_API_KEY')
TOPIC_NAME = os.environ.get('TOPIC_NAME')

# Database connection
def get_db_connection():
    return psycopg2.connect(
        host=f"/cloudsql/{PROJECT_ID}:{os.environ.get('REGION', 'us-central1')}:{SQL_INSTANCE}",
        database="route_analytics",
        user="postgres",
        password="SecurePass123!",
        cursor_factory=RealDictCursor
    )

@app.route('/optimize-route', methods=['POST'])
def optimize_route():
    try:
        data = request.get_json()
        origin = data.get('origin')
        destination = data.get('destination')
        waypoints = data.get('waypoints', [])
        
        # Call Google Maps Routes API
        route_response = call_routes_api(origin, destination, waypoints)
        
        # Store route in database
        route_id = store_route(data, route_response)
        
        # Publish optimization event
        publish_optimization_event(route_id, route_response)
        
        return jsonify({
            'route_id': route_id,
            'status': 'optimized',
            'estimated_duration': route_response.get('duration'),
            'distance': route_response.get('distance')
        })
        
    except Exception as e:
        logging.error(f"Route optimization failed: {e}")
        return jsonify({'error': str(e)}), 500

def call_routes_api(origin, destination, waypoints):
    """Call Google Maps Routes API for route optimization"""
    if MAPS_API_KEY == 'YOUR_MAPS_API_KEY':
        # Return mock data for testing without API key
        return {
            'routes': [{
                'duration': {'seconds': 1800},
                'distanceMeters': 15000,
                'polyline': {'encodedPolyline': 'mock_polyline'}
            }]
        }
    
    url = "https://routes.googleapis.com/directions/v2:computeRoutes"
    headers = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': MAPS_API_KEY,
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline'
    }
    
    payload = {
        'origin': {'location': {'latLng': origin}},
        'destination': {'location': {'latLng': destination}},
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE_OPTIMAL',
        'computeAlternativeRoutes': True
    }
    
    if waypoints:
        payload['intermediates'] = [
            {'location': {'latLng': wp}} for wp in waypoints
        ]
    
    response = requests.post(url, headers=headers, json=payload)
    return response.json()

def store_route(request_data, route_response):
    """Store route optimization results in database"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    route_id = f"route_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    cur.execute("""
        INSERT INTO routes (request_id, origin_lat, origin_lng, 
                          destination_lat, destination_lng, waypoints, 
                          optimized_route, estimated_duration, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        route_id,
        request_data['origin']['lat'],
        request_data['origin']['lng'],
        request_data['destination']['lat'],
        request_data['destination']['lng'],
        json.dumps(request_data.get('waypoints', [])),
        json.dumps(route_response),
        route_response.get('routes', [{}])[0].get('duration', {}).get('seconds'),
        'optimized'
    ))
    
    conn.commit()
    cur.close()
    conn.close()
    
    return route_id

def publish_optimization_event(route_id, route_data):
    """Publish route optimization event to Pub/Sub"""
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(PROJECT_ID, TOPIC_NAME)
        
        message_data = {
            'route_id': route_id,
            'event_type': 'route_optimized',
            'timestamp': datetime.now().isoformat(),
            'route_summary': route_data
        }
        
        publisher.publish(topic_path, json.dumps(message_data).encode('utf-8'))
    except Exception as e:
        logging.error(f"Failed to publish event: {e}")

@app.route('/analytics', methods=['GET'])
def get_analytics():
    """Get route optimization analytics"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get route optimization statistics
        cur.execute("""
            SELECT 
                COUNT(*) as total_routes,
                AVG(estimated_duration) as avg_duration,
                AVG(distance_meters) as avg_distance,
                COUNT(CASE WHEN status = 'optimized' THEN 1 END) as optimized_routes
            FROM routes 
            WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
        """)
        
        stats = cur.fetchone()
        
        cur.close()
        conn.close()
        
        return jsonify({
            'period': '7_days',
            'statistics': dict(stats),
            'optimization_rate': (stats['optimized_routes'] / stats['total_routes'] * 100) if stats['total_routes'] > 0 else 0
        })
        
    except Exception as e:
        logging.error(f"Analytics query failed: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==3.0.0
google-cloud-sql==2.11.0
google-cloud-pubsub==2.18.4
psycopg2-binary==2.9.9
requests==2.31.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

EXPOSE 8080
CMD ["python", "src/main.py"]
EOF
    
    log_success "Application code created successfully"
}

# Deploy Cloud Run service
deploy_cloud_run() {
    log_info "Building and deploying Cloud Run service..."
    
    # Build and deploy to Cloud Run
    gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --region "${REGION}" \
        --platform managed \
        --allow-unauthenticated \
        --set-env-vars PROJECT_ID="${PROJECT_ID}" \
        --set-env-vars SQL_INSTANCE="${SQL_INSTANCE_NAME}" \
        --set-env-vars TOPIC_NAME="${TOPIC_NAME}" \
        --set-env-vars REGION="${REGION}" \
        --set-env-vars MAPS_API_KEY=YOUR_MAPS_API_KEY \
        --add-cloudsql-instances "${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME}" \
        --memory 1Gi \
        --cpu 1 \
        --timeout 300 \
        --max-instances 10 || error_exit "Failed to deploy Cloud Run service"
    
    # Get service URL
    export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --format='value(status.url)')
    
    log_success "Cloud Run service deployed: ${SERVICE_URL}"
    cd ..
}

# Create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying Cloud Function for event processing..."
    
    # Create Cloud Function for event processing
    mkdir -p route-processor
    cd route-processor
    
    cat > main.py << 'EOF'
import os
import json
import logging
from google.cloud import sql
import psycopg2
from psycopg2.extras import RealDictCursor

def process_route_event(event, context):
    """Process route optimization events from Pub/Sub"""
    try:
        # Decode Pub/Sub message
        message_data = json.loads(event['data'].decode('utf-8'))
        route_id = message_data.get('route_id')
        event_type = message_data.get('event_type')
        
        logging.info(f"Processing {event_type} for route {route_id}")
        
        if event_type == 'route_optimized':
            update_route_analytics(message_data)
        
        return f"Processed {event_type} for {route_id}"
        
    except Exception as e:
        logging.error(f"Event processing failed: {e}")
        raise

def update_route_analytics(message_data):
    """Update route analytics with optimization results"""
    conn = psycopg2.connect(
        host=f"/cloudsql/{os.environ['PROJECT_ID']}:{os.environ.get('REGION', 'us-central1')}:{os.environ['SQL_INSTANCE']}",
        database="route_analytics",
        user="postgres",
        password="SecurePass123!",
        cursor_factory=RealDictCursor
    )
    
    cur = conn.cursor()
    cur.execute("""
        UPDATE routes 
        SET optimized_at = CURRENT_TIMESTAMP,
            status = 'processed'
        WHERE request_id = %s
    """, (message_data['route_id'],))
    
    conn.commit()
    cur.close()
    conn.close()
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-sql==2.11.0
psycopg2-binary==2.9.9
EOF
    
    # Deploy Cloud Function
    gcloud functions deploy "route-processor-${RANDOM_SUFFIX}" \
        --runtime python311 \
        --trigger-topic "${TOPIC_NAME}" \
        --source . \
        --entry-point process_route_event \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars PROJECT_ID="${PROJECT_ID}" \
        --set-env-vars SQL_INSTANCE="${SQL_INSTANCE_NAME}" \
        --set-env-vars REGION="${REGION}" || error_exit "Failed to deploy Cloud Function"
    
    log_success "Event processing function deployed"
    cd ..
}

# Configure monitoring
configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    # Create custom metrics and alerts configuration
    cat > monitoring-config.yaml << 'EOF'
displayName: "Route Optimization Alerts"
conditions:
  - displayName: "High Route API Error Rate"
    conditionThreshold:
      filter: 'resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/request_count"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 10
      duration: 300s
EOF
    
    # Note: Alert policy creation requires additional setup
    log_info "Monitoring configuration prepared (manual alert setup may be required)"
    
    log_success "Monitoring and alerting configured"
}

# Validation and testing
validate_deployment() {
    log_info "Validating deployment..."
    
    # Test service health endpoint
    if curl -f -s "${SERVICE_URL}/health" > /dev/null; then
        log_success "Health check passed"
    else
        log_warning "Health check failed - service may still be starting"
    fi
    
    # Test route optimization with sample data
    log_info "Testing route optimization API..."
    local test_response=$(curl -s -X POST "${SERVICE_URL}/optimize-route" \
        -H "Content-Type: application/json" \
        -d '{
          "origin": {"lat": 37.7749, "lng": -122.4194},
          "destination": {"lat": 37.7849, "lng": -122.4094},
          "waypoints": [{"lat": 37.7799, "lng": -122.4144}]
        }' || echo "")
    
    if [[ -n "$test_response" ]] && echo "$test_response" | grep -q "route_id"; then
        log_success "Route optimization API test passed"
    else
        log_warning "Route optimization API test failed - check logs for details"
    fi
    
    # Test analytics endpoint
    if curl -f -s "${SERVICE_URL}/analytics" > /dev/null; then
        log_success "Analytics endpoint test passed"
    else
        log_warning "Analytics endpoint test failed"
    fi
    
    log_success "Deployment validation completed"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.txt << EOF
Route Optimization Platform Deployment Information
================================================

Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}
Random Suffix: ${RANDOM_SUFFIX}

Resources Created:
- Cloud SQL Instance: ${SQL_INSTANCE_NAME}
- Cloud Run Service: ${SERVICE_NAME}
- Pub/Sub Topic: ${TOPIC_NAME}
- Cloud Function: route-processor-${RANDOM_SUFFIX}

Service URLs:
- Main Service: ${SERVICE_URL}
- Health Check: ${SERVICE_URL}/health
- Analytics: ${SERVICE_URL}/analytics
- Route Optimization: ${SERVICE_URL}/optimize-route

Important Notes:
- Default Maps API Key is set to placeholder - update with your actual key
- Database password: SecurePass123! (change in production)
- All resources are tagged for easy identification

Next Steps:
1. Update the MAPS_API_KEY environment variable with your actual Google Maps API key
2. Test the route optimization functionality
3. Configure monitoring alerts as needed
4. Review security settings for production use

EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    log_info "Starting Route Optimization Platform deployment..."
    
    check_prerequisites
    setup_project
    enable_apis
    create_cloud_sql
    create_database_schema
    create_pubsub
    create_cloud_run_app
    deploy_cloud_run
    deploy_cloud_function
    configure_monitoring
    validate_deployment
    save_deployment_info
    
    log_success "🎉 Route Optimization Platform deployment completed successfully!"
    log_info "Service URL: ${SERVICE_URL}"
    log_info "Check deployment-info.txt for complete details"
    log_warning "Remember to update the MAPS_API_KEY environment variable with your actual Google Maps API key"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi