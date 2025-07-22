#!/bin/bash

# Infrastructure Health Assessment with Cloud Workload Manager and Cloud Deploy - Deployment Script
# This script deploys the complete infrastructure health assessment pipeline
# including Cloud Workload Manager, Cloud Deploy, monitoring, and serverless components

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Check if PROJECT_ID is provided as argument or environment variable
    if [ $# -gt 0 ]; then
        export PROJECT_ID="$1"
    elif [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="infrastructure-health-$(date +%s)"
        log_warning "No PROJECT_ID provided. Using generated ID: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource naming
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CLUSTER_NAME="health-cluster-${RANDOM_SUFFIX}"
    export DEPLOYMENT_PIPELINE="health-pipeline-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="health-assessor-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > .env_vars << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
CLUSTER_NAME=${CLUSTER_NAME}
DEPLOYMENT_PIPELINE=${DEPLOYMENT_PIPELINE}
FUNCTION_NAME=${FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
}

# Function to configure gcloud
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_success "gcloud configuration updated"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "workloadmanager.googleapis.com"
        "clouddeploy.googleapis.com" 
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "container.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable ${api} --quiet; then
            log_success "${api} enabled"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for assessment reports..."
    
    local bucket_name="${PROJECT_ID}-health-assessments"
    
    # Create storage bucket
    if gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${bucket_name} 2>/dev/null; then
        log_success "Storage bucket created: gs://${bucket_name}"
    else
        if gsutil ls gs://${bucket_name} >/dev/null 2>&1; then
            log_warning "Storage bucket already exists: gs://${bucket_name}"
        else
            log_error "Failed to create storage bucket"
            exit 1
        fi
    fi
    
    # Enable versioning
    gsutil versioning set on gs://${bucket_name}
    log_success "Versioning enabled on storage bucket"
    
    # Set lifecycle policy
    cat > lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set lifecycle.json gs://${bucket_name}
    log_success "Lifecycle policy applied to storage bucket"
    
    rm -f lifecycle.json
}

# Function to create GKE cluster
create_gke_cluster() {
    log_info "Creating GKE cluster for infrastructure assessment..."
    
    # Check if cluster already exists
    if gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} >/dev/null 2>&1; then
        log_warning "GKE cluster already exists: ${CLUSTER_NAME}"
        return 0
    fi
    
    # Create GKE cluster
    if gcloud container clusters create ${CLUSTER_NAME} \
        --zone=${ZONE} \
        --num-nodes=3 \
        --enable-cloud-monitoring \
        --enable-cloud-logging \
        --enable-autorepair \
        --enable-autoupgrade \
        --machine-type=e2-medium \
        --disk-size=50GB \
        --quiet; then
        log_success "GKE cluster created: ${CLUSTER_NAME}"
    else
        log_error "Failed to create GKE cluster"
        exit 1
    fi
    
    # Get cluster credentials
    if gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE} --quiet; then
        log_success "GKE cluster credentials obtained"
    else
        log_error "Failed to get cluster credentials"
        exit 1
    fi
}

# Function to create Pub/Sub topics
create_pubsub_topics() {
    log_info "Creating Pub/Sub topics for event-driven architecture..."
    
    # Create health assessment events topic
    if gcloud pubsub topics create health-assessment-events --quiet 2>/dev/null; then
        log_success "Topic created: health-assessment-events"
    else
        log_warning "Topic already exists: health-assessment-events"
    fi
    
    # Create subscription for deployment pipeline
    if gcloud pubsub subscriptions create health-deployment-trigger \
        --topic=health-assessment-events --quiet 2>/dev/null; then
        log_success "Subscription created: health-deployment-trigger"
    else
        log_warning "Subscription already exists: health-deployment-trigger"
    fi
    
    # Create monitoring alerts topic
    if gcloud pubsub topics create health-monitoring-alerts --quiet 2>/dev/null; then
        log_success "Topic created: health-monitoring-alerts"
    else
        log_warning "Topic already exists: health-monitoring-alerts"
    fi
    
    log_success "Pub/Sub infrastructure configured"
}

