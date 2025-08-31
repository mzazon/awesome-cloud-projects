#!/bin/bash

# Deploy script for Smart Code Documentation with ADK and Cloud Functions
# This script deploys the complete infrastructure for intelligent code documentation
# using Google Cloud's Agent Development Kit (ADK) and serverless functions.

set -euo pipefail

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Exiting deployment."
    log_info "Run './destroy.sh' to clean up any partially created resources."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="adk-docs"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Smart Code Documentation with ADK and Cloud Functions

OPTIONS:
    -p, --project-id     Google Cloud project ID (required)
    -r, --region         Deployment region (default: ${DEFAULT_REGION})
    -z, --zone          Deployment zone (default: ${DEFAULT_ZONE})
    -h, --help          Show this help message
    --skip-apis         Skip API enablement (use if APIs are already enabled)
    --dry-run          Show what would be deployed without executing

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 -p my-project -r us-west1 -z us-west1-a
    $0 --project-id my-project --dry-run

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        log_info "gsutil is typically included with Google Cloud CLI"
        exit 1
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed or not in PATH"
        log_info "Python 3.11+ is required for ADK development"
        exit 1
    fi
    
    # Check Python version (require 3.11+)
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if python3 -c "import sys; exit(0 if sys.version_info >= (3, 11) else 1)"; then
        log_success "Python ${PYTHON_VERSION} is compatible"
    else
        log_error "Python 3.11+ is required, found Python ${PYTHON_VERSION}"
        exit 1
    fi
    
    # Check if pip is available
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 is not installed or not in PATH"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate project and set up environment
setup_environment() {
    log_info "Setting up environment..."
    
    # Validate project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access"
        log_info "Ensure the project exists and you have the necessary permissions"
        exit 1
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    
    # Set up resource names
    export INPUT_BUCKET="${PROJECT_ID}-code-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="${PROJECT_ID}-docs-output-${RANDOM_SUFFIX}"
    export TEMP_BUCKET="${PROJECT_ID}-processing-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="adk-code-documentation"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}, Zone: ${ZONE}"
    log_info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    if [[ "${SKIP_APIS}" == "true" ]]; then
        log_warning "Skipping API enablement as requested"
        return
    fi
    
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
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
    
    log_info "Waiting for API enablement to propagate..."
    sleep 30
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    local buckets=("${INPUT_BUCKET}" "${OUTPUT_BUCKET}" "${TEMP_BUCKET}")
    local bucket_purposes=("code input" "documentation output" "processing temp")
    
    for i in "${!buckets[@]}"; do
        local bucket="${buckets[$i]}"
        local purpose="${bucket_purposes[$i]}"
        
        log_info "Creating ${purpose} bucket: ${bucket}"
        
        if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket}"; then
            log_success "Created bucket: ${bucket}"
            
            # Set appropriate lifecycle policies for temp bucket
            if [[ "${bucket}" == "${TEMP_BUCKET}" ]]; then
                log_info "Setting lifecycle policy for temporary bucket..."
                cat > /tmp/lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 7}
      }
    ]
  }
}
EOF
                gsutil lifecycle set /tmp/lifecycle.json "gs://${bucket}"
                rm -f /tmp/lifecycle.json
                log_success "Applied lifecycle policy to temp bucket"
            fi
        else
            log_error "Failed to create bucket: ${bucket}"
            exit 1
        fi
    done
    
    log_success "All storage buckets created successfully"
}

# Function to set up ADK development environment
setup_adk_environment() {
    log_info "Setting up ADK development environment..."
    
    # Create development directory
    ADK_DIR="${SCRIPT_DIR}/../adk-workspace"
    mkdir -p "${ADK_DIR}"
    cd "${ADK_DIR}"
    
    # Create virtual environment if it doesn't exist
    if [[ ! -d "adk-env" ]]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv adk-env
    fi
    
    # Activate virtual environment
    source adk-env/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install ADK and required dependencies
    log_info "Installing Google ADK and dependencies..."
    local packages=(
        "google-adk==1.0.0"
        "functions-framework==3.5.0"
        "google-cloud-storage==2.14.0"
        "gitpython==3.1.43"
        "google-cloud-aiplatform==1.46.0"
    )
    
    for package in "${packages[@]}"; do
        log_info "Installing ${package}..."
        pip install "${package}"
    done
    
    log_success "ADK environment setup completed"
}

