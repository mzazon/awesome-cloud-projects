#!/bin/bash

#################################################################################
# Smart Contract Security Auditing Deployment Script
# 
# This script deploys a complete smart contract security auditing solution
# using Google Cloud Document AI and Vertex AI services.
#
# Components deployed:
# - Cloud Storage bucket with lifecycle policies
# - Document AI processor for contract analysis  
# - Cloud Function with storage trigger
# - Sample contracts and documentation for testing
#
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Project with billing enabled
# - Required IAM permissions (Document AI Editor, Vertex AI User)
#################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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
    log_error "Run destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Initialize deployment variables
initialize_variables() {
    log_info "Initializing deployment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-smart-contract-audit-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-contract-audit-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-contract-security-analyzer}"
    
    # Save deployment state
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Variables initialized - Project: ${PROJECT_ID}, Region: ${REGION}"
}

# Configure project and enable APIs
configure_project() {
    log_info "Configuring Google Cloud project and enabling APIs..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"
    gcloud config set compute/region "${REGION}" 2>&1 | tee -a "${LOG_FILE}"
    gcloud config set compute/zone "${ZONE}" 2>&1 | tee -a "${LOG_FILE}"
    
    # Enable required APIs
    log_info "Enabling required APIs (this may take a few minutes)..."
    gcloud services enable documentai.googleapis.com \
        aiplatform.googleapis.com \
        cloudfunctions.googleapis.com \
        storage.googleapis.com \
        eventarc.googleapis.com \
        artifactregistry.googleapis.com \
        cloudbuild.googleapis.com 2>&1 | tee -a "${LOG_FILE}"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be ready..."
    sleep 30
    
    log_success "Project configured and APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for contract artifacts..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" 2>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create storage bucket with uniform access control
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
    
    # Enable versioning for audit trail compliance
    gsutil versioning set on "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
    
    # Create and set bucket lifecycle policy for cost optimization
    cat > "${SCRIPT_DIR}/lifecycle.json" << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
    
    # Create directory structure in bucket
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/contracts/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/documentation/.placeholder"
    echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/audit-reports/.placeholder"
    
    log_success "Storage bucket created: gs://${BUCKET_NAME}"
}

# Create Document AI processor
create_document_ai_processor() {
    log_info "Creating Document AI processor for contract analysis..."
    
    # Check if processor already exists
    EXISTING_PROCESSOR=$(gcloud documentai processors list \
        --location="${REGION}" \
        --filter="displayName:'Smart Contract Security Parser'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${EXISTING_PROCESSOR}" ]]; then
        export PROCESSOR_ID=$(echo "${EXISTING_PROCESSOR}" | cut -d'/' -f6)
        log_warning "Document AI processor already exists: ${PROCESSOR_ID}"
        # Update deployment state
        echo "PROCESSOR_ID=${PROCESSOR_ID}" >> "${DEPLOYMENT_STATE_FILE}"
        return 0
    fi
    
    # Create Document AI processor for smart contract parsing
    gcloud documentai processors create \
        --location="${REGION}" \
        --display-name="Smart Contract Security Parser" \
        --type="FORM_PARSER_PROCESSOR" 2>&1 | tee -a "${LOG_FILE}"
    
    # Get the processor ID for use in Cloud Functions
    export PROCESSOR_ID=$(gcloud documentai processors list \
        --location="${REGION}" \
        --filter="displayName:'Smart Contract Security Parser'" \
        --format="value(name)" | cut -d'/' -f6)
    
    if [[ -z "${PROCESSOR_ID}" ]]; then
        log_error "Failed to retrieve Document AI processor ID"
        exit 1
    fi
    
    # Update deployment state
    echo "PROCESSOR_ID=${PROCESSOR_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log_success "Document AI processor created: ${PROCESSOR_ID}"
}

# Prepare Cloud Function source code
prepare_function_code() {
    log_info "Preparing Cloud Function source code..."
    
    # Create function source directory
    FUNCTION_DIR="${SCRIPT_DIR}/contract-security-function"
    mkdir -p "${FUNCTION_DIR}"
    
    # Create main function file
    cat > "${FUNCTION_DIR}/main.py" << 'EOF'
import functions_framework
from google.cloud import documentai_v1 as documentai
from google.cloud import aiplatform
from google.cloud import storage
import json
import os
import re
from typing import Dict, List

# Initialize clients
storage_client = storage.Client()
docai_client = documentai.DocumentProcessorServiceClient()

@functions_framework.cloud_event
def analyze_contract_security(cloud_event):
    """Analyze smart contract for security vulnerabilities using Document AI and Vertex AI"""
    
    # Extract file information from Cloud Storage event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    print(f"Processing contract file: {file_name}")
    
    # Download contract file from Cloud Storage
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    if not file_name.endswith(('.sol', '.txt', '.md', '.pdf')):
        print(f"Skipping non-contract file: {file_name}")
        return
    
    # Extract text using Document AI
    extracted_text = process_with_document_ai(blob)
    
    # Analyze for security vulnerabilities using Vertex AI
    vulnerability_report = analyze_with_vertex_ai(extracted_text, file_name)
    
    # Save audit report to Cloud Storage
    save_audit_report(bucket, file_name, vulnerability_report)
    
    print(f"Security analysis completed for: {file_name}")

def process_with_document_ai(blob) -> str:
    """Extract text from contract file using Document AI"""
    
    project_id = os.environ.get('GCP_PROJECT')
    location = os.environ.get('PROCESSOR_LOCATION', 'us-central1')
    processor_id = os.environ.get('PROCESSOR_ID')
    
    # Read file content
    file_content = blob.download_as_bytes()
    
    # Create Document AI request
    name = f"projects/{project_id}/locations/{location}/processors/{processor_id}"
    
    request = documentai.ProcessRequest(
        name=name,
        raw_document=documentai.RawDocument(
            content=file_content,
            mime_type=get_mime_type(blob.name)
        )
    )
    
    # Process document
    result = docai_client.process_document(request=request)
    document = result.document
    
    return document.text

def get_mime_type(filename: str) -> str:
    """Determine MIME type based on file extension"""
    
    if filename.endswith('.pdf'):
        return 'application/pdf'
    elif filename.endswith(('.sol', '.txt', '.md')):
        return 'text/plain'
    else:
        return 'application/octet-stream'

def analyze_with_vertex_ai(contract_text: str, filename: str) -> Dict:
    """Analyze contract for security vulnerabilities using Vertex AI"""
    
    # Initialize Vertex AI
    aiplatform.init(project=os.environ.get('GCP_PROJECT'), location=os.environ.get('PROCESSOR_LOCATION', 'us-central1'))
    
    # Security analysis prompt based on OWASP Smart Contract Top 10
    security_prompt = f"""
    Analyze the following smart contract for security vulnerabilities based on the OWASP Smart Contract Top 10 (2025):

    Contract File: {filename}
    Contract Code:
    {contract_text}

    Please identify and analyze potential vulnerabilities in these categories:
    1. Access Control Flaws - Check for missing or improper access modifiers
    2. Logic Errors - Look for calculation errors, race conditions, or flawed business logic
    3. Lack of Input Validation - Identify missing input checks and validation
    4. Reentrancy Vulnerabilities - Check for state changes after external calls
    5. Integer Overflow/Underflow - Look for arithmetic operations without safe math
    6. Gas Limit Issues - Identify unbounded loops or expensive operations
    7. Timestamp Dependence - Check for reliance on block.timestamp
    8. Front-running Vulnerabilities - Look for transaction ordering dependencies
    9. Denial of Service - Identify potential DoS attack vectors
    10. Cryptographic Issues - Check for weak randomness or poor key management

    For each vulnerability found, provide:
    - Severity Level (Critical/High/Medium/Low)
    - Line numbers or code sections affected
    - Detailed explanation of the vulnerability
    - Recommended remediation steps
    - Code examples of secure alternatives

    Format your response as JSON with the following structure:
    {{
        "contract_name": "{filename}",
        "overall_risk_score": "1-10",
        "vulnerabilities_found": [],
        "recommendations": [],
        "compliance_status": "Pass/Fail/Needs Review"
    }}
    """
    
    try:
        # Use Gemini Pro for analysis
        from vertexai.generative_models import GenerativeModel
        
        model = GenerativeModel("gemini-1.5-pro")
        response = model.generate_content(security_prompt)
        
        # Parse response as JSON
        try:
            vulnerability_report = json.loads(response.text)
        except json.JSONDecodeError:
            # Fallback if response isn't valid JSON
            vulnerability_report = {
                "contract_name": filename,
                "overall_risk_score": "5",
                "vulnerabilities_found": [response.text],
                "recommendations": ["Review the analysis above for detailed findings"],
                "compliance_status": "Needs Review"
            }
        
        return vulnerability_report
        
    except Exception as e:
        print(f"Error in Vertex AI analysis: {str(e)}")
        return {
            "contract_name": filename,
            "error": str(e),
            "status": "Analysis Failed"
        }

def save_audit_report(bucket, original_filename: str, report: Dict):
    """Save security audit report to Cloud Storage"""
    
    # Create report filename
    base_name = original_filename.split('.')[0]
    report_filename = f"audit-reports/{base_name}_security_audit.json"
    
    # Upload report to Cloud Storage
    report_blob = bucket.blob(report_filename)
    report_blob.upload_from_string(
        json.dumps(report, indent=2),
        content_type='application/json'
    )
    
    print(f"Audit report saved: {report_filename}")
EOF
    
    # Create requirements.txt for Cloud Function dependencies
    cat > "${FUNCTION_DIR}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-documentai==2.*
google-cloud-aiplatform==1.*
google-cloud-storage==2.*
google-cloud-core==2.*
vertexai==1.*
EOF
    
    log_success "Cloud Function source code prepared"
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function with storage trigger..."
    
    # Check if function already exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" 2>/dev/null; then
        log_warning "Cloud Function ${FUNCTION_NAME} already exists, updating..."
    fi
    
    # Deploy Cloud Function with Cloud Storage trigger
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --runtime=python311 \
        --source="${SCRIPT_DIR}/contract-security-function" \
        --entry-point=analyze_contract_security \
        --trigger-bucket="${BUCKET_NAME}" \
        --memory=1GB \
        --timeout=540s \
        --set-env-vars="PROCESSOR_ID=${PROCESSOR_ID},PROCESSOR_LOCATION=${REGION}" \
        --quiet 2>&1 | tee -a "${LOG_FILE}"
    
    log_success "Cloud Function deployed: ${FUNCTION_NAME}"
    log_info "Function will trigger on uploads to: gs://${BUCKET_NAME}"
}

