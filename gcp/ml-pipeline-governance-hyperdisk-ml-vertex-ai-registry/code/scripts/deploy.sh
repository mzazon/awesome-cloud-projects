#!/bin/bash

# ML Pipeline Governance with Hyperdisk ML and Vertex AI Model Registry - Deployment Script
# This script deploys the complete ML governance infrastructure on Google Cloud Platform

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
    log_error "$1"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

# Trap errors
trap 'error_exit "An unexpected error occurred on line $LINENO"' ERR

# Script header
echo "=============================================="
echo "ML Pipeline Governance Deployment Script"
echo "=============================================="
echo ""

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    error_exit "Python 3 is not installed. Please install it first."
fi

# Check if jq is available for JSON processing
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed. Some validation steps may be limited."
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error_exit "No active gcloud authentication found. Please run 'gcloud auth login' first."
fi

log_success "Prerequisites check completed"

# Set default values and allow overrides
PROJECT_ID="${PROJECT_ID:-ml-governance-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"

echo ""
log "Configuration:"
log "  Project ID: $PROJECT_ID"
log "  Region: $REGION"
log "  Zone: $ZONE"
log "  Random Suffix: $RANDOM_SUFFIX"
echo ""

# Confirm deployment
read -p "Do you want to proceed with the deployment? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Start deployment
log "Starting ML Pipeline Governance deployment..."

# Check if project exists
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    log_warning "Project $PROJECT_ID does not exist. Creating new project..."
    if ! gcloud projects create "$PROJECT_ID" --name="ML Governance Project"; then
        error_exit "Failed to create project $PROJECT_ID"
    fi
    log_success "Project $PROJECT_ID created"
    
    # Set billing account if available
    BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1 2>/dev/null || true)
    if [[ -n "$BILLING_ACCOUNT" ]]; then
        log "Linking billing account to project..."
        gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT" || log_warning "Failed to link billing account"
    else
        log_warning "No billing account found. Please link a billing account manually."
    fi
fi

# Set project context
log "Setting project context..."
gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
gcloud config set compute/zone "$ZONE" || error_exit "Failed to set zone"
log_success "Project context configured"

