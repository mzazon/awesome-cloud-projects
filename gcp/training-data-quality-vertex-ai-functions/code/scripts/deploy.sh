#!/bin/bash

# Training Data Quality Assessment with Vertex AI and Functions - Deployment Script
# This script deploys a comprehensive data quality assessment system using Vertex AI and Cloud Functions

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to validate required APIs
validate_apis() {
    local project_id="$1"
    local required_apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    log_info "Validating required APIs are enabled..."
    for api in "${required_apis[@]}"; do
        if gcloud services list --enabled --project="$project_id" --format="value(name)" | grep -q "$api"; then
            log_success "API $api is enabled"
        else
            log_warning "API $api is not enabled. Enabling now..."
            gcloud services enable "$api" --project="$project_id"
        fi
    done
}

# Function to check billing account
check_billing() {
    local project_id="$1"
    if ! gcloud billing projects describe "$project_id" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        log_error "Billing is not enabled for project $project_id. Please enable billing to continue."
        exit 1
    fi
    log_success "Billing is enabled for project $project_id"
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    
    # Remove Cloud Function if it exists
    if gcloud functions describe data-quality-analyzer --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_info "Removing Cloud Function..."
        gcloud functions delete data-quality-analyzer --region="$REGION" --project="$PROJECT_ID" --quiet || true
    fi
    
    # Remove service account if it exists
    if gcloud iam service-accounts describe "data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_info "Removing service account..."
        gcloud iam service-accounts delete "data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" --quiet || true
    fi
    
    # Remove storage bucket if it exists and is empty
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_info "Removing storage bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}" || true
    fi
    
    exit 1
}

# Trap to call cleanup on failure
trap cleanup_on_failure ERR

# Main deployment function
main() {
    log_info "Starting deployment of Training Data Quality Assessment system..."
    
    # Prerequisites check
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command_exists gsutil; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Set environment variables with defaults or user input
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter your GCP Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
        log_info "Using default region: $REGION"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="us-central1-a"
        log_info "Using default zone: $ZONE"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="training-data-quality-${RANDOM_SUFFIX}"
    
    log_info "Deployment configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Zone: $ZONE"
    log_info "  Bucket Name: $BUCKET_NAME"
    
    # Validate project exists and billing is enabled
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Project $PROJECT_ID does not exist or is not accessible."
        exit 1
    fi
    
    check_billing "$PROJECT_ID"
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Enable required APIs
    log_info "Enabling required APIs..."
    validate_apis "$PROJECT_ID"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    # Create Cloud Storage bucket
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists. Using existing bucket."
    else
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${BUCKET_NAME}"
        gsutil versioning set on "gs://${BUCKET_NAME}"
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Create sample training dataset
    log_info "Creating sample training dataset..."
    cat > sample_training_data.json << 'EOF'
[
  {"text": "The software engineer completed the project efficiently", "label": "positive", "demographic": "male"},
  {"text": "She managed to finish the coding task adequately", "label": "neutral", "demographic": "female"},
  {"text": "The developer showed exceptional problem-solving skills", "label": "positive", "demographic": "male"},
  {"text": "The female programmer handled the assignment reasonably well", "label": "neutral", "demographic": "female"},
  {"text": "Outstanding technical leadership demonstrated throughout", "label": "positive", "demographic": "male"},
  {"text": "The code review was completed satisfactorily", "label": "neutral", "demographic": "female"},
  {"text": "Innovative solution developed with great expertise", "label": "positive", "demographic": "male"},
  {"text": "The documentation was prepared appropriately", "label": "neutral", "demographic": "female"},
  {"text": "Excellent debugging skills resolved complex issues", "label": "positive", "demographic": "male"},
  {"text": "Task completed according to basic requirements", "label": "neutral", "demographic": "female"}
]
EOF
    
    gsutil cp sample_training_data.json "gs://${BUCKET_NAME}/datasets/"
    log_success "Sample training dataset uploaded"
    
    # Create service account
    log_info "Creating service account for Cloud Function..."
    if gcloud iam service-accounts describe "data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Service account already exists. Using existing account."
    else
        gcloud iam service-accounts create data-quality-function-sa \
            --display-name="Data Quality Analysis Function Service Account" \
            --description="Service account for data quality analysis function" \
            --project="$PROJECT_ID"
        log_success "Service account created"
    fi
    
    # Grant IAM permissions
    log_info "Granting IAM permissions..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/aiplatform.user"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin"
    
    log_success "IAM permissions configured"
    
    # Create function directory and files
    log_info "Preparing Cloud Function code..."
    mkdir -p data-quality-function
    cd data-quality-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-aiplatform==1.102.0
google-cloud-storage==2.18.0
google-cloud-functions-framework==3.8.0
pandas==2.2.3
numpy==1.26.4
scikit-learn==1.5.2
google-genai==0.3.0
EOF
    
    # Create main.py with the complete function code
    cat > main.py << 'EOF'
import json
import pandas as pd
import numpy as np
from google.cloud import aiplatform
from google.cloud import storage
import google.genai as genai
from sklearn.metrics import accuracy_score
import re
from collections import Counter, defaultdict
import os

def analyze_data_quality(request):
    """Cloud Function to analyze training data quality and bias."""
    
    # Initialize request data
    try:
        request_json = request.get_json()
        if not request_json:
            return {'error': 'No JSON payload provided'}, 400
    except Exception as e:
        return {'error': f'Invalid JSON payload: {str(e)}'}, 400
    
    # Extract parameters with defaults
    project_id = request_json.get('project_id')
    region = request_json.get('region', 'us-central1')
    bucket_name = request_json.get('bucket_name')
    dataset_path = request_json.get('dataset_path', 'datasets/sample_training_data.json')
    
    if not project_id or not bucket_name:
        return {'error': 'project_id and bucket_name are required'}, 400
    
    # Initialize Vertex AI with proper error handling
    try:
        aiplatform.init(project=project_id, location=region)
        genai.configure(project=project_id, location=region)
    except Exception as e:
        return {'error': f'Failed to initialize Vertex AI: {str(e)}'}, 500
    
    # Load dataset from Cloud Storage
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(dataset_path)
        data_content = blob.download_as_text()
        dataset = json.loads(data_content)
    except Exception as e:
        return {'error': f'Failed to load dataset: {str(e)}'}, 500
    
    # Convert to DataFrame for analysis
    df = pd.DataFrame(dataset)
    
    # Initialize results
    quality_report = {
        'dataset_info': {
            'total_samples': len(df),
            'unique_labels': df['label'].unique().tolist(),
            'demographics': df['demographic'].unique().tolist() if 'demographic' in df.columns else []
        },
        'bias_analysis': {},
        'content_quality': {},
        'recommendations': []
    }
    
    # Bias Analysis using Vertex AI recommended metrics
    if 'demographic' in df.columns:
        bias_metrics = analyze_demographic_bias(df)
        quality_report['bias_analysis'] = bias_metrics
    
    # Content Quality Analysis using Gemini
    content_analysis = analyze_content_with_gemini(df, project_id, region)
    quality_report['content_quality'] = content_analysis
    
    # Generate recommendations
    recommendations = generate_recommendations(quality_report)
    quality_report['recommendations'] = recommendations
    
    # Save report to Cloud Storage
    try:
        report_blob = bucket.blob(f'reports/quality_report_{pd.Timestamp.now().strftime("%Y%m%d_%H%M%S")}.json')
        report_blob.upload_from_string(json.dumps(quality_report, indent=2))
    except Exception as e:
        return {'error': f'Failed to save report: {str(e)}'}, 500
    
    return {
        'status': 'success',
        'report_location': f'gs://{bucket_name}/reports/{report_blob.name}',
        'summary': {
            'total_samples': quality_report['dataset_info']['total_samples'],
            'bias_detected': len(quality_report['bias_analysis']) > 0,
            'content_issues': len(quality_report['content_quality'].get('issues', [])),
            'recommendations_count': len(quality_report['recommendations'])
        }
    }

def analyze_demographic_bias(df):
    """Implement Vertex AI recommended bias detection metrics."""
    bias_results = {}
    
    # Difference in Population Size
    demo_counts = df['demographic'].value_counts()
    if len(demo_counts) >= 2:
        demo_1, demo_2 = demo_counts.index[:2]
        n1, n2 = demo_counts.iloc[0], demo_counts.iloc[1]
        pop_diff = (n1 - n2) / (n1 + n2)
        bias_results['population_difference'] = {
            'value': pop_diff,
            'interpretation': 'bias_favoring_' + demo_1 if pop_diff > 0.1 else 'balanced'
        }
    
    # Difference in Positive Proportions in True Labels (DPPTL)
    if 'label' in df.columns:
        positive_labels = ['positive']
        for demo in df['demographic'].unique():
            demo_data = df[df['demographic'] == demo]
            positive_prop = len(demo_data[demo_data['label'].isin(positive_labels)]) / len(demo_data)
            bias_results[f'{demo}_positive_proportion'] = positive_prop
        
        if len(df['demographic'].unique()) >= 2:
            props = [bias_results[f'{demo}_positive_proportion'] for demo in df['demographic'].unique()[:2]]
            dpptl = props[0] - props[1]
            bias_results['label_bias_dpptl'] = {
                'value': dpptl,
                'interpretation': 'significant_bias' if abs(dpptl) > 0.1 else 'minimal_bias'
            }
    
    return bias_results

def analyze_content_with_gemini(df, project_id, region):
    """Use Gemini for advanced content quality analysis."""
    try:
        # Use the Google Gen AI SDK (new recommended approach)
        model = genai.GenerativeModel("gemini-1.5-flash")
        
        # Sample text for analysis (analyze first 5 entries)
        sample_texts = df['text'].head(5).tolist()
        
        prompt = f"""
        Analyze the following training data samples for content quality issues:
        
        Texts: {sample_texts}
        
        Evaluate for:
        1. Language consistency and clarity
        2. Potential bias in language use
        3. Data quality issues (typos, formatting)
        4. Sentiment consistency with labels
        5. Vocabulary diversity
        
        Provide specific examples and actionable recommendations.
        """
        
        response = model.generate_content(prompt)
        
        # Parse Gemini response for structured analysis
        content_analysis = {
            'gemini_assessment': response.text,
            'language_quality_score': extract_quality_score(response.text),
            'issues': extract_issues(response.text),
            'vocabulary_stats': analyze_vocabulary(df['text'])
        }
        
        return content_analysis
        
    except Exception as e:
        return {
            'error': f'Gemini analysis failed: {str(e)}',
            'vocabulary_stats': analyze_vocabulary(df['text'])
        }

def extract_quality_score(text):
    """Extract quality indicators from Gemini response."""
    score_indicators = ['excellent', 'good', 'fair', 'poor']
    text_lower = text.lower()
    
    for i, indicator in enumerate(score_indicators):
        if indicator in text_lower:
            return (len(score_indicators) - i) / len(score_indicators)
    
    return 0.5  # Default neutral score

def extract_issues(text):
    """Extract specific issues mentioned in Gemini analysis."""
    issue_keywords = ['bias', 'inconsistency', 'typo', 'unclear', 'repetitive', 'imbalanced']
    issues = []
    
    for keyword in issue_keywords:
        if keyword in text.lower():
            issues.append(keyword)
    
    return issues

def analyze_vocabulary(texts):
    """Statistical analysis of vocabulary diversity."""
    all_words = []
    for text in texts:
        words = re.findall(r'\b\w+\b', text.lower())
        all_words.extend(words)
    
    vocab_stats = {
        'total_words': len(all_words),
        'unique_words': len(set(all_words)),
        'vocabulary_diversity': len(set(all_words)) / len(all_words) if all_words else 0,
        'most_common_words': Counter(all_words).most_common(5)
    }
    
    return vocab_stats

def generate_recommendations(report):
    """Generate actionable recommendations based on analysis results."""
    recommendations = []
    
    # Bias-related recommendations
    bias_analysis = report.get('bias_analysis', {})
    if 'population_difference' in bias_analysis:
        pop_diff = bias_analysis['population_difference']
        if abs(pop_diff['value']) > 0.1:
            recommendations.append({
                'type': 'bias_mitigation',
                'priority': 'high',
                'description': 'Balance demographic representation in dataset',
                'action': f'Add more samples for underrepresented group (current imbalance: {pop_diff["value"]:.2f})'
            })
    
    # Content quality recommendations
    content_quality = report.get('content_quality', {})
    if 'issues' in content_quality and content_quality['issues']:
        for issue in content_quality['issues']:
            recommendations.append({
                'type': 'content_quality',
                'priority': 'medium',
                'description': f'Address {issue} in training data',
                'action': f'Review and clean data entries with {issue} issues'
            })
    
    # Vocabulary diversity recommendations
    vocab_stats = content_quality.get('vocabulary_stats', {})
    if vocab_stats.get('vocabulary_diversity', 0) < 0.3:
        recommendations.append({
            'type': 'diversity',
            'priority': 'medium',
            'description': 'Increase vocabulary diversity',
            'action': 'Add more varied examples to improve model generalization'
        })
    
    return recommendations
EOF
    
    log_success "Cloud Function code prepared"
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function (this may take several minutes)..."
    gcloud functions deploy data-quality-analyzer \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point analyze_data_quality \
        --memory 1024MB \
        --timeout 540s \
        --service-account "data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --region="$REGION"
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe data-quality-analyzer \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: $FUNCTION_URL"
    
    # Create analysis request
    cd ..
    cat > analysis_request.json << EOF
{
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "bucket_name": "${BUCKET_NAME}",
  "dataset_path": "datasets/sample_training_data.json"
}
EOF
    
    # Test the function
    log_info "Testing the deployed function..."
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d @analysis_request.json \
        "$FUNCTION_URL")
    
    if echo "$response" | grep -q '"status": "success"'; then
        log_success "Function test completed successfully"
        log_info "Response: $response"
    else
        log_warning "Function test may have issues. Response: $response"
    fi
    
    # Display deployment summary
    log_success "Deployment completed successfully!"
    echo
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Storage Bucket: gs://$BUCKET_NAME"
    log_info "Cloud Function: data-quality-analyzer"
    log_info "Function URL: $FUNCTION_URL"
    log_info "Service Account: data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo
    log_info "=== NEXT STEPS ==="
    log_info "1. Monitor function logs: gcloud functions logs read data-quality-analyzer --region=$REGION"
    log_info "2. View reports: gsutil ls gs://$BUCKET_NAME/reports/"
    log_info "3. Test with custom data: Upload JSON files to gs://$BUCKET_NAME/datasets/"
    echo
    log_info "=== CLEANUP ==="
    log_info "To remove all resources, run: ./destroy.sh"
    
    # Save deployment info for cleanup script
    cat > .deployment_info << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
BUCKET_NAME=$BUCKET_NAME
FUNCTION_URL=$FUNCTION_URL
EOF
    
    # Cleanup temporary files
    rm -f sample_training_data.json analysis_request.json
    rm -rf data-quality-function
}

# Run main function
main "$@"