# Create sample contracts and documentation
create_sample_content() {
    log_info "Creating sample smart contract and documentation for testing..."
    
    # Create sample smart contract with security vulnerabilities
    cat > "${SCRIPT_DIR}/sample_vulnerable_contract.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VulnerableBank {
    mapping(address => uint256) public balances;
    mapping(address => bool) public isAdmin;
    
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    
    constructor() {
        isAdmin[msg.sender] = true;
    }
    
    // Vulnerability: Missing access control
    function setAdmin(address _admin) public {
        isAdmin[_admin] = true;
    }
    
    function deposit() public payable {
        require(msg.value > 0, "Must deposit positive amount");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    
    // Vulnerability: Reentrancy attack vector
    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        
        // External call before state change - reentrancy vulnerability
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
        
        balances[msg.sender] -= _amount;
        emit Withdrawal(msg.sender, _amount);
    }
    
    // Vulnerability: Integer overflow in older Solidity versions
    function unsafeAdd(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b; // Could overflow in Solidity < 0.8.0
    }
    
    // Vulnerability: Timestamp dependence
    function isLuckyTime() public view returns (bool) {
        return block.timestamp % 2 == 0;
    }
    
    // Admin function with proper access control
    function emergencyWithdraw() public {
        require(isAdmin[msg.sender], "Only admin");
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function getBalance() public view returns (uint256) {
        return balances[msg.sender];
    }
}
EOF
    
    # Create contract documentation
    cat > "${SCRIPT_DIR}/contract_security_spec.md" << 'EOF'
# VulnerableBank Smart Contract Security Specification

## Contract Overview
VulnerableBank is a demonstration smart contract showing common security vulnerabilities in DeFi applications.

## Security Requirements
- Only contract owner should have admin privileges
- All withdrawals must prevent reentrancy attacks
- Balance updates must occur before external calls
- Input validation required for all public functions
- Time-based logic should not depend on block.timestamp

## Known Vulnerabilities (Intentional)
1. **Access Control**: setAdmin function lacks proper access control
2. **Reentrancy**: withdraw function vulnerable to reentrancy attacks
3. **State Management**: External calls before state updates
4. **Timestamp Dependence**: isLuckyTime relies on block.timestamp

## Compliance Requirements
- Must pass OWASP Smart Contract Top 10 security checks
- Requires integration with OpenZeppelin security libraries
- All admin functions must emit appropriate events

## Audit History
- Initial deployment: Never audited (demonstration purposes)
- Known issues: Multiple critical vulnerabilities present
EOF
    
    # Upload sample files to trigger analysis
    gsutil cp "${SCRIPT_DIR}/sample_vulnerable_contract.sol" "gs://${BUCKET_NAME}/contracts/" 2>&1 | tee -a "${LOG_FILE}"
    gsutil cp "${SCRIPT_DIR}/contract_security_spec.md" "gs://${BUCKET_NAME}/documentation/" 2>&1 | tee -a "${LOG_FILE}"
    
    log_success "Sample contract and documentation uploaded"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment status..."
    
    # Check bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_error "Storage bucket verification failed"
        return 1
    fi
    
    # Check Document AI processor
    if ! gcloud documentai processors describe "projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}" >/dev/null 2>&1; then
        log_error "Document AI processor verification failed"
        return 1
    fi
    
    # Check Cloud Function
    if ! gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_error "Cloud Function verification failed"
        return 1
    fi
    
    log_success "All components deployed successfully"
}

# Display deployment summary
display_summary() {
    log_success "Smart Contract Security Auditing Solution Deployed Successfully!"
    echo ""
    log_info "Deployment Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Storage Bucket: gs://${BUCKET_NAME}"
    echo "  Document AI Processor ID: ${PROCESSOR_ID}"
    echo "  Cloud Function: ${FUNCTION_NAME}"
    echo ""
    log_info "Next Steps:"
    echo "  1. Upload smart contract files (.sol, .md, .pdf) to gs://${BUCKET_NAME}/contracts/"
    echo "  2. Check audit reports in gs://${BUCKET_NAME}/audit-reports/"
    echo "  3. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo ""
    log_info "Estimated monthly cost: \$15-25 for moderate usage"
    echo ""
    log_warning "Remember to run destroy.sh when finished to avoid ongoing charges"
}

# Main deployment flow
main() {
    echo "========================================="
    echo "Smart Contract Security Auditing Deployment"
    echo "========================================="
    echo ""
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    check_prerequisites
    initialize_variables
    configure_project
    create_storage_bucket
    create_document_ai_processor
    prepare_function_code
    deploy_cloud_function
    create_sample_content
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully at $(date)"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi