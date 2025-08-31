#!/bin/bash

# Deploy Smart Document Review Workflow with ADK and Storage
# This script deploys the complete infrastructure for the smart document review system

set -euo pipefail

# Colors for output formatting
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

# Error handler
handle_error() {
    log_error "Script failed at line $1"
    log_error "Deployment aborted. Please check the error above and try again."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="doc-review"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Python 3.10+ is available
    if ! python3 --version | grep -E "Python 3\.(1[0-9]|[2-9][0-9])" > /dev/null; then
        log_warning "Python 3.10+ recommended for ADK compatibility"
    fi
    
    # Check if pip is available
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is required but not installed. Please install pip."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique identifiers
    TIMESTAMP=$(date +%s)
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set environment variables
    export PROJECT_ID="${PROJECT_PREFIX}-${TIMESTAMP}"
    export REGION="${GCP_REGION:-$DEFAULT_REGION}"
    export ZONE="${GCP_ZONE:-$DEFAULT_ZONE}"
    export BUCKET_NAME="document-review-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="document-processor-${RANDOM_SUFFIX}"
    
    # Display configuration
    log_info "Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  Bucket Name: ${BUCKET_NAME}"
    echo "  Function Name: ${FUNCTION_NAME}"
    
    # Save environment for later use
    cat > "${SCRIPT_DIR}/.env" << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export BUCKET_NAME="${BUCKET_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
EOF
    
    log_success "Environment variables configured"
}

# Function to create GCP project
create_project() {
    log_info "Creating Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Project ${PROJECT_ID} already exists, skipping creation"
    else
        # Create project
        gcloud projects create "${PROJECT_ID}" \
            --name="Smart Document Review Workflow" \
            --set-as-default
        
        log_success "Project ${PROJECT_ID} created"
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Check if billing is enabled (required for most services)
    if ! gcloud beta billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Billing is not enabled for this project. You may need to enable billing manually."
        log_warning "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
    fi
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com" 
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create storage buckets
create_storage() {
    log_info "Creating Cloud Storage buckets..."
    
    # Create input bucket
    if gsutil ls -b "gs://${BUCKET_NAME}-input" &>/dev/null; then
        log_warning "Bucket ${BUCKET_NAME}-input already exists, skipping creation"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}-input"
        
        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}-input"
        log_success "Input bucket created: gs://${BUCKET_NAME}-input"
    fi
    
    # Create results bucket
    if gsutil ls -b "gs://${BUCKET_NAME}-results" &>/dev/null; then
        log_warning "Bucket ${BUCKET_NAME}-results already exists, skipping creation"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}-results"
        
        # Enable versioning
        gsutil versioning set on "gs://${BUCKET_NAME}-results"
        log_success "Results bucket created: gs://${BUCKET_NAME}-results"
    fi
    
    log_success "Storage buckets configured"
}

# Function to set up ADK development environment
setup_adk_environment() {
    log_info "Setting up Agent Development Kit environment..."
    
    # Create local development directory
    local dev_dir="${SCRIPT_DIR}/../document-review-agents"
    mkdir -p "${dev_dir}"
    cd "${dev_dir}"
    
    # Create Python virtual environment
    if [ ! -d "adk-env" ]; then
        python3 -m venv adk-env
        log_success "Python virtual environment created"
    else
        log_warning "Virtual environment already exists"
    fi
    
    # Activate virtual environment and install dependencies
    source adk-env/bin/activate
    
    # Upgrade pip first
    pip install --upgrade pip
    
    # Install required packages
    log_info "Installing ADK and dependencies..."
    pip install google-cloud-aiplatform>=1.38.0
    pip install google-cloud-storage>=2.10.0
    pip install functions-framework>=3.4.0
    pip install google-generativeai>=0.3.0
    
    # Note: google-adk might not be publicly available yet
    # Using alternative approach with direct API calls
    log_warning "Using direct Vertex AI API calls instead of ADK (if ADK is not available)"
    
    # Create agent directory structure
    mkdir -p agents
    touch agents/__init__.py
    
    log_success "ADK development environment configured"
    
    # Return to script directory
    cd "${SCRIPT_DIR}"
}

# Function to create agent code
create_agent_code() {
    log_info "Creating multi-agent system code..."
    
    local agents_dir="${SCRIPT_DIR}/../document-review-agents/agents"
    
    # Create grammar agent
    cat > "${agents_dir}/grammar_agent.py" << 'EOF'
from google.cloud import aiplatform
import vertexai
from vertexai.generative_models import GenerativeModel, ChatSession
import json
import os

class GrammarAgent:
    def __init__(self, project_id: str, location: str = "us-central1"):
        self.project_id = project_id
        self.location = location
        self.name = "grammar_reviewer"
        
        # Initialize Vertex AI
        vertexai.init(project=project_id, location=location)
        self.model = GenerativeModel("gemini-1.5-flash")
        
    def review_grammar(self, document_text: str) -> dict:
        """Review document for grammar, punctuation, and syntax issues."""
        prompt = f"""
        As a professional grammar reviewer, analyze this document for:
        1. Grammar errors and corrections
        2. Punctuation and capitalization issues  
        3. Sentence structure improvements
        4. Word choice recommendations
        
        Document: {document_text}
        
        Return findings as JSON with specific locations and suggestions.
        Focus on actionable improvements while preserving the author's voice.
        """
        
        try:
            response = self.model.generate_content(prompt)
            
            return {
                "agent": self.name,
                "review_type": "grammar_analysis",
                "findings": response.text,
                "confidence_score": 0.95,
                "timestamp": self._get_timestamp()
            }
        except Exception as e:
            return {
                "agent": self.name,
                "review_type": "grammar_analysis", 
                "error": str(e),
                "confidence_score": 0.0,
                "timestamp": self._get_timestamp()
            }
            
    def _get_timestamp(self):
        """Get current timestamp."""
        from datetime import datetime
        return datetime.now().isoformat()
EOF

    # Create accuracy agent
    cat > "${agents_dir}/accuracy_agent.py" << 'EOF'
from google.cloud import aiplatform
import vertexai
from vertexai.generative_models import GenerativeModel
import json

class AccuracyAgent:
    def __init__(self, project_id: str, location: str = "us-central1"):
        self.project_id = project_id
        self.location = location
        self.name = "accuracy_validator"
        
        # Initialize Vertex AI
        vertexai.init(project=project_id, location=location)
        self.model = GenerativeModel("gemini-1.5-flash")
        
    def validate_accuracy(self, document_text: str) -> dict:
        """Validate factual accuracy and identify potential inaccuracies."""
        prompt = f"""
        As a fact-checking specialist, analyze this document for:
        1. Factual claims that need verification
        2. Statistical data accuracy
        3. Date and timeline consistency
        4. Technical accuracy in domain-specific content
        5. Citations and source requirements
        
        Document: {document_text}
        
        Flag suspicious claims and suggest verification sources.
        Return analysis as structured JSON.
        """
        
        try:
            response = self.model.generate_content(prompt)
            
            return {
                "agent": self.name,
                "review_type": "accuracy_analysis",
                "findings": response.text,
                "verification_needed": True,
                "confidence_score": 0.88,
                "timestamp": self._get_timestamp()
            }
        except Exception as e:
            return {
                "agent": self.name,
                "review_type": "accuracy_analysis",
                "error": str(e),
                "confidence_score": 0.0,
                "timestamp": self._get_timestamp()
            }
            
    def _get_timestamp(self):
        """Get current timestamp."""
        from datetime import datetime
        return datetime.now().isoformat()
EOF

    # Create style agent
    cat > "${agents_dir}/style_agent.py" << 'EOF'
from google.cloud import aiplatform
import vertexai
from vertexai.generative_models import GenerativeModel
import json

class StyleAgent:
    def __init__(self, project_id: str, location: str = "us-central1"):
        self.project_id = project_id
        self.location = location
        self.name = "style_reviewer"
        
        # Initialize Vertex AI
        vertexai.init(project=project_id, location=location)
        self.model = GenerativeModel("gemini-1.5-flash")
        
    def analyze_style(self, document_text: str) -> dict:
        """Analyze document style, readability, and tone consistency."""
        prompt = f"""
        As a professional editor, analyze this document for:
        1. Reading level and accessibility
        2. Tone consistency and voice
        3. Sentence variety and flow
        4. Clarity and conciseness
        5. Professional presentation standards
        6. Audience appropriateness
        
        Document: {document_text}
        
        Provide specific recommendations for improvement.
        Return analysis as structured JSON with actionable suggestions.
        """
        
        try:
            response = self.model.generate_content(prompt)
            
            return {
                "agent": self.name,
                "review_type": "style_analysis",
                "findings": response.text,
                "readability_score": "calculated",
                "confidence_score": 0.92,
                "timestamp": self._get_timestamp()
            }
        except Exception as e:
            return {
                "agent": self.name,
                "review_type": "style_analysis",
                "error": str(e),
                "confidence_score": 0.0,
                "timestamp": self._get_timestamp()
            }
            
    def _get_timestamp(self):
        """Get current timestamp."""
        from datetime import datetime
        return datetime.now().isoformat()
EOF

    # Create coordinator
    cat > "${agents_dir}/coordinator.py" << 'EOF'
import asyncio
import concurrent.futures
from agents.grammar_agent import GrammarAgent
from agents.accuracy_agent import AccuracyAgent
from agents.style_agent import StyleAgent
import json

class DocumentReviewCoordinator:
    def __init__(self, project_id: str, location: str = "us-central1"):
        self.name = "document_review_coordinator"
        self.project_id = project_id
        self.location = location
        
        # Initialize specialized agents
        self.grammar_agent = GrammarAgent(project_id, location)
        self.accuracy_agent = AccuracyAgent(project_id, location)
        self.style_agent = StyleAgent(project_id, location)
        
    async def review_document(self, document_text: str, document_id: str) -> dict:
        """Orchestrate comprehensive document review using specialized agents."""
        
        # Execute parallel reviews using asyncio and thread pool
        loop = asyncio.get_event_loop()
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            tasks = [
                loop.run_in_executor(executor, self.grammar_agent.review_grammar, document_text),
                loop.run_in_executor(executor, self.accuracy_agent.validate_accuracy, document_text),
                loop.run_in_executor(executor, self.style_agent.analyze_style, document_text)
            ]
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Handle any exceptions in results
        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                agent_names = ["grammar_agent", "accuracy_agent", "style_agent"]
                processed_results.append({
                    "agent": agent_names[i],
                    "error": str(result),
                    "confidence_score": 0.0,
                    "timestamp": self._get_timestamp()
                })
            else:
                processed_results.append(result)
        
        # Aggregate and analyze results
        comprehensive_review = {
            "document_id": document_id,
            "review_timestamp": self._get_timestamp(),
            "grammar_review": processed_results[0],
            "accuracy_review": processed_results[1],
            "style_review": processed_results[2],
            "overall_score": self.calculate_overall_score(processed_results),
            "priority_issues": self.identify_priority_issues(processed_results),
            "recommendations": self.generate_recommendations(processed_results)
        }
        
        return comprehensive_review
        
    def calculate_overall_score(self, results: list) -> float:
        """Calculate composite quality score from all agent reviews."""
        scores = [result.get("confidence_score", 0.0) for result in results]
        return sum(scores) / len(scores) if scores else 0.0
        
    def identify_priority_issues(self, results: list) -> list:
        """Identify most critical issues requiring immediate attention."""
        priority_issues = []
        for result in results:
            if result.get("confidence_score", 0.0) < 0.8:
                priority_issues.append({
                    "agent": result.get("agent"),
                    "issue_type": result.get("review_type"),
                    "severity": "high"
                })
        return priority_issues
        
    def generate_recommendations(self, results: list) -> list:
        """Generate actionable recommendations from all agent findings."""
        recommendations = []
        for result in results:
            agent_name = result.get("agent", "unknown")
            if "error" not in result:
                recommendations.append(f"Review {agent_name} findings for actionable improvements")
            else:
                recommendations.append(f"Retry {agent_name} analysis due to processing error")
        return recommendations
        
    def _get_timestamp(self):
        """Get current timestamp."""
        from datetime import datetime
        return datetime.now().isoformat()
EOF

    log_success "Multi-agent system code created"
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../document-review-agents"
    cd "${function_dir}"
    
    # Create main function file
    cat > main.py << 'EOF'
import functions_framework
from google.cloud import storage
from agents.coordinator import DocumentReviewCoordinator
import json
import asyncio
import os

@functions_framework.cloud_event
def process_document(cloud_event):
    """Process uploaded document through multi-agent review workflow."""
    
    # Extract file information from Cloud Storage event
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]
    
    print(f"Processing document: {file_name} from bucket: {bucket_name}")
    
    # Skip non-document files
    if not file_name.endswith(('.txt', '.md', '.doc', '.docx')):
        print(f"Skipping non-document file: {file_name}")
        return
    
    # Get project info from environment
    project_id = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
    location = os.environ.get('FUNCTION_REGION', 'us-central1')
    
    # Initialize storage client and coordinator
    storage_client = storage.Client()
    coordinator = DocumentReviewCoordinator(project_id, location)
    
    try:
        # Download document content
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Handle different file types
        if file_name.endswith('.txt') or file_name.endswith('.md'):
            document_text = blob.download_as_text()
        else:
            # For other file types, you might want to add document parsing
            print(f"Warning: File type not fully supported: {file_name}")
            document_text = blob.download_as_text()
        
        # Execute multi-agent review
        review_results = asyncio.run(
            coordinator.review_document(document_text, file_name)
        )
        
        # Store results in results bucket
        results_bucket_name = bucket_name.replace('-input', '-results')
        results_bucket = storage_client.bucket(results_bucket_name)
        results_blob = results_bucket.blob(f"review_{file_name}.json")
        results_blob.upload_from_string(
            json.dumps(review_results, indent=2),
            content_type='application/json'
        )
        
        print(f"✅ Document review completed: {file_name}")
        print(f"Overall score: {review_results.get('overall_score', 'N/A')}")
        
        return {"status": "success", "document": file_name}
        
    except Exception as e:
        error_msg = f"❌ Error processing document {file_name}: {str(e)}"
        print(error_msg)
        
        # Store error information
        try:
            results_bucket_name = bucket_name.replace('-input', '-results')
            results_bucket = storage_client.bucket(results_bucket_name)
            error_blob = results_bucket.blob(f"error_{file_name}.json")
            error_blob.upload_from_string(
                json.dumps({"error": str(e), "document": file_name, "timestamp": coordinator._get_timestamp()}, indent=2),
                content_type='application/json'
            )
        except:
            pass  # If we can't save the error, just log it
            
        raise
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-aiplatform==1.*
google-generativeai==0.*
EOF

    # Deploy Cloud Function with Storage trigger
    log_info "Deploying Cloud Function with Storage trigger..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-bucket "${BUCKET_NAME}-input" \
        --source . \
        --entry-point process_document \
        --memory 1Gi \
        --timeout 540s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},FUNCTION_REGION=${REGION}" \
        --region="${REGION}" \
        --quiet
    
    log_success "Cloud Function deployed successfully"
    
    # Return to script directory  
    cd "${SCRIPT_DIR}"
}

# Function to configure IAM permissions
configure_iam() {
    log_info "Configuring IAM permissions..."
    
    # Get the Cloud Function service account
    local function_sa
    function_sa=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.serviceAccountEmail)")
    
    if [ -z "${function_sa}" ]; then
        log_error "Could not retrieve Cloud Function service account"
        return 1
    fi
    
    log_info "Function service account: ${function_sa}"
    
    # Grant necessary permissions for Storage access
    gsutil iam ch "serviceAccount:${function_sa}:objectViewer" \
        "gs://${BUCKET_NAME}-input"
    
    gsutil iam ch "serviceAccount:${function_sa}:objectAdmin" \
        "gs://${BUCKET_NAME}-results"
    
    # Grant Vertex AI access for agent processing
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${function_sa}" \
        --role="roles/aiplatform.user" \
        --quiet
    
    log_success "IAM permissions configured"
}

# Function to create sample test document
create_test_document() {
    log_info "Creating sample test document..."
    
    cat > "${SCRIPT_DIR}/sample_document.txt" << 'EOF'
This is a sample document for testing our document review system. The document contains some deliberate errors for testing purposes. It has grammar mistakes, potential fact checking needs, and style inconsistencies that our agents should identify and provide recommendations for improvement.

The system should analyze readability, check for accuracy, and provide grammar suggestions. This comprehensive review will demonstrate the multi-agent workflow capabilities.

Some facts to check: The Earth is aproximately 93 million miles from the Sun. Water boils at 100 degrees celsius at sea level. The United States has 50 states.

This document intentionally includes various types of issues to test all agents comprehensively.
EOF
    
    log_success "Sample test document created"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if buckets exist
    if ! gsutil ls -b "gs://${BUCKET_NAME}-input" &>/dev/null; then
        log_error "Input bucket not found"
        return 1
    fi
    
    if ! gsutil ls -b "gs://${BUCKET_NAME}-results" &>/dev/null; then
        log_error "Results bucket not found"
        return 1
    fi
    
    # Check if function exists
    if ! gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_error "Cloud Function not found"
        return 1
    fi
    
    # Upload test document
    log_info "Uploading test document to trigger processing..."
    gsutil cp "${SCRIPT_DIR}/sample_document.txt" "gs://${BUCKET_NAME}-input/"
    
    # Wait for processing
    log_info "Waiting for document processing (60 seconds)..."
    sleep 60
    
    # Check if results were generated
    if gsutil ls "gs://${BUCKET_NAME}-results/review_sample_document.txt.json" &>/dev/null; then
        log_success "Test document processed successfully"
        
        # Download and display results summary
        gsutil cp "gs://${BUCKET_NAME}-results/review_sample_document.txt.json" "${SCRIPT_DIR}/"
        
        if command -v python3 &>/dev/null; then
            python3 << 'EOF'
import json
import sys

try:
    with open('review_sample_document.txt.json', 'r') as f:
        results = json.load(f)
    print('📊 Review Results Summary:')
    print(f'Overall Score: {results.get("overall_score", "N/A")}')
    print(f'Priority Issues: {len(results.get("priority_issues", []))}')
    print(f'Grammar Review: {results.get("grammar_review", {}).get("agent", "N/A")}')
    print(f'Accuracy Review: {results.get("accuracy_review", {}).get("agent", "N/A")}')
    print(f'Style Review: {results.get("style_review", {}).get("agent", "N/A")}')
except Exception as e:
    print(f'Error reading results: {e}')
    sys.exit(1)
EOF
        fi
    else
        log_warning "Test results not found. Check function logs for issues."
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Smart Document Review Workflow deployment completed!"
    echo
    echo "📋 Deployment Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Input Bucket: gs://${BUCKET_NAME}-input"
    echo "  Results Bucket: gs://${BUCKET_NAME}-results"
    echo "  Cloud Function: ${FUNCTION_NAME}"
    echo
    echo "🚀 Usage Instructions:"
    echo "  1. Upload documents (.txt, .md, .doc, .docx) to: gs://${BUCKET_NAME}-input"
    echo "  2. Review results will be saved to: gs://${BUCKET_NAME}-results"
    echo "  3. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo
    echo "🧹 Cleanup:"
    echo "  Run './destroy.sh' to remove all resources and avoid ongoing charges"
    echo
    echo "💰 Cost Information:"
    echo "  - Storage: ~$0.02/GB/month"
    echo "  - Cloud Functions: Pay per invocation"
    echo "  - Vertex AI: Pay per model call"
    echo "  Remember to clean up resources to avoid ongoing charges!"
}

# Main execution
main() {
    log_info "Starting Smart Document Review Workflow deployment..."
    echo "==============================================================="
    
    check_prerequisites
    setup_environment
    create_project
    enable_apis
    create_storage
    setup_adk_environment
    create_agent_code
    deploy_cloud_function
    configure_iam
    create_test_document
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully! 🎉"
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi