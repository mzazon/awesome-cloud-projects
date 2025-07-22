#!/bin/bash

# Scientific Workflow Orchestration with Cloud Batch API and Vertex AI Workbench
# Deployment Script for GCP Infrastructure
# Version: 1.0
# Last Updated: 2025-07-12

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
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Clean up resources in reverse order
    if [[ -n "${WORKBENCH_NAME:-}" ]]; then
        log "Attempting to delete Workbench instance..."
        gcloud notebooks instances delete "${WORKBENCH_NAME}" \
            --location="${ZONE}" \
            --quiet || true
    fi
    
    if [[ -n "${JOB_NAME:-}" ]]; then
        log "Attempting to cancel Batch job..."
        gcloud batch jobs delete "${JOB_NAME}" \
            --location="${REGION}" \
            --quiet || true
    fi
    
    if [[ -n "${DATASET_NAME:-}" ]]; then
        log "Attempting to delete BigQuery dataset..."
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || true
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Attempting to delete Cloud Storage bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}" || true
    fi
    
    log_warning "Partial cleanup completed. Please verify all resources have been removed."
}

# Set trap for error handling
trap cleanup_on_error ERR

# Display banner
echo "================================================="
echo "  Scientific Workflow Orchestration Deployment"
echo "  Cloud Batch API + Vertex AI Workbench"
echo "================================================="
echo

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud CLI is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
fi

# Check if bq CLI is installed
if ! command -v bq &> /dev/null; then
    error_exit "BigQuery CLI (bq) is not installed. Please install it with 'gcloud components install bq'"
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    error_exit "Cloud Storage CLI (gsutil) is not installed. Please install it with 'gcloud components install gsutil'"
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
fi

log_success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

# Allow user to override project ID
if [[ -z "${PROJECT_ID:-}" ]]; then
    export PROJECT_ID="genomics-workflow-$(date +%s)"
fi

# Set default values
export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export BUCKET_NAME="genomics-data-${RANDOM_SUFFIX}"
export DATASET_NAME="genomics_analysis_${RANDOM_SUFFIX//-/_}" # Replace hyphens for BigQuery compatibility
export WORKBENCH_NAME="genomics-workbench-${RANDOM_SUFFIX}"
export JOB_NAME="genomic-processing-${RANDOM_SUFFIX}"

log "Project ID: ${PROJECT_ID}"
log "Region: ${REGION}"
log "Zone: ${ZONE}"
log "Bucket Name: ${BUCKET_NAME}"
log "Dataset Name: ${DATASET_NAME}"
log "Workbench Name: ${WORKBENCH_NAME}"

# Check if project exists or create it
log "Checking Google Cloud project..."
if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
    log_warning "Project ${PROJECT_ID} does not exist. Creating new project..."
    gcloud projects create "${PROJECT_ID}" || error_exit "Failed to create project ${PROJECT_ID}"
    log_success "Created project ${PROJECT_ID}"
fi

# Set default project and region
gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"

log_success "Project configuration completed"

# Check billing account
log "Checking billing account..."
BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open=true" --format="value(name)" | head -n1)
if [[ -z "${BILLING_ACCOUNT}" ]]; then
    error_exit "No active billing account found. Please set up billing at https://console.cloud.google.com/billing"
fi

# Link billing account to project
gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}" || log_warning "Billing may already be linked"

log_success "Billing account configured"

