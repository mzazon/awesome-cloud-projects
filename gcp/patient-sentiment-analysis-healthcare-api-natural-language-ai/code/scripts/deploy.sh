#!/bin/bash

# Deploy script for Patient Sentiment Analysis with Cloud Healthcare API and Natural Language AI
# This script deploys the complete healthcare sentiment analysis pipeline

set -euo pipefail

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_info "Attempting to delete project: ${PROJECT_ID}"
        gcloud projects delete "${PROJECT_ID}" --quiet || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random values."
        exit 1
    fi
    
    # Check if bq command is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available. Please ensure it's installed with gcloud."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core configuration
    export PROJECT_ID="healthcare-sentiment-$(date +%s)"
    export REGION="us-central1"
    export ZONE="us-central1-a"
    export DATASET_ID="healthcare_analytics"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export HEALTHCARE_DATASET="patient-records-${RANDOM_SUFFIX}"
    export FHIR_STORE="patient-fhir-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="sentiment-processor-${RANDOM_SUFFIX}"
    export PUBSUB_TOPIC="fhir-notifications-${RANDOM_SUFFIX}"
    export BQ_DATASET="patient_sentiment_${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Healthcare Dataset: ${HEALTHCARE_DATASET}"
    log_info "FHIR Store: ${FHIR_STORE}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Pub/Sub Topic: ${PUBSUB_TOPIC}"
    log_info "BigQuery Dataset: ${BQ_DATASET}"
    
    log_success "Environment variables configured"
}

# Create and configure project
setup_project() {
    log_info "Creating and configuring project..."
    
    # Create project
    if gcloud projects create "${PROJECT_ID}" --quiet; then
        log_success "Project created: ${PROJECT_ID}"
    else
        log_error "Failed to create project. Please check if the project ID is available."
        exit 1
    fi
    
    # Set default configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account (required for APIs)
    log_info "Please ensure billing is enabled for project ${PROJECT_ID}"
    log_warning "You may need to manually link a billing account in the Google Cloud Console"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "healthcare.googleapis.com"
        "language.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

# Create Healthcare dataset and FHIR store
create_healthcare_resources() {
    log_info "Creating Healthcare API resources..."
    
    # Create Pub/Sub topic first (required for FHIR store notifications)
    log_info "Creating Pub/Sub topic: ${PUBSUB_TOPIC}"
    if gcloud pubsub topics create "${PUBSUB_TOPIC}" --quiet; then
        log_success "Pub/Sub topic created"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create healthcare dataset
    log_info "Creating Healthcare dataset: ${HEALTHCARE_DATASET}"
    if gcloud healthcare datasets create "${HEALTHCARE_DATASET}" \
        --location="${REGION}" --quiet; then
        log_success "Healthcare dataset created"
    else
        log_error "Failed to create Healthcare dataset"
        exit 1
    fi
    
    # Create FHIR store with Pub/Sub notifications
    log_info "Creating FHIR store: ${FHIR_STORE}"
    if gcloud healthcare fhir-stores create "${FHIR_STORE}" \
        --dataset="${HEALTHCARE_DATASET}" \
        --location="${REGION}" \
        --version=R4 \
        --pubsub-topic="projects/${PROJECT_ID}/topics/${PUBSUB_TOPIC}" \
        --quiet; then
        log_success "FHIR store created with Pub/Sub notifications"
    else
        log_error "Failed to create FHIR store"
        exit 1
    fi
    
    log_success "Healthcare API resources created successfully"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub subscription..."
    
    # Create subscription for Cloud Functions trigger
    if gcloud pubsub subscriptions create "${PUBSUB_TOPIC}-sub" \
        --topic="${PUBSUB_TOPIC}" --quiet; then
        log_success "Pub/Sub subscription created"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    log_success "Pub/Sub resources configured"
}

# Create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery resources..."
    
    # Create BigQuery dataset
    log_info "Creating BigQuery dataset: ${BQ_DATASET}"
    if bq mk --dataset \
        --location="${REGION}" \
        --description="Patient sentiment analysis results" \
        "${PROJECT_ID}:${BQ_DATASET}" > /dev/null 2>&1; then
        log_success "BigQuery dataset created"
    else
        log_error "Failed to create BigQuery dataset"
        exit 1
    fi
    
    # Create table for sentiment analysis results
    log_info "Creating sentiment analysis table..."
    local schema="patient_id:STRING,observation_id:STRING,text_content:STRING,sentiment_score:FLOAT,magnitude:FLOAT,overall_sentiment:STRING,processing_timestamp:TIMESTAMP,fhir_resource_type:STRING"
    
    if bq mk --table \
        "${PROJECT_ID}:${BQ_DATASET}.sentiment_analysis" \
        "${schema}" > /dev/null 2>&1; then
        log_success "BigQuery table created"
    else
        log_error "Failed to create BigQuery table"
        exit 1
    fi
    
    log_success "BigQuery resources created successfully"
}

# Create Cloud Function
create_cloud_function() {
    log_info "Creating Cloud Function for sentiment analysis..."
    
    # Create function source directory
    local function_dir="sentiment-function"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create function code
    cat > main.py << 'EOF'
import json
import base64
import logging
from google.cloud import language_v1
from google.cloud import bigquery
from google.cloud import healthcare_v1
import functions_framework

# Initialize clients
language_client = language_v1.LanguageServiceClient()
bq_client = bigquery.Client()
healthcare_client = healthcare_v1.FhirServiceClient()

@functions_framework.cloud_event
def process_fhir_sentiment(cloud_event):
    """Process FHIR events and perform sentiment analysis."""
    
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(cloud_event.data["message"]["data"])
        event_data = json.loads(pubsub_message.decode())
        
        logging.info(f"Processing FHIR event: {event_data}")
        
        # Extract FHIR resource information
        resource_name = event_data.get("name", "")
        event_type = event_data.get("eventType", "")
        
        if "Observation" in resource_name and event_type in ["CREATED", "UPDATED"]:
            # Fetch FHIR resource
            response = healthcare_client.get_fhir_resource(name=resource_name)
            fhir_resource = json.loads(response.data.decode())
            
            # Extract text content from FHIR observation
            text_content = extract_text_from_observation(fhir_resource)
            
            if text_content:
                # Perform sentiment analysis
                sentiment_result = analyze_sentiment(text_content)
                
                # Store results in BigQuery
                store_sentiment_results(fhir_resource, text_content, sentiment_result)
                
                logging.info(f"Sentiment analysis completed for {resource_name}")
        
    except Exception as e:
        logging.error(f"Error processing FHIR event: {str(e)}")

def extract_text_from_observation(fhir_resource):
    """Extract text content from FHIR Observation resource."""
    text_content = ""
    
    # Extract from valueString
    if "valueString" in fhir_resource:
        text_content += fhir_resource["valueString"] + " "
    
    # Extract from note field
    if "note" in fhir_resource:
        for note in fhir_resource["note"]:
            if "text" in note:
                text_content += note["text"] + " "
    
    # Extract from component values
    if "component" in fhir_resource:
        for component in fhir_resource["component"]:
            if "valueString" in component:
                text_content += component["valueString"] + " "
    
    return text_content.strip()

def analyze_sentiment(text_content):
    """Analyze sentiment using Natural Language AI."""
    document = language_v1.Document(
        content=text_content,
        type_=language_v1.Document.Type.PLAIN_TEXT
    )
    
    response = language_client.analyze_sentiment(
        request={"document": document}
    )
    
    sentiment = response.document_sentiment
    
    # Determine overall sentiment category
    if sentiment.score > 0.25:
        overall_sentiment = "POSITIVE"
    elif sentiment.score < -0.25:
        overall_sentiment = "NEGATIVE"
    else:
        overall_sentiment = "NEUTRAL"
    
    return {
        "score": sentiment.score,
        "magnitude": sentiment.magnitude,
        "overall_sentiment": overall_sentiment
    }

def store_sentiment_results(fhir_resource, text_content, sentiment_result):
    """Store sentiment analysis results in BigQuery."""
    import os
    from datetime import datetime
    
    project_id = os.environ.get("GCP_PROJECT")
    dataset_id = os.environ.get("BQ_DATASET")
    table_id = "sentiment_analysis"
    
    table_ref = bq_client.dataset(dataset_id).table(table_id)
    table = bq_client.get_table(table_ref)
    
    # Extract patient ID and observation ID
    patient_id = fhir_resource.get("subject", {}).get("reference", "").replace("Patient/", "")
    observation_id = fhir_resource.get("id", "unknown")
    
    row = {
        "patient_id": patient_id,
        "observation_id": observation_id,
        "text_content": text_content,
        "sentiment_score": sentiment_result["score"],
        "magnitude": sentiment_result["magnitude"],
        "overall_sentiment": sentiment_result["overall_sentiment"],
        "processing_timestamp": datetime.utcnow().isoformat(),
        "fhir_resource_type": "Observation"
    }
    
    errors = bq_client.insert_rows_json(table, [row])
    if errors:
        logging.error(f"BigQuery insert errors: {errors}")
    else:
        logging.info("Sentiment results stored in BigQuery")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-language==2.13.4
google-cloud-bigquery==3.25.0
google-cloud-healthcare==1.12.0
functions-framework==3.5.0
EOF
    
    log_success "Cloud Function code created"
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=python39 \
        --trigger-topic="${PUBSUB_TOPIC}" \
        --entry-point=process_fhir_sentiment \
        --memory=512MB \
        --timeout=540s \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},BQ_DATASET=${BQ_DATASET}" \
        --region="${REGION}" \
        --quiet; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    cd ..
    
    log_success "Cloud Function deployment completed"
}

# Configure IAM permissions
configure_iam() {
    log_info "Configuring IAM permissions for Cloud Function..."
    
    # Get function service account
    local function_sa
    function_sa=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceAccountEmail)")
    
    if [[ -z "${function_sa}" ]]; then
        log_error "Failed to get function service account"
        exit 1
    fi
    
    log_info "Function service account: ${function_sa}"
    
    # Grant Healthcare API access
    log_info "Granting Healthcare API access..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${function_sa}" \
        --role="roles/healthcare.fhirResourceReader" \
        --quiet; then
        log_success "Healthcare API access granted"
    else
        log_error "Failed to grant Healthcare API access"
        exit 1
    fi
    
    # Grant Natural Language API access
    log_info "Granting Natural Language API access..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${function_sa}" \
        --role="roles/ml.developer" \
        --quiet; then
        log_success "Natural Language API access granted"
    else
        log_error "Failed to grant Natural Language API access"
        exit 1
    fi
    
    # Grant BigQuery access
    log_info "Granting BigQuery access..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${function_sa}" \
        --role="roles/bigquery.dataEditor" \
        --quiet; then
        log_success "BigQuery access granted"
    else
        log_error "Failed to grant BigQuery access"
        exit 1
    fi
    
    log_success "IAM permissions configured successfully"
}

# Create sample test data
create_test_data() {
    log_info "Creating sample FHIR test data..."
    
    # Create sample patient record
    cat > sample-patient.json << 'EOF'
{
  "resourceType": "Patient",
  "id": "patient-001",
  "identifier": [
    {
      "use": "usual",
      "system": "http://hospital.example.org",
      "value": "12345"
    }
  ],
  "name": [
    {
      "use": "official",
      "family": "Smith",
      "given": ["John"]
    }
  ],
  "gender": "male",
  "birthDate": "1980-01-01"
}
EOF
    
    # Create sample observations with different sentiments
    cat > positive-observation.json << 'EOF'
{
  "resourceType": "Observation",
  "id": "obs-001",
  "status": "final",
  "category": [
    {
      "coding": [
        {
          "system": "http://terminology.hl7.org/CodeSystem/observation-category",
          "code": "survey",
          "display": "Survey"
        }
      ]
    }
  ],
  "code": {
    "coding": [
      {
        "system": "http://loinc.org",
        "code": "72133-2",
        "display": "Patient satisfaction"
      }
    ]
  },
  "subject": {
    "reference": "Patient/patient-001"
  },
  "valueString": "The staff was incredibly helpful and caring during my stay. The nurses were attentive and made me feel comfortable throughout the treatment process.",
  "note": [
    {
      "text": "Patient expressed high satisfaction with nursing care and overall treatment experience. Mentioned feeling well-supported during recovery period."
    }
  ]
}
EOF
    
    cat > negative-observation.json << 'EOF'
{
  "resourceType": "Observation",
  "id": "obs-002",
  "status": "final",
  "category": [
    {
      "coding": [
        {
          "system": "http://terminology.hl7.org/CodeSystem/observation-category",
          "code": "survey",
          "display": "Survey"
        }
      ]
    }
  ],
  "code": {
    "coding": [
      {
        "system": "http://loinc.org",
        "code": "72133-2",
        "display": "Patient satisfaction"
      }
    ]
  },
  "subject": {
    "reference": "Patient/patient-001"
  },
  "valueString": "The wait times were extremely long and the staff seemed overwhelmed. I felt frustrated and anxious during my visit.",
  "note": [
    {
      "text": "Patient reported dissatisfaction with wait times and perceived staff stress levels affecting their experience."
    }
  ]
}
EOF
    
    cat > neutral-observation.json << 'EOF'
{
  "resourceType": "Observation",
  "id": "obs-003",
  "status": "final",
  "category": [
    {
      "coding": [
        {
          "system": "http://terminology.hl7.org/CodeSystem/observation-category",
          "code": "survey",
          "display": "Survey"
        }
      ]
    }
  ],
  "code": {
    "coding": [
      {
        "system": "http://loinc.org",
        "code": "72133-2",
        "display": "Patient satisfaction"
      }
    ]
  ],
  "subject": {
    "reference": "Patient/patient-001"
  },
  "valueString": "The medical procedure was completed as scheduled. The facility was clean and the equipment appeared modern.",
  "note": [
    {
      "text": "Standard care delivery with no notable positive or negative feedback from patient."
    }
  ]
}
EOF
    
    log_success "Sample FHIR test data created"
}

# Upload test data to FHIR store
upload_test_data() {
    log_info "Uploading test data to FHIR store..."
    
    # Get access token
    local access_token
    access_token=$(gcloud auth print-access-token)
    
    # Upload patient record
    log_info "Uploading patient record..."
    if curl -s -X POST \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/fhir+json" \
        -d @sample-patient.json \
        "https://healthcare.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/datasets/${HEALTHCARE_DATASET}/fhirStores/${FHIR_STORE}/fhir/Patient" \
        > /dev/null; then
        log_success "Patient record uploaded"
    else
        log_warning "Failed to upload patient record (this may be expected)"
    fi
    
    # Upload observation records (these will trigger sentiment analysis)
    local observations=("positive-observation.json" "negative-observation.json" "neutral-observation.json")
    
    for obs_file in "${observations[@]}"; do
        log_info "Uploading ${obs_file}..."
        if curl -s -X POST \
            -H "Authorization: Bearer ${access_token}" \
            -H "Content-Type: application/fhir+json" \
            -d @"${obs_file}" \
            "https://healthcare.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/datasets/${HEALTHCARE_DATASET}/fhirStores/${FHIR_STORE}/fhir/Observation" \
            > /dev/null; then
            log_success "${obs_file} uploaded successfully"
        else
            log_warning "Failed to upload ${obs_file}"
        fi
        
        # Wait between uploads to avoid rate limits
        sleep 2
    done
    
    log_success "Test data upload completed"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check FHIR store
    log_info "Checking FHIR store status..."
    if gcloud healthcare fhir-stores describe "${FHIR_STORE}" \
        --dataset="${HEALTHCARE_DATASET}" \
        --location="${REGION}" > /dev/null 2>&1; then
        log_success "FHIR store is accessible"
    else
        log_error "FHIR store validation failed"
        exit 1
    fi
    
    # Check Cloud Function
    log_info "Checking Cloud Function status..."
    if gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" > /dev/null 2>&1; then
        log_success "Cloud Function is deployed"
    else
        log_error "Cloud Function validation failed"
        exit 1
    fi
    
    # Check BigQuery dataset
    log_info "Checking BigQuery dataset..."
    if bq ls "${PROJECT_ID}:${BQ_DATASET}" > /dev/null 2>&1; then
        log_success "BigQuery dataset is accessible"
    else
        log_error "BigQuery dataset validation failed"
        exit 1
    fi
    
    # Wait for function processing and check results
    log_info "Waiting for sentiment analysis processing (60 seconds)..."
    sleep 60
    
    # Check for sentiment analysis results
    log_info "Checking for sentiment analysis results..."
    local result_count
    result_count=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 \
        "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.${BQ_DATASET}.sentiment_analysis\`" | tail -n +2)
    
    if [[ "${result_count}" -gt 0 ]]; then
        log_success "Sentiment analysis results found: ${result_count} records"
    else
        log_warning "No sentiment analysis results found yet. This may take a few minutes."
    fi
    
    log_success "Deployment validation completed"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.txt << EOF
Healthcare Sentiment Analysis Deployment Information
===================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Healthcare Dataset: ${HEALTHCARE_DATASET}
FHIR Store: ${FHIR_STORE}
Cloud Function: ${FUNCTION_NAME}
Pub/Sub Topic: ${PUBSUB_TOPIC}
BigQuery Dataset: ${BQ_DATASET}

Deployment completed at: $(date)

To view sentiment analysis results:
bq query --use_legacy_sql=false "SELECT * FROM \`${PROJECT_ID}.${BQ_DATASET}.sentiment_analysis\` ORDER BY processing_timestamp DESC"

To view function logs:
gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

To clean up resources:
./destroy.sh

EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    log_info "Starting Healthcare Sentiment Analysis deployment..."
    log_info "This will create a complete patient sentiment analysis pipeline using Google Cloud services"
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_healthcare_resources
    create_pubsub_resources
    create_bigquery_resources
    create_cloud_function
    configure_iam
    create_test_data
    upload_test_data
    validate_deployment
    save_deployment_info
    
    log_success "Healthcare Sentiment Analysis deployment completed successfully!"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Check deployment-info.txt for detailed information"
    log_warning "Remember to clean up resources when done to avoid charges"
    
    # Clean up temporary files
    rm -f sample-*.json positive-*.json negative-*.json neutral-*.json
    rm -rf sentiment-function/
}

# Run main function
main "$@"