# Function to create workload assessment configuration
create_workload_assessment() {
    log_info "Creating Cloud Workload Manager assessment configuration..."
    
    cat > workload-assessment.yaml << EOF
apiVersion: workloadmanager.googleapis.com/v1
kind: Evaluation
metadata:
  name: infrastructure-health-assessment
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  workloadType: "kubernetes"
  resourceFilters:
    - resource: "//container.googleapis.com/projects/${PROJECT_ID}/zones/${ZONE}/clusters/${CLUSTER_NAME}"
  rules:
    - ruleId: "security-scan"
      description: "Security configuration assessment"
      enabled: true
    - ruleId: "performance-check"
      description: "Performance optimization assessment"
      enabled: true
    - ruleId: "cost-optimization"
      description: "Cost optimization recommendations"
      enabled: true
  outputConfig:
    gcsDestination:
      uri: "gs://${PROJECT_ID}-health-assessments/evaluations/"
EOF
    
    log_success "Workload Manager assessment configuration created"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function for assessment processing..."
    
    # Create function directory
    mkdir -p health-function
    cd health-function
    
    # Create function source code
    cat > main.py << 'EOF'
import json
import logging
from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework
import os

@functions_framework.cloud_event
def process_health_assessment(cloud_event):
    """Process Workload Manager assessment results"""
    
    # Initialize clients
    publisher = pubsub_v1.PublisherClient()
    storage_client = storage.Client()
    
    # Parse assessment data
    data = cloud_event.data
    bucket_name = data.get('bucketId')
    object_name = data.get('objectId')
    
    if not bucket_name or not object_name:
        logging.error("Missing bucket or object information")
        return
    
    try:
        # Download assessment report
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(object_name)
        assessment_data = json.loads(blob.download_as_text())
        
        # Analyze assessment results
        critical_issues = []
        recommendations = []
        
        for result in assessment_data.get('results', []):
            if result.get('severity') == 'HIGH':
                critical_issues.append(result)
            if result.get('hasRecommendation', False):
                recommendations.append(result)
        
        # Trigger deployment if critical issues found
        if critical_issues:
            project_id = os.environ.get('PROJECT_ID')
            topic_path = publisher.topic_path(project_id, 'health-assessment-events')
            
            message_data = {
                'assessment_id': assessment_data.get('id'),
                'critical_issues': len(critical_issues),
                'recommendations': len(recommendations),
                'trigger_deployment': True
            }
            
            publisher.publish(topic_path, json.dumps(message_data).encode('utf-8'))
            logging.info(f"Published assessment results: {len(critical_issues)} critical issues")
    
    except Exception as e:
        logging.error(f"Error processing assessment: {str(e)}")
        raise
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
functions-framework==3.5.0
google-cloud-pubsub==2.20.1
google-cloud-storage==2.10.0
EOF
    
    # Deploy Cloud Function
    if gcloud functions deploy ${FUNCTION_NAME} \
        --runtime=python311 \
        --trigger-bucket=${PROJECT_ID}-health-assessments \
        --entry-point=process_health_assessment \
        --memory=256MB \
        --timeout=60s \
        --set-env-vars=PROJECT_ID=${PROJECT_ID} \
        --quiet; then
        log_success "Cloud Function deployed: ${FUNCTION_NAME}"
    else
        log_error "Failed to deploy Cloud Function"
        cd ..
        exit 1
    fi
    
    cd ..
}

# Function to create Cloud Deploy pipeline
create_cloud_deploy_pipeline() {
    log_info "Creating Cloud Deploy delivery pipeline..."
    
    cat > clouddeploy.yaml << EOF
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: ${DEPLOYMENT_PIPELINE}
description: Infrastructure health remediation pipeline
serialPipeline:
  stages:
  - targetId: staging-target
  - targetId: production-target
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging-target
description: Staging environment for health remediation
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: production-target
description: Production environment for health remediation
gke:
  cluster: projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}
requireApproval: true
EOF
    
    # Register delivery pipeline and targets
    if gcloud deploy apply \
        --file=clouddeploy.yaml \
        --region=${REGION} \
        --quiet; then
        log_success "Cloud Deploy pipeline created: ${DEPLOYMENT_PIPELINE}"
    else
        log_error "Failed to create Cloud Deploy pipeline"
        exit 1
    fi
}

# Function to create remediation templates
create_remediation_templates() {
    log_info "Creating remediation configuration templates..."
    
    mkdir -p remediation-templates
    
    # Create security remediation template
    cat > remediation-templates/security-fixes.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: security-policy-enforcer
  labels:
    app: security-enforcer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: security-enforcer
  template:
    metadata:
      labels:
        app: security-enforcer
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
      - name: policy-enforcer
        image: gcr.io/google-containers/pause:3.1
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF
    
    # Create performance optimization template
    cat > remediation-templates/performance-fixes.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: performance-tuning
data:
  cpu-limits: "enabled"
  memory-limits: "enabled"
  auto-scaling: "enabled"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: workload-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: target-workload
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF
    
    log_success "Remediation templates created"
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring Cloud Monitoring for health alerts..."
    
    # Create alert policy configuration
    cat > health-alert-policy.json << EOF
{
  "displayName": "Infrastructure Health Critical Issues",
  "conditions": [
    {
      "displayName": "Critical assessment findings",
      "conditionThreshold": {
        "filter": "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"health-assessment-events\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    
    # Create alert policy
    if gcloud alpha monitoring policies create \
        --policy-from-file=health-alert-policy.json \
        --quiet; then
        log_success "Alert policy created for critical health issues"
    else
        log_warning "Failed to create alert policy (may require alpha component)"
    fi
    
    # Create custom metrics for deployment success
    if gcloud logging metrics create deployment_success \
        --description="Track successful health remediation deployments" \
        --log-filter='resource.type="cloud_function" AND "deployment successful"' \
        --quiet 2>/dev/null; then
        log_success "Custom metric created: deployment_success"
    else
        log_warning "Custom metric already exists: deployment_success"
    fi
    
    log_success "Cloud Monitoring configured"
}

# Function to run validation tests
run_validation() {
    log_info "Running deployment validation tests..."
    
    # Check Workload Manager
    log_info "Checking Workload Manager configuration..."
    if [ -f "workload-assessment.yaml" ]; then
        log_success "Workload Manager configuration file exists"
    else
        log_warning "Workload Manager configuration file not found"
    fi
    
    # Check storage bucket
    log_info "Validating storage bucket..."
    if gsutil ls gs://${PROJECT_ID}-health-assessments/ >/dev/null 2>&1; then
        log_success "Storage bucket accessible"
    else
        log_error "Storage bucket not accessible"
    fi
    
    # Check GKE cluster
    log_info "Validating GKE cluster..."
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "GKE cluster accessible"
    else
        log_error "GKE cluster not accessible"
    fi
    
    # Check Cloud Function
    log_info "Validating Cloud Function..."
    if gcloud functions describe ${FUNCTION_NAME} >/dev/null 2>&1; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Cloud Function not found"
    fi
    
    # Check Cloud Deploy pipeline
    log_info "Validating Cloud Deploy pipeline..."
    if gcloud deploy delivery-pipelines describe ${DEPLOYMENT_PIPELINE} --region=${REGION} >/dev/null 2>&1; then
        log_success "Cloud Deploy pipeline configured successfully"
    else
        log_error "Cloud Deploy pipeline not found"
    fi
    
    # Check Pub/Sub topics
    log_info "Validating Pub/Sub topics..."
    if gcloud pubsub topics describe health-assessment-events >/dev/null 2>&1; then
        log_success "Pub/Sub topics configured successfully"
    else
        log_error "Pub/Sub topics not found"
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Infrastructure Health Assessment Pipeline Deployed Successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "GKE Cluster: ${CLUSTER_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Deployment Pipeline: ${DEPLOYMENT_PIPELINE}"
    echo "Storage Bucket: gs://${PROJECT_ID}-health-assessments"
    echo
    echo "=== Next Steps ==="
    echo "1. Review the workload-assessment.yaml configuration"
    echo "2. Monitor assessment results in Cloud Storage"
    echo "3. Check Cloud Function logs for processing status"
    echo "4. Test remediation templates in the staging environment"
    echo "5. Configure notification channels for monitoring alerts"
    echo
    echo "=== Important Files ==="
    echo "- Environment variables: .env_vars"
    echo "- Assessment config: workload-assessment.yaml"
    echo "- Deploy config: clouddeploy.yaml"
    echo "- Remediation templates: remediation-templates/"
    echo
    log_warning "Remember to run the destroy.sh script to clean up resources when done testing!"
}

# Main deployment function
main() {
    echo "=== Infrastructure Health Assessment Deployment ==="
    echo "Starting deployment of automated infrastructure health assessment pipeline..."
    echo
    
    # Run deployment steps
    check_prerequisites
    setup_environment "$@"
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_gke_cluster
    create_pubsub_topics
    create_workload_assessment
    deploy_cloud_function
    create_cloud_deploy_pipeline
    create_remediation_templates
    configure_monitoring
    run_validation
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed on line $LINENO. Check the logs above for details."' ERR

# Run main function with all arguments
main "$@"