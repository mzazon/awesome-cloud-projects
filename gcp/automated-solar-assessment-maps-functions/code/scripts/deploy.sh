#!/bin/bash

# Automated Solar Assessment with Solar API and Functions - Deployment Script
# This script deploys the complete infrastructure for automated solar property assessment
# including Cloud Storage buckets, Cloud Functions, and Google Maps Platform API configuration

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    echo -e "${RED}Deployment failed. Check ${LOG_FILE} for details.${NC}"
    exit 1
}

# Success message function
success() {
    log "INFO" "$1"
    echo -e "${GREEN}✅ $1${NC}"
}

# Info message function
info() {
    log "INFO" "$1"
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Warning message function
warning() {
    log "WARN" "$1"
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating deployment prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
        error_exit "Not authenticated with Google Cloud. Please run: gcloud auth login"
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error_exit "Google Cloud project not set. Please run: gcloud config set project YOUR_PROJECT_ID"
        fi
    fi
    
    success "Prerequisites validation completed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Use existing PROJECT_ID or get from gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    fi
    
    # Set default region if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names to avoid conflicts
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "${TIMESTAMP: -6}")
    export FUNCTION_NAME="${FUNCTION_NAME:-solar-processor-${RANDOM_SUFFIX}}"
    export INPUT_BUCKET="${INPUT_BUCKET:-solar-input-${RANDOM_SUFFIX}}"
    export OUTPUT_BUCKET="${OUTPUT_BUCKET:-solar-results-${RANDOM_SUFFIX}}"
    export API_KEY_NAME="${API_KEY_NAME:-solar-assessment-key-${RANDOM_SUFFIX}}"
    
    # Display configuration
    info "Deployment configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Function Name: ${FUNCTION_NAME}"
    echo "  Input Bucket: gs://${INPUT_BUCKET}"
    echo "  Output Bucket: gs://${OUTPUT_BUCKET}"
    echo "  API Key Name: ${API_KEY_NAME}"
    
    success "Environment setup completed"
}

# Enable required Google Cloud APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "solar.googleapis.com"
        "serviceusage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${PROJECT_ID}" 2>>"${LOG_FILE}"; then
            success "Enabled ${api}"
        else
            error_exit "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully activated..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    info "Creating Cloud Storage buckets..."
    
    # Create input bucket
    info "Creating input bucket: gs://${INPUT_BUCKET}"
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${INPUT_BUCKET}" 2>>"${LOG_FILE}"; then
        success "Created input bucket: gs://${INPUT_BUCKET}"
    else
        error_exit "Failed to create input bucket"
    fi
    
    # Create output bucket
    info "Creating output bucket: gs://${OUTPUT_BUCKET}"
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${OUTPUT_BUCKET}" 2>>"${LOG_FILE}"; then
        success "Created output bucket: gs://${OUTPUT_BUCKET}"
    else
        error_exit "Failed to create output bucket"
    fi
    
    # Enable versioning for data protection
    info "Enabling versioning on buckets..."
    gsutil versioning set on "gs://${INPUT_BUCKET}" 2>>"${LOG_FILE}" || warning "Failed to enable versioning on input bucket"
    gsutil versioning set on "gs://${OUTPUT_BUCKET}" 2>>"${LOG_FILE}" || warning "Failed to enable versioning on output bucket"
    
    success "Cloud Storage buckets created successfully"
}

# Create Google Maps Platform API key
create_api_key() {
    info "Creating Google Maps Platform API key..."
    
    # Check if API key already exists
    if gcloud services api-keys list --filter="displayName:${API_KEY_NAME}" --format="value(name)" 2>/dev/null | grep -q "${API_KEY_NAME}"; then
        warning "API key ${API_KEY_NAME} already exists, skipping creation"
        SOLAR_API_KEY=$(gcloud services api-keys get-key-string --location=global "${API_KEY_NAME}" --format="value(keyString)" 2>/dev/null)
    else
        # Create the API key
        info "Creating new API key: ${API_KEY_NAME}"
        if gcloud services api-keys create --display-name="${API_KEY_NAME}" --api-restrictions-service=solar.googleapis.com 2>>"${LOG_FILE}"; then
            success "Created API key: ${API_KEY_NAME}"
            
            # Get the key string
            SOLAR_API_KEY=$(gcloud services api-keys get-key-string --location=global "${API_KEY_NAME}" --format="value(keyString)" 2>/dev/null)
            
            if [[ -z "${SOLAR_API_KEY}" ]]; then
                error_exit "Failed to retrieve API key string"
            fi
        else
            error_exit "Failed to create API key"
        fi
    fi
    
    export SOLAR_API_KEY
    success "API key configuration completed"
}

# Prepare Cloud Function source code
prepare_function_source() {
    info "Preparing Cloud Function source code..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    mkdir -p "${function_dir}"
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.6.0
google-cloud-storage==2.17.0
requests==2.32.3
pandas==2.2.2
EOF
    
    # Create main.py with the Cloud Function code
    cat > "${function_dir}/main.py" << 'EOF'
import json
import pandas as pd
import requests
from google.cloud import storage
import os
from io import StringIO
import functions_framework
import time

# Initialize Cloud Storage client
storage_client = storage.Client()

@functions_framework.cloud_event
def process_solar_assessment(cloud_event):
    """
    Process uploaded CSV files and perform solar assessments
    Triggered by Cloud Storage object creation events
    """
    # Extract file information from cloud event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    # Only process CSV files
    if not file_name.endswith('.csv'):
        print(f"Skipping non-CSV file: {file_name}")
        return
    
    print(f"Processing solar assessment for: {file_name}")
    
    try:
        # Download CSV file from input bucket
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        csv_content = blob.download_as_text()
        
        # Parse CSV file
        df = pd.read_csv(StringIO(csv_content))
        
        # Validate required columns
        required_columns = ['address', 'latitude', 'longitude']
        if not all(col in df.columns for col in required_columns):
            raise ValueError(f"CSV must contain columns: {required_columns}")
        
        # Process each property
        results = []
        solar_api_key = os.environ.get('SOLAR_API_KEY')
        
        if not solar_api_key:
            raise ValueError("SOLAR_API_KEY environment variable not set")
        
        for index, row in df.iterrows():
            try:
                solar_data = get_building_insights(
                    row['latitude'], 
                    row['longitude'], 
                    solar_api_key
                )
                
                # Extract solar potential data with safe navigation
                solar_potential = solar_data.get('solarPotential', {})
                roof_stats = solar_potential.get('wholeRoofStats', {})
                
                # Combine original data with solar insights
                result = {
                    'address': row['address'],
                    'latitude': row['latitude'],
                    'longitude': row['longitude'],
                    'solar_potential_kwh_per_year': solar_potential.get('maxArrayPanelsCount', 0) * 400,  # Estimated 400 kWh per panel
                    'roof_area_sqm': roof_stats.get('areaMeters2', 0),
                    'max_panels': solar_potential.get('maxArrayPanelsCount', 0),
                    'sunshine_quantiles': roof_stats.get('sunshineQuantiles', []),
                    'imagery_quality': solar_data.get('imageryQuality', 'UNKNOWN'),
                    'postal_code': solar_data.get('postalCode', ''),
                    'region_code': solar_data.get('regionCode', ''),
                    'assessment_timestamp': pd.Timestamp.now().isoformat()
                }
                results.append(result)
                
                print(f"✅ Processed: {row['address']}")
                
                # Add delay to respect API rate limits
                time.sleep(0.1)
                
            except Exception as e:
                print(f"❌ Error processing {row['address']}: {str(e)}")
                # Add error record to maintain data completeness
                results.append({
                    'address': row['address'],
                    'latitude': row['latitude'],
                    'longitude': row['longitude'],
                    'error': str(e),
                    'assessment_timestamp': pd.Timestamp.now().isoformat()
                })
        
        # Save results to output bucket
        output_bucket_name = os.environ.get('OUTPUT_BUCKET')
        if output_bucket_name:
            save_results_to_storage(results, output_bucket_name, file_name)
        
        print(f"✅ Solar assessment completed for {len(results)} properties")
        
    except Exception as e:
        print(f"❌ Error processing file {file_name}: {str(e)}")
        raise

def get_building_insights(latitude, longitude, api_key):
    """
    Get solar insights for a building location using Solar API
    """
    url = "https://solar.googleapis.com/v1/buildingInsights:findClosest"
    
    params = {
        'location.latitude': latitude,
        'location.longitude': longitude,
        'requiredQuality': 'MEDIUM',
        'key': api_key
    }
    
    try:
        response = requests.get(url, params=params, timeout=30)
        
        if response.status_code == 200:
            return response.json()
        elif response.status_code == 404:
            # Building not found - return empty data structure
            return {
                'solarPotential': {
                    'maxArrayPanelsCount': 0,
                    'wholeRoofStats': {
                        'areaMeters2': 0,
                        'sunshineQuantiles': []
                    }
                },
                'imageryQuality': 'NOT_FOUND'
            }
        else:
            response.raise_for_status()
    except requests.RequestException as e:
        print(f"API request failed: {str(e)}")
        raise

def save_results_to_storage(results, bucket_name, original_filename):
    """
    Save assessment results to Cloud Storage
    """
    # Create results DataFrame
    results_df = pd.DataFrame(results)
    
    # Generate output filename
    base_name = original_filename.replace('.csv', '')
    output_filename = f"{base_name}_solar_assessment_{pd.Timestamp.now().strftime('%Y%m%d_%H%M%S')}.csv"
    
    # Save to output bucket
    output_bucket = storage_client.bucket(bucket_name)
    output_blob = output_bucket.blob(output_filename)
    
    # Convert DataFrame to CSV string and upload
    csv_string = results_df.to_csv(index=False)
    output_blob.upload_from_string(csv_string, content_type='text/csv')
    
    print(f"✅ Results saved to gs://{bucket_name}/{output_filename}")
EOF
    
    success "Cloud Function source code prepared"
}

# Deploy Cloud Function
deploy_function() {
    info "Deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" 2>>"${LOG_FILE}"
    gcloud config set compute/region "${REGION}" 2>>"${LOG_FILE}"
    gcloud config set functions/region "${REGION}" 2>>"${LOG_FILE}"
    
    # Deploy the Cloud Function
    info "Deploying function: ${FUNCTION_NAME}"
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-bucket "${INPUT_BUCKET}" \
        --source "${function_dir}" \
        --entry-point process_solar_assessment \
        --memory 512Mi \
        --timeout 540s \
        --set-env-vars "SOLAR_API_KEY=${SOLAR_API_KEY},OUTPUT_BUCKET=${OUTPUT_BUCKET}" \
        --max-instances 10 \
        --region "${REGION}" \
        --project "${PROJECT_ID}" \
        --quiet 2>>"${LOG_FILE}"; then
        success "Cloud Function deployed successfully: ${FUNCTION_NAME}"
    else
        error_exit "Failed to deploy Cloud Function"
    fi
}

# Create sample test data
create_sample_data() {
    info "Creating sample property data for testing..."
    
    local sample_file="${SCRIPT_DIR}/sample_properties.csv"
    
    cat > "${sample_file}" << 'EOF'
address,latitude,longitude
"1600 Amphitheatre Pkwy, Mountain View, CA",37.4220041,-122.0862515
"One Apple Park Way, Cupertino, CA",37.3348274,-122.0090531
"1 Tesla Rd, Austin, TX",30.2711286,-97.7436995
"350 5th Ave, New York, NY",40.7484405,-73.9856644
"Space Needle, Seattle, WA",47.6205063,-122.3492774
EOF
    
    success "Sample property data created: ${sample_file}"
    info "Upload this file to gs://${INPUT_BUCKET}/ to test the solar assessment pipeline"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    # Check if buckets exist
    if gsutil ls -b "gs://${INPUT_BUCKET}" >/dev/null 2>&1; then
        success "Input bucket verified: gs://${INPUT_BUCKET}"
    else
        error_exit "Input bucket not found: gs://${INPUT_BUCKET}"
    fi
    
    if gsutil ls -b "gs://${OUTPUT_BUCKET}" >/dev/null 2>&1; then
        success "Output bucket verified: gs://${OUTPUT_BUCKET}"
    else
        error_exit "Output bucket not found: gs://${OUTPUT_BUCKET}"
    fi
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        success "Cloud Function verified: ${FUNCTION_NAME}"
    else
        error_exit "Cloud Function not found: ${FUNCTION_NAME}"
    fi
    
    # Check if API key exists
    if gcloud services api-keys list --filter="displayName:${API_KEY_NAME}" --format="value(name)" | grep -q "${API_KEY_NAME}"; then
        success "API key verified: ${API_KEY_NAME}"
    else
        error_exit "API key not found: ${API_KEY_NAME}"
    fi
    
    success "Deployment verification completed successfully"
}

# Display deployment summary
display_summary() {
    echo
    echo "=========================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo
    echo "📋 Deployment Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Function Name: ${FUNCTION_NAME}"
    echo "  Input Bucket: gs://${INPUT_BUCKET}"
    echo "  Output Bucket: gs://${OUTPUT_BUCKET}"
    echo "  API Key Name: ${API_KEY_NAME}"
    echo
    echo "🚀 Next Steps:"
    echo "  1. Upload CSV files to gs://${INPUT_BUCKET}/ to trigger processing"
    echo "  2. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "  3. Check results in: gs://${OUTPUT_BUCKET}/"
    echo "  4. Use sample data: ${SCRIPT_DIR}/sample_properties.csv"
    echo
    echo "📊 Test the deployment:"
    echo "  gsutil cp ${SCRIPT_DIR}/sample_properties.csv gs://${INPUT_BUCKET}/"
    echo
    echo "📝 View logs:"
    echo "  tail -f ${LOG_FILE}"
    echo
    warning "IMPORTANT: Remember to run destroy.sh when you're done to avoid ongoing charges"
    echo
}

# Main deployment function
main() {
    echo "Starting automated solar assessment infrastructure deployment..."
    echo "Log file: ${LOG_FILE}"
    echo
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Execute deployment steps
    validate_prerequisites
    setup_environment
    enable_apis
    create_storage_buckets
    create_api_key
    prepare_function_source
    deploy_function
    create_sample_data
    verify_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error_exit "Deployment interrupted by user"' INT TERM

# Execute main function
main "$@"