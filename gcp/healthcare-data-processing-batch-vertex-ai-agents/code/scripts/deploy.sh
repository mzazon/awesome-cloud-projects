#!/bin/bash

# Healthcare Data Processing with Cloud Batch and Vertex AI Agents - Deployment Script
# This script deploys the complete healthcare data processing infrastructure
# including Cloud Batch, Vertex AI Agents, Cloud Healthcare API, and Cloud Storage

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
    log_error "Deployment failed. Cleaning up resources..."
    # Note: Cleanup will be handled by destroy.sh if needed
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Please install openssl."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-healthcare-ai-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-healthcare-data-${RANDOM_SUFFIX}}"
    export DATASET_ID="${DATASET_ID:-healthcare_dataset_${RANDOM_SUFFIX}}"
    export FHIR_STORE_ID="${FHIR_STORE_ID:-patient_records_${RANDOM_SUFFIX}}"
    export JOB_NAME="${JOB_NAME:-healthcare-processing-${RANDOM_SUFFIX}}"
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    log_info "  Dataset ID: ${DATASET_ID}"
    log_info "  FHIR Store ID: ${FHIR_STORE_ID}"
    
    log_success "Environment variables configured"
}

# Create or verify project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Healthcare AI Processing" \
            --labels="purpose=healthcare,environment=demo" || {
            log_error "Failed to create project. You may need billing account access."
            exit 1
        }
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "healthcare.googleapis.com"
        "batch.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    log_success "All required APIs enabled"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating HIPAA-compliant Cloud Storage bucket..."
    
    # Create bucket
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" || {
        log_error "Failed to create storage bucket"
        exit 1
    }
    
    # Enable versioning for data protection
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Set uniform bucket-level access
    gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"
    
    # Create directory structure
    echo "Healthcare data processing bucket created" | gsutil cp - "gs://${BUCKET_NAME}/README.txt"
    
    log_success "Storage bucket created: ${BUCKET_NAME}"
}

# Set up Cloud Healthcare API
setup_healthcare_api() {
    log_info "Setting up Cloud Healthcare API dataset and FHIR store..."
    
    # Create healthcare dataset
    gcloud healthcare datasets create "${DATASET_ID}" \
        --location="${REGION}" \
        --description="Healthcare AI processing dataset" || {
        log_error "Failed to create healthcare dataset"
        exit 1
    }
    
    # Create FHIR store for patient records
    gcloud healthcare fhir-stores create "${FHIR_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" \
        --version=R4 \
        --enable-update-create || {
        log_error "Failed to create FHIR store"
        exit 1
    }
    
    log_success "Healthcare API dataset and FHIR store created"
}

