#!/bin/bash

# =============================================================================
# Deploy Script for Smart Email Template Generation with Gemini and Firestore
# 
# This script deploys the complete infrastructure for an AI-powered email
# template generation system using Vertex AI Gemini, Firestore, and Cloud Functions.
#
# Services deployed:
# - Firestore Database (native mode)
# - Cloud Function (2nd gen)
# - Vertex AI Gemini integration
# - Sample data initialization
#
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Project with billing enabled
# - Required permissions for Cloud Functions, Firestore, and Vertex AI
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if user is authenticated with gcloud
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
}

# Function to check if billing is enabled for the project
check_billing() {
    local project_id=$1
    local billing_account
    billing_account=$(gcloud beta billing projects describe "$project_id" --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "$billing_account" ]]; then
        log_error "Billing is not enabled for project: $project_id"
        log_error "Please enable billing in the Google Cloud Console: https://console.cloud.google.com/billing"
        exit 1
    fi
    log_info "Billing is enabled for project: $project_id"
}

# Function to enable required APIs
enable_apis() {
    local project_id=$1
    log_info "Enabling required APIs for project: $project_id"
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "eventarc.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --project="$project_id"
    done
    
    log_success "All required APIs enabled"
    
    # Wait for API enablement to propagate
    log_info "Waiting for API enablement to propagate..."
    sleep 10
}

# Function to create Firestore database
create_firestore_database() {
    local database_id=$1
    local region=$2
    local project_id=$3
    
    log_info "Creating Firestore database: $database_id in region: $region"
    
    # Check if database already exists
    if gcloud firestore databases describe "$database_id" --project="$project_id" >/dev/null 2>&1; then
        log_warning "Firestore database $database_id already exists"
        return 0
    fi
    
    # Create Firestore database in native mode
    gcloud firestore databases create \
        --database="$database_id" \
        --location="$region" \
        --type=firestore-native \
        --project="$project_id"
    
    # Wait for database creation to complete
    log_info "Waiting for Firestore database creation to complete..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if gcloud firestore databases describe "$database_id" --project="$project_id" >/dev/null 2>&1; then
            log_success "Firestore database created successfully: $database_id"
            break
        fi
        log_info "Attempt $attempt/$max_attempts: Waiting for database creation..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Timeout waiting for Firestore database creation"
        exit 1
    fi
}

# Function to initialize sample data in Firestore
initialize_sample_data() {
    local database_id=$1
    local project_id=$2
    
    log_info "Initializing sample data in Firestore database: $database_id"
    
    # Create temporary Python script for data initialization
    cat > /tmp/init_firestore_data.py << 'EOF'
import os
import sys
from google.cloud import firestore

def main():
    try:
        # Initialize Firestore client with specific database
        project_id = os.environ.get('PROJECT_ID')
        database_id = os.environ.get('DATABASE_ID')
        
        if not project_id or not database_id:
            print("ERROR: PROJECT_ID and DATABASE_ID environment variables must be set")
            sys.exit(1)
            
        db = firestore.Client(project=project_id, database=database_id)
        
        # Sample user preferences
        user_prefs = {
            "company": "TechStart Solutions",
            "industry": "Software",
            "tone": "professional yet friendly",
            "primaryColor": "#2196F3",
            "targetAudience": "B2B technology decision makers",
            "brandVoice": "innovative, trustworthy, solution-focused"
        }
        
        # Sample campaign types
        campaign_types = {
            "newsletter": {
                "purpose": "weekly company updates and industry insights",
                "cta": "Read More",
                "length": "medium"
            },
            "product_launch": {
                "purpose": "introduce new features and capabilities",
                "cta": "Learn More",
                "length": "long"
            },
            "welcome": {
                "purpose": "onboard new subscribers",
                "cta": "Get Started",
                "length": "short"
            }
        }
        
        # Initialize default user preferences
        db.collection('userPreferences').document('default').set(user_prefs)
        print("✅ User preferences initialized")
        
        # Initialize campaign types
        for campaign_type, config in campaign_types.items():
            db.collection('campaignTypes').document(campaign_type).set(config)
        print("✅ Campaign types initialized")
        
        print("✅ Sample data initialized successfully in Firestore")
        
    except Exception as e:
        print(f"ERROR: Failed to initialize sample data: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    
    # Install required Python packages and run initialization
    if command_exists pip3; then
        pip3 install google-cloud-firestore --quiet --user
    else
        log_error "pip3 not found. Please install Python 3 and pip3"
        exit 1
    fi
    
    # Set environment variables and run initialization
    export PROJECT_ID="$project_id"
    export DATABASE_ID="$database_id"
    
    python3 /tmp/init_firestore_data.py
    
    # Clean up temporary file
    rm -f /tmp/init_firestore_data.py
    
    log_success "Sample data initialization completed"
}

# Function to create Cloud Function source code
create_function_source() {
    local function_dir=$1
    
    log_info "Creating Cloud Function source code in: $function_dir"
    
    # Create function directory
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create requirements.txt with current stable versions
    cat > requirements.txt << 'EOF'
google-cloud-firestore==2.16.0
google-cloud-aiplatform==1.70.0
functions-framework==3.8.1
google-auth==2.35.0
flask==3.0.3
vertexai==1.71.1
EOF
    
    # Create main function file
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Firestore client with specific database
database_id = os.environ.get('DATABASE_ID')
project_id = os.environ.get('PROJECT_ID', os.environ.get('GCP_PROJECT'))

if not database_id:
    logger.error("DATABASE_ID environment variable not set")
    raise ValueError("DATABASE_ID environment variable is required")

db = firestore.Client(project=project_id, database=database_id)

# Initialize Vertex AI
if project_id:
    vertexai.init(project=project_id, location="us-central1")
else:
    logger.error("PROJECT_ID not found in environment variables")
    raise ValueError("PROJECT_ID environment variable is required")

@functions_framework.http
def generate_email_template(request):
    """
    Generate personalized email templates using Gemini and Firestore.
    """
    # Set CORS headers for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)

    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {"error": "Invalid JSON request"}, 400, headers
        
        campaign_type = request_json.get('campaign_type', 'newsletter')
        subject_theme = request_json.get('subject_theme', 'company updates')
        custom_context = request_json.get('custom_context', '')
        
        logger.info(f"Processing template request: campaign_type={campaign_type}, subject_theme={subject_theme}")
        
        # Fetch user preferences from Firestore
        prefs_ref = db.collection('userPreferences').document('default')
        prefs_doc = prefs_ref.get()
        
        if not prefs_doc.exists:
            # Create default preferences if none exist
            default_prefs = {
                "company": "Your Company",
                "industry": "Technology",
                "tone": "professional yet friendly",
                "targetAudience": "business professionals",
                "brandVoice": "trustworthy and innovative"
            }
            prefs_ref.set(default_prefs)
            user_prefs = default_prefs
            logger.info("Created default user preferences")
        else:
            user_prefs = prefs_doc.to_dict()
        
        # Fetch campaign configuration
        campaign_ref = db.collection('campaignTypes').document(campaign_type)
        campaign_doc = campaign_ref.get()
        
        if not campaign_doc.exists:
            # Create default campaign type
            default_campaign = {
                "purpose": "general communication",
                "cta": "Learn More",
                "length": "medium"
            }
            campaign_ref.set(default_campaign)
            campaign_config = default_campaign
            logger.info(f"Created default campaign type: {campaign_type}")
        else:
            campaign_config = campaign_doc.to_dict()
        
        # Generate email template using Gemini
        template = generate_with_gemini(
            user_prefs, campaign_config, subject_theme, custom_context
        )
        
        # Store generated template in Firestore
        template_data = {
            "campaign_type": campaign_type,
            "subject_theme": subject_theme,
            "subject_line": template["subject"],
            "email_body": template["body"],
            "generated_at": firestore.SERVER_TIMESTAMP,
            "user_preferences": user_prefs
        }
        
        template_ref = db.collection('generatedTemplates').add(template_data)
        template_id = template_ref[1].id
        
        logger.info(f"Template generated and stored with ID: {template_id}")
        
        # Return successful response
        return {
            "success": True,
            "template_id": template_id,
            "template": template,
            "campaign_type": campaign_type
        }, 200, headers
        
    except Exception as e:
        logger.error(f"Error generating email template: {str(e)}")
        return {"error": f"Template generation failed: {str(e)}"}, 500, headers

def generate_with_gemini(user_prefs, campaign_config, subject_theme, custom_context):
    """
    Use Vertex AI Gemini to generate email content.
    """
    try:
        # Initialize Gemini model
        model = GenerativeModel("gemini-1.5-flash")
        
        # Construct detailed prompt for email generation
        prompt = f"""
You are an expert email marketing copywriter. Generate a professional email template with the following specifications:

Company Information:
- Company: {user_prefs.get('company', 'Your Company')}
- Industry: {user_prefs.get('industry', 'Technology')}
- Brand Voice: {user_prefs.get('brandVoice', 'professional')}
- Target Audience: {user_prefs.get('targetAudience', 'professionals')}

Email Configuration:
- Campaign Type: {campaign_config.get('purpose', 'general communication')}
- Tone: {user_prefs.get('tone', 'professional')}
- Call-to-Action: {campaign_config.get('cta', 'Learn More')}
- Length: {campaign_config.get('length', 'medium')}
- Subject Theme: {subject_theme}

Additional Context: {custom_context}

Please generate:
1. A compelling subject line (under 60 characters)
2. Email body with proper structure (greeting, body paragraphs, call-to-action, closing)
3. Maintain the specified tone and brand voice
4. Include placeholders for personalization like [First Name], [Company Name]

Format the response as JSON with "subject" and "body" fields only.
"""
        
        # Generate content with Gemini
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.7,
                "top_p": 0.8,
                "top_k": 40,
                "max_output_tokens": 1024,
            }
        )
        
        try:
            # Parse JSON response from Gemini
            content = response.text.strip()
            if content.startswith('```json'):
                content = content[7:-3]
            elif content.startswith('```'):
                content = content[3:-3]
            
            template_data = json.loads(content)
            
            # Validate required fields
            if "subject" not in template_data or "body" not in template_data:
                raise ValueError("Missing required fields in generated template")
            
            return template_data
            
        except json.JSONDecodeError:
            # Fallback: parse unstructured response
            subject_line = f"Exciting Updates from {user_prefs.get('company', 'Your Company')}"
            body_content = response.text
            
            return {
                "subject": subject_line,
                "body": body_content
            }
    
    except Exception as e:
        logger.error(f"Gemini generation error: {str(e)}")
        # Fallback template
        return {
            "subject": f"Updates from {user_prefs.get('company', 'Your Company')}",
            "body": f"Hello [First Name],\n\nWe hope this email finds you well. We wanted to share some exciting updates about {subject_theme}.\n\n[Email content will be generated here]\n\nBest regards,\nThe {user_prefs.get('company', 'Your Company')} Team"
        }
EOF
    
    log_success "Cloud Function source code created"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    local function_name=$1
    local region=$2
    local project_id=$3
    local database_id=$4
    local function_dir=$5
    
    log_info "Deploying Cloud Function: $function_name"
    
    cd "$function_dir"
    
    # Deploy Cloud Function with optimized settings
    gcloud functions deploy "$function_name" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_email_template \
        --memory 512Mi \
        --timeout 120s \
        --max-instances 10 \
        --region="$region" \
        --project="$project_id" \
        --set-env-vars "PROJECT_ID=$project_id,DATABASE_ID=$database_id"
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$function_name" \
        --gen2 \
        --region="$region" \
        --project="$project_id" \
        --format="value(serviceConfig.uri)")
    
    log_success "Cloud Function deployed successfully"
    log_success "Function URL: $function_url"
    
    # Store function URL in a file for later use
    echo "$function_url" > /tmp/function_url.txt
    
    return 0
}

# Function to test the deployed function
test_deployment() {
    local function_url=$1
    
    log_info "Testing deployed function..."
    
    # Test with a simple request
    local test_response
    test_response=$(curl -s -X POST "$function_url" \
        -H "Content-Type: application/json" \
        -d '{
            "campaign_type": "newsletter",
            "subject_theme": "deployment test",
            "custom_context": "testing the deployed email template generator"
        }')
    
    if echo "$test_response" | grep -q '"success":true'; then
        log_success "Function test completed successfully"
        log_info "Sample response: $(echo "$test_response" | head -c 200)..."
    else
        log_warning "Function test returned unexpected response: $test_response"
    fi
}

# Function to display deployment summary
display_summary() {
    local project_id=$1
    local region=$2
    local function_name=$3
    local database_id=$4
    local function_url=$5
    
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Project ID: $project_id"
    log_info "Region: $region"
    log_info "Function Name: $function_name"
    log_info "Database ID: $database_id"
    log_info "Function URL: $function_url"
    echo
    log_info "You can test the function with:"
    echo "curl -X POST '$function_url' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"campaign_type\": \"newsletter\", \"subject_theme\": \"test\"}'"
    echo
    log_warning "Remember to run the destroy script when you're done to avoid charges!"
}

# Main deployment function
main() {
    log_info "Starting deployment of Smart Email Template Generation system..."
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) not found. Please install it first."
        log_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    if ! command_exists python3; then
        log_error "Python 3 not found. Please install Python 3."
        exit 1
    fi
    
    if ! command_exists curl; then
        log_error "curl not found. Please install curl."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Set configuration variables
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "${timestamp: -6}")
    
    # Use provided PROJECT_ID or create a new one
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="email-gen-${timestamp}"
        log_info "No PROJECT_ID provided, using: $PROJECT_ID"
        log_warning "Make sure to create this project in Google Cloud Console and enable billing"
    fi
    
    local REGION="${REGION:-us-central1}"
    local ZONE="${ZONE:-us-central1-a}"
    local FUNCTION_NAME="email-template-generator-${random_suffix}"
    local DATABASE_ID="email-templates-${random_suffix}"
    local FUNCTION_DIR="./email-template-function"
    
    log_info "Configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Database ID: $DATABASE_ID"
    
    # Set gcloud configuration
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Check billing
    check_billing "$PROJECT_ID"
    
    # Enable required APIs
    enable_apis "$PROJECT_ID"
    
    # Create Firestore database
    create_firestore_database "$DATABASE_ID" "$REGION" "$PROJECT_ID"
    
    # Initialize sample data
    initialize_sample_data "$DATABASE_ID" "$PROJECT_ID"
    
    # Create function source code
    create_function_source "$FUNCTION_DIR"
    
    # Deploy Cloud Function
    deploy_cloud_function "$FUNCTION_NAME" "$REGION" "$PROJECT_ID" "$DATABASE_ID" "$FUNCTION_DIR"
    
    # Get function URL
    local function_url
    if [[ -f /tmp/function_url.txt ]]; then
        function_url=$(cat /tmp/function_url.txt)
        rm -f /tmp/function_url.txt
    else
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format="value(serviceConfig.uri)")
    fi
    
    # Test deployment
    test_deployment "$function_url"
    
    # Save deployment info for cleanup script
    cat > .deployment_info << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
FUNCTION_NAME=$FUNCTION_NAME
DATABASE_ID=$DATABASE_ID
FUNCTION_URL=$function_url
FUNCTION_DIR=$FUNCTION_DIR
EOF
    
    # Display summary
    display_summary "$PROJECT_ID" "$REGION" "$FUNCTION_NAME" "$DATABASE_ID" "$function_url"
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"