# Enable required APIs
log "Enabling required Google Cloud APIs..."
REQUIRED_APIS=(
    "batch.googleapis.com"
    "notebooks.googleapis.com"
    "bigquery.googleapis.com"
    "storage.googleapis.com"
    "aiplatform.googleapis.com"
    "compute.googleapis.com"
    "iam.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    log "Enabling ${api}..."
    gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
done

log_success "All required APIs enabled"

# Wait for API propagation
log "Waiting for API propagation..."
sleep 10

# Create Cloud Storage infrastructure
log "Creating Cloud Storage infrastructure..."

# Create primary data bucket with regional storage
gsutil mb -p "${PROJECT_ID}" \
    -c STANDARD \
    -l "${REGION}" \
    "gs://${BUCKET_NAME}" || error_exit "Failed to create storage bucket"

# Enable versioning for data protection
gsutil versioning set on "gs://${BUCKET_NAME}" || error_exit "Failed to enable versioning"

# Create directory structure for genomic workflow
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw-data/.keep" || true
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/processed-data/.keep" || true
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/results/.keep" || true
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/scripts/.keep" || true
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/notebooks/.keep" || true

log_success "Cloud Storage infrastructure created: gs://${BUCKET_NAME}"

# Create BigQuery dataset and tables
log "Setting up BigQuery data warehouse..."

# Create BigQuery dataset for genomic analysis
bq mk --project_id="${PROJECT_ID}" \
    --location="${REGION}" \
    --description="Genomic analysis dataset for variant calling and ML" \
    "${DATASET_NAME}" || error_exit "Failed to create BigQuery dataset"

# Create table for storing variant call data
bq mk --table \
    "${PROJECT_ID}:${DATASET_NAME}.variant_calls" \
    chromosome:STRING,position:INTEGER,reference:STRING,alternate:STRING,quality:FLOAT,filter:STRING,info:STRING,sample_id:STRING,genotype:STRING,depth:INTEGER,allele_frequency:FLOAT || error_exit "Failed to create variant_calls table"

# Create table for storing analysis results
bq mk --table \
    "${PROJECT_ID}:${DATASET_NAME}.analysis_results" \
    sample_id:STRING,variant_id:STRING,gene:STRING,effect:STRING,clinical_significance:STRING,drug_response:STRING,confidence_score:FLOAT,analysis_timestamp:TIMESTAMP || error_exit "Failed to create analysis_results table"

log_success "BigQuery dataset and tables created: ${DATASET_NAME}"

# Create and upload genomic processing script
log "Creating genomic processing pipeline..."

cat > genomic_pipeline.py << 'EOF'
#!/usr/bin/env python3
import os
import subprocess
import pandas as pd
from google.cloud import bigquery
from google.cloud import storage
import time

def process_genomic_sample(sample_id, input_file, output_bucket):
    """Process genomic sample through variant calling pipeline"""
    print(f"Processing sample: {sample_id}")
    
    # Simulate variant calling pipeline steps
    # In real implementation, this would include:
    # 1. Quality control (FastQC)
    # 2. Alignment (BWA-MEM or similar)
    # 3. Variant calling (GATK HaplotypeCaller)
    # 4. Annotation (VEP or SnpEff)
    
    # Generate synthetic variant data for demonstration
    variants = []
    for chrom in range(1, 23):  # Chromosomes 1-22
        for pos in range(1000000, 2000000, 50000):  # Sample positions
            variants.append({
                'chromosome': f'chr{chrom}',
                'position': pos,
                'reference': 'A',
                'alternate': 'G',
                'quality': 30.0 + (pos % 100),
                'filter': 'PASS',
                'info': f'DP={100 + (pos % 50)};AF=0.{pos % 100:02d}',
                'sample_id': sample_id,
                'genotype': '0/1',
                'depth': 50 + (pos % 30),
                'allele_frequency': round(0.01 + (pos % 50) / 100, 3)
            })
    
    # Upload results to BigQuery
    client = bigquery.Client()
    dataset_id = os.environ.get('DATASET_NAME')
    table_id = f"{dataset_id}.variant_calls"
    
    job_config = bigquery.LoadJobConfig(
        write_disposition="WRITE_APPEND",
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    
    job = client.load_table_from_json(variants, table_id, job_config=job_config)
    job.result()  # Wait for job to complete
    
    print(f"✅ Processed {len(variants)} variants for sample {sample_id}")
    return len(variants)

if __name__ == "__main__":
    sample_id = os.environ.get('BATCH_TASK_INDEX', '0')
    input_file = f"sample_{sample_id}.fastq"
    output_bucket = os.environ.get('BUCKET_NAME')
    
    variant_count = process_genomic_sample(f"SAMPLE_{sample_id}", input_file, output_bucket)
    print(f"Pipeline completed: {variant_count} variants processed")
EOF

# Upload processing script to Cloud Storage
gsutil cp genomic_pipeline.py "gs://${BUCKET_NAME}/scripts/" || error_exit "Failed to upload processing script"

log_success "Genomic processing script created and uploaded"

# Create and upload ML analysis notebook
log "Creating ML analysis notebook..."

cat > genomic_ml_analysis.ipynb << EOF
{
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {},
      "source": [
        "# Genomic Variant Analysis and Drug Discovery ML Pipeline\\n",
        "\\n",
        "This notebook demonstrates machine learning analysis of genomic variants for drug discovery insights."
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "# Import required libraries\\n",
        "import pandas as pd\\n",
        "import numpy as np\\n",
        "from google.cloud import bigquery\\n",
        "import matplotlib.pyplot as plt\\n",
        "import seaborn as sns\\n",
        "from sklearn.ensemble import RandomForestClassifier\\n",
        "from sklearn.model_selection import train_test_split\\n",
        "from sklearn.metrics import classification_report, confusion_matrix\\n",
        "import warnings\\n",
        "warnings.filterwarnings('ignore')\\n",
        "\\n",
        "# Initialize BigQuery client\\n",
        "client = bigquery.Client()\\n",
        "dataset_name = '${DATASET_NAME}'\\n",
        "\\n",
        "print('✅ Environment initialized')"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "source": [
        "# Query variant data from BigQuery\\n",
        "query = f\\\"\\\"\\\"\\n",
        "SELECT \\n",
        "    chromosome,\\n",
        "    position,\\n",
        "    reference,\\n",
        "    alternate,\\n",
        "    quality,\\n",
        "    sample_id,\\n",
        "    depth,\\n",
        "    allele_frequency\\n",
        "FROM \\\`{dataset_name}.variant_calls\\\`\\n",
        "WHERE quality > 20\\n",
        "LIMIT 10000\\n",
        "\\\"\\\"\\\"\\n",
        "\\n",
        "# Load data into pandas DataFrame\\n",
        "variants_df = client.query(query).to_dataframe()\\n",
        "print(f'Loaded {len(variants_df)} variant records')\\n",
        "print(variants_df.head())"
      ]
    }
  ],
  "metadata": {
    "kernelspec": {
      "display_name": "Python 3",
      "language": "python",
      "name": "python3"
    }
  },
  "nbformat": 4,
  "nbformat_minor": 4
}
EOF

# Upload notebook to Cloud Storage
gsutil cp genomic_ml_analysis.ipynb "gs://${BUCKET_NAME}/notebooks/" || error_exit "Failed to upload ML notebook"

log_success "ML analysis notebook created and uploaded"

# Deploy Vertex AI Workbench instance
log "Deploying Vertex AI Workbench instance..."

# Check if the instance already exists
if gcloud notebooks instances describe "${WORKBENCH_NAME}" --location="${ZONE}" &> /dev/null; then
    log_warning "Workbench instance ${WORKBENCH_NAME} already exists. Skipping creation."
else
    gcloud notebooks instances create "${WORKBENCH_NAME}" \
        --location="${ZONE}" \
        --environment=tf-2-11-cu113-notebooks \
        --machine-type=n1-standard-4 \
        --boot-disk-size=100GB \
        --boot-disk-type=pd-standard \
        --data-disk-size=200GB \
        --data-disk-type=pd-ssd \
        --install-gpu-driver \
        --metadata="bigquery-dataset=${DATASET_NAME},storage-bucket=${BUCKET_NAME}" || error_exit "Failed to create Workbench instance"
    
    # Wait for instance to be ready
    log "Waiting for Workbench instance to be ready..."
    while true; do
        STATE=$(gcloud notebooks instances describe "${WORKBENCH_NAME}" \
            --location="${ZONE}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${STATE}" == "ACTIVE" ]]; then
            break
        elif [[ "${STATE}" == "FAILED" ]] || [[ "${STATE}" == "UNKNOWN" ]]; then
            error_exit "Workbench instance failed to start properly"
        fi
        
        log "Instance state: ${STATE}. Waiting..."
        sleep 30
    done
