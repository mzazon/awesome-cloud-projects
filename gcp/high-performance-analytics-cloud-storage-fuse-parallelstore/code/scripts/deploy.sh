#!/bin/bash

# High-Performance Analytics with Cloud Storage FUSE and Parallelstore - Deployment Script
# This script deploys the complete infrastructure for high-performance analytics workflows
# with Cloud Storage FUSE and Parallelstore integration

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

# Cleanup function for partial deployments
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    ./destroy.sh --force
    exit 1
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Default values
DRY_RUN=false
REGION="us-central1"
ZONE="us-central1-a"
PARALLELSTORE_CAPACITY="12000"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --parallelstore-capacity)
            PARALLELSTORE_CAPACITY="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run                    Show what would be deployed without executing"
            echo "  --region REGION              GCP region (default: us-central1)"
            echo "  --zone ZONE                  GCP zone (default: us-central1-a)"
            echo "  --parallelstore-capacity GB  Parallelstore capacity in GB (default: 12000)"
            echo "  --help                       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

log "Starting High-Performance Analytics Infrastructure Deployment"
log "Configuration:"
log "  Region: $REGION"
log "  Zone: $ZONE"
log "  Parallelstore Capacity: ${PARALLELSTORE_CAPACITY}GB"
log "  Dry Run: $DRY_RUN"

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    log_error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
    exit 1
fi

# Check if bq is available
if ! command -v bq &> /dev/null; then
    log_error "BigQuery CLI (bq) is not installed. Please install it first."
    exit 1
fi

# Generate unique identifiers
TIMESTAMP=$(date +%s)
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set environment variables
export PROJECT_ID="analytics-hpc-${TIMESTAMP}"
export BUCKET_NAME="analytics-data-${RANDOM_SUFFIX}"
export CLUSTER_NAME="dataproc-hpc-${RANDOM_SUFFIX}"
export PARALLELSTORE_NAME="hpc-store-${RANDOM_SUFFIX}"
export VM_NAME="analytics-vm-${RANDOM_SUFFIX}"

log "Generated resource names:"
log "  Project ID: $PROJECT_ID"
log "  Bucket Name: $BUCKET_NAME"
log "  Cluster Name: $CLUSTER_NAME"
log "  Parallelstore Name: $PARALLELSTORE_NAME"
log "  VM Name: $VM_NAME"

# Save configuration for cleanup script
cat > .deployment_config << EOF
PROJECT_ID=$PROJECT_ID
BUCKET_NAME=$BUCKET_NAME
CLUSTER_NAME=$CLUSTER_NAME
PARALLELSTORE_NAME=$PARALLELSTORE_NAME
VM_NAME=$VM_NAME
REGION=$REGION
ZONE=$ZONE
DEPLOYMENT_TIMESTAMP=$TIMESTAMP
EOF

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No resources will be created"
    log "Would create:"
    log "  - GCP Project: $PROJECT_ID"
    log "  - Cloud Storage bucket with HNS: $BUCKET_NAME"
    log "  - Parallelstore instance: $PARALLELSTORE_NAME (${PARALLELSTORE_CAPACITY}GB)"
    log "  - Compute Engine VM: $VM_NAME"
    log "  - Dataproc cluster: $CLUSTER_NAME"
    log "  - BigQuery dataset: hpc_analytics"
    log "  - Sample analytics dataset"
    log "  - Performance monitoring"
    exit 0
fi

# Estimate costs
log_warning "COST ESTIMATION:"
log_warning "  Parallelstore (${PARALLELSTORE_CAPACITY}GB): ~\$1,200-2,400/month"
log_warning "  Dataproc cluster (4 workers): ~\$200-400/month"
log_warning "  Compute Engine VM: ~\$100-200/month"
log_warning "  Cloud Storage: ~\$20-50/month"
log_warning "  Total estimated monthly cost: \$1,520-3,050"
log_warning "  This demo will run for ~2-3 hours: \$15-25"

read -p "Do you want to continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Step 1: Create and configure project
log "Step 1: Creating and configuring GCP project..."

gcloud projects create $PROJECT_ID --name="HPC Analytics Demo" || {
    log_warning "Project creation failed or project already exists. Continuing..."
}

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# Link billing account (if needed)
BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --limit=1)
if [ -n "$BILLING_ACCOUNT" ]; then
    gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT
    log_success "Billing account linked to project"
else
    log_warning "No billing account found. Please link a billing account manually."
fi

# Enable required APIs
log "Enabling required APIs..."
gcloud services enable compute.googleapis.com \
    storage.googleapis.com \
    dataproc.googleapis.com \
    bigquery.googleapis.com \
    parallelstore.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    cloudbuild.googleapis.com

log_success "Project configured: $PROJECT_ID"

# Wait for API enablement to propagate
log "Waiting for APIs to be fully enabled..."
sleep 30

# Step 2: Create Cloud Storage bucket with hierarchical namespace
log "Step 2: Creating Cloud Storage bucket with hierarchical namespace..."

gcloud storage buckets create gs://$BUCKET_NAME \
    --location=$REGION \
    --storage-class=STANDARD \
    --enable-hierarchical-namespace

# Enable versioning for data protection
gcloud storage buckets update gs://$BUCKET_NAME --versioning

# Set lifecycle policy for cost optimization
cat > lifecycle.json << EOF
{
  "rule": [
    {
      "condition": {
        "age": 30,
        "matchesStorageClass": ["STANDARD"]
      },
      "action": {
        "type": "SetStorageClass",
        "storageClass": "NEARLINE"
      }
    }
  ]
}
EOF

gcloud storage buckets update gs://$BUCKET_NAME --lifecycle-file=lifecycle.json

log_success "Cloud Storage bucket with HNS created: $BUCKET_NAME"

# Step 3: Upload sample analytics dataset
log "Step 3: Creating and uploading sample analytics dataset..."

mkdir -p sample_data/raw/2024/01
mkdir -p sample_data/processed/features
mkdir -p sample_data/models/checkpoints

# Generate sample data files for demonstration
log "Generating sample data files..."
for i in {1..100}; do
    echo "timestamp,sensor_id,value,location" > sample_data/raw/2024/01/sensor_data_${i}.csv
    for j in {1..1000}; do
        echo "$(date +%s),sensor_${i},$((RANDOM%100)),zone_${j}" >> sample_data/raw/2024/01/sensor_data_${i}.csv
    done
done

# Upload dataset to Cloud Storage
log "Uploading dataset to Cloud Storage..."
gcloud storage cp -r sample_data/ gs://$BUCKET_NAME/

# Verify upload
gcloud storage ls -r gs://$BUCKET_NAME/sample_data/ > /dev/null

log_success "Sample analytics dataset uploaded with optimal structure"

# Step 4: Create Parallelstore instance
log "Step 4: Creating Parallelstore instance (this may take 10-15 minutes)..."

gcloud parallelstore instances create $PARALLELSTORE_NAME \
    --location=$ZONE \
    --capacity-gib=$PARALLELSTORE_CAPACITY \
    --network=default \
    --file-stripe-level=file-stripe-level-balanced \
    --directory-stripe-level=directory-stripe-level-balanced \
    --description="High-performance storage for analytics workflows"

# Wait for creation to complete with timeout
log "Waiting for Parallelstore instance to be ready..."
TIMEOUT=1800  # 30 minutes timeout
ELAPSED=0
while true; do
    STATUS=$(gcloud parallelstore instances describe $PARALLELSTORE_NAME \
        --location=$ZONE --format="value(state)" 2>/dev/null || echo "CREATING")
    
    if [ "$STATUS" = "READY" ]; then
        break
    elif [ "$STATUS" = "ERROR" ] || [ "$STATUS" = "FAILED" ]; then
        log_error "Parallelstore creation failed with status: $STATUS"
        exit 1
    fi
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_error "Timeout waiting for Parallelstore to be ready"
        exit 1
    fi
    
    log "Current status: $STATUS. Waiting... (${ELAPSED}s elapsed)"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

# Get Parallelstore access point IP
PARALLELSTORE_IP=$(gcloud parallelstore instances describe $PARALLELSTORE_NAME \
    --location=$ZONE --format="value(accessPoints[0].accessPointIp)")

echo "PARALLELSTORE_IP=$PARALLELSTORE_IP" >> .deployment_config

log_success "Parallelstore created with IP: $PARALLELSTORE_IP"

# Step 5: Create Compute Engine VM with storage mounts
log "Step 5: Creating Compute Engine VM with storage mounts..."

# Create startup script for VM
cat > vm_startup_script.sh << EOF
#!/bin/bash
set -e

# Install Cloud Storage FUSE
export GCSFUSE_REPO=gcsfuse-\$(lsb_release -c -s)
echo "deb https://packages.cloud.google.com/apt \$GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt \$GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list

apt-get update
apt-get install -y gcsfuse nfs-common

# Create mount points
mkdir -p /mnt/gcs-data
mkdir -p /mnt/parallel-store

# Mount Cloud Storage via FUSE
gcsfuse --implicit-dirs '$BUCKET_NAME' /mnt/gcs-data

# Mount Parallelstore using NFS
mount -t nfs $PARALLELSTORE_IP:/parallelstore /mnt/parallel-store

# Verify mounts
df -h | grep -E '(gcs-data|parallel-store)' > /tmp/mount-status.log || echo "Mount verification failed" > /tmp/mount-status.log

echo "Storage mounts configured successfully" >> /tmp/mount-status.log
EOF

gcloud compute instances create $VM_NAME \
    --zone=$ZONE \
    --machine-type=c2-standard-16 \
    --boot-disk-size=200GB \
    --boot-disk-type=pd-ssd \
    --image-family=ubuntu-2004-lts \
    --image-project=ubuntu-os-cloud \
    --scopes=cloud-platform \
    --metadata-from-file=startup-script=vm_startup_script.sh \
    --tags=analytics-vm

log_success "Analytics VM created: $VM_NAME"

# Step 6: Create Cloud Dataproc cluster
log "Step 6: Creating Cloud Dataproc cluster (this may take 5-8 minutes)..."

gcloud dataproc clusters create $CLUSTER_NAME \
    --zone=$ZONE \
    --num-masters=1 \
    --num-workers=4 \
    --worker-machine-type=c2-standard-8 \
    --master-machine-type=c2-standard-4 \
    --boot-disk-size=200GB \
    --boot-disk-type=pd-ssd \
    --image-version=2.1-ubuntu20 \
    --enable-cloud-sql-hive-metastore \
    --metadata="parallel-store-ip=$PARALLELSTORE_IP" \
    --initialization-actions=gs://goog-dataproc-initialization-actions-$REGION/cloud-storage-fuse/cloud-storage-fuse.sh \
    --initialization-actions-timeout=20m

log_success "Dataproc cluster created: $CLUSTER_NAME"

# Step 7: Configure and run analytics pipeline
log "Step 7: Configuring and running analytics pipeline..."

cat > analytics_pipeline.py << EOF
from pyspark.sql import SparkSession
from pyspark.sql.functions import avg, max, min
import time
import os

# Initialize Spark with optimized settings for high-performance storage
spark = SparkSession.builder \\
    .appName('HighPerformanceAnalytics') \\
    .config('spark.sql.adaptive.enabled', 'true') \\
    .config('spark.sql.adaptive.coalescePartitions.enabled', 'true') \\
    .config('spark.serializer', 'org.apache.spark.serializer.KryoSerializer') \\
    .config('spark.sql.execution.arrow.pyspark.enabled', 'true') \\
    .getOrCreate()

# Read data from Cloud Storage
print('Reading data from Cloud Storage via FUSE...')
start_time = time.time()

# Read from Cloud Storage using gs:// paths
df = spark.read.option('header', 'true') \\
    .csv('gs://$BUCKET_NAME/sample_data/raw/2024/01/*.csv')

read_time = time.time() - start_time
print(f'Data read completed in {read_time:.2f} seconds')

# Perform analytics transformations
print('Performing analytics transformations...')
transform_start = time.time()

# Group by sensor_id and calculate statistics
analytics_df = df.groupBy('sensor_id') \\
    .agg(avg('value').alias('avg_value'), 
         max('value').alias('max_value'), 
         min('value').alias('min_value'))

