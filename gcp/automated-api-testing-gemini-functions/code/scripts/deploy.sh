#!/bin/bash

# Automated API Testing with Gemini and Functions - Deployment Script
# This script deploys the complete AI-powered API testing infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Default configuration
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_ZONE="us-central1-a"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_error "You may need to run the destroy script to clean up partial deployment."
    exit 1
}

trap cleanup_on_error ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Automated API Testing with Gemini and Functions infrastructure on GCP.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -z, --zone ZONE              Deployment zone (default: ${DEFAULT_ZONE})
    -s, --suffix SUFFIX          Custom suffix for resource names (optional)
    -h, --help                   Show this help message
    --skip-apis                  Skip API enablement (assumes APIs are already enabled)
    --dry-run                    Show what would be deployed without executing

Examples:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --region us-west1 --suffix test
    $0 --project-id my-gcp-project --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    PROJECT_ID=""
    REGION="${DEFAULT_REGION}"
    ZONE="${DEFAULT_ZONE}"
    CUSTOM_SUFFIX=""
    SKIP_APIS=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -s|--suffix)
                CUSTOM_SUFFIX="$2"
                shift 2
                ;;
            --skip-apis)
                SKIP_APIS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required. Use -p or --project-id to specify."
        usage
        exit 1
    fi

    # Generate unique suffix if not provided
    if [[ -z "${CUSTOM_SUFFIX}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX="${CUSTOM_SUFFIX}"
    fi

    # Set resource names
    FUNCTION_NAME="api-test-orchestrator-${RANDOM_SUFFIX}"
    SERVICE_NAME="api-test-runner-${RANDOM_SUFFIX}"
    BUCKET_NAME="${PROJECT_ID}-test-results-${RANDOM_SUFFIX}"

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Resource Suffix: ${RANDOM_SUFFIX}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Service Name: ${SERVICE_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install gcloud: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        log_error "Please install Google Cloud SDK with gsutil"
        exit 1
    fi

    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Required for generating random suffixes."
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Verify project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access to it"
        exit 1
    fi

    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Unable to verify billing status. Ensure billing is enabled for the project."
    fi

    log_success "Prerequisites check completed"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project to ${PROJECT_ID}"
        log_info "[DRY RUN] Would set region to ${REGION}"
        log_info "[DRY RUN] Would set zone to ${ZONE}"
        return
    fi

    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"

    log_success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    if [[ "${SKIP_APIS}" == "true" ]]; then
        log_info "Skipping API enablement as requested"
        return
    fi

    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "run.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi

    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${PROJECT_ID}"; then
            log_success "Enabled ${api}"
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

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for test results..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        log_info "[DRY RUN] Would enable versioning and create folder structure"
        return
    fi

    # Check if bucket already exists
    if gsutil ls -b gs://"${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        # Create bucket
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            gs://"${BUCKET_NAME}"
        
        log_success "Created bucket gs://${BUCKET_NAME}"
    fi

    # Enable versioning
    gsutil versioning set on gs://"${BUCKET_NAME}"
    log_success "Enabled versioning on bucket"

    # Create folder structure
    log_info "Setting up bucket folder structure..."
    gsutil cp /dev/null gs://"${BUCKET_NAME}"/test-specifications/.keep
    gsutil cp /dev/null gs://"${BUCKET_NAME}"/test-results/.keep
    gsutil cp /dev/null gs://"${BUCKET_NAME}"/reports/.keep

    log_success "Storage bucket setup completed"
}

# Create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying test generator Cloud Function..."

    local function_dir="${PROJECT_ROOT}/test-generator-function"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create function directory: ${function_dir}"
        log_info "[DRY RUN] Would deploy function: ${FUNCTION_NAME}"
        return
    fi

    # Create function directory
    mkdir -p "${function_dir}"
    cd "${function_dir}"

    # Create main.py
    cat > main.py << 'EOF'
import json
import os
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
import vertexai
from vertexai.generative_models import GenerativeModel

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
LOCATION = os.environ.get('FUNCTION_REGION', 'us-central1')
vertexai.init(project=PROJECT_ID, location=LOCATION)

@functions_framework.http
def generate_test_cases(request):
    """Generate test cases using Gemini AI based on API specification"""
    
    if request.method != 'POST':
        return {'error': 'Only POST method supported'}, 405
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        api_spec = request_json.get('api_specification', '')
        target_endpoints = request_json.get('endpoints', [])
        test_types = request_json.get('test_types', ['functional', 'security', 'performance'])
        
        if not api_spec:
            return {'error': 'API specification required'}, 400
        
        # Initialize Gemini 2.0 Flash model
        model = GenerativeModel("gemini-2.0-flash")
        
        # Create comprehensive prompt for test generation
        prompt = f"""
        Analyze the following API specification and generate comprehensive test cases:
        
        API Specification:
        {api_spec}
        
        Target Endpoints: {target_endpoints if target_endpoints else 'All endpoints'}
        Test Types: {test_types}
        
        Generate test cases that include:
        1. Positive test cases for each endpoint
        2. Negative test cases (invalid inputs, edge cases)
        3. Security test cases (authentication, authorization, input validation)
        4. Performance test cases (load testing scenarios)
        5. Data validation test cases
        
        Format the response as a JSON array with the following structure:
        {{
            "test_cases": [
                {{
                    "id": "unique_test_id",
                    "name": "test_case_name",
                    "description": "test_description",
                    "endpoint": "api_endpoint",
                    "method": "HTTP_method",
                    "headers": {{}},
                    "payload": {{}},
                    "expected_status": 200,
                    "expected_response": {{}},
                    "test_type": "functional|security|performance",
                    "priority": "high|medium|low"
                }}
            ]
        }}
        
        Ensure test cases cover edge cases, error conditions, and security vulnerabilities.
        """
        
        # Generate test cases using Gemini
        response = model.generate_content(prompt)
        
        # Parse and validate the AI response
        ai_response = response.text
        
        # Store generated test cases in Cloud Storage
        storage_client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME')
        bucket = storage_client.bucket(bucket_name)
        
        # Create blob for test cases
        blob_name = f"test-specifications/generated-tests-{request_json.get('request_id', 'unknown')}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(ai_response, content_type='application/json')
        
        return {
            'status': 'success',
            'test_cases_generated': True,
            'storage_location': f"gs://{bucket_name}/{blob_name}",
            'ai_response': ai_response
        }
        
    except Exception as e:
        return {'error': f'Test generation failed: {str(e)}'}, 500

EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-aiplatform==1.70.*
google-cloud-storage==2.18.*
vertexai==1.70.*
EOF

    # Deploy the function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --source . \
        --entry-point generate_test_cases \
        --memory 1GB \
        --timeout 300s \
        --set-env-vars BUCKET_NAME="${BUCKET_NAME}" \
        --allow-unauthenticated \
        --region="${REGION}"

    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")

    cd - > /dev/null

    log_success "Cloud Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}"
}

# Create and deploy Cloud Run service
deploy_cloud_run_service() {
    log_info "Creating and deploying test runner Cloud Run service..."

    local service_dir="${PROJECT_ROOT}/test-runner-service"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create service directory: ${service_dir}"
        log_info "[DRY RUN] Would deploy service: ${SERVICE_NAME}"
        return
    fi

    # Create service directory
    mkdir -p "${service_dir}"
    cd "${service_dir}"

    # Create main.py
    cat > main.py << 'EOF'
import json
import os
import time
import requests
from google.cloud import storage
from google.cloud import logging as cloud_logging
from flask import Flask, request, jsonify
import concurrent.futures
from threading import Lock

app = Flask(__name__)

# Initialize Cloud Logging
logging_client = cloud_logging.Client()
logging_client.setup_logging()

# Thread-safe result storage
results_lock = Lock()
test_results = []

class APITestRunner:
    def __init__(self, bucket_name):
        self.storage_client = storage.Client()
        self.bucket_name = bucket_name
        
    def execute_test_case(self, test_case):
        """Execute a single test case and return results"""
        start_time = time.time()
        
        try:
            # Prepare request
            url = test_case.get('endpoint', '')
            method = test_case.get('method', 'GET').upper()
            headers = test_case.get('headers', {})
            payload = test_case.get('payload', {})
            expected_status = test_case.get('expected_status', 200)
            timeout = test_case.get('timeout', 30)
            
            # Execute HTTP request
            response = requests.request(
                method=method,
                url=url,
                headers=headers,
                json=payload if payload else None,
                timeout=timeout
            )
            
            execution_time = time.time() - start_time
            
            # Validate response
            status_match = response.status_code == expected_status
            
            # Create test result
            result = {
                'test_id': test_case.get('id'),
                'test_name': test_case.get('name'),
                'status': 'PASSED' if status_match else 'FAILED',
                'execution_time': execution_time,
                'actual_status': response.status_code,
                'expected_status': expected_status,
                'response_size': len(response.content),
                'endpoint': url,
                'method': method,
                'timestamp': time.time(),
                'error_message': None if status_match else f"Status mismatch: expected {expected_status}, got {response.status_code}"
            }
            
            return result
            
        except Exception as e:
            execution_time = time.time() - start_time
            return {
                'test_id': test_case.get('id'),
                'test_name': test_case.get('name'),
                'status': 'ERROR',
                'execution_time': execution_time,
                'actual_status': None,
                'expected_status': test_case.get('expected_status'),
                'response_size': 0,
                'endpoint': test_case.get('endpoint'),
                'method': test_case.get('method'),
                'timestamp': time.time(),
                'error_message': str(e)
            }
    
    def run_test_suite(self, test_cases, max_workers=10):
        """Execute multiple test cases concurrently"""
        results = []
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_test = {
                executor.submit(self.execute_test_case, test_case): test_case 
                for test_case in test_cases
            }
            
            for future in concurrent.futures.as_completed(future_to_test):
                result = future.result()
                results.append(result)
        
        return results
    
    def save_results(self, results, test_run_id):
        """Save test results to Cloud Storage"""
        bucket = self.storage_client.bucket(self.bucket_name)
        
        # Save detailed results
        results_blob = bucket.blob(f"test-results/{test_run_id}-detailed.json")
        results_blob.upload_from_string(
            json.dumps(results, indent=2),
            content_type='application/json'
        )
        
        # Generate summary report
        summary = self.generate_summary(results)
        summary_blob = bucket.blob(f"reports/{test_run_id}-summary.json")
        summary_blob.upload_from_string(
            json.dumps(summary, indent=2),
            content_type='application/json'
        )
        
        return {
            'detailed_results': f"gs://{self.bucket_name}/test-results/{test_run_id}-detailed.json",
            'summary_report': f"gs://{self.bucket_name}/reports/{test_run_id}-summary.json"
        }
    
    def generate_summary(self, results):
        """Generate test execution summary"""
        total_tests = len(results)
        passed_tests = sum(1 for r in results if r['status'] == 'PASSED')
        failed_tests = sum(1 for r in results if r['status'] == 'FAILED')
        error_tests = sum(1 for r in results if r['status'] == 'ERROR')
        
        avg_execution_time = sum(r['execution_time'] for r in results) / total_tests if total_tests > 0 else 0
        
        return {
            'test_run_timestamp': time.time(),
            'total_tests': total_tests,
            'passed_tests': passed_tests,
            'failed_tests': failed_tests,
            'error_tests': error_tests,
            'pass_rate': (passed_tests / total_tests * 100) if total_tests > 0 else 0,
            'average_execution_time': avg_execution_time,
            'fastest_test': min((r['execution_time'] for r in results), default=0),
            'slowest_test': max((r['execution_time'] for r in results), default=0)
        }

@app.route('/run-tests', methods=['POST'])
def run_tests():
    """Execute test cases provided in request"""
    try:
        data = request.get_json()
        test_cases = data.get('test_cases', [])
        test_run_id = data.get('test_run_id', f"run-{int(time.time())}")
        
        if not test_cases:
            return jsonify({'error': 'No test cases provided'}), 400
        
        # Initialize test runner
        bucket_name = os.environ.get('BUCKET_NAME')
        runner = APITestRunner(bucket_name)
        
        # Execute tests
        results = runner.run_test_suite(test_cases)
        
        # Save results
        storage_info = runner.save_results(results, test_run_id)
        
        return jsonify({
            'status': 'completed',
            'test_run_id': test_run_id,
            'total_tests': len(results),
            'results_summary': runner.generate_summary(results),
            'storage_locations': storage_info
        })
        
    except Exception as e:
        return jsonify({'error': f'Test execution failed: {str(e)}'}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': time.time()})

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
Flask==3.0.*
google-cloud-storage==2.18.*
google-cloud-logging==3.11.*
requests==2.32.*
gunicorn==23.0.*
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app"]
EOF

    # Deploy the service
    log_info "Deploying Cloud Run service..."
    gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --region="${REGION}" \
        --allow-unauthenticated \
        --set-env-vars BUCKET_NAME="${BUCKET_NAME}" \
        --memory 2Gi \
        --cpu 2 \
        --timeout 900 \
        --max-instances 10 \
        --platform managed

    # Get service URL
    SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --format="value(status.url)")

    cd - > /dev/null

    log_success "Cloud Run service deployed successfully"
    log_info "Service URL: ${SERVICE_URL}"
}

# Create workflow script
create_workflow_script() {
    log_info "Creating end-to-end testing workflow script..."

    local workflow_file="${PROJECT_ROOT}/test-workflow.py"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create workflow script: ${workflow_file}"
        return
    fi

    cat > "${workflow_file}" << 'EOF'
import json
import requests
import time
import sys
import os

def run_api_testing_workflow(api_spec, target_base_url):
    """Complete API testing workflow"""
    
    print("🚀 Starting automated API testing workflow...")
    
    # Step 1: Generate test cases using AI
    print("\n📝 Generating test cases with Gemini AI...")
    
    function_url = os.environ.get('FUNCTION_URL')
    if not function_url:
        print("❌ FUNCTION_URL environment variable not set")
        return False
    
    generation_payload = {
        "api_specification": api_spec,
        "endpoints": [f"{target_base_url}/posts", f"{target_base_url}/users"],
        "test_types": ["functional", "security"],
        "request_id": f"workflow-{int(time.time())}"
    }
    
    response = requests.post(function_url, json=generation_payload)
    
    if response.status_code != 200:
        print(f"❌ Test generation failed: {response.text}")
        return False
    
    generation_result = response.json()
    print(f"✅ Test cases generated: {generation_result['storage_location']}")
    
    # Parse AI-generated test cases
    try:
        ai_response = json.loads(generation_result['ai_response'])
        test_cases = ai_response.get('test_cases', [])
    except json.JSONDecodeError:
        print("❌ Failed to parse AI-generated test cases")
        return False
    
    print(f"📋 Generated {len(test_cases)} test cases")
    
    # Step 2: Execute test cases
    print("\n🧪 Executing test cases...")
    
    service_url = os.environ.get('SERVICE_URL')
    if not service_url:
        print("❌ SERVICE_URL environment variable not set")
        return False
    
    test_run_id = f"workflow-{int(time.time())}"
    
    execution_payload = {
        "test_cases": test_cases,
        "test_run_id": test_run_id
    }
    
    response = requests.post(f"{service_url}/run-tests", json=execution_payload)
    
    if response.status_code != 200:
        print(f"❌ Test execution failed: {response.text}")
        return False
    
    execution_result = response.json()
    print(f"✅ Test execution completed: {execution_result['test_run_id']}")
    
    # Step 3: Display results
    print("\n📊 Test Results Summary:")
    summary = execution_result['results_summary']
    print(f"   Total Tests: {summary['total_tests']}")
    print(f"   Passed: {summary['passed_tests']}")
    print(f"   Failed: {summary['failed_tests']}")
    print(f"   Errors: {summary['error_tests']}")
    print(f"   Pass Rate: {summary['pass_rate']:.1f}%")
    print(f"   Avg Execution Time: {summary['average_execution_time']:.2f}s")
    
    storage_locations = execution_result['storage_locations']
    print(f"\n💾 Results stored at:")
    print(f"   Detailed: {storage_locations['detailed_results']}")
    print(f"   Summary: {storage_locations['summary_report']}")
    
    return True

# Example API specification for demonstration
sample_api_spec = '''
{
  "openapi": "3.0.0",
  "info": {
    "title": "JSONPlaceholder API",
    "version": "1.0.0"
  },
  "paths": {
    "/posts": {
      "get": {
        "summary": "Get all posts",
        "responses": {
          "200": {
            "description": "List of posts"
          }
        }
      },
      "post": {
        "summary": "Create post",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "title": {"type": "string"},
                  "body": {"type": "string"},
                  "userId": {"type": "integer"}
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Post created"
          }
        }
      }
    },
    "/users": {
      "get": {
        "summary": "Get all users",
        "responses": {
          "200": {
            "description": "List of users"
          }
        }
      }
    }
  }
}
'''

if __name__ == "__main__":
    # Use JSONPlaceholder for testing - a free REST API for testing
    target_url = "https://jsonplaceholder.typicode.com"
    
    if run_api_testing_workflow(sample_api_spec, target_url):
        print("\n🎉 Automated API testing workflow completed successfully!")
    else:
        print("\n💥 Workflow failed!")
        sys.exit(1)
EOF

    chmod +x "${workflow_file}"

    log_success "Workflow script created successfully"
    log_info "Usage: FUNCTION_URL=<function-url> SERVICE_URL=<service-url> python ${workflow_file}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment with health checks"
        return
    fi

    # Test Cloud Function health
    log_info "Testing Cloud Function deployment..."
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_success "Cloud Function is deployed and accessible"
    else
        log_error "Cloud Function validation failed"
        return 1
    fi

    # Test Cloud Run service health
    log_info "Testing Cloud Run service deployment..."
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &> /dev/null; then
        log_success "Cloud Run service is deployed and accessible"
    else
        log_error "Cloud Run service validation failed"
        return 1
    fi

    # Test storage bucket access
    log_info "Testing storage bucket access..."
    if gsutil ls gs://"${BUCKET_NAME}" &> /dev/null; then
        log_success "Storage bucket is accessible"
    else
        log_error "Storage bucket validation failed"
        return 1
    fi

    log_success "Deployment validation completed successfully"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."

    local deployment_info_file="${SCRIPT_DIR}/deployment_info.env"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would save deployment info to: ${deployment_info_file}"
        return
    fi

    cat > "${deployment_info_file}" << EOF
# Automated API Testing with Gemini and Functions - Deployment Information
# Generated on $(date)

export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export SERVICE_NAME="${SERVICE_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export FUNCTION_URL="${FUNCTION_URL:-}"
export SERVICE_URL="${SERVICE_URL:-}"

# Usage:
# source ${deployment_info_file}
# FUNCTION_URL=\${FUNCTION_URL} SERVICE_URL=\${SERVICE_URL} python test-workflow.py
EOF

    log_success "Deployment information saved to: ${deployment_info_file}"
}

# Print deployment summary
print_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log_info ""
    log_info "Deployed Infrastructure:"
    log_info "  📦 Project ID: ${PROJECT_ID}"
    log_info "  🌍 Region: ${REGION}"
    log_info "  ⚡ Cloud Function: ${FUNCTION_NAME}"
    log_info "  🚀 Cloud Run Service: ${SERVICE_NAME}"
    log_info "  💾 Storage Bucket: gs://${BUCKET_NAME}"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Source the deployment info: source ${SCRIPT_DIR}/deployment_info.env"
    log_info "  2. Test the workflow: FUNCTION_URL=\${FUNCTION_URL} SERVICE_URL=\${SERVICE_URL} python test-workflow.py"
    log_info "  3. Monitor usage in Google Cloud Console"
    log_info "  4. When done testing, run the destroy script: ./destroy.sh --project-id ${PROJECT_ID}"
    log_info ""
    log_info "Estimated monthly cost: \$5-15 for moderate usage"
    log_info "Log file: ${LOG_FILE}"
}

# Main execution
main() {
    log_info "=== Automated API Testing with Gemini and Functions - Deployment Script ==="
    log_info "Starting deployment at $(date)"
    log_info ""

    parse_args "$@"
    check_prerequisites
    configure_gcloud
    enable_apis
    create_storage_bucket
    deploy_cloud_function
    deploy_cloud_run_service
    create_workflow_script
    validate_deployment
    save_deployment_info
    print_summary

    log_success "Deployment completed successfully in $(date)"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi