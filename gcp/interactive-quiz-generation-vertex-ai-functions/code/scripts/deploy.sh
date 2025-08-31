#!/bin/bash

# Deploy Interactive Quiz Generation with Vertex AI and Functions
# This script automates the deployment of the complete quiz generation system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        echo "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing jq for JSON processing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install jq
            else
                error "Please install jq manually: https://jqlang.github.io/jq/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            else
                error "Please install jq manually: https://jqlang.github.io/jq/"
                exit 1
            fi
        fi
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="quiz-generation-$(date +%s)"
        log "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    
    # Set default zone if not provided
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="us-central1-a"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="quiz-materials-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="quiz-generator-${RANDOM_SUFFIX}"
    export DELIVERY_FUNCTION_NAME="quiz-delivery-${RANDOM_SUFFIX}"
    export SCORING_FUNCTION_NAME="quiz-scoring-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
DELIVERY_FUNCTION_NAME=${DELIVERY_FUNCTION_NAME}
SCORING_FUNCTION_NAME=${SCORING_FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Bucket Name: ${BUCKET_NAME}"
}

# Function to create and configure GCP project
setup_project() {
    log "Setting up GCP project..."
    
    # Check if project already exists
    if gcloud projects describe ${PROJECT_ID} &> /dev/null; then
        warning "Project ${PROJECT_ID} already exists, using existing project"
    else
        # Create new project
        log "Creating new project: ${PROJECT_ID}"
        gcloud projects create ${PROJECT_ID} --name="Quiz Generation Demo"
        
        # Check if billing account is available and link it
        BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --filter="open:true" | head -n1)
        if [[ -n "${BILLING_ACCOUNT}" ]]; then
            log "Linking billing account: ${BILLING_ACCOUNT}"
            gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT}
        else
            warning "No active billing account found. Please link billing manually:"
            echo "gcloud billing projects link ${PROJECT_ID} --billing-account=BILLING_ACCOUNT_ID"
        fi
    fi
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable ${api} --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create service account
create_service_account() {
    log "Creating service account for Vertex AI access..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com &> /dev/null; then
        warning "Service account already exists"
    else
        gcloud iam service-accounts create quiz-ai-service \
            --display-name="Quiz Generation AI Service" \
            --description="Service account for Vertex AI quiz generation"
    fi
    
    # Grant necessary permissions
    log "Granting IAM permissions..."
    
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/aiplatform.user" \
        --quiet
    
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet
    
    success "Service account configured with proper permissions"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for learning materials..."
    
    # Check if bucket already exists
    if gsutil ls -b gs://${BUCKET_NAME} &> /dev/null; then
        warning "Bucket ${BUCKET_NAME} already exists"
    else
        # Create storage bucket
        gsutil mb -p ${PROJECT_ID} \
            -c STANDARD \
            -l ${REGION} \
            gs://${BUCKET_NAME}
        
        # Enable versioning
        gsutil versioning set on gs://${BUCKET_NAME}
    fi
    
    # Set up bucket structure
    log "Creating bucket structure..."
    echo "" | gsutil cp - gs://${BUCKET_NAME}/uploads/.keep
    echo "" | gsutil cp - gs://${BUCKET_NAME}/quizzes/.keep
    echo "" | gsutil cp - gs://${BUCKET_NAME}/results/.keep
    
    # Set bucket lifecycle for cost optimization
    log "Configuring lifecycle policy..."
    cat > lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"}, 
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set lifecycle.json gs://${BUCKET_NAME}
    rm lifecycle.json
    
    success "Cloud Storage bucket created with organized structure"
}