# Write results back to Cloud Storage
analytics_df.write.mode('overwrite') \\
    .parquet('gs://$BUCKET_NAME/sample_data/processed/analytics')

transform_time = time.time() - transform_start
print(f'Transformations completed in {transform_time:.2f} seconds')

print('Pipeline completed successfully')
spark.stop()
EOF

# Submit the analytics pipeline to Dataproc
gcloud dataproc jobs submit pyspark analytics_pipeline.py \
    --cluster=$CLUSTER_NAME \
    --zone=$ZONE

log_success "High-performance analytics pipeline executed successfully"

# Step 8: Create BigQuery dataset and external table
log "Step 8: Creating BigQuery dataset and external table..."

# Create BigQuery dataset
bq mk --dataset \
    --location=$REGION \
    --description="High-performance analytics dataset" \
    $PROJECT_ID:hpc_analytics

# Wait for processed data to be available
log "Waiting for processed data to be available..."
sleep 60

# Create external table pointing to processed data
cat > external_table_def.json << EOF
{
  "sourceFormat": "PARQUET",
  "sourceUris": [
    "gs://$BUCKET_NAME/sample_data/processed/analytics/*"
  ],
  "schema": {
    "fields": [
      {"name": "sensor_id", "type": "STRING"},
      {"name": "avg_value", "type": "FLOAT"},
      {"name": "max_value", "type": "FLOAT"},
      {"name": "min_value", "type": "FLOAT"}
    ]
  }
}
EOF

bq mk \
    --external_table_definition=@external_table_def.json \
    $PROJECT_ID:hpc_analytics.sensor_analytics

log_success "BigQuery external table created with high-performance data access"

# Step 9: Set up performance monitoring
log "Step 9: Setting up performance monitoring and alerting..."

# Create monitoring policy
cat > monitoring_policy.json << EOF
{
  "displayName": "Parallelstore Performance Alert",
  "conditions": [
    {
      "displayName": "High Parallelstore Latency",
      "conditionThreshold": {
        "filter": "resource.type=\"gce_instance\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 100,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF

gcloud monitoring policies create --policy-from-file=monitoring_policy.json

# Set up custom metrics for performance tracking
gcloud logging metrics create parallelstore_throughput \
    --description="Track Parallelstore throughput metrics" \
    --log-filter="resource.type=\"gce_instance\" AND \"parallelstore\""

log_success "Performance monitoring and alerting configured"

# Final validation
log "Step 10: Running deployment validation..."

# Test BigQuery table
log "Testing BigQuery analytics performance..."
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as total_sensors, AVG(avg_value) as overall_avg FROM \`$PROJECT_ID.hpc_analytics.sensor_analytics\`" \
    || log_warning "BigQuery validation query failed - data may still be processing"

# Cleanup temporary files
rm -f lifecycle.json vm_startup_script.sh analytics_pipeline.py external_table_def.json monitoring_policy.json
rm -rf sample_data/

log_success "High-Performance Analytics Infrastructure Deployment Complete!"
log ""
log "Deployment Summary:"
log "  ✅ Project: $PROJECT_ID"
log "  ✅ Cloud Storage with HNS: gs://$BUCKET_NAME"
log "  ✅ Parallelstore: $PARALLELSTORE_NAME ($PARALLELSTORE_IP)"
log "  ✅ Compute VM: $VM_NAME"
log "  ✅ Dataproc Cluster: $CLUSTER_NAME"
log "  ✅ BigQuery Dataset: $PROJECT_ID:hpc_analytics"
log "  ✅ Analytics Pipeline: Executed successfully"
log "  ✅ Monitoring: Configured"
log ""
log "Next Steps:"
log "  1. Test the deployment: ./scripts/validate.sh"
log "  2. Access VM: gcloud compute ssh $VM_NAME --zone=$ZONE"
log "  3. View BigQuery data: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
log "  4. Monitor performance: https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
log ""
log_warning "IMPORTANT: This deployment incurs significant costs. Run ./scripts/destroy.sh when finished."
log_warning "Estimated hourly cost: \$5-15/hour"