# Create service accounts and IAM roles
setup_service_accounts() {
    log_info "Creating service accounts and setting up IAM roles..."
    
    # Create service account for Vertex AI agent
    gcloud iam service-accounts create healthcare-ai-agent \
        --display-name="Healthcare AI Analysis Agent" \
        --description="Service account for AI-powered healthcare data analysis" || {
        log_warning "Service account may already exist"
    }
    
    # Create service account for batch processing
    gcloud iam service-accounts create healthcare-batch-processor \
        --display-name="Healthcare Batch Processor" \
        --description="Service account for batch processing jobs" || {
        log_warning "Service account may already exist"
    }
    
    # Grant necessary permissions to AI agent
    local ai_roles=(
        "roles/aiplatform.user"
        "roles/healthcare.fhirResourceEditor"
        "roles/storage.objectViewer"
        "roles/logging.logWriter"
    )
    
    for role in "${ai_roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:healthcare-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" --quiet
    done
    
    # Grant necessary permissions to batch processor
    local batch_roles=(
        "roles/batch.jobsEditor"
        "roles/storage.objectAdmin"
        "roles/healthcare.fhirResourceReader"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${batch_roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:healthcare-batch-processor@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" --quiet
    done
    
    log_success "Service accounts and IAM roles configured"
}

# Create healthcare data processor script
create_processor_script() {
    log_info "Creating healthcare data processor script..."
    
    cat > healthcare_processor.py << 'EOF'
#!/usr/bin/env python3

import os
import json
import sys
from google.cloud import storage
from google.cloud import healthcare_v1
from google.cloud import aiplatform
from google.cloud import monitoring_v3
import logging

def process_healthcare_file(bucket_name, file_name, project_id, region):
    """Process healthcare file with AI analysis and FHIR conversion."""
    
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    logger = logging.getLogger(__name__)
    
    try:
        # Initialize clients
        storage_client = storage.Client()
        
        # Download file from storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        file_content = blob.download_as_text()
        
        logger.info(f"Processing healthcare file: {file_name}")
        
        # Analyze content with AI (simulated for demo)
        analysis_results = analyze_with_ai_agent(file_content, project_id, region)
        
        # Convert to FHIR format
        fhir_resource = convert_to_fhir(file_content, analysis_results)
        
        # Store in Healthcare API (simulated for demo)
        store_in_fhir(fhir_resource, project_id, region)
        
        # Monitor compliance
        monitor_compliance(analysis_results, project_id)
        
        logger.info("Healthcare processing completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"Error processing healthcare file: {str(e)}")
        return False

def analyze_with_ai_agent(content, project_id, region):
    """Analyze medical content using Vertex AI agent."""
    
    # Initialize Vertex AI
    aiplatform.init(project=project_id, location=region)
    
    # Simulated analysis for demo purposes
    analysis = {
        "clinical_insights": {"diagnosis": "routine_checkup", "medications": [], "procedures": []},
        "compliance_status": {"hipaa_compliant": True, "phi_detected": False},
        "critical_findings": {"urgent": False, "alert_level": "normal"},
        "structured_data": {"patient_id": "12345", "encounter_date": "2025-07-12"}
    }
    
    return analysis

def convert_to_fhir(content, analysis):
    """Convert processed data to FHIR format."""
    fhir_resource = {
        "resourceType": "Patient",
        "id": analysis["structured_data"]["patient_id"],
        "meta": {
            "versionId": "1",
            "lastUpdated": "2025-07-12T10:00:00Z"
        },
        "identifier": [
            {
                "system": "hospital-system",
                "value": analysis["structured_data"]["patient_id"]
            }
        ]
    }
    return fhir_resource

def store_in_fhir(fhir_resource, project_id, region):
    """Store processed data in FHIR store."""
    print(f"Storing FHIR resource: {fhir_resource['id']}")

def monitor_compliance(analysis, project_id):
    """Monitor compliance and generate alerts if needed."""
    if not analysis["compliance_status"]["hipaa_compliant"]:
        print("COMPLIANCE ALERT: Non-compliant healthcare data detected")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--region", required=True)
    
    args = parser.parse_args()
    success = process_healthcare_file(args.bucket, args.file, args.project, args.region)
    sys.exit(0 if success else 1)
EOF
    
    # Upload processor to Cloud Storage
    gsutil cp healthcare_processor.py "gs://${BUCKET_NAME}/scripts/"
    
    log_success "Healthcare data processor script created and uploaded"
}

# Create batch job template
create_batch_job_template() {
    log_info "Creating Cloud Batch job template..."
    
    cat > healthcare-batch-job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: healthcare-processing-template
spec:
  taskGroups:
  - name: healthcare-analysis
    taskSpec:
      runnables:
      - script:
          text: |
            #!/bin/bash
            echo "Starting healthcare data processing..."
            
            # Install Python dependencies
            pip3 install google-cloud-storage google-cloud-healthcare google-cloud-aiplatform google-cloud-monitoring
            
            # Download and run the processor
            gsutil cp gs://${BUCKET_NAME}/scripts/healthcare_processor.py /tmp/
            
            python3 /tmp/healthcare_processor.py \
              --bucket=\${BUCKET_NAME} \
              --file=\${FILE_NAME} \
              --project=\${PROJECT_ID} \
              --region=\${REGION}
            
            echo "Healthcare processing completed"
      computeResource:
        cpuMilli: 2000
        memoryMib: 4096
      maxRetryCount: 3
      maxRunDuration: 3600s
    taskCount: 1
    parallelism: 1
  allocationPolicy:
    instances:
    - policy:
        provisioningModel: STANDARD
        machineType: e2-standard-2
        serviceAccount:
          email: healthcare-batch-processor@${PROJECT_ID}.iam.gserviceaccount.com
  logsPolicy:
    destination: CLOUD_LOGGING
EOF
    
    # Upload batch job template
    gsutil cp healthcare-batch-job.yaml "gs://${BUCKET_NAME}/templates/"
    
    log_success "Batch job template created and uploaded"
}

# Deploy Cloud Function for automation
deploy_cloud_function() {
    log_info "Deploying Cloud Function for automated job triggering..."
    
    # Create function directory
    mkdir -p healthcare-function
    cd healthcare-function
    
    # Create function source code
    cat > main.py << EOF
import functions_framework
from google.cloud import batch_v1
import os
import json

@functions_framework.cloud_event
def trigger_healthcare_processing(cloud_event):
    """Trigger healthcare data processing when files are uploaded."""
    
    try:
        # Extract file information from the event
        file_name = cloud_event.data.get('name', '')
        bucket = cloud_event.data.get('bucket', '')
        
        print(f"Processing trigger for file: {file_name} in bucket: {bucket}")
        
        # Skip non-data files
        if not file_name.endswith(('.json', '.txt', '.csv')):
            print(f"Skipping non-data file: {file_name}")
            return {"status": "skipped", "reason": "non-data file"}
        
        # Initialize Batch client
        batch_client = batch_v1.BatchServiceClient()
        
        # Configure the healthcare processing job
        job = {
            "allocation_policy": {
                "instances": [
                    {
                        "policy": {
                            "machine_type": "e2-standard-2",
                            "provisioning_model": "STANDARD",
                            "service_account": {
                                "email": f"healthcare-batch-processor@{os.environ['PROJECT_ID']}.iam.gserviceaccount.com"
                            }
                        }
                    }
                ]
            },
            "task_groups": [
                {
                    "task_spec": {
                        "runnables": [
                            {
                                "script": {
                                    "text": f'''#!/bin/bash
pip3 install google-cloud-storage google-cloud-healthcare google-cloud-aiplatform google-cloud-monitoring
gsutil cp gs://{bucket}/scripts/healthcare_processor.py /tmp/
python3 /tmp/healthcare_processor.py --bucket={bucket} --file={file_name} --project={os.environ['PROJECT_ID']} --region={os.environ['REGION']}
'''
                                }
                            }
                        ],
                        "compute_resource": {
                            "cpu_milli": 2000,
                            "memory_mib": 4096
                        },
                        "max_retry_count": 3,
                        "max_run_duration": "3600s"
                    },
                    "task_count": 1
                }
            ],
            "logs_policy": {
                "destination": "CLOUD_LOGGING"
            }
        }
        
        # Submit the batch job
        parent = f"projects/{os.environ['PROJECT_ID']}/locations/{os.environ['REGION']}"
        job_id = f"healthcare-processing-{file_name.replace('/', '-').replace('.', '-')}"
        
        response = batch_client.create_job(
            parent=parent,
            job_id=job_id,
            job=job
        )
        
        print(f"Healthcare processing job created: {response.name}")
        return {"status": "job_created", "job_name": response.name}
        
    except Exception as e:
        print(f"Error creating batch job: {str(e)}")
        return {"status": "error", "message": str(e)}
EOF
    
    # Create requirements file
    cat > requirements.txt << EOF
functions-framework==3.*
google-cloud-batch
google-cloud-storage
EOF
    
    # Deploy the Cloud Function
    gcloud functions deploy healthcare-processor-trigger \
        --runtime=python311 \
        --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
        --trigger-event-filters="bucket=${BUCKET_NAME}" \
        --entry-point=trigger_healthcare_processing \
        --memory=512MB \
        --timeout=540s \
        --service-account="healthcare-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --quiet
    
    cd ..
    rm -rf healthcare-function
    
    log_success "Cloud Function deployed successfully"
}

# Set up monitoring dashboard
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create monitoring dashboard configuration
    cat > monitoring-dashboard.json << EOF
{
  "displayName": "Healthcare Data Processing Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Batch Job Success Rate",
          "scorecard": {
            "gaugeView": {
              "upperBound": 100.0
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            },
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"batch_job\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Healthcare Processing Latency",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"batch_job\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
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
    gcloud monitoring dashboards create \
        --config-from-file=monitoring-dashboard.json \
        --quiet || log_warning "Dashboard creation may have failed"
    
    log_success "Monitoring dashboard configured"
}

# Create sample test data
create_test_data() {
    log_info "Creating sample healthcare test data..."
    
    cat > sample_medical_record.json << EOF
{
  "patient_id": "PATIENT_12345",
  "encounter_date": "2025-07-12",
  "chief_complaint": "Routine checkup",
  "vital_signs": {
    "blood_pressure": "120/80",
    "heart_rate": 72,
    "temperature": 98.6
  },
  "assessment": "Patient appears healthy",
  "plan": "Continue current medications, follow up in 6 months"
}
EOF
    
    # Upload test data
    gsutil cp sample_medical_record.json "gs://${BUCKET_NAME}/test/"
    
    log_success "Sample test data created and uploaded"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "✅ Storage bucket is accessible"
    else
        log_error "❌ Storage bucket verification failed"
        return 1
    fi
    
    # Check healthcare dataset
    if gcloud healthcare datasets describe "${DATASET_ID}" --location="${REGION}" &>/dev/null; then
        log_success "✅ Healthcare dataset is created"
    else
        log_error "❌ Healthcare dataset verification failed"
        return 1
    fi
    
    # Check FHIR store
    if gcloud healthcare fhir-stores describe "${FHIR_STORE_ID}" --dataset="${DATASET_ID}" --location="${REGION}" &>/dev/null; then
        log_success "✅ FHIR store is created"
    else
        log_error "❌ FHIR store verification failed"
        return 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe healthcare-processor-trigger --region="${REGION}" &>/dev/null; then
        log_success "✅ Cloud Function is deployed"
    else
        log_error "❌ Cloud Function verification failed"
        return 1
    fi
    
    log_success "All components verified successfully!"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================================================================================="
    echo "Healthcare Data Processing Infrastructure Deployed Successfully!"
    echo "=================================================================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Healthcare Dataset: ${DATASET_ID}"
    echo "FHIR Store: ${FHIR_STORE_ID}"
    echo "Cloud Function: healthcare-processor-trigger"
    echo ""
    echo "Next Steps:"
    echo "1. Upload healthcare data files to gs://${BUCKET_NAME}/data/"
    echo "2. Monitor processing in Cloud Console > Batch"
    echo "3. View results in Cloud Console > Healthcare API"
    echo "4. Check logs in Cloud Console > Logging"
    echo ""
    echo "Test the deployment:"
    echo "gsutil cp sample_medical_record.json gs://${BUCKET_NAME}/test/"
    echo ""
    echo "Clean up resources:"
    echo "./destroy.sh"
    echo "=================================================================================="
}

# Main execution
main() {
    log_info "Starting Healthcare Data Processing deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    setup_healthcare_api
    setup_service_accounts
    create_processor_script
    create_batch_job_template
    deploy_cloud_function
    setup_monitoring
    create_test_data
    verify_deployment
    display_summary
    
    log_success "Healthcare Data Processing infrastructure deployed successfully!"
}

# Run main function
main "$@"