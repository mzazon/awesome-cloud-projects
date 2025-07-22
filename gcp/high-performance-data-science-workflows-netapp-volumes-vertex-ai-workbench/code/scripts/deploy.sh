#!/bin/bash
set -euo pipefail

# High-Performance Data Science Workflows with Cloud NetApp Volumes and Vertex AI Workbench
# Deployment Script for GCP Recipe
# This script deploys the complete infrastructure for high-performance data science workflows

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
handle_error() {
    log_error "Script failed at line $1"
    log_error "Cleaning up partial deployment..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-ml-netapp-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
NETWORK_NAME="${NETWORK_NAME:-netapp-ml-network}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
STORAGE_POOL_NAME="${STORAGE_POOL_NAME:-ml-pool-${RANDOM_SUFFIX}}"
VOLUME_NAME="${VOLUME_NAME:-ml-datasets-${RANDOM_SUFFIX}}"
WORKBENCH_NAME="${WORKBENCH_NAME:-ml-workbench-${RANDOM_SUFFIX}}"
BUCKET_NAME="${BUCKET_NAME:-ml-datalake-${PROJECT_ID}-${RANDOM_SUFFIX}}"

# Display banner
cat << 'EOF'
============================================================
  High-Performance Data Science Workflows Deployment
  GCP Recipe: NetApp Volumes + Vertex AI Workbench
============================================================
EOF

log_info "Starting deployment with the following configuration:"
echo "  Project ID:      ${PROJECT_ID}"
echo "  Region:          ${REGION}"
echo "  Zone:            ${ZONE}"
echo "  Network:         ${NETWORK_NAME}"
echo "  Storage Pool:    ${STORAGE_POOL_NAME}"
echo "  Volume:          ${VOLUME_NAME}"
echo "  Workbench:       ${WORKBENCH_NAME}"
echo "  Bucket:          ${BUCKET_NAME}"
echo ""

# Dry run check
if [[ "${DRY_RUN}" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be created"
    exit 0
fi

# Prerequisites check
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
    exit 1
fi

# Check authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    log_error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
    exit 1
fi

# Check for required tools
for tool in openssl curl; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "$tool is not installed or not in PATH"
        exit 1
    fi
done

log_success "Prerequisites check completed"

# Confirmation prompt
if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
    echo ""
    read -p "Proceed with deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
fi

# Set gcloud configuration
log_info "Configuring gcloud settings..."
gcloud config set project "${PROJECT_ID}" --quiet
gcloud config set compute/region "${REGION}" --quiet
gcloud config set compute/zone "${ZONE}" --quiet

# Enable required APIs
log_info "Enabling required Google Cloud APIs..."
REQUIRED_APIS=(
    "compute.googleapis.com"
    "notebooks.googleapis.com"
    "netapp.googleapis.com"
    "storage.googleapis.com"
    "aiplatform.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    log_info "Enabling ${api}..."
    gcloud services enable "${api}" --quiet
done

log_success "APIs enabled successfully"

# Create VPC Network and Subnet
log_info "Creating VPC network and subnet..."

# Check if network already exists
if gcloud compute networks describe "${NETWORK_NAME}" --quiet &>/dev/null; then
    log_warning "Network ${NETWORK_NAME} already exists, skipping creation"
else
    gcloud compute networks create "${NETWORK_NAME}" \
        --subnet-mode=custom \
        --description="Network for ML workflows with NetApp storage" \
        --quiet
    log_success "VPC network created: ${NETWORK_NAME}"
fi

# Check if subnet already exists
if gcloud compute networks subnets describe "${NETWORK_NAME}-subnet" --region="${REGION}" --quiet &>/dev/null; then
    log_warning "Subnet ${NETWORK_NAME}-subnet already exists, skipping creation"
else
    gcloud compute networks subnets create "${NETWORK_NAME}-subnet" \
        --network="${NETWORK_NAME}" \
        --range=10.0.0.0/24 \
        --region="${REGION}" \
        --description="Subnet for ML instances and NetApp volumes" \
        --quiet
    log_success "Subnet created: ${NETWORK_NAME}-subnet"
fi

# Create NetApp Storage Pool
log_info "Creating Cloud NetApp Volumes storage pool..."

# Check if storage pool already exists
if gcloud netapp storage-pools describe "${STORAGE_POOL_NAME}" --location="${REGION}" --quiet &>/dev/null; then
    log_warning "Storage pool ${STORAGE_POOL_NAME} already exists, skipping creation"
else
    gcloud netapp storage-pools create "${STORAGE_POOL_NAME}" \
        --location="${REGION}" \
        --service-level=PREMIUM \
        --capacity-gib=1024 \
        --network="${NETWORK_NAME}" \
        --description="High-performance storage pool for ML datasets" \
        --quiet

    # Wait for storage pool creation to complete
    log_info "Waiting for storage pool creation to complete..."
    timeout=300  # 5 minutes timeout
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        state=$(gcloud netapp storage-pools describe "${STORAGE_POOL_NAME}" \
            --location="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$state" == "READY" ]]; then
            break
        elif [[ "$state" == "ERROR" ]]; then
            log_error "Storage pool creation failed"
            exit 1
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Storage pool state: $state (waiting...)"
    done

    if [[ $elapsed -ge $timeout ]]; then
        log_error "Storage pool creation timed out after ${timeout} seconds"
        exit 1
    fi

    log_success "NetApp storage pool created: ${STORAGE_POOL_NAME}"
fi

# Create NetApp Volume
log_info "Creating Cloud NetApp Volume for datasets..."

# Check if volume already exists
if gcloud netapp volumes describe "${VOLUME_NAME}" --location="${REGION}" --quiet &>/dev/null; then
    log_warning "Volume ${VOLUME_NAME} already exists, skipping creation"
else
    gcloud netapp volumes create "${VOLUME_NAME}" \
        --location="${REGION}" \
        --storage-pool="${STORAGE_POOL_NAME}" \
        --capacity-gib=500 \
        --share-name="ml-datasets" \
        --protocols=NFSV3 \
        --unix-permissions=0755 \
        --description="Shared volume for ML datasets and models" \
        --quiet

    # Wait for volume creation and get details
    log_info "Waiting for volume creation to complete..."
    timeout=180  # 3 minutes timeout
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        state=$(gcloud netapp volumes describe "${VOLUME_NAME}" \
            --location="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$state" == "READY" ]]; then
            break
        elif [[ "$state" == "ERROR" ]]; then
            log_error "Volume creation failed"
            exit 1
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Volume state: $state (waiting...)"
    done

    if [[ $elapsed -ge $timeout ]]; then
        log_error "Volume creation timed out after ${timeout} seconds"
        exit 1
    fi

    log_success "NetApp volume created: ${VOLUME_NAME}"
fi

# Get volume details for mounting
VOLUME_IP=$(gcloud netapp volumes describe "${VOLUME_NAME}" \
    --location="${REGION}" \
    --format="value(mountOptions[0].export)" || echo "")

EXPORT_PATH=$(gcloud netapp volumes describe "${VOLUME_NAME}" \
    --location="${REGION}" \
    --format="value(mountOptions[0].exportFullPath)" || echo "")

if [[ -z "$VOLUME_IP" || -z "$EXPORT_PATH" ]]; then
    log_error "Failed to retrieve volume mount information"
    exit 1
fi

log_info "Volume mount details:"
echo "  IP Address: $VOLUME_IP"
echo "  Export Path: $EXPORT_PATH"

# Create Vertex AI Workbench Instance
log_info "Creating Vertex AI Workbench instance with GPU support..."

# Check if workbench instance already exists
if gcloud notebooks instances describe "${WORKBENCH_NAME}" --location="${ZONE}" --quiet &>/dev/null; then
    log_warning "Workbench instance ${WORKBENCH_NAME} already exists, skipping creation"
else
    gcloud notebooks instances create "${WORKBENCH_NAME}" \
        --location="${ZONE}" \
        --machine-type=n1-standard-4 \
        --accelerator-type=NVIDIA_TESLA_T4 \
        --accelerator-core-count=1 \
        --boot-disk-size=100GB \
        --boot-disk-type=SSD \
        --network="${NETWORK_NAME}" \
        --subnet="${NETWORK_NAME}-subnet" \
        --no-public-ip \
        --metadata="enable-oslogin=true" \
        --image-family=tf-ent-2-11-cu113-notebooks \
        --image-project=deeplearning-platform-release \
        --quiet

    # Wait for instance to be ready
    log_info "Waiting for Workbench instance to be ready..."
    timeout=600  # 10 minutes timeout
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        state=$(gcloud notebooks instances describe "${WORKBENCH_NAME}" \
            --location="${ZONE}" \
            --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$state" == "ACTIVE" ]]; then
            break
        elif [[ "$state" == "ERROR" ]]; then
            log_error "Workbench instance creation failed"
            exit 1
        fi
        
        sleep 30
        elapsed=$((elapsed + 30))
        log_info "Workbench instance state: $state (waiting...)"
    done

    if [[ $elapsed -ge $timeout ]]; then
        log_error "Workbench instance creation timed out after ${timeout} seconds"
        exit 1
    fi

    log_success "Vertex AI Workbench instance created: ${WORKBENCH_NAME}"
fi

# Mount NetApp Volume to Workbench Instance
log_info "Mounting NetApp volume to Workbench instance..."

# Create mount point and mount NetApp volume via SSH
gcloud compute ssh "${WORKBENCH_NAME}" \
    --zone="${ZONE}" \
    --quiet \
    --command="
        sudo mkdir -p /mnt/ml-datasets && \
        sudo mount -t nfs ${VOLUME_IP}:${EXPORT_PATH} /mnt/ml-datasets && \
        sudo chmod 755 /mnt/ml-datasets && \
        echo '${VOLUME_IP}:${EXPORT_PATH} /mnt/ml-datasets nfs defaults 0 0' | sudo tee -a /etc/fstab > /dev/null
    " || {
        log_error "Failed to mount NetApp volume"
        exit 1
    }

# Verify mount was successful
if gcloud compute ssh "${WORKBENCH_NAME}" \
    --zone="${ZONE}" \
    --quiet \
    --command="df -h /mnt/ml-datasets" &>/dev/null; then
    log_success "NetApp volume mounted successfully to /mnt/ml-datasets"
else
    log_error "NetApp volume mount verification failed"
    exit 1
fi

# Create Cloud Storage bucket for data lake integration
log_info "Creating Cloud Storage bucket for data pipeline..."

if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
    log_warning "Bucket ${BUCKET_NAME} already exists, skipping creation"
else
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" || {
        log_error "Failed to create Cloud Storage bucket"
        exit 1
    }
    log_success "Cloud Storage bucket created: ${BUCKET_NAME}"
fi

# Set up sample dataset and environment
log_info "Setting up sample dataset and Jupyter environment..."

gcloud compute ssh "${WORKBENCH_NAME}" \
    --zone="${ZONE}" \
    --quiet \
    --command="
        # Create directory structure
        sudo mkdir -p /mnt/ml-datasets/{raw-data,processed-data,models,notebooks,config} && \
        sudo chown -R jupyter:jupyter /mnt/ml-datasets && \
        
        # Download sample dataset
        cd /mnt/ml-datasets/raw-data && \
        curl -s -o sample_data.csv 'https://storage.googleapis.com/cloud-samples-data/ai-platform/iris/iris_data.csv' && \
        
        # Create performance test notebook
        cat > /mnt/ml-datasets/notebooks/netapp_performance_test.ipynb << 'EOF'
{
 \"cells\": [
  {
   \"cell_type\": \"code\",
   \"metadata\": {},
   \"source\": [
    \"import pandas as pd\\n\",
    \"import numpy as np\\n\",
    \"import time\\n\",
    \"import os\\n\\n\",
    \"# Test NetApp volume performance\\n\",
    \"data_path = '/mnt/ml-datasets/raw-data/sample_data.csv'\\n\",
    \"print(f'Reading data from NetApp volume: {data_path}')\\n\\n\",
    \"start_time = time.time()\\n\",
    \"df = pd.read_csv(data_path)\\n\",
    \"load_time = time.time() - start_time\\n\\n\",
    \"print(f'Data loaded in {load_time:.4f} seconds')\\n\",
    \"print(f'Dataset shape: {df.shape}')\\n\",
    \"print(f'NetApp volume mount status:')\\n\",
    \"os.system('df -h /mnt/ml-datasets')\"
   ]
  }
 ],
 \"metadata\": {
  \"kernelspec\": {
   \"display_name\": \"Python 3\",
   \"language\": \"python\",
   \"name\": \"python3\"
  }
 },
 \"nbformat\": 4,
 \"nbformat_minor\": 4
}
EOF
        
        # Create data sync script
        cat > /mnt/ml-datasets/sync_to_storage.py << 'EOF'