# Function to create ADK agent code
create_adk_agents() {
    log_info "Creating ADK multi-agent system code..."
    
    # Create main code analysis agent
    cat > main.py << 'EOF'
import os
from google.adk import LlmAgent
from google.adk.tools import Tool
from google.cloud import storage
import tempfile
import git
import json
from typing import Dict, List, Any

class CodeAnalysisAgent:
    def __init__(self, project_id: str):
        self.project_id = project_id
        self.storage_client = storage.Client()
        
        # Initialize ADK LLM Agent with Vertex AI Gemini
        self.agent = LlmAgent(
            model_name="gemini-1.5-pro",
            project_id=project_id,
            location="us-central1",
            system_prompt="""You are a code analysis expert specializing in 
            understanding software architecture, function relationships, and 
            code patterns. Analyze code repositories to extract structural 
            information, identify key components, and understand business logic."""
        )
        
        # Add code parsing tools
        self.agent.add_tool(self._create_code_parser_tool())

    def _create_code_parser_tool(self) -> Tool:
        def parse_code_structure(file_content: str, file_path: str) -> Dict[str, Any]:
            """Parse code to extract functions, classes, and imports."""
            import ast
            import re
            
            structure = {
                "file_path": file_path,
                "functions": [],
                "classes": [],
                "imports": [],
                "complexity_score": 0
            }
            
            try:
                if file_path.endswith('.py'):
                    tree = ast.parse(file_content)
                    
                    for node in ast.walk(tree):
                        if isinstance(node, ast.FunctionDef):
                            structure["functions"].append({
                                "name": node.name,
                                "line_start": node.lineno,
                                "args": [arg.arg for arg in node.args.args],
                                "docstring": ast.get_docstring(node)
                            })
                        elif isinstance(node, ast.ClassDef):
                            structure["classes"].append({
                                "name": node.name,
                                "line_start": node.lineno,
                                "methods": [n.name for n in node.body if isinstance(n, ast.FunctionDef)],
                                "docstring": ast.get_docstring(node)
                            })
                        elif isinstance(node, ast.Import):
                            for alias in node.names:
                                structure["imports"].append(alias.name)
                        elif isinstance(node, ast.ImportFrom):
                            if node.module:
                                for alias in node.names:
                                    structure["imports"].append(f"{node.module}.{alias.name}")
                
                structure["complexity_score"] = len(structure["functions"]) * 2 + len(structure["classes"]) * 5
                
            except Exception as e:
                structure["error"] = str(e)
            
            return structure
        
        return Tool(
            name="code_parser",
            description="Parse code files to extract structural information",
            func=parse_code_structure
        )

    def analyze_repository(self, repo_path: str) -> Dict[str, Any]:
        """Analyze a complete repository for documentation generation."""
        analysis_result = {
            "repository_structure": {},
            "file_analyses": [],
            "overall_complexity": 0,
            "documentation_suggestions": []
        }
        
        total_complexity = 0
        
        # Process repository files
        for root, dirs, files in os.walk(repo_path):
            for file in files:
                if file.endswith(('.py', '.js', '.ts', '.java', '.cpp', '.c')):
                    file_path = os.path.join(root, file)
                    relative_path = os.path.relpath(file_path, repo_path)
                    
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                    
                    # Use ADK agent to analyze the file
                    prompt = f"""
                    Analyze this code file and provide insights:
                    File: {relative_path}
                    Content: {content[:2000]}...
                    
                    Please provide:
                    1. Purpose and functionality
                    2. Key components and their roles
                    3. Dependencies and relationships
                    4. Documentation quality assessment
                    5. Suggestions for improvement
                    """
                    
                    response = self.agent.generate(prompt)
                    
                    # Parse code structure
                    structure = self.agent.tools[0].func(content, relative_path)
                    total_complexity += structure.get("complexity_score", 0)
                    
                    analysis_result["file_analyses"].append({
                        "file_path": relative_path,
                        "analysis": response,
                        "structure": structure
                    })
        
        analysis_result["overall_complexity"] = total_complexity
        return analysis_result
EOF

    # Create documentation generation agent
    cat > documentation_agent.py << 'EOF'
from google.adk import LlmAgent
from typing import Dict, Any, List
import json
import re

class DocumentationAgent:
    def __init__(self, project_id: str):
        self.agent = LlmAgent(
            model_name="gemini-1.5-pro",
            project_id=project_id,
            location="us-central1",
            system_prompt="""You are a technical documentation expert who creates 
            clear, comprehensive documentation from code analysis. Generate 
            documentation that helps developers understand both the technical 
            implementation and business purpose of code components."""
        )

    def generate_documentation(self, analysis_data: Dict[str, Any]) -> Dict[str, Any]:
        """Generate comprehensive documentation from code analysis."""
        
        documentation = {
            "overview": "",
            "architecture": "",
            "components": [],
            "api_reference": [],
            "usage_examples": [],
            "setup_instructions": ""
        }
        
        # Generate overview documentation
        overview_prompt = f"""
        Based on this code analysis, generate a comprehensive overview:
        {json.dumps(analysis_data, indent=2)[:3000]}
        
        Create an overview that includes:
        1. Project purpose and goals
        2. Main architecture patterns used
        3. Key technologies and frameworks
        4. High-level component relationships
        """
        
        overview_response = self.agent.generate(overview_prompt)
        documentation["overview"] = overview_response
        
        # Generate component documentation
        for file_analysis in analysis_data.get("file_analyses", []):
            component_prompt = f"""
            Generate detailed component documentation for:
            File: {file_analysis['file_path']}
            Analysis: {file_analysis['analysis']}
            Structure: {json.dumps(file_analysis['structure'], indent=2)}
            
            Create documentation including:
            1. Component purpose and responsibilities
            2. Public APIs and interfaces
            3. Usage examples
            4. Configuration options
            5. Dependencies and relationships
            """
            
            component_response = self.agent.generate(component_prompt)
            
            documentation["components"].append({
                "file_path": file_analysis['file_path'],
                "documentation": component_response,
                "functions": file_analysis['structure'].get('functions', []),
                "classes": file_analysis['structure'].get('classes', [])
            })
        
        return documentation

    def format_markdown_documentation(self, documentation: Dict[str, Any]) -> str:
        """Format documentation as structured markdown."""
        
        markdown_content = f"""# Project Documentation

## Overview
{documentation['overview']}

## Architecture
{documentation.get('architecture', 'Architecture documentation will be generated based on component analysis.')}

## Components

"""
        
        for component in documentation["components"]:
            markdown_content += f"""
### {component['file_path']}

{component['documentation']}

#### Functions

"""
            for func in component.get('functions', []):
                docstring = func.get('docstring', 'No description available')
                args = ', '.join(func.get('args', []))
                markdown_content += f"- **{func['name']}({args})**: {docstring}\n"
            
            markdown_content += "\n#### Classes\n\n"
            for cls in component.get('classes', []):
                docstring = cls.get('docstring', 'No description available')
                methods = ', '.join(cls.get('methods', []))
                markdown_content += f"- **{cls['name']}**: {docstring}\n"
                if methods:
                    markdown_content += f"  - Methods: {methods}\n"
            
            markdown_content += "\n---\n\n"
        
        return markdown_content
EOF

    # Create quality review agent
    cat > review_agent.py << 'EOF'
from google.adk import LlmAgent
from typing import Dict, Any, List, Tuple
import re

class QualityReviewAgent:
    def __init__(self, project_id: str):
        self.agent = LlmAgent(
            model_name="gemini-1.5-pro",
            project_id=project_id,
            location="us-central1",
            system_prompt="""You are a documentation quality expert who reviews 
            technical documentation for accuracy, completeness, clarity, and 
            usefulness. Provide constructive feedback and improvement suggestions."""
        )

    def review_documentation(self, documentation: str, code_analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Review generated documentation for quality and completeness."""
        
        review_prompt = f"""
        Review this technical documentation for quality:
        
        Documentation:
        {documentation[:4000]}
        
        Original Code Analysis:
        {str(code_analysis)[:2000]}
        
        Evaluate the documentation on:
        1. Accuracy - Does it correctly represent the code?
        2. Completeness - Are all important components covered?
        3. Clarity - Is it easy to understand?
        4. Structure - Is it well-organized?
        5. Usefulness - Will it help developers?
        
        Provide:
        - Overall quality score (1-10)
        - Specific strengths
        - Areas for improvement
        - Actionable recommendations
        """
        
        review_response = self.agent.generate(review_prompt)
        
        # Extract quality metrics
        quality_metrics = self._extract_quality_metrics(review_response)
        
        return {
            "review_summary": review_response,
            "quality_score": quality_metrics.get("score", 7),
            "strengths": quality_metrics.get("strengths", []),
            "improvements": quality_metrics.get("improvements", []),
            "recommendations": quality_metrics.get("recommendations", []),
            "approved": quality_metrics.get("score", 7) >= 7
        }

    def _extract_quality_metrics(self, review_text: str) -> Dict[str, Any]:
        """Extract structured quality metrics from review text."""
        metrics = {
            "score": 7,
            "strengths": [],
            "improvements": [],
            "recommendations": []
        }
        
        # Extract quality score
        score_match = re.search(r'score[:\s]*(\d+)', review_text.lower())
        if score_match:
            metrics["score"] = int(score_match.group(1))
        
        # Extract sections using simple parsing
        sections = review_text.split('\n')
        current_section = None
        
        for line in sections:
            line = line.strip()
            if 'strength' in line.lower():
                current_section = 'strengths'
            elif 'improvement' in line.lower() or 'area' in line.lower():
                current_section = 'improvements'
            elif 'recommend' in line.lower():
                current_section = 'recommendations'
            elif line.startswith('-') or line.startswith('•'):
                if current_section and current_section in metrics:
                    metrics[current_section].append(line.lstrip('- •'))
        
        return metrics

    def suggest_improvements(self, documentation: str, review_results: Dict[str, Any]) -> str:
        """Generate improved documentation based on review feedback."""
        
        improvement_prompt = f"""
        Improve this documentation based on the review feedback:
        
        Original Documentation:
        {documentation}
        
        Review Feedback:
        {review_results['review_summary']}
        
        Key Areas for Improvement:
        {chr(10).join(f"- {item}" for item in review_results.get('improvements', []))}
        
        Generate an improved version that addresses the feedback while maintaining 
        the original structure and adding missing information.
        """
        
        improved_response = self.agent.generate(improvement_prompt)
        return improved_response
EOF

    log_success "ADK agent code created successfully"
}

# Function to create Cloud Function orchestrator
create_cloud_function() {
    log_info "Creating Cloud Function orchestrator..."
    
    # Create the main orchestrator function
    cat > orchestrator.py << 'EOF'
import functions_framework
from google.cloud import storage
import tempfile
import os
import json
import zipfile
import git
from main import CodeAnalysisAgent
from documentation_agent import DocumentationAgent
from review_agent import QualityReviewAgent

@functions_framework.cloud_event
def process_code_repository(cloud_event):
    """
    Cloud Function triggered by Cloud Storage events to process code repositories
    and generate intelligent documentation using ADK multi-agent system.
    """
    
    # Extract event data
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    if not file_name.endswith('.zip'):
        print(f"Skipping non-zip file: {file_name}")
        return
    
    project_id = os.environ.get('GCP_PROJECT')
    output_bucket = os.environ.get('OUTPUT_BUCKET')
    temp_bucket = os.environ.get('TEMP_BUCKET')
    
    storage_client = storage.Client()
    
    try:
        # Download and extract repository
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_path = download_and_extract_repo(
                storage_client, bucket_name, file_name, temp_dir
            )
            
            # Initialize ADK agents
            print("Initializing ADK multi-agent system...")
            code_agent = CodeAnalysisAgent(project_id)
            doc_agent = DocumentationAgent(project_id)
            review_agent = QualityReviewAgent(project_id)
            
            # Step 1: Analyze code repository
            print("Analyzing code repository...")
            analysis_results = code_agent.analyze_repository(repo_path)
            
            # Store intermediate results
            store_intermediate_results(
                storage_client, temp_bucket, f"{file_name}/analysis.json", 
                analysis_results
            )
            
            # Step 2: Generate documentation
            print("Generating documentation...")
            documentation = doc_agent.generate_documentation(analysis_results)
            markdown_docs = doc_agent.format_markdown_documentation(documentation)
            
            # Step 3: Quality review
            print("Performing quality review...")
            review_results = review_agent.review_documentation(
                markdown_docs, analysis_results
            )
            
            # Step 4: Improve documentation if needed
            if not review_results.get('approved', False):
                print("Improving documentation based on review feedback...")
                improved_docs = review_agent.suggest_improvements(
                    markdown_docs, review_results
                )
                final_documentation = improved_docs
            else:
                final_documentation = markdown_docs
            
            # Step 5: Store final results
            output_data = {
                "repository": file_name,
                "analysis": analysis_results,
                "documentation": final_documentation,
                "review": review_results,
                "metadata": {
                    "processing_timestamp": cloud_event.timestamp,
                    "agent_versions": {
                        "adk_version": "1.0.0",
                        "model": "gemini-1.5-pro"
                    }
                }
            }
            
            store_final_documentation(
                storage_client, output_bucket, file_name, output_data
            )
            
            print(f"✅ Successfully processed repository: {file_name}")
            print(f"Quality Score: {review_results.get('quality_score', 'N/A')}")
            
    except Exception as e:
        print(f"Error processing repository {file_name}: {str(e)}")
        raise

def download_and_extract_repo(storage_client, bucket_name, file_name, temp_dir):
    """Download and extract repository zip file."""
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    zip_path = os.path.join(temp_dir, 'repo.zip')
    blob.download_to_filename(zip_path)
    
    extract_path = os.path.join(temp_dir, 'extracted')
    os.makedirs(extract_path, exist_ok=True)
    
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_path)
    
    return extract_path

def store_intermediate_results(storage_client, bucket_name, object_name, data):
    """Store intermediate processing results."""
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    
    json_data = json.dumps(data, indent=2, ensure_ascii=False, default=str)
    blob.upload_from_string(json_data, content_type='application/json')

def store_final_documentation(storage_client, bucket_name, repo_name, output_data):
    """Store final documentation results."""
    bucket = storage_client.bucket(bucket_name)
    
    # Store complete results as JSON
    json_blob = bucket.blob(f"{repo_name}/complete_results.json")
    json_data = json.dumps(output_data, indent=2, ensure_ascii=False, default=str)
    json_blob.upload_from_string(json_data, content_type='application/json')
    
    # Store markdown documentation separately
    docs_blob = bucket.blob(f"{repo_name}/README.md")
    docs_blob.upload_from_string(
        output_data['documentation'], 
        content_type='text/markdown'
    )
    
    # Store analysis summary
    summary_blob = bucket.blob(f"{repo_name}/analysis_summary.json")
    summary_data = {
        "total_files": len(output_data['analysis'].get('file_analyses', [])),
        "complexity_score": output_data['analysis'].get('overall_complexity', 0),
        "quality_score": output_data['review'].get('quality_score', 0),
        "processing_timestamp": output_data['metadata']['processing_timestamp']
    }
    summary_blob.upload_from_string(
        json.dumps(summary_data, indent=2, default=str), 
        content_type='application/json'
    )
EOF

    # Create requirements.txt for Cloud Function
    cat > requirements.txt << 'EOF'
google-adk==1.0.0
google-cloud-storage==2.14.0
functions-framework==3.5.0
GitPython==3.1.43
google-cloud-aiplatform==1.46.0
EOF

    log_success "Cloud Function code created successfully"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Function with the following configuration:"
        log_info "  Function Name: ${FUNCTION_NAME}"
        log_info "  Runtime: python311"
        log_info "  Trigger: Cloud Storage bucket ${INPUT_BUCKET}"
        log_info "  Memory: 1024MB"
        log_info "  Timeout: 540s"
        return
    fi
    
    # Deploy the Cloud Function
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-bucket "${INPUT_BUCKET}" \
        --source . \
        --entry-point process_code_repository \
        --memory 1024MB \
        --timeout 540s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},OUTPUT_BUCKET=${OUTPUT_BUCKET},TEMP_BUCKET=${TEMP_BUCKET}" \
        --region "${REGION}" \
        --quiet
    
    if [[ $? -eq 0 ]]; then
        log_success "Cloud Function deployed successfully"
        log_info "Function Name: ${FUNCTION_NAME}"
        log_info "Trigger Bucket: ${INPUT_BUCKET}"
        log_info "Output Bucket: ${OUTPUT_BUCKET}"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Function to create sample repository for testing
create_sample_repository() {
    log_info "Creating sample repository for testing..."
    
    # Create sample repository structure
    local sample_dir="/tmp/sample_project"
    mkdir -p "${sample_dir}/src/utils" "${sample_dir}/tests"
    
    # Create sample Python modules
    cat > "${sample_dir}/src/main.py" << 'EOF'
"""
Main application module for demonstrating ADK documentation capabilities.
This module orchestrates various services and handles user interactions.
"""

from typing import Dict, List, Optional
import asyncio
from utils.data_processor import DataProcessor
from utils.config_manager import ConfigManager

class ApplicationService:
    """
    Core application service that manages business logic and coordinates
    between different system components for optimal performance.
    """
    
    def __init__(self, config_path: str):
        self.config = ConfigManager(config_path)
        self.processor = DataProcessor(self.config.get_db_settings())
        self.is_running = False
    
    async def start_service(self) -> bool:
        """
        Initialize and start the application service with proper error handling
        and resource management.
        """
        try:
            await self.processor.initialize_connections()
            self.is_running = True
            return True
        except Exception as e:
            print(f"Failed to start service: {e}")
            return False
    
    def process_user_data(self, user_id: str, data: Dict) -> Optional[Dict]:
        """Process user data through the configured data pipeline."""
        if not self.is_running:
            raise RuntimeError("Service not started")
        
        return self.processor.transform_data(user_id, data)
EOF

    cat > "${sample_dir}/src/utils/data_processor.py" << 'EOF'
"""
Data processing utilities for handling various data transformation tasks
with support for multiple data formats and validation rules.
"""

from typing import Dict, Any, List
import json
import asyncio

class DataProcessor:
    """Handles data transformation and validation for the application."""
    
    def __init__(self, db_config: Dict[str, Any]):
        self.db_config = db_config
        self.connection_pool = None
    
    async def initialize_connections(self):
        """Set up database connections and connection pooling."""
        # Simulate async database connection setup
        await asyncio.sleep(0.1)
        self.connection_pool = {"status": "connected", "pool_size": 10}
    
    def transform_data(self, user_id: str, raw_data: Dict) -> Dict:
        """
        Transform raw user data according to business rules and validation schema.
        
        Args:
            user_id: Unique identifier for the user
            raw_data: Raw data dictionary to be processed
            
        Returns:
            Transformed and validated data dictionary
        """
        transformed = {
            "user_id": user_id,
            "processed_at": "2025-07-12T00:00:00Z",
            "data": self._validate_and_clean(raw_data),
            "status": "processed"
        }
        return transformed
    
    def _validate_and_clean(self, data: Dict) -> Dict:
        """Internal method for data validation and cleaning."""
        # Remove None values and empty strings
        cleaned = {k: v for k, v in data.items() if v is not None and v != ""}
        return cleaned
EOF

    cat > "${sample_dir}/src/utils/config_manager.py" << 'EOF'
"""Configuration management utilities for application settings."""

import json
from typing import Dict, Any

class ConfigManager:
    """Manages application configuration with support for multiple environments."""
    
    def __init__(self, config_path: str):
        self.config_path = config_path
        self.config_data = self._load_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from file or return defaults."""
        try:
            with open(self.config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """Return default configuration settings."""
        return {
            "database": {
                "host": "localhost",
                "port": 5432,
                "name": "app_db"
            },
            "api": {
                "timeout": 30,
                "retry_attempts": 3
            }
        }
    
    def get_db_settings(self) -> Dict[str, Any]:
        """Get database configuration settings."""
        return self.config_data.get("database", {})
EOF

    # Create package and zip the sample project
    (cd "${sample_dir}" && zip -r "/tmp/sample_project.zip" .)
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Upload sample repository to trigger documentation process
        log_info "Uploading sample repository to trigger documentation process..."
        gsutil cp "/tmp/sample_project.zip" "gs://${INPUT_BUCKET}/"
        log_success "Sample repository uploaded successfully"
    else
        log_info "[DRY RUN] Would upload sample repository to gs://${INPUT_BUCKET}/"
    fi
    
    # Cleanup temp files
    rm -rf "${sample_dir}" "/tmp/sample_project.zip"
    
    log_success "Sample repository created and processed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "=== CREATED RESOURCES ==="
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Input Bucket: gs://${INPUT_BUCKET}"
    echo "Output Bucket: gs://${OUTPUT_BUCKET}"
    echo "Temp Bucket: gs://${TEMP_BUCKET}"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Upload a code repository (as ZIP file) to: gs://${INPUT_BUCKET}"
    echo "2. Monitor function execution: gcloud functions logs read ${FUNCTION_NAME} --gen2 --region ${REGION}"
    echo "3. Check generated documentation in: gs://${OUTPUT_BUCKET}"
    echo
    echo "=== ESTIMATED COSTS ==="
    echo "- Cloud Functions: ~\$0.40 per 1M invocations + compute time"
    echo "- Cloud Storage: ~\$0.020 per GB per month"
    echo "- Vertex AI (Gemini): ~\$0.00125 per 1K input tokens, \$0.00375 per 1K output tokens"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh --project-id ${PROJECT_ID}"
    echo
}

# Main deployment function
main() {
    # Default values
    PROJECT_ID=""
    REGION="${DEFAULT_REGION}"
    ZONE="${DEFAULT_ZONE}"
    SKIP_APIS="false"
    DRY_RUN="false"
    
    # Parse command line arguments
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
            --skip-apis)
                SKIP_APIS="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required"
        usage
        exit 1
    fi
    
    # Display banner
    echo "=================================="
    echo "  ADK Smart Code Documentation"
    echo "         Deployment Script"
    echo "=================================="
    echo
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be created"
        echo
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_buckets
    setup_adk_environment
    create_adk_agents
    create_cloud_function
    deploy_cloud_function
    create_sample_repository
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        display_summary
    else
        log_info "[DRY RUN] All deployment steps validated successfully"
        log_info "Run without --dry-run to perform actual deployment"
    fi
}

# Run main function with all arguments
main "$@"