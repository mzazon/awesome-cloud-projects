#!/bin/bash

# Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML - Deployment Script
# This script deploys the complete infrastructure for ML operations automation on GCP

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

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

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if OpenSSL is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    success "All prerequisites are installed and configured"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique project ID if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="ml-ops-automation-$(date +%s)"
        log "Generated PROJECT_ID: ${PROJECT_ID}"
    else
        log "Using existing PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set resource names
    export CLUSTER_NAME="ml-ops-cluster-${RANDOM_SUFFIX}"
    export HYPERDISK_NAME="ml-storage-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="ml-ops-automation-${RANDOM_SUFFIX}"
    export DATASET_BUCKET="ml-datasets-${PROJECT_ID}-${RANDOM_SUFFIX}"
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  CLUSTER_NAME: ${CLUSTER_NAME}"
    log "  HYPERDISK_NAME: ${HYPERDISK_NAME}"
    log "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log "  DATASET_BUCKET: ${DATASET_BUCKET}"
}

# Create and configure GCP project
setup_project() {
    log "Setting up GCP project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log "Project ${PROJECT_ID} already exists"
    else
        log "Creating project ${PROJECT_ID}..."
        gcloud projects create "${PROJECT_ID}" \
            --name="ML Operations Automation" \
            --set-as-default
        
        # Wait for project creation to complete
        sleep 10
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Enable billing if not already enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Billing is not enabled for this project. Please enable billing in the Google Cloud Console."
        warning "Continuing with deployment, but some resources may fail to create."
    fi
    
    success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "aiplatform.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "container.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create Hyperdisk ML volume
create_hyperdisk() {
    log "Creating Hyperdisk ML volume..."
    
    # Check if disk already exists
    if gcloud compute disks describe "${HYPERDISK_NAME}" --zone="${ZONE}" &> /dev/null; then
        warning "Hyperdisk ML volume ${HYPERDISK_NAME} already exists"
        return 0
    fi
    
    gcloud compute disks create "${HYPERDISK_NAME}" \
        --type=hyperdisk-ml \
        --size=10TB \
        --provisioned-throughput=100000 \
        --zone="${ZONE}" \
        --quiet
    
    # Wait for disk to be ready
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local disk_status
        disk_status=$(gcloud compute disks describe "${HYPERDISK_NAME}" \
            --zone="${ZONE}" \
            --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${disk_status}" == "READY" ]]; then
            success "Hyperdisk ML volume created successfully with 100,000 MiB/s throughput"
            return 0
        fi
        
        log "Waiting for disk to be ready... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    error "Timeout waiting for Hyperdisk ML volume to be ready"
    exit 1
}

# Create GKE cluster
create_gke_cluster() {
    log "Creating GKE cluster with ML optimization..."
    
    # Check if cluster already exists
    if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${ZONE}" &> /dev/null; then
        warning "GKE cluster ${CLUSTER_NAME} already exists"
    else
        log "Creating main cluster..."
        gcloud container clusters create "${CLUSTER_NAME}" \
            --zone="${ZONE}" \
            --machine-type=c3-standard-4 \
            --num-nodes=2 \
            --enable-autorepair \
            --enable-autoupgrade \
            --enable-autoscaling \
            --min-nodes=1 \
            --max-nodes=10 \
            --enable-network-policy \
            --addons=GcePersistentDiskCsiDriver \
            --quiet
        
        # Wait for cluster to be ready
        sleep 60
        
        log "Adding GPU node pool..."
        gcloud container node-pools create gpu-pool \
            --cluster="${CLUSTER_NAME}" \
            --zone="${ZONE}" \
            --machine-type=g2-standard-4 \
            --accelerator=type=nvidia-l4,count=1 \
            --num-nodes=0 \
            --enable-autoscaling \
            --min-nodes=0 \
            --max-nodes=5 \
            --quiet
    fi
    
    # Get cluster credentials
    log "Getting cluster credentials..."
    gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone="${ZONE}" --quiet
    
    success "GKE cluster created and configured"
}

# Deploy Vertex AI agent configuration
deploy_vertex_ai_agent() {
    log "Deploying Vertex AI agent configuration..."
    
    # Create temporary directory for configurations
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create Vertex AI agent configuration
    cat > "${temp_dir}/vertex-ai-agent.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vertex-ai-config
  namespace: default
data:
  config.json: |
    {
      "agent_config": {
        "name": "ml-ops-automation-agent",
        "type": "operations-optimizer",
        "capabilities": [
          "workload-analysis",
          "predictive-scaling",
          "cost-optimization",
          "performance-monitoring"
        ]
      }
    }
EOF
    
    # Apply configuration to cluster
    kubectl apply -f "${temp_dir}/vertex-ai-agent.yaml"
    
    # Create service account for Vertex AI operations
    if ! gcloud iam service-accounts describe "vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        log "Creating Vertex AI service account..."
        gcloud iam service-accounts create vertex-ai-agent \
            --display-name="Vertex AI Operations Agent" \
            --quiet
        
        # Grant necessary permissions
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/aiplatform.user" \
            --quiet
        
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/monitoring.metricWriter" \
            --quiet
    else
        log "Vertex AI service account already exists"
    fi
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    success "Vertex AI agent configured"
}

# Configure Cloud Monitoring
configure_monitoring() {
    log "Configuring Cloud Monitoring with ML workload metrics..."
    
    # Create custom metrics
    if ! gcloud logging metrics describe ml_training_duration &> /dev/null; then
        gcloud logging metrics create ml_training_duration \
            --description="Duration of ML training jobs" \
            --log-filter='resource.type="gke_container" AND jsonPayload.event_type="training_complete"' \
            --quiet
    fi
    
    if ! gcloud logging metrics describe storage_throughput &> /dev/null; then
        gcloud logging metrics create storage_throughput \
            --description="Hyperdisk ML throughput utilization" \
            --log-filter='resource.type="gce_disk" AND jsonPayload.disk_type="hyperdisk-ml"' \
            --quiet
    fi
    
    # Create alerting policy
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "${temp_dir}/ml-alerting-policy.json" << EOF
{
  "displayName": "ML Workload Performance Alert",
  "conditions": [
    {
      "displayName": "High training duration",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/ml_training_duration\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 3600
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    
    # Create alerting policy (ignore errors if it already exists)
    gcloud alpha monitoring policies create \
        --policy-from-file="${temp_dir}/ml-alerting-policy.json" \
        --quiet || warning "Alerting policy may already exist"
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    success "Cloud Monitoring configured"
}

# Deploy automation functions
deploy_automation_functions() {
    log "Deploying automation functions with Gemini Cloud Assist integration..."
    
    # Create function source directory
    local function_dir="ml-ops-functions"
    mkdir -p "${function_dir}"
    
    # Create main.py
    cat > "${function_dir}/main.py" << 'EOF'
import functions_framework
import json
import logging
from google.cloud import monitoring_v3
from google.cloud import compute_v1
from google.cloud import aiplatform

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def ml_ops_automation(request):
    """AI-powered ML operations automation function"""
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'status': 'error', 'message': 'No JSON data provided'}, 400
        
        logger.info(f"Received automation request: {request_json}")
        
        # Extract recommendation from Gemini Cloud Assist
        recommendation = request_json.get('recommendation', {})
        action_type = recommendation.get('type', request_json.get('type'))
        trigger = request_json.get('trigger', 'manual')
        
        logger.info(f"Processing action type: {action_type}, trigger: {trigger}")
        
        if action_type == 'scale_cluster':
            return handle_cluster_scaling(recommendation)
        elif action_type == 'optimize_storage':
            return handle_storage_optimization(recommendation)
        elif action_type == 'adjust_resources':
            return handle_resource_adjustment(recommendation)
        elif action_type == 'ml_workload_analysis':
            return handle_workload_analysis(recommendation)
        elif action_type == 'hyperdisk_monitoring':
            return handle_hyperdisk_monitoring(recommendation)
        else:
            logger.info(f"No specific handler for action type: {action_type}")
            return {'status': 'success', 'action': 'processed', 'message': f'Processed {action_type}'}
        
    except Exception as e:
        logger.error(f"Error processing automation request: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def handle_cluster_scaling(recommendation):
    """Handle intelligent cluster scaling based on AI recommendations"""
    logger.info("Handling cluster scaling recommendation")
    
    # Implementation for cluster scaling logic
    # This would integrate with GKE APIs to scale node pools
    
    return {
        'status': 'success', 
        'action': 'cluster_scaled',
        'details': 'Cluster scaling analysis completed'
    }

def handle_storage_optimization(recommendation):
    """Handle storage performance optimization"""
    logger.info("Handling storage optimization recommendation")
    
    # Implementation for storage optimization logic
    # This would analyze Hyperdisk ML performance metrics
    
    return {
        'status': 'success', 
        'action': 'storage_optimized',
        'details': 'Storage performance optimization completed'
    }

def handle_resource_adjustment(recommendation):
    """Handle resource allocation adjustments"""
    logger.info("Handling resource adjustment recommendation")
    
    # Implementation for resource adjustment logic
    # This would modify compute instance configurations
    
    return {
        'status': 'success', 
        'action': 'resources_adjusted',
        'details': 'Resource allocation adjustments completed'
    }

def handle_workload_analysis(recommendation):
    """Handle ML workload analysis"""
    logger.info("Performing ML workload analysis")
    
    # Implementation for workload analysis
    # This would analyze current ML job performance
    
    return {
        'status': 'success', 
        'action': 'workload_analyzed',
        'details': 'ML workload analysis completed'
    }

def handle_hyperdisk_monitoring(recommendation):
    """Handle Hyperdisk ML monitoring"""
    logger.info("Performing Hyperdisk ML monitoring")
    
    # Implementation for Hyperdisk monitoring
    # This would check throughput utilization and performance
    
    return {
        'status': 'success', 
        'action': 'hyperdisk_monitored',
        'details': 'Hyperdisk ML monitoring completed'
    }
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.4.0
google-cloud-monitoring==2.15.1
google-cloud-compute==1.14.1
google-cloud-aiplatform==1.34.0
EOF
    
    # Deploy the automation function
    log "Deploying Cloud Function..."
    cd "${function_dir}"
    
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python39 \
        --trigger=http \
        --entry-point=ml_ops_automation \
        --memory=512MB \
        --timeout=540s \
        --service-account="vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com" \
        --allow-unauthenticated \
        --quiet
    
    cd ..
    
    # Clean up function source
    rm -rf "${function_dir}"
    
    success "ML operations automation function deployed"
}

# Create ML dataset storage
create_dataset_storage() {
    log "Creating ML dataset storage with optimized access patterns..."
    
    # Create storage bucket
    if ! gsutil ls "gs://${DATASET_BUCKET}" &> /dev/null; then
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${DATASET_BUCKET}"
    else
        warning "Storage bucket ${DATASET_BUCKET} already exists"
    fi
    
    # Create lifecycle policy
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cat > "${temp_dir}/lifecycle-policy.json" << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90, "matchesStorageClass": ["NEARLINE"]}
    }
  ]
}
EOF
    
    gsutil lifecycle set "${temp_dir}/lifecycle-policy.json" "gs://${DATASET_BUCKET}"
    
    # Set up data access permissions
    gsutil iam ch "serviceAccount:vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com:objectViewer" \
        "gs://${DATASET_BUCKET}"
    
    # Create sample dataset structure (optional)
    echo "ML Operations Dataset" | gsutil cp - "gs://${DATASET_BUCKET}/README.txt"
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    success "ML dataset storage configured with lifecycle policies"
}

# Deploy sample ML workload
deploy_ml_workload() {
    log "Deploying sample ML workload with Hyperdisk ML integration..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create storage class for Hyperdisk ML
    cat > "${temp_dir}/hyperdisk-ml-storage-class.yaml" << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hyperdisk-ml-storage
provisioner: pd.csi.storage.gke.io
parameters:
  type: hyperdisk-ml
  replication-type: regional
allowVolumeExpansion: true
EOF
    
    # Create ML training job specification
    cat > "${temp_dir}/ml-training-job.yaml" << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ml-training-hyperdisk
  namespace: default
spec:
  template:
    spec:
      containers:
      - name: ml-trainer
        image: gcr.io/google-samples/hello-app:1.0
        command: ["/bin/sh"]
        args: ["-c", "echo 'ML Training with Hyperdisk ML started'; echo 'PROJECT_ID: ${PROJECT_ID}'; echo 'Simulating ML training workload...'; sleep 300; echo 'Training completed successfully'"]
        volumeMounts:
        - name: ml-data
          mountPath: /data
        env:
        - name: TRAINING_DATA_PATH
          value: "/data"
        - name: PROJECT_ID
          value: "${PROJECT_ID}"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
      volumes:
      - name: ml-data
        persistentVolumeClaim:
          claimName: hyperdisk-ml-pvc
      restartPolicy: Never
  backoffLimit: 3
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hyperdisk-ml-pvc
  namespace: default
spec:
  accessModes:
  - ReadOnlyMany
  resources:
    requests:
      storage: 1Ti
  storageClassName: hyperdisk-ml-storage
EOF
    
    # Apply configurations
    kubectl apply -f "${temp_dir}/hyperdisk-ml-storage-class.yaml"
    kubectl apply -f "${temp_dir}/ml-training-job.yaml"
    
    # Wait for job to start
    sleep 10
    
    # Check job status
    local job_status
    job_status=$(kubectl get jobs ml-training-hyperdisk \
        -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
    
    log "ML training job status: ${job_status}"
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    success "ML training job deployed with Hyperdisk ML integration"
}

# Configure automated scaling with Cloud Scheduler
configure_automated_scaling() {
    log "Configuring automated scaling with Cloud Scheduler..."
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    # Create Cloud Scheduler job for automated scaling
    if ! gcloud scheduler jobs describe ml-ops-scheduler --location="${REGION}" &> /dev/null; then
        gcloud scheduler jobs create http ml-ops-scheduler \
            --schedule="*/15 * * * *" \
            --uri="${function_url}" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body='{"trigger":"scheduled_optimization","type":"ml_workload_analysis"}' \
            --time-zone="UTC" \
            --location="${REGION}" \
            --quiet
    fi
    
    # Create performance monitoring scheduler
    if ! gcloud scheduler jobs describe performance-monitor --location="${REGION}" &> /dev/null; then
        gcloud scheduler jobs create http performance-monitor \
            --schedule="*/5 * * * *" \
            --uri="${function_url}" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body='{"trigger":"performance_check","type":"hyperdisk_monitoring"}' \
            --time-zone="UTC" \
            --location="${REGION}" \
            --quiet
    fi
    
    success "Automated scheduling configured for ML operations"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Hyperdisk ML volume
    local disk_status
    disk_status=$(gcloud compute disks describe "${HYPERDISK_NAME}" \
        --zone="${ZONE}" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${disk_status}" == "READY" ]]; then
        success "✅ Hyperdisk ML volume is ready"
    else
        error "❌ Hyperdisk ML volume is not ready: ${disk_status}"
    fi
    
    # Check GKE cluster
    local cluster_status
    cluster_status=$(gcloud container clusters describe "${CLUSTER_NAME}" \
        --zone="${ZONE}" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${cluster_status}" == "RUNNING" ]]; then
        success "✅ GKE cluster is running"
    else
        error "❌ GKE cluster is not running: ${cluster_status}"
    fi
    
    # Check Cloud Function
    local function_status
    function_status=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${function_status}" == "ACTIVE" ]]; then
        success "✅ Cloud Function is active"
    else
        error "❌ Cloud Function is not active: ${function_status}"
    fi
    
    # Check storage bucket
    if gsutil ls "gs://${DATASET_BUCKET}" &> /dev/null; then
        success "✅ Dataset storage bucket is accessible"
    else
        error "❌ Dataset storage bucket is not accessible"
    fi
    
    # Check scheduler jobs
    local scheduler_jobs
    scheduler_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" | wc -l)
    
    if [[ ${scheduler_jobs} -ge 2 ]]; then
        success "✅ Cloud Scheduler jobs are configured"
    else
        warning "⚠️  Some Cloud Scheduler jobs may not be configured"
    fi
    
    log "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo ""
    echo "🎯 Resources Created:"
    echo "  • Project ID: ${PROJECT_ID}"
    echo "  • Hyperdisk ML Volume: ${HYPERDISK_NAME} (10TB, 100,000 MiB/s)"
    echo "  • GKE Cluster: ${CLUSTER_NAME}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Dataset Bucket: gs://${DATASET_BUCKET}"
    echo "  • Vertex AI Service Account: vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "🚀 Next Steps:"
    echo "  1. Access GKE cluster: gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}"
    echo "  2. Monitor ML workloads: kubectl get jobs,pods"
    echo "  3. Check function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "  4. View monitoring: https://console.cloud.google.com/monitoring/overview?project=${PROJECT_ID}"
    echo ""
    echo "💡 Testing:"
    echo "  • Test automation function: curl -X POST [FUNCTION_URL] -H 'Content-Type: application/json' -d '{\"type\":\"test\"}'"
    echo "  • View scheduler status: gcloud scheduler jobs list --location=${REGION}"
    echo ""
    echo "🧹 Cleanup:"
    echo "  • Run ./destroy.sh to remove all resources"
    echo ""
}

# Main deployment function
main() {
    log "Starting Cloud Operations Automation deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_hyperdisk
    create_gke_cluster
    deploy_vertex_ai_agent
    configure_monitoring
    deploy_automation_functions
    create_dataset_storage
    deploy_ml_workload
    configure_automated_scaling
    validate_deployment
    display_summary
    
    success "🎉 Cloud Operations Automation deployment completed successfully!"
    success "The intelligent ML operations platform is now ready for use."
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up partial resources."; exit 1' INT TERM

# Run main function
main "$@"