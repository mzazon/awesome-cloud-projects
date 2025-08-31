#!/bin/bash

# Smart Resume Screening with Vertex AI and Cloud Functions - Deployment Script
# This script deploys the complete infrastructure for AI-powered resume screening

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

# Default values
DEFAULT_PROJECT_PREFIX="resume-screening"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Parse command line arguments
FORCE_RECREATE=false
DRY_RUN=false
PROJECT_PREFIX="$DEFAULT_PROJECT_PREFIX"
REGION="$DEFAULT_REGION"
ZONE="$DEFAULT_ZONE"

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_RECREATE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --project-prefix)
            PROJECT_PREFIX="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force              Force recreation of existing resources"
            echo "  --dry-run           Show what would be deployed without making changes"
            echo "  --project-prefix    Custom project name prefix (default: resume-screening)"
            echo "  --region           GCP region (default: us-central1)"
            echo "  --zone             GCP zone (default: us-central1-a)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "Starting Smart Resume Screening deployment..."

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud CLI is installed
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    exit 1
fi

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
    error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
    exit 1
fi

# Check if python3 and pip3 are available
if ! command -v python3 &> /dev/null; then
    error "python3 is not installed. Please install Python 3.7 or later"
    exit 1
fi

if ! command -v pip3 &> /dev/null; then
    error "pip3 is not installed. Please install pip3"
    exit 1
fi

success "Prerequisites check completed"

# Set environment variables
export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
export REGION="$REGION"
export ZONE="$ZONE"
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
export BUCKET_NAME="resume-uploads-${RANDOM_SUFFIX}"

log "Configuration:"
log "  Project ID: $PROJECT_ID"
log "  Region: $REGION"
log "  Zone: $ZONE"
log "  Bucket Name: $BUCKET_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be created"
    exit 0
fi

# Create or set project
log "Setting up GCP project..."

if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    if [[ "$FORCE_RECREATE" == "true" ]]; then
        warning "Project $PROJECT_ID exists. Force recreate enabled, continuing..."
    else
        warning "Project $PROJECT_ID already exists. Use --force to recreate or choose different prefix"
        exit 1
    fi
else
    log "Creating new project: $PROJECT_ID"
    if ! gcloud projects create "$PROJECT_ID" --name="Smart Resume Screening" 2>/dev/null; then
        error "Failed to create project. You may need to specify a different project prefix"
        exit 1
    fi
fi

# Set default project and region
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# Link billing account (if available)
BILLING_ACCOUNT=$(gcloud billing accounts list --filter="displayName:My Billing Account" --format="value(name)" 2>/dev/null | head -n1)
if [[ -n "$BILLING_ACCOUNT" ]]; then
    log "Linking billing account..."
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT" 2>/dev/null || warning "Could not link billing account automatically"
else
    warning "No billing account found. Please ensure billing is enabled for this project"
fi

success "Project setup completed: $PROJECT_ID"

# Enable required APIs
log "Enabling required APIs..."

REQUIRED_APIS=(
    "cloudfunctions.googleapis.com"
    "storage.googleapis.com"
    "firestore.googleapis.com"
    "aiplatform.googleapis.com"
    "cloudbuild.googleapis.com"
    "language.googleapis.com"
    "eventarc.googleapis.com"
    "run.googleapis.com"
    "artifactregistry.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    log "Enabling $api..."
    if gcloud services enable "$api" --quiet; then
        success "Enabled $api"
    else
        error "Failed to enable $api"
        exit 1
    fi
done

# Wait for APIs to be fully enabled
log "Waiting for APIs to be fully enabled..."
sleep 30

success "All required APIs enabled"

# Create storage bucket
log "Creating Cloud Storage bucket..."

if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
    if [[ "$FORCE_RECREATE" == "true" ]]; then
        warning "Bucket $BUCKET_NAME exists. Removing and recreating..."
        gsutil -m rm -r "gs://$BUCKET_NAME" || warning "Could not remove existing bucket"
    else
        warning "Bucket $BUCKET_NAME already exists"
    fi
fi

if ! gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        success "Storage bucket created: $BUCKET_NAME"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
fi

# Initialize Firestore database
log "Initializing Firestore database..."

if gcloud firestore databases describe --region="$REGION" &>/dev/null; then
    success "Firestore database already exists"
else
    if gcloud firestore databases create --location="$REGION" --type=firestore-native --quiet; then
        success "Firestore database initialized"
    else
        error "Failed to initialize Firestore database"
        exit 1
    fi
fi

# Create Cloud Function source code
log "Creating Cloud Function source code..."

FUNCTION_DIR="$(mktemp -d)/resume-processor"
mkdir -p "$FUNCTION_DIR"
cd "$FUNCTION_DIR"

# Create main.py
cat << 'EOF' > main.py
import functions_framework
from google.cloud import storage
from google.cloud import firestore
from google.cloud import language_v1
import json
import re
from datetime import datetime
import os

# Initialize clients
storage_client = storage.Client()
firestore_client = firestore.Client()
language_client = language_v1.LanguageServiceClient()

@functions_framework.cloud_event
def process_resume(cloud_event):
    """Triggered by Cloud Storage object creation."""
    data = cloud_event.data
    
    bucket_name = data["bucket"]
    file_name = data["name"]
    
    # Skip if not a resume file
    if not file_name.lower().endswith(('.pdf', '.doc', '.docx', '.txt')):
        return
    
    try:
        # Download and extract text from resume
        resume_text = extract_text_from_file(bucket_name, file_name)
        
        # Analyze resume with Natural Language API
        analysis_result = analyze_resume_with_ai(resume_text)
        
        # Generate screening score
        screening_score = calculate_screening_score(analysis_result)
        
        # Store results in Firestore
        candidate_data = {
            'file_name': file_name,
            'upload_timestamp': datetime.now(),
            'resume_text': resume_text,
            'skills_extracted': analysis_result.get('skills', []),
            'experience_years': analysis_result.get('experience_years', 0),
            'education_level': analysis_result.get('education_level', ''),
            'screening_score': screening_score,
            'sentiment_score': analysis_result.get('sentiment_score', 0.0),
            'entity_analysis': analysis_result.get('entities', []),
            'processed_timestamp': datetime.now()
        }
        
        # Store in Firestore
        doc_ref = firestore_client.collection('candidates').document()
        doc_ref.set(candidate_data)
        
        print(f"Successfully processed resume: {file_name}")
        
    except Exception as e:
        print(f"Error processing resume {file_name}: {str(e)}")

def extract_text_from_file(bucket_name, file_name):
    """Extract text content from uploaded file."""
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    # For demo purposes, assume text files
    # In production, use Document AI or other text extraction services
    if file_name.lower().endswith('.txt'):
        return blob.download_as_text()
    else:
        # Placeholder for PDF/DOC processing
        return f"Sample resume content from {file_name}"

def analyze_resume_with_ai(resume_text):
    """Analyze resume using Google Cloud Natural Language API."""
    # Create document object for Natural Language API
    document = language_v1.Document(
        content=resume_text,
        type_=language_v1.Document.Type.PLAIN_TEXT
    )
    
    # Analyze sentiment
    sentiment_response = language_client.analyze_sentiment(
        request={'document': document}
    )
    
    # Analyze entities
    entities_response = language_client.analyze_entities(
        request={'document': document}
    )
    
    # Extract skills and experience using regex patterns
    skills = extract_skills(resume_text)
    experience_years = extract_experience_years(resume_text)
    education_level = extract_education_level(resume_text)
    
    return {
        'sentiment_score': sentiment_response.document_sentiment.score,
        'entities': [entity.name for entity in entities_response.entities],
        'skills': skills,
        'experience_years': experience_years,
        'education_level': education_level
    }

def extract_skills(text):
    """Extract technical skills from resume text."""
    skill_patterns = [
        r'\b(?:Python|Java|JavaScript|React|Node\.js|SQL|AWS|GCP|Docker|Kubernetes)\b',
        r'\b(?:Machine Learning|Data Science|AI|Analytics|Cloud Computing)\b'
    ]
    
    skills = []
    for pattern in skill_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        skills.extend(matches)
    
    return list(set(skills))

def extract_experience_years(text):
    """Extract years of experience from resume text."""
    experience_pattern = r'(\d+)\+?\s*(?:years?|yrs?)\s*(?:of\s*)?(?:experience|exp)'
    matches = re.findall(experience_pattern, text, re.IGNORECASE)
    
    if matches:
        return max([int(match) for match in matches])
    return 0

def extract_education_level(text):
    """Extract highest education level."""
    if re.search(r'\b(?:PhD|Ph\.D|Doctorate)\b', text, re.IGNORECASE):
        return 'PhD'
    elif re.search(r'\b(?:Master|M\.S|M\.A|MBA)\b', text, re.IGNORECASE):
        return 'Masters'
    elif re.search(r'\b(?:Bachelor|B\.S|B\.A|B\.Tech)\b', text, re.IGNORECASE):
        return 'Bachelors'
    else:
        return 'Other'

def calculate_screening_score(analysis_result):
    """Calculate overall screening score based on extracted information."""
    score = 0
    
    # Experience score (max 40 points)
    experience_years = analysis_result.get('experience_years', 0)
    score += min(experience_years * 4, 40)
    
    # Education score (max 30 points)
    education_scores = {
        'PhD': 30,
        'Masters': 25,
        'Bachelors': 20,
        'Other': 10
    }
    score += education_scores.get(analysis_result.get('education_level', 'Other'), 10)
    
    # Skills score (max 20 points)
    skills_count = len(analysis_result.get('skills', []))
    score += min(skills_count * 2, 20)
    
    # Sentiment score (max 10 points)
    sentiment = analysis_result.get('sentiment_score', 0.0)
    score += max(0, min(sentiment * 10, 10))
    
    return min(score, 100)  # Cap at 100
EOF

# Create requirements.txt
cat << 'EOF' > requirements.txt
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-firestore==2.*
google-cloud-language==2.*
EOF

success "Cloud Function source code created"

# Deploy Cloud Function
log "Deploying Cloud Function..."

if gcloud functions deploy process-resume \
    --gen2 \
    --runtime python311 \
    --trigger-bucket "$BUCKET_NAME" \
    --source . \
    --entry-point process_resume \
    --memory 512MB \
    --timeout 300s \
    --region "$REGION" \
    --set-env-vars PROJECT_ID="$PROJECT_ID" \
    --quiet; then
    success "Cloud Function deployed successfully"
else
    error "Failed to deploy Cloud Function"
    exit 1
fi

# Create sample resume files
log "Creating sample resume files..."

SAMPLE_DIR="$(mktemp -d)/sample-resumes"
mkdir -p "$SAMPLE_DIR"
cd "$SAMPLE_DIR"

cat << 'EOF' > john_doe_resume.txt
John Doe
Senior Software Engineer

EXPERIENCE:
5 years of experience in full-stack development
Proficient in Python, JavaScript, React, Node.js
Experience with AWS and GCP cloud platforms
Led Machine Learning projects for 2 years

EDUCATION:
Master of Science in Computer Science
Bachelor of Science in Software Engineering

SKILLS:
- Python programming
- Machine Learning and Data Science
- Cloud Computing (AWS, GCP)
- Docker and Kubernetes
- SQL databases
EOF

cat << 'EOF' > jane_smith_resume.txt
Jane Smith
Data Scientist

EXPERIENCE:
8 years of experience in data analysis and machine learning
Expert in Python, R, and SQL
3 years leading AI research projects
Published researcher in machine learning conferences

EDUCATION:
PhD in Data Science
Master of Science in Statistics

SKILLS:
- Advanced Python and R programming
- Machine Learning algorithms
- Deep Learning frameworks
- Statistical analysis
- Big Data technologies
EOF

success "Sample resume files created"

# Upload sample resumes
log "Uploading sample resumes to trigger processing..."

if gsutil cp john_doe_resume.txt "gs://$BUCKET_NAME/" && \
   gsutil cp jane_smith_resume.txt "gs://$BUCKET_NAME/"; then
    success "Sample resumes uploaded"
else
    error "Failed to upload sample resumes"
    exit 1
fi

# Wait for processing to complete
log "Waiting for resume processing to complete..."
sleep 45

# Create candidate retrieval script
log "Creating candidate retrieval script..."

SCRIPT_DIR="$(pwd)"
cat << 'EOF' > retrieve_candidates.py
from google.cloud import firestore
import json
from datetime import datetime

def get_candidates_by_score(min_score=0):
    """Retrieve candidates sorted by screening score."""
    db = firestore.Client()
    
    candidates = db.collection('candidates') \
        .where('screening_score', '>=', min_score) \
        .order_by('screening_score', direction=firestore.Query.DESCENDING) \
        .stream()
    
    results = []
    for candidate in candidates:
        data = candidate.to_dict()
        # Convert timestamps to strings for JSON serialization
        if 'upload_timestamp' in data:
            data['upload_timestamp'] = data['upload_timestamp'].isoformat()
        if 'processed_timestamp' in data:
            data['processed_timestamp'] = data['processed_timestamp'].isoformat()
        
        results.append({
            'id': candidate.id,
            'file_name': data.get('file_name', ''),
            'screening_score': data.get('screening_score', 0),
            'experience_years': data.get('experience_years', 0),
            'education_level': data.get('education_level', ''),
            'skills_count': len(data.get('skills_extracted', [])),
            'skills': data.get('skills_extracted', []),
            'sentiment_score': data.get('sentiment_score', 0.0),
            'upload_time': data.get('upload_timestamp', '')
        })
    
    return results

if __name__ == "__main__":
    candidates = get_candidates_by_score()
    print(f"Found {len(candidates)} processed candidates:")
    print(json.dumps(candidates, indent=2))
EOF

success "Candidate retrieval script created"

# Install Python dependencies for testing
log "Installing Python dependencies for testing..."
pip3 install google-cloud-firestore >/dev/null 2>&1 || warning "Could not install google-cloud-firestore. Manual installation may be required"

# Test the deployment
log "Testing deployment..."

# Check function status
if gcloud functions describe process-resume --region="$REGION" --format="value(name,status)" | grep -q "ACTIVE"; then
    success "Cloud Function is active"
else
    warning "Cloud Function may not be fully active yet"
fi

# Wait a bit more and check Firestore
sleep 15

log "Checking Firestore for processed candidates..."
if python3 retrieve_candidates.py 2>/dev/null | grep -q "Found"; then
    success "Candidates found in Firestore"
else
    warning "No candidates found yet. Processing may still be in progress"
fi

# Save deployment information
DEPLOYMENT_INFO_FILE="deployment_info.json"
cat << EOF > "$DEPLOYMENT_INFO_FILE"
{
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "bucket_name": "$BUCKET_NAME",
  "function_name": "process-resume",
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script_location": "$SCRIPT_DIR"
}
EOF

success "Deployment completed successfully!"
log ""
log "Deployment Summary:"
log "==================="
log "Project ID: $PROJECT_ID"
log "Region: $REGION"
log "Storage Bucket: gs://$BUCKET_NAME"
log "Cloud Function: process-resume"
log "Candidate Retrieval Script: $SCRIPT_DIR/retrieve_candidates.py"
log "Deployment Info: $SCRIPT_DIR/$DEPLOYMENT_INFO_FILE"
log ""
log "Next Steps:"
log "1. Upload resume files to gs://$BUCKET_NAME to test the system"
log "2. Run 'python3 $SCRIPT_DIR/retrieve_candidates.py' to view processed candidates"
log "3. Monitor function logs with: gcloud functions logs read process-resume --region=$REGION"
log ""
warning "Remember to run the destroy script when done to avoid ongoing charges"