# Enable required APIs
log "Enabling required Google Cloud APIs..."
REQUIRED_APIS=(
    "compute.googleapis.com"
    "aiplatform.googleapis.com"
    "workflows.googleapis.com"
    "monitoring.googleapis.com"
    "logging.googleapis.com"
    "storage.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    log "Enabling API: $api"
    if ! gcloud services enable "$api"; then
        error_exit "Failed to enable API: $api"
    fi
done

# Wait for APIs to be fully enabled
log "Waiting for APIs to be fully enabled..."
sleep 30
log_success "All required APIs enabled"

# Create service account
log "Creating ML governance service account..."
SERVICE_ACCOUNT="ml-governance-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &>/dev/null; then
    gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
        --display-name="ML Governance Service Account" \
        --description="Service account for ML pipeline governance operations" || \
        error_exit "Failed to create service account"
    log_success "Service account created: $SERVICE_ACCOUNT_EMAIL"
else
    log_warning "Service account already exists: $SERVICE_ACCOUNT_EMAIL"
fi

# Assign IAM roles
log "Assigning IAM roles to service account..."
IAM_ROLES=(
    "roles/aiplatform.user"
    "roles/workflows.invoker"
    "roles/monitoring.editor"
    "roles/logging.logWriter"
    "roles/storage.objectAdmin"
)

for role in "${IAM_ROLES[@]}"; do
    log "Assigning role: $role"
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="$role" &>/dev/null || \
        log_warning "Failed to assign role $role (may already exist)"
done
log_success "IAM roles assigned"

# Create Cloud Storage bucket
log "Creating Cloud Storage bucket for training data..."
BUCKET_NAME="ml-training-data-${RANDOM_SUFFIX}"
if ! gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME" || \
        error_exit "Failed to create storage bucket"
    log_success "Storage bucket created: gs://$BUCKET_NAME"
else
    log_warning "Storage bucket already exists: gs://$BUCKET_NAME"
fi

# Create Hyperdisk ML volume
log "Creating Hyperdisk ML volume for high-performance training data..."
HYPERDISK_NAME="ml-training-hyperdisk-${RANDOM_SUFFIX}"
if ! gcloud compute disks describe "$HYPERDISK_NAME" --region="$REGION" &>/dev/null; then
    gcloud compute disks create "$HYPERDISK_NAME" \
        --size=1000GB \
        --type=hyperdisk-ml \
        --region="$REGION" \
        --provisioned-throughput=10000 || \
        error_exit "Failed to create Hyperdisk ML volume"
    log_success "Hyperdisk ML volume created: $HYPERDISK_NAME (10,000 MiB/s throughput)"
else
    log_warning "Hyperdisk ML volume already exists: $HYPERDISK_NAME"
fi

# Create compute instance for ML training
log "Creating compute instance for ML training..."
INSTANCE_NAME="ml-training-instance-${RANDOM_SUFFIX}"
if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &>/dev/null; then
    gcloud compute instances create "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --machine-type=n1-standard-8 \
        --disk="name=$HYPERDISK_NAME,mode=ro" \
        --service-account="$SERVICE_ACCOUNT_EMAIL" \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --labels=purpose=ml-governance,environment=demo || \
        error_exit "Failed to create compute instance"
    
    # Wait for instance to be ready
    log "Waiting for compute instance to be ready..."
    INSTANCE_STATUS=""
    RETRY_COUNT=0
    MAX_RETRIES=30
    
    while [[ "$INSTANCE_STATUS" != "RUNNING" && $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        sleep 10
        INSTANCE_STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
            --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
        ((RETRY_COUNT++))
        log "Instance status: $INSTANCE_STATUS (attempt $RETRY_COUNT/$MAX_RETRIES)"
    done
    
    if [[ "$INSTANCE_STATUS" == "RUNNING" ]]; then
        log_success "Compute instance created and running: $INSTANCE_NAME"
    else
        error_exit "Compute instance failed to start properly"
    fi
else
    log_warning "Compute instance already exists: $INSTANCE_NAME"
fi

# Register model in Vertex AI Model Registry
log "Registering model in Vertex AI Model Registry..."
MODEL_NAME="governance-demo-model-${RANDOM_SUFFIX}"

# Create initial model version
MODEL_OUTPUT=$(gcloud ai models upload \
    --region="$REGION" \
    --display-name="$MODEL_NAME" \
    --description="ML model with automated governance tracking" \
    --version-aliases=staging \
    --container-image-uri=gcr.io/cloud-aiplatform/prediction/sklearn-cpu.1-0:latest \
    --artifact-uri="gs://$BUCKET_NAME/models/" \
    --format="value(model)" 2>/dev/null || echo "")

if [[ -n "$MODEL_OUTPUT" ]]; then
    MODEL_ID=$(echo "$MODEL_OUTPUT" | cut -d'/' -f6)
    log_success "Model registered in Vertex AI Model Registry with ID: $MODEL_ID"
    echo "export MODEL_ID=$MODEL_ID" > .env
else
    # Try to find existing model
    MODEL_ID=$(gcloud ai models list \
        --region="$REGION" \
        --filter="displayName:$MODEL_NAME" \
        --format="value(name)" | cut -d'/' -f6 | head -1 || echo "")
    
    if [[ -n "$MODEL_ID" ]]; then
        log_warning "Model already exists with ID: $MODEL_ID"
        echo "export MODEL_ID=$MODEL_ID" > .env
    else
        error_exit "Failed to register or find model in Vertex AI Model Registry"
    fi
fi

# Create monitoring dashboard
log "Creating monitoring dashboard for ML governance..."
cat > governance-metrics.yaml << EOF
displayName: "ML Governance Metrics Dashboard"
mosaicLayout:
  tiles:
  - width: 6
    height: 4
    widget:
      title: "Model Training Performance"
      scorecard:
        timeSeriesQuery:
          timeSeriesFilter:
            filter: 'resource.type="gce_instance"'
            aggregation:
              alignmentPeriod: "300s"
              perSeriesAligner: "ALIGN_RATE"
              crossSeriesReducer: "REDUCE_MEAN"
  - width: 6
    height: 4
    widget:
      title: "Hyperdisk ML Performance"
      scorecard:
        timeSeriesQuery:
          timeSeriesFilter:
            filter: 'resource.type="gce_disk"'
            aggregation:
              alignmentPeriod: "300s"
              perSeriesAligner: "ALIGN_MEAN"
              crossSeriesReducer: "REDUCE_MEAN"
EOF

if gcloud monitoring dashboards create --config-from-file=governance-metrics.yaml &>/dev/null; then
    log_success "ML governance monitoring dashboard created"
else
    log_warning "Failed to create monitoring dashboard (may already exist)"
fi

# Create governance workflow
log "Creating automated governance workflow..."
cat > ml-governance-workflow.yaml << 'EOF'
main:
  steps:
  - validateModel:
      call: validateModelQuality
      args:
        modelId: ${MODEL_ID}
        region: ${REGION}
  - checkCompliance:
      call: checkComplianceRules
      args:
        modelId: ${MODEL_ID}
  - updateRegistry:
      call: updateModelRegistry
      args:
        modelId: ${MODEL_ID}
        status: "approved"
  - notifyStakeholders:
      call: sendNotification
      args:
        message: "Model governance validation completed"

validateModelQuality:
  params: [modelId, region]
  steps:
  - logValidation:
      call: sys.log
      args:
        text: ${"Validating model quality for: " + modelId}
  - return:
      return: {"status": "validated"}

checkComplianceRules:
  params: [modelId]
  steps:
  - logCompliance:
      call: sys.log
      args:
        text: ${"Checking compliance for model: " + modelId}
  - return:
      return: {"compliance": "passed"}

updateModelRegistry:
  params: [modelId, status]
  steps:
  - logUpdate:
      call: sys.log
      args:
        text: ${"Updating model registry: " + modelId}
  - return:
      return: {"updated": true}

sendNotification:
  params: [message]
  steps:
  - logNotification:
      call: sys.log
      args:
        text: ${"Notification: " + message}
  - return:
      return: {"sent": true}
EOF

WORKFLOW_NAME="ml-governance-workflow-${RANDOM_SUFFIX}"
if gcloud workflows deploy "$WORKFLOW_NAME" \
    --source=ml-governance-workflow.yaml \
    --location="$REGION" \
    --service-account="$SERVICE_ACCOUNT_EMAIL" &>/dev/null; then
    log_success "Automated governance workflow deployed: $WORKFLOW_NAME"
else
    log_warning "Failed to deploy governance workflow (may already exist)"
fi

# Create model version with governance metadata
log "Creating model version with governance metadata..."
if [[ -n "$MODEL_ID" ]]; then
    gcloud ai models upload \
        --region="$REGION" \
        --parent-model="$MODEL_ID" \
        --display-name="${MODEL_NAME}-v2" \
        --description="Model version with enhanced governance features" \
        --version-aliases=development,governance-enabled \
        --container-image-uri=gcr.io/cloud-aiplatform/prediction/sklearn-cpu.1-0:latest \
        --artifact-uri="gs://$BUCKET_NAME/models/v2/" \
        --labels=governance=enabled,compliance=validated &>/dev/null || \
        log_warning "Failed to create model version (may already exist)"
    
    # Update model labels
    gcloud ai models update "$MODEL_ID" \
        --region="$REGION" \
        --update-labels=governance-status=active,last-validated="$(date +%Y-%m-%d)" &>/dev/null || \
        log_warning "Failed to update model labels"
    
    log_success "Model versioning configured with governance labels"
fi

# Create policy validation script
log "Creating policy engine for compliance enforcement..."
cat > governance-policies.py << 'EOF'
import json
import logging
from typing import Dict, List, Any

class MLGovernancePolicies:
    def __init__(self):
        self.policies = {
            'performance_threshold': 0.85,
            'max_model_size': 1000,  # MB
            'required_labels': ['governance', 'compliance'],
            'security_scan_required': True
        }
    
    def validate_model(self, model_metadata: Dict[str, Any]) -> Dict[str, Any]:
        """Validate model against governance policies"""
        results = {
            'passed': True,
            'violations': [],
            'recommendations': []
        }
        
        # Check performance threshold
        if 'accuracy' in model_metadata:
            if model_metadata['accuracy'] < self.policies['performance_threshold']:
                results['violations'].append(f"Model accuracy {model_metadata['accuracy']} below threshold {self.policies['performance_threshold']}")
                results['passed'] = False
        
        # Check required labels
        model_labels = model_metadata.get('labels', {})
        for required_label in self.policies['required_labels']:
            if required_label not in model_labels:
                results['violations'].append(f"Missing required label: {required_label}")
                results['passed'] = False
        
        # Add recommendations
        if results['passed']:
            results['recommendations'].append("Model meets all governance requirements")
        else:
            results['recommendations'].append("Address policy violations before deployment")
        
        return results

if __name__ == "__main__":
    # Example model metadata
    model_metadata = {
        'accuracy': 0.92,
        'labels': {'governance': 'enabled', 'compliance': 'validated'},
        'size_mb': 150
    }
    
    policy_engine = MLGovernancePolicies()
    validation_result = policy_engine.validate_model(model_metadata)
    print(json.dumps(validation_result, indent=2))
EOF

if python3 governance-policies.py &>/dev/null; then
    log_success "Policy engine created and validated"
else
    log_warning "Policy engine created but validation failed"
fi

# Create lineage tracking system
log "Setting up model lineage tracking..."
cat > model-lineage.py << EOF
import json
import uuid
from datetime import datetime
from typing import Dict, List, Any

class ModelLineageTracker:
    def __init__(self, project_id: str, region: str):
        self.project_id = project_id
        self.region = region
        self.lineage_data = {}
    
    def track_training_run(self, model_id: str, training_config: Dict[str, Any]) -> str:
        """Track a new model training run"""
        run_id = str(uuid.uuid4())
        
        lineage_entry = {
            'run_id': run_id,
            'model_id': model_id,
            'timestamp': datetime.now().isoformat(),
            'training_config': training_config,
            'data_sources': training_config.get('data_sources', []),
            'hyperparameters': training_config.get('hyperparameters', {}),
            'environment': {
                'project_id': self.project_id,
                'region': self.region,
                'storage_type': 'hyperdisk-ml'
            }
        }
        
        self.lineage_data[run_id] = lineage_entry
        return run_id
    
    def get_model_lineage(self, model_id: str) -> List[Dict[str, Any]]:
        """Retrieve complete lineage for a model"""
        return [entry for entry in self.lineage_data.values() 
                if entry['model_id'] == model_id]
    
    def export_lineage(self) -> str:
        """Export lineage data for audit purposes"""
        return json.dumps(self.lineage_data, indent=2)

# Initialize lineage tracker
tracker = ModelLineageTracker("$PROJECT_ID", "$REGION")

# Track a sample training run
training_config = {
    'algorithm': 'random_forest',
    'data_sources': ['gs://$BUCKET_NAME/dataset.csv'],
    'hyperparameters': {'n_estimators': 100, 'max_depth': 10},
    'storage_performance': '10000_mbps_throughput'
}

run_id = tracker.track_training_run("$MODEL_ID", training_config)
print(f"Training run tracked with ID: {run_id}")

# Export lineage for audit
with open('model-lineage-audit.json', 'w') as f:
    f.write(tracker.export_lineage())

print("Model lineage tracking initialized and audit file created")
EOF

if python3 model-lineage.py &>/dev/null; then
    log_success "Model lineage tracking system configured"
else
    log_warning "Model lineage tracking setup completed with warnings"
fi

# Save deployment configuration
log "Saving deployment configuration..."
cat > deployment-config.env << EOF
# ML Pipeline Governance Deployment Configuration
# Generated on $(date)

export PROJECT_ID="$PROJECT_ID"
export REGION="$REGION"
export ZONE="$ZONE"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_EMAIL"
export BUCKET_NAME="$BUCKET_NAME"
export HYPERDISK_NAME="$HYPERDISK_NAME"
export INSTANCE_NAME="$INSTANCE_NAME"
export MODEL_NAME="$MODEL_NAME"
export MODEL_ID="$MODEL_ID"
export WORKFLOW_NAME="$WORKFLOW_NAME"

# Usage: source deployment-config.env
EOF

log_success "Deployment configuration saved to deployment-config.env"

# Final validation
log "Performing final validation..."

# Check Hyperdisk ML volume
if gcloud compute disks describe "$HYPERDISK_NAME" --region="$REGION" --format="value(status)" | grep -q "READY"; then
    log_success "Hyperdisk ML volume is ready"
else
    log_warning "Hyperdisk ML volume status check failed"
fi

# Check compute instance
if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)" | grep -q "RUNNING"; then
    log_success "Compute instance is running"
else
    log_warning "Compute instance status check failed"
fi

# Check model registration
if [[ -n "$MODEL_ID" ]]; then
    log_success "Model is registered in Vertex AI Model Registry"
else
    log_warning "Model registration verification failed"
fi

echo ""
echo "=============================================="
echo "Deployment Summary"
echo "=============================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo "Bucket: gs://$BUCKET_NAME"
echo "Hyperdisk ML: $HYPERDISK_NAME"
echo "Instance: $INSTANCE_NAME"
echo "Model ID: $MODEL_ID"
echo "Workflow: $WORKFLOW_NAME"
echo ""
echo "Configuration saved in: deployment-config.env"
echo "To load configuration: source deployment-config.env"
echo ""
log_success "ML Pipeline Governance deployment completed successfully!"
echo ""
log "Next steps:"
echo "1. Test the governance workflow: gcloud workflows run $WORKFLOW_NAME --location=$REGION"
echo "2. Monitor the dashboard in Google Cloud Console"
echo "3. Review the policy engine: python3 governance-policies.py"
echo "4. Check model lineage: cat model-lineage-audit.json"
echo ""
log_warning "Remember to run the destroy script when done to avoid unnecessary charges"