fi

log_success "Vertex AI Workbench instance created: ${WORKBENCH_NAME}"

# Create Batch job configuration
log "Configuring Cloud Batch job..."

cat > batch_job_config.json << EOF
{
  "taskGroups": [{
    "taskSpec": {
      "runnables": [{
        "container": {
          "imageUri": "gcr.io/google.com/cloudsdktool/cloud-sdk:latest",
          "commands": [
            "/bin/bash",
            "-c",
            "pip install google-cloud-bigquery google-cloud-storage pandas && gsutil cp gs://${BUCKET_NAME}/scripts/genomic_pipeline.py . && python3 genomic_pipeline.py"
          ]
        }
      }],
      "computeResource": {
        "cpuMilli": 2000,
        "memoryMib": 4096
      },
      "environment": {
        "variables": {
          "DATASET_NAME": "${DATASET_NAME}",
          "BUCKET_NAME": "${BUCKET_NAME}",
          "PROJECT_ID": "${PROJECT_ID}"
        }
      }
    },
    "taskCount": 5,
    "parallelism": 3
  }],
  "allocationPolicy": {
    "instances": [{
      "instanceTemplate": {
        "machineType": "e2-standard-2",
        "provisioningModel": "STANDARD"
      }
    }]
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF

# Submit Batch job for genomic processing
log "Submitting Cloud Batch job..."

gcloud batch jobs submit "${JOB_NAME}" \
    --location="${REGION}" \
    --config=batch_job_config.json || error_exit "Failed to submit Batch job"

log_success "Cloud Batch job submitted: ${JOB_NAME}"

# Create and run results processing script
log "Creating results processing pipeline..."

cat > process_results.py << EOF
#!/usr/bin/env python3
import pandas as pd
from google.cloud import bigquery
import numpy as np
from datetime import datetime
import os

def process_analysis_results():
    """Process ML analysis results and store in BigQuery"""
    client = bigquery.Client()
    dataset_name = os.environ.get('DATASET_NAME')
    
    # Query processed variants
    query = f"""
    SELECT 
        sample_id,
        chromosome,
        position,
        reference,
        alternate,
        allele_frequency,
        quality
    FROM \`{dataset_name}.variant_calls\`
    WHERE quality > 25
    LIMIT 1000
    """
    
    variants_df = client.query(query).to_dataframe()
    
    # Generate analysis results
    results = []
    for _, variant in variants_df.iterrows():
        variant_id = f"{variant['chromosome']}:{variant['position']}:{variant['reference']}>{variant['alternate']}"
        
        # Simulate gene annotation and effect prediction
        genes = ['BRCA1', 'TP53', 'EGFR', 'KRAS', 'PIK3CA', 'PTEN', 'RB1', 'APC']
        effects = ['missense', 'nonsense', 'frameshift', 'splice_site', 'regulatory']
        clinical_sig = ['Benign', 'Likely_Benign', 'VUS', 'Likely_Pathogenic', 'Pathogenic']
        drug_responses = ['Erlotinib_Responsive', 'Trastuzumab_Responsive', 'Pembrolizumab_Responsive', 'No_Response']
        
        result = {
            'sample_id': variant['sample_id'],
            'variant_id': variant_id,
            'gene': np.random.choice(genes),
            'effect': np.random.choice(effects),
            'clinical_significance': np.random.choice(clinical_sig, p=[0.4, 0.25, 0.2, 0.1, 0.05]),
            'drug_response': np.random.choice(drug_responses, p=[0.3, 0.25, 0.25, 0.2]),
            'confidence_score': round(np.random.uniform(0.6, 0.95), 3),
            'analysis_timestamp': datetime.utcnow().isoformat()
        }
        results.append(result)
    
    # Insert results into BigQuery
    table_id = f"{dataset_name}.analysis_results"
    job_config = bigquery.LoadJobConfig(
        write_disposition="WRITE_APPEND",
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    
    job = client.load_table_from_json(results, table_id, job_config=job_config)
    job.result()
    
    print(f"✅ Processed {len(results)} analysis results")
    return len(results)

if __name__ == "__main__":
    count = process_analysis_results()
    print(f"Analysis pipeline completed: {count} results stored")
EOF

# Wait for Batch job to complete before running results processing
log "Waiting for Batch job to complete before processing results..."
while true; do
    JOB_STATE=$(gcloud batch jobs describe "${JOB_NAME}" \
        --location="${REGION}" \
        --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${JOB_STATE}" == "SUCCEEDED" ]]; then
        log_success "Batch job completed successfully"
        break
    elif [[ "${JOB_STATE}" == "FAILED" ]]; then
        log_warning "Batch job failed, but continuing with deployment"
        break
    elif [[ "${JOB_STATE}" == "UNKNOWN" ]]; then
        log_warning "Unable to determine job state, continuing with deployment"
        break
    fi
    
    log "Batch job state: ${JOB_STATE}. Waiting..."
    sleep 60
done

# Run results processing with timeout
export DATASET_NAME="${DATASET_NAME}"
timeout 300 python3 process_results.py || log_warning "Results processing timed out or failed"

log_success "Analysis results pipeline deployed"

# Clean up temporary files
rm -f genomic_pipeline.py batch_job_config.json genomic_ml_analysis.ipynb process_results.py

# Display deployment summary
echo
echo "================================================="
echo "           DEPLOYMENT COMPLETED"
echo "================================================="
echo
log_success "Scientific Workflow Orchestration infrastructure deployed successfully!"
echo
echo "Resource Summary:"
echo "  📦 Project ID: ${PROJECT_ID}"
echo "  🪣 Storage Bucket: gs://${BUCKET_NAME}"
echo "  📊 BigQuery Dataset: ${DATASET_NAME}"
echo "  💻 Workbench Instance: ${WORKBENCH_NAME}"
echo "  ⚙️  Batch Job: ${JOB_NAME}"
echo
echo "Access URLs:"
echo "  🔬 Vertex AI Workbench: https://console.cloud.google.com/ai-platform/notebooks/instances?project=${PROJECT_ID}"
echo "  📈 BigQuery Console: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
echo "  🗄️  Cloud Storage: https://console.cloud.google.com/storage/browser/${BUCKET_NAME}?project=${PROJECT_ID}"
echo "  ⚡ Cloud Batch: https://console.cloud.google.com/batch/jobs?project=${PROJECT_ID}"
echo
echo "Next Steps:"
echo "  1. Access the Vertex AI Workbench to start ML analysis"
echo "  2. Download the ML notebook: gsutil cp gs://${BUCKET_NAME}/notebooks/genomic_ml_analysis.ipynb ."
echo "  3. Monitor batch job progress in the Cloud Console"
echo "  4. Query genomic data in BigQuery for analysis"
echo
echo "💡 Remember to run ./destroy.sh when finished to avoid ongoing charges!"
echo "================================================="

# Save environment variables for destroy script
cat > .deployment_vars << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export BUCKET_NAME="${BUCKET_NAME}"
export DATASET_NAME="${DATASET_NAME}"
export WORKBENCH_NAME="${WORKBENCH_NAME}"
export JOB_NAME="${JOB_NAME}"
EOF

log_success "Deployment variables saved to .deployment_vars"
log_success "Deployment completed successfully!"

exit 0