# Function to create function directories and code
create_function_code() {
    log "Creating Cloud Function code..."
    
    # Create base directory
    mkdir -p quiz-functions
    cd quiz-functions
    
    # Create quiz generator function
    log "Creating quiz generation function..."
    mkdir -p quiz-generator
    cd quiz-generator
    
    cat > requirements.txt << 'EOF'
google-cloud-aiplatform==1.75.0
google-cloud-storage==2.18.0
functions-framework==3.8.1
Flask==3.0.3
PyPDF2==3.0.1
python-docx==1.1.2
EOF
    
    cat > main.py << 'EOF'
import json
import os
from typing import Dict, List, Any
from google.cloud import aiplatform
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework
from flask import Request, jsonify

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
REGION = os.environ.get('REGION', 'us-central1')

vertexai.init(project=PROJECT_ID, location=REGION)
model = GenerativeModel("gemini-1.5-flash-002")

@functions_framework.http
def generate_quiz(request: Request) -> Any:
    """Generate quiz from uploaded content using Vertex AI."""
    
    if request.method == 'OPTIONS':
        return _handle_cors()
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        content_text = request_json.get('content', '')
        question_count = request_json.get('question_count', 5)
        difficulty = request_json.get('difficulty', 'medium')
        
        if not content_text:
            return jsonify({'error': 'Content text is required'}), 400
        
        # Generate quiz using Vertex AI
        quiz = _generate_quiz_with_ai(content_text, question_count, difficulty)
        
        # Store quiz in Cloud Storage
        quiz_id = _store_quiz(quiz)
        
        response = jsonify({
            'quiz_id': quiz_id,
            'quiz': quiz,
            'status': 'success'
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        error_response = jsonify({'error': str(e), 'status': 'error'})
        error_response.headers.add('Access-Control-Allow-Origin', '*')
        return error_response, 500

def _generate_quiz_with_ai(content: str, count: int, difficulty: str) -> Dict:
    """Use Vertex AI to generate quiz questions from content."""
    
    prompt = f"""
    Based on the following educational content, generate {count} quiz questions at {difficulty} difficulty level.
    
    Create a mix of question types:
    - Multiple choice (4 options each)
    - True/False
    - Short answer
    
    Content:
    {content[:4000]}  # Limit content to stay within token limits
    
    Return the response as valid JSON with this structure:
    {{
        "title": "Quiz Title",
        "questions": [
            {{
                "type": "multiple_choice",
                "question": "Question text",
                "options": ["A", "B", "C", "D"],
                "correct_answer": 0,
                "explanation": "Why this answer is correct"
            }},
            {{
                "type": "true_false",
                "question": "Question text",
                "correct_answer": true,
                "explanation": "Explanation"
            }},
            {{
                "type": "short_answer",
                "question": "Question text",
                "sample_answer": "Expected answer",
                "explanation": "Explanation"
            }}
        ]
    }}
    """
    
    response = model.generate_content(prompt)
    
    try:
        # Clean response text and parse as JSON
        response_text = response.text.strip()
        if response_text.startswith('```json'):
            response_text = response_text[7:-3].strip()
        elif response_text.startswith('```'):
            response_text = response_text[3:-3].strip()
        
        quiz_data = json.loads(response_text)
        
        # Validate quiz structure
        if 'questions' not in quiz_data or not quiz_data['questions']:
            raise ValueError("Invalid quiz structure")
            
        return quiz_data
        
    except (json.JSONDecodeError, ValueError) as e:
        print(f"Error parsing AI response: {e}. Using fallback quiz.")
        # Fallback if AI doesn't return valid JSON
        return {
            "title": "Generated Quiz",
            "questions": [{
                "type": "multiple_choice",
                "question": "What is the main topic of the provided content?",
                "options": ["Topic A", "Topic B", "Topic C", "Topic D"],
                "correct_answer": 0,
                "explanation": "Based on content analysis"
            }]
        }

def _store_quiz(quiz_data: Dict) -> str:
    """Store generated quiz in Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME')
    bucket = storage_client.bucket(bucket_name)
    
    # Generate unique quiz ID
    quiz_id = f"quiz_{os.urandom(8).hex()}"
    blob_name = f"quizzes/{quiz_id}.json"
    
    blob = bucket.blob(blob_name)
    blob.upload_from_string(
        json.dumps(quiz_data, indent=2),
        content_type='application/json'
    )
    
    return quiz_id

def _handle_cors():
    """Handle CORS preflight requests."""
    response = jsonify({'status': 'ok'})
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
    return response
EOF
    
    cd ..
    
    # Create quiz delivery function
    log "Creating quiz delivery function..."
    mkdir -p quiz-delivery
    cd quiz-delivery
    
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.18.0
functions-framework==3.8.1
Flask==3.0.3
EOF
    
    cat > main.py << 'EOF'
import json
import os
from google.cloud import storage
import functions_framework
from flask import Request, jsonify

@functions_framework.http
def deliver_quiz(request: Request):
    """Deliver quiz to students with proper formatting."""
    
    if request.method == 'OPTIONS':
        return _handle_cors()
    
    try:
        # Get quiz ID from request
        quiz_id = request.args.get('quiz_id')
        if not quiz_id:
            return jsonify({'error': 'Quiz ID required'}), 400
        
        # Retrieve quiz from storage
        quiz_data = _get_quiz_from_storage(quiz_id)
        if not quiz_data:
            return jsonify({'error': 'Quiz not found'}), 404
        
        # Format quiz for delivery (remove answers for student view)
        student_quiz = _format_for_students(quiz_data)
        
        response = jsonify({
            'quiz_id': quiz_id,
            'quiz': student_quiz,
            'status': 'success'
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        error_response = jsonify({'error': str(e)})
        error_response.headers.add('Access-Control-Allow-Origin', '*')
        return error_response, 500

def _get_quiz_from_storage(quiz_id: str):
    """Retrieve quiz from Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME')
    bucket = storage_client.bucket(bucket_name)
    
    blob_name = f"quizzes/{quiz_id}.json"
    blob = bucket.blob(blob_name)
    
    if not blob.exists():
        return None
    
    quiz_content = blob.download_as_text()
    return json.loads(quiz_content)

def _format_for_students(quiz_data):
    """Remove correct answers for student delivery."""
    
    formatted_quiz = {
        'title': quiz_data.get('title', 'Quiz'),
        'questions': []
    }
    
    for i, question in enumerate(quiz_data.get('questions', [])):
        student_question = {
            'id': i,
            'type': question['type'],
            'question': question['question']
        }
        
        if question['type'] == 'multiple_choice':
            student_question['options'] = question['options']
        
        formatted_quiz['questions'].append(student_question)
    
    return formatted_quiz

def _handle_cors():
    """Handle CORS preflight requests."""
    response = jsonify({'status': 'ok'})
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
    return response
EOF
    
    cd ..
    
    # Create quiz scoring function
    log "Creating quiz scoring function..."
    mkdir -p quiz-scoring
    cd quiz-scoring
    
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.18.0
functions-framework==3.8.1
Flask==3.0.3
EOF
    
    cat > main.py << 'EOF'
import json
import os
from datetime import datetime
from google.cloud import storage
import functions_framework
from flask import Request, jsonify

@functions_framework.http
def score_quiz(request: Request):
    """Score submitted quiz and provide feedback."""
    
    if request.method == 'OPTIONS':
        return _handle_cors()
    
    try:
        # Parse submission data
        request_json = request.get_json(silent=True)
        if not request_json:
            return jsonify({'error': 'No submission data'}), 400
        
        quiz_id = request_json.get('quiz_id')
        student_answers = request_json.get('answers', {})
        student_id = request_json.get('student_id', 'anonymous')
        
        # Get original quiz with answers
        quiz_data = _get_quiz_from_storage(quiz_id)
        if not quiz_data:
            return jsonify({'error': 'Quiz not found'}), 404
        
        # Calculate score and feedback
        results = _calculate_score(quiz_data, student_answers)
        
        # Store results
        result_id = _store_results(quiz_id, student_id, student_answers, results)
        
        response = jsonify({
            'result_id': result_id,
            'score': results['score'],
            'total_questions': results['total_questions'],
            'percentage': results['percentage'],
            'feedback': results['feedback'],
            'status': 'success'
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        error_response = jsonify({'error': str(e)})
        error_response.headers.add('Access-Control-Allow-Origin', '*')
        return error_response, 500

def _get_quiz_from_storage(quiz_id: str):
    """Retrieve quiz from Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME')
    bucket = storage_client.bucket(bucket_name)
    
    blob_name = f"quizzes/{quiz_id}.json"
    blob = bucket.blob(blob_name)
    
    if not blob.exists():
        return None
    
    quiz_content = blob.download_as_text()
    return json.loads(quiz_content)

def _calculate_score(quiz_data, student_answers):
    """Calculate score and provide detailed feedback."""
    
    questions = quiz_data.get('questions', [])
    correct_count = 0
    total_questions = len(questions)
    feedback = []
    
    for i, question in enumerate(questions):
        question_id = str(i)
        student_answer = student_answers.get(question_id)
        
        is_correct = False
        explanation = question.get('explanation', 'No explanation available')
        
        if question['type'] == 'multiple_choice':
            correct_answer = question['correct_answer']
            is_correct = student_answer == correct_answer
            
        elif question['type'] == 'true_false':
            correct_answer = question['correct_answer']
            is_correct = student_answer == correct_answer
            
        elif question['type'] == 'short_answer':
            # Simple text matching for short answers
            correct_answer = question.get('sample_answer', '').lower()
            student_text = str(student_answer).lower() if student_answer else ''
            is_correct = correct_answer in student_text or student_text in correct_answer
        
        if is_correct:
            correct_count += 1
        
        feedback.append({
            'question_id': i,
            'question': question['question'],
            'correct': is_correct,
            'explanation': explanation
        })
    
    percentage = (correct_count / total_questions * 100) if total_questions > 0 else 0
    
    return {
        'score': correct_count,
        'total_questions': total_questions,
        'percentage': round(percentage, 2),
        'feedback': feedback
    }

def _store_results(quiz_id, student_id, answers, results):
    """Store quiz results in Cloud Storage."""
    
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME')
    bucket = storage_client.bucket(bucket_name)
    
    result_id = f"result_{os.urandom(8).hex()}"
    blob_name = f"results/{result_id}.json"
    
    result_data = {
        'result_id': result_id,
        'quiz_id': quiz_id,
        'student_id': student_id,
        'timestamp': datetime.utcnow().isoformat(),
        'answers': answers,
        'results': results
    }
    
    blob = bucket.blob(blob_name)
    blob.upload_from_string(
        json.dumps(result_data, indent=2),
        content_type='application/json'
    )
    
    return result_id

def _handle_cors():
    """Handle CORS preflight requests."""
    response = jsonify({'status': 'ok'})
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
    return response
EOF
    
    cd ../..
    
    success "Function code created successfully"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    cd quiz-functions
    
    # Deploy quiz generation function
    log "Deploying quiz generation function..."
    cd quiz-generator
    
    gcloud functions deploy ${FUNCTION_NAME} \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_quiz \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars BUCKET_NAME=${BUCKET_NAME},REGION=${REGION} \
        --service-account quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com \
        --quiet
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
        --format="value(httpsTrigger.url)")
    echo "FUNCTION_URL=${FUNCTION_URL}" >> ../../.env
    
    cd ../quiz-delivery
    
    # Deploy quiz delivery function
    log "Deploying quiz delivery function..."
    gcloud functions deploy ${DELIVERY_FUNCTION_NAME} \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point deliver_quiz \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars BUCKET_NAME=${BUCKET_NAME} \
        --quiet
    
    # Get delivery function URL
    DELIVERY_URL=$(gcloud functions describe ${DELIVERY_FUNCTION_NAME} \
        --format="value(httpsTrigger.url)")
    echo "DELIVERY_URL=${DELIVERY_URL}" >> ../../.env
    
    cd ../quiz-scoring
    
    # Deploy scoring function
    log "Deploying quiz scoring function..."
    gcloud functions deploy ${SCORING_FUNCTION_NAME} \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point score_quiz \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars BUCKET_NAME=${BUCKET_NAME} \
        --quiet
    
    # Get scoring function URL
    SCORING_URL=$(gcloud functions describe ${SCORING_FUNCTION_NAME} \
        --format="value(httpsTrigger.url)")
    echo "SCORING_URL=${SCORING_URL}" >> ../../.env
    
    cd ../..
    
    success "All Cloud Functions deployed successfully"
    success "Generation URL: ${FUNCTION_URL}"
    success "Delivery URL: ${DELIVERY_URL}"
    success "Scoring URL: ${SCORING_URL}"
}

# Function to create sample content for testing
create_sample_content() {
    log "Creating sample content for testing..."
    
    cat > sample_content.json << 'EOF'
{
  "content": "Cloud computing is a technology that enables on-demand access to computing resources over the internet. Key benefits include scalability, cost-effectiveness, and flexibility. Major cloud service models include Infrastructure as a Service (IaaS), Platform as a Service (PaaS), and Software as a Service (SaaS). Cloud deployment models include public, private, hybrid, and multi-cloud approaches.",
  "question_count": 3,
  "difficulty": "medium"
}
EOF
    
    success "Sample content created for system testing"
}

# Function to test the deployed system
test_system() {
    log "Testing the deployed system..."
    
    # Source environment variables
    source .env
    
    # Test quiz generation
    log "Testing quiz generation..."
    if curl -X POST ${FUNCTION_URL} \
        -H "Content-Type: application/json" \
        -d @sample_content.json \
        -o quiz_response.json \
        --fail --silent --show-error; then
        
        success "Quiz generation test passed"
        
        # Extract quiz ID for further testing
        QUIZ_ID=$(cat quiz_response.json | jq -r '.quiz_id')
        log "Generated Quiz ID: ${QUIZ_ID}"
        
        # Test quiz delivery
        log "Testing quiz delivery..."
        if curl "${DELIVERY_URL}?quiz_id=${QUIZ_ID}" \
            -o delivered_quiz.json \
            --fail --silent --show-error; then
            success "Quiz delivery test passed"
        else
            error "Quiz delivery test failed"
        fi
        
        # Test quiz scoring
        log "Testing quiz scoring..."
        cat > student_submission.json << EOF
{
  "quiz_id": "${QUIZ_ID}",
  "student_id": "test_student_001",
  "answers": {
    "0": 1,
    "1": true,
    "2": "cloud services"
  }
}
EOF
        
        if curl -X POST ${SCORING_URL} \
            -H "Content-Type: application/json" \
            -d @student_submission.json \
            -o scoring_results.json \
            --fail --silent --show-error; then
            success "Quiz scoring test passed"
        else
            error "Quiz scoring test failed"
        fi
        
    else
        error "Quiz generation test failed"
    fi
    
    success "System testing completed"
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment Summary"
    echo "===================="
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "Deployed Functions:"
    echo "- Quiz Generation: ${FUNCTION_URL}"
    echo "- Quiz Delivery: ${DELIVERY_URL}"
    echo "- Quiz Scoring: ${SCORING_URL}"
    echo ""
    echo "Service Account: quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "Environment variables saved to .env file"
    echo "Use './destroy.sh' to clean up all resources"
    echo ""
    success "Interactive Quiz Generation system deployed successfully!"
}

# Main deployment function
main() {
    log "Starting Interactive Quiz Generation with Vertex AI and Functions deployment"
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_service_account
    create_storage_bucket
    create_function_code
    deploy_functions
    create_sample_content
    test_system
    show_deployment_summary
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up partial deployment."; exit 1' INT TERM

# Run main function
main "$@"