import subprocess
import os

def sync_models_to_storage():
    '''Sync trained models to Cloud Storage for versioning'''
    bucket_name = '${BUCKET_NAME}'
    local_path = '/mnt/ml-datasets/models/'
    
    if os.path.exists(local_path):
        cmd = f'gsutil -m rsync -r {local_path} gs://{bucket_name}/models/'
        subprocess.run(cmd, shell=True, check=True)
        print(f'Models synced to gs://{bucket_name}/models/')
    else:
        print(f'Local models directory not found: {local_path}')

if __name__ == '__main__':
    sync_models_to_storage()
EOF
        chmod +x /mnt/ml-datasets/sync_to_storage.py
        
        # Create team requirements file
        cat > /mnt/ml-datasets/config/requirements.txt << 'EOF'
pandas>=1.5.0
numpy>=1.21.0
scikit-learn>=1.1.0
tensorflow>=2.11.0
matplotlib>=3.5.0
seaborn>=0.11.0
jupyter>=1.0.0
plotly>=5.0.0
EOF
    " || {
        log_error "Failed to set up sample dataset and environment"
        exit 1
    }

log_success "Sample dataset and Jupyter environment configured"

# Upload sample data to Cloud Storage
log_info "Setting up Cloud Storage data pipeline..."
gsutil cp gs://cloud-samples-data/ai-platform/iris/iris_training.csv \
    "gs://${BUCKET_NAME}/raw-data/" || {
    log_warning "Failed to copy sample data to Cloud Storage (non-critical)"
}

# Display deployment summary
cat << EOF

============================================================
            DEPLOYMENT COMPLETED SUCCESSFULLY
============================================================

Resource Summary:
  ✅ VPC Network:          ${NETWORK_NAME}
  ✅ NetApp Storage Pool:  ${STORAGE_POOL_NAME}
  ✅ NetApp Volume:        ${VOLUME_NAME}
  ✅ Workbench Instance:   ${WORKBENCH_NAME}
  ✅ Cloud Storage Bucket: ${BUCKET_NAME}

Access Information:
  🔗 Jupyter URL: Get the URL with this command:
     gcloud notebooks instances describe ${WORKBENCH_NAME} --location=${ZONE} --format="value(proxyUri)"
  
  📁 Shared Dataset Location: /mnt/ml-datasets/
  📊 Performance Test: /mnt/ml-datasets/notebooks/netapp_performance_test.ipynb

Next Steps:
  1. Access Jupyter notebook via the URL above
  2. Navigate to /mnt/ml-datasets/notebooks/
  3. Run the performance test notebook to validate setup
  4. Start your data science workflows!

Cleanup:
  Run ./destroy.sh to remove all created resources

============================================================
EOF

# Save deployment state for cleanup
cat > "${HOME}/.ml-netapp-deployment-state" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
NETWORK_NAME=${NETWORK_NAME}
STORAGE_POOL_NAME=${STORAGE_POOL_NAME}
VOLUME_NAME=${VOLUME_NAME}
WORKBENCH_NAME=${WORKBENCH_NAME}
BUCKET_NAME=${BUCKET_NAME}
DEPLOYED_AT=$(date)
EOF

log_success "Deployment state saved to ${HOME}/.ml-netapp-deployment-state"
log_success "High-Performance Data Science Workflows deployment completed successfully!"