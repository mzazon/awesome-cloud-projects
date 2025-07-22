#!/bin/bash

# Deploy script for AlloyDB AI Performance Automation Recipe
# This script deploys the complete infrastructure for automated database performance optimization
# with AlloyDB AI, Cloud Monitoring, Vertex AI, and Cloud Functions

set -euo pipefail

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    ./destroy.sh --force-cleanup || true
    exit 1
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "0.0.0")
    REQUIRED_VERSION="450.0.0"
    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$GCLOUD_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
        log_warning "gcloud version $GCLOUD_VERSION detected. Version $REQUIRED_VERSION or higher recommended."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project set. Run 'gcloud config set project PROJECT_ID' first."
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Unable to verify billing status. Ensure billing is enabled for project $PROJECT_ID"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Export project and region configuration
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CLUSTER_NAME="alloydb-perf-cluster-${RANDOM_SUFFIX}"
    export INSTANCE_NAME="alloydb-perf-primary-${RANDOM_SUFFIX}"
    export VPC_NAME="alloydb-perf-vpc-${RANDOM_SUFFIX}"
    export SUBNET_NAME="alloydb-perf-subnet-${RANDOM_SUFFIX}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Save configuration for cleanup
    cat > .deployment_config << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
CLUSTER_NAME=${CLUSTER_NAME}
INSTANCE_NAME=${INSTANCE_NAME}
VPC_NAME=${VPC_NAME}
SUBNET_NAME=${SUBNET_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment configured: Project=${PROJECT_ID}, Region=${REGION}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "alloydb.googleapis.com"
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "servicenetworking.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create VPC network and private service connection
create_network() {
    log_info "Creating VPC network and private service connection..."
    
    # Create VPC network
    log_info "Creating VPC network: $VPC_NAME"
    gcloud compute networks create "$VPC_NAME" \
        --subnet-mode=custom \
        --bgp-routing-mode=regional \
        --quiet
    
    # Create subnet
    log_info "Creating subnet: $SUBNET_NAME"
    gcloud compute networks subnets create "$SUBNET_NAME" \
        --network="$VPC_NAME" \
        --range=10.0.0.0/24 \
        --region="$REGION" \
        --quiet
    
    # Create private service connection for AlloyDB
    log_info "Creating private service connection for AlloyDB..."
    gcloud compute addresses create "alloydb-range-${RANDOM_SUFFIX}" \
        --global \
        --purpose=VPC_PEERING \
        --prefix-length=16 \
        --network="$VPC_NAME" \
        --quiet
    
    # Establish VPC peering
    log_info "Establishing VPC peering connection..."
    gcloud services vpc-peerings connect \
        --service=servicenetworking.googleapis.com \
        --ranges="alloydb-range-${RANDOM_SUFFIX}" \
        --network="$VPC_NAME" \
        --quiet
    
    log_success "VPC network and private service connection established"
}

# Function to deploy AlloyDB AI cluster
deploy_alloydb() {
    log_info "Deploying AlloyDB AI cluster..."
    
    # Create AlloyDB cluster
    log_info "Creating AlloyDB cluster: $CLUSTER_NAME"
    gcloud alloydb clusters create "$CLUSTER_NAME" \
        --network="$VPC_NAME" \
        --region="$REGION" \
        --database-flags=cloudsql.iam_authentication=on \
        --quiet
    
    # Create primary instance
    log_info "Creating AlloyDB primary instance: $INSTANCE_NAME"
    gcloud alloydb instances create "$INSTANCE_NAME" \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" \
        --instance-type=PRIMARY \
        --cpu-count=4 \
        --memory-size=16GB \
        --availability-type=ZONAL \
        --quiet
    
    # Wait for instance to be ready
    log_info "Waiting for AlloyDB instance to be ready..."
    while true; do
        STATUS=$(gcloud alloydb instances describe "$INSTANCE_NAME" \
            --cluster="$CLUSTER_NAME" \
            --region="$REGION" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$STATUS" == "READY" ]]; then
            break
        elif [[ "$STATUS" == "FAILED" ]]; then
            log_error "AlloyDB instance creation failed"
            exit 1
        fi
        
        log_info "Instance status: $STATUS. Waiting..."
        sleep 30
    done
    
    # Get connection information
    export ALLOYDB_IP=$(gcloud alloydb instances describe "$INSTANCE_NAME" \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" \
        --format="value(ipAddress)")
    
    log_success "AlloyDB AI cluster deployed successfully (IP: $ALLOYDB_IP)"
}

# Function to configure Cloud Monitoring
setup_monitoring() {
    log_info "Configuring Cloud Monitoring for AlloyDB performance metrics..."
    
    # Create custom metric descriptors
    cat > custom_metrics.yaml << 'EOF'
type: "custom.googleapis.com/alloydb/query_performance_score"
labels:
- key: "database_name"
  value_type: STRING
- key: "query_type"
  value_type: STRING
metric_kind: GAUGE
value_type: DOUBLE
unit: "1"
description: "AI-generated performance score for database queries"
display_name: "AlloyDB Query Performance Score"
EOF
    
    # Create alerting policy
    cat > alert_policy.yaml << 'EOF'
displayName: "AlloyDB Performance Anomaly Alert"
conditions:
- displayName: "High query latency detected"
  conditionThreshold:
    filter: 'resource.type="alloydb_database"'
    comparison: COMPARISON_GREATER_THAN
    thresholdValue: 1000
    duration: "300s"
notificationChannels: []
enabled: true
EOF
    
    # Apply monitoring configuration
    if gcloud alpha monitoring policies create --policy-from-file=alert_policy.yaml --quiet 2>/dev/null; then
        log_success "Monitoring alerting policy created"
    else
        log_warning "Failed to create alerting policy - may already exist"
    fi
    
    # Create performance dashboard
    cat > dashboard_config.json << 'EOF'
{
  "displayName": "AlloyDB AI Performance Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Query Performance Score",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"alloydb_database\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "AI Optimization Actions",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"cloud_function\"",
                "aggregation": {
                  "alignmentPeriod": "3600s",
                  "perSeriesAligner": "ALIGN_SUM"
                }
              }
            }
          }
        }
      }
    ]
  }
}
EOF
    
    if gcloud monitoring dashboards create --config-from-file=dashboard_config.json --quiet; then
        log_success "Performance dashboard created"
    else
        log_warning "Failed to create dashboard - may already exist"
    fi
    
    log_success "Cloud Monitoring configured successfully"
}

# Function to deploy Vertex AI components
deploy_vertex_ai() {
    log_info "Deploying Vertex AI model for performance analysis..."
    
    # Create Vertex AI dataset
    log_info "Creating Vertex AI dataset..."
    DATASET_DISPLAY_NAME="alloydb-performance-dataset-${RANDOM_SUFFIX}"
    
    if gcloud ai datasets create \
        --display-name="$DATASET_DISPLAY_NAME" \
        --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml" \
        --region="$REGION" \
        --quiet; then
        
        # Get dataset ID
        export DATASET_ID=$(gcloud ai datasets list \
            --region="$REGION" \
            --filter="displayName:$DATASET_DISPLAY_NAME" \
            --format="value(name)" | cut -d'/' -f6)
        
        log_success "Vertex AI dataset created (ID: $DATASET_ID)"
    else
        log_warning "Dataset creation failed - may already exist"
    fi
    
    log_success "Vertex AI components deployed"
}

# Function to create and deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Creating and deploying Cloud Functions for automated optimization..."
    
    # Create source directory
    mkdir -p alloydb-optimizer
    cd alloydb-optimizer
    
    # Create main.py for the optimizer function
    cat > main.py << 'EOF'
import functions_framework
import json
import os
import time
import logging
from google.cloud import alloydb_v1
from google.cloud import aiplatform
from google.cloud import monitoring_v3

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def optimize_alloydb_performance(cloud_event):
    """Analyze performance metrics and apply optimizations"""
    
    # Initialize clients
    try:
        alloydb_client = alloydb_v1.AlloyDBAdminClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        # Get environment variables
        project_id = os.environ.get('PROJECT_ID')
        cluster_name = os.environ.get('CLUSTER_NAME')
        
        if not project_id or not cluster_name:
            logger.error("Missing required environment variables")
            return
        
        logger.info(f"Processing performance optimization for cluster: {cluster_name}")
        
        # Parse cloud event data
        event_data = cloud_event.data
        if isinstance(event_data, bytes):
            event_data = json.loads(event_data.decode('utf-8'))
        
        action = event_data.get('action', 'analyze_performance')
        
        # Fetch current performance metrics
        project_name = f"projects/{project_id}"
        
        # Query recent performance data
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": int(time.time())},
            "start_time": {"seconds": int(time.time() - 3600)}
        })
        
        # Get AlloyDB metrics
        try:
            results = monitoring_client.list_time_series(
                request={
                    "name": project_name,
                    "filter": 'resource.type="alloydb_database"',
                    "interval": interval,
                    "view": monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
                }
            )
            
            # Analyze metrics and determine optimizations
            optimizations = analyze_performance_data(results)
            
            # Apply optimization recommendations
            for optimization in optimizations:
                apply_optimization(optimization, cluster_name)
                
            logger.info(f"Applied {len(optimizations)} performance optimizations")
            
        except Exception as e:
            logger.error(f"Failed to process metrics: {str(e)}")
            
    except Exception as e:
        logger.error(f"Optimization failed: {str(e)}")
        raise

def analyze_performance_data(metrics):
    """Analyze performance metrics using AI model"""
    # Simplified analysis - in production, this would use Vertex AI
    optimizations = []
    
    for time_series in metrics:
        # Basic performance analysis
        if hasattr(time_series, 'points') and time_series.points:
            latest_value = time_series.points[0].value.double_value
            
            # Simple threshold-based recommendations
            if latest_value > 1000:  # High latency
                optimizations.append({
                    'type': 'query_optimization',
                    'description': 'High query latency detected',
                    'recommendation': 'Consider query optimization or index creation'
                })
    
    return optimizations

def apply_optimization(optimization, cluster_name):
    """Apply specific optimization to AlloyDB"""
    # Log the optimization action
    logger.info(f"Applying optimization: {optimization['type']} - {optimization['description']}")
    
    # In production, this would execute actual optimization commands
    # For this example, we just log the recommendations
    logger.info(f"Recommendation: {optimization['recommendation']}")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-alloydb==1.*
google-cloud-aiplatform==1.*
google-cloud-monitoring==2.*
EOF
    
    # Create Pub/Sub topic
    log_info "Creating Pub/Sub topic for performance events..."
    gcloud pubsub topics create alloydb-performance-events --quiet || log_warning "Topic may already exist"
    
    # Deploy the Cloud Function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy alloydb-performance-optimizer \
        --gen2 \
        --runtime=python311 \
        --region="$REGION" \
        --source=. \
        --entry-point=optimize_alloydb_performance \
        --trigger-topic=alloydb-performance-events \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},CLUSTER_NAME=${CLUSTER_NAME}" \
        --timeout=540s \
        --memory=512MB \
        --quiet
    
    cd ..
    
    log_success "Cloud Functions deployed successfully"
}

# Function to configure Cloud Scheduler
setup_scheduler() {
    log_info "Configuring automated performance monitoring with Cloud Scheduler..."
    
    # Create scheduler job for regular performance analysis
    log_info "Creating performance analyzer scheduler job..."
    gcloud scheduler jobs create pubsub performance-analyzer \
        --schedule="*/15 * * * *" \
        --topic=alloydb-performance-events \
        --message-body="{\"action\":\"analyze_performance\",\"cluster\":\"${CLUSTER_NAME}\"}" \
        --time-zone="America/New_York" \
        --quiet || log_warning "Scheduler job may already exist"
    
    # Create daily optimization report scheduler
    log_info "Creating daily performance report scheduler job..."
    gcloud scheduler jobs create pubsub daily-performance-report \
        --schedule="0 9 * * *" \
        --topic=alloydb-performance-events \
        --message-body="{\"action\":\"generate_report\",\"cluster\":\"${CLUSTER_NAME}\"}" \
        --time-zone="America/New_York" \
        --quiet || log_warning "Scheduler job may already exist"
    
    log_success "Automated performance monitoring scheduled"
    log_success "Performance analysis runs every 15 minutes"
    log_success "Daily optimization reports generated at 9 AM"
}

# Function to configure vector search
setup_vector_search() {
    log_info "Setting up vector search for performance pattern analysis..."
    
    # Create SQL setup script for vector search
    cat > setup_vector_search.sql << 'EOF'
-- Enable vector extension for performance analysis
CREATE EXTENSION IF NOT EXISTS vector;

-- Create table for performance metric embeddings
CREATE TABLE IF NOT EXISTS performance_embeddings (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metric_type VARCHAR(100),
    embedding vector(512),
    performance_score FLOAT,
    optimization_applied TEXT,
    effectiveness_score FLOAT
);

-- Create index for efficient vector similarity search
CREATE INDEX IF NOT EXISTS idx_performance_embeddings_vector 
ON performance_embeddings 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Create function for performance pattern matching
CREATE OR REPLACE FUNCTION find_similar_patterns(
    query_embedding vector(512),
    similarity_threshold FLOAT DEFAULT 0.8
)
RETURNS TABLE(
    id INT,
    similarity FLOAT,
    optimization_applied TEXT,
    effectiveness_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pe.id,
        1 - (pe.embedding <=> query_embedding) as similarity,
        pe.optimization_applied,
        pe.effectiveness_score
    FROM performance_embeddings pe
    WHERE 1 - (pe.embedding <=> query_embedding) > similarity_threshold
    ORDER BY pe.embedding <=> query_embedding
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;
EOF
    
    log_success "Vector search setup script created: setup_vector_search.sql"
    log_info "To apply vector search configuration, connect to AlloyDB and run the SQL script"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check AlloyDB cluster status
    STATUS=$(gcloud alloydb clusters describe "$CLUSTER_NAME" \
        --region="$REGION" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$STATUS" == "READY" ]]; then
        log_success "AlloyDB cluster is ready"
    else
        log_error "AlloyDB cluster status: $STATUS"
        return 1
    fi
    
    # Check Cloud Functions
    if gcloud functions describe alloydb-performance-optimizer \
        --gen2 \
        --region="$REGION" \
        --format="value(state)" 2>/dev/null | grep -q "ACTIVE"; then
        log_success "Cloud Function is active"
    else
        log_warning "Cloud Function may not be fully ready yet"
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe alloydb-performance-events &>/dev/null; then
        log_success "Pub/Sub topic exists"
    else
        log_error "Pub/Sub topic not found"
        return 1
    fi
    
    # Check Scheduler jobs
    if gcloud scheduler jobs describe performance-analyzer &>/dev/null; then
        log_success "Scheduler jobs configured"
    else
        log_warning "Scheduler jobs may not be fully configured"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "AlloyDB Cluster: $CLUSTER_NAME"
    echo "AlloyDB Instance: $INSTANCE_NAME"
    echo "VPC Network: $VPC_NAME"
    echo "Subnet: $SUBNET_NAME"
    if [[ -n "${ALLOYDB_IP:-}" ]]; then
        echo "AlloyDB IP: $ALLOYDB_IP"
    fi
    echo ""
    echo "Next Steps:"
    echo "1. Connect to AlloyDB and run setup_vector_search.sql to enable vector capabilities"
    echo "2. Access the performance dashboard at: https://console.cloud.google.com/monitoring/dashboards"
    echo "3. Monitor Cloud Function logs for optimization activities"
    echo "4. Configure additional alerting channels as needed"
    echo ""
    echo "Clean up resources by running: ./destroy.sh"
    echo "===================="
}

# Main deployment function
main() {
    log_info "Starting AlloyDB AI Performance Automation deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_network
    deploy_alloydb
    setup_monitoring
    deploy_vertex_ai
    deploy_cloud_functions
    setup_scheduler
    setup_vector_search
    validate_deployment
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"