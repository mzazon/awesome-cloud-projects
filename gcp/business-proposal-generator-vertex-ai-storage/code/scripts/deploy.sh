#!/bin/bash

# Business Proposal Generator Deployment Script
# This script deploys the complete business proposal generator solution
# using Vertex AI, Cloud Functions, and Cloud Storage on Google Cloud Platform

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate GCP CLI and authentication
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure it's installed with gcloud."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if current project is set
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        log_error "No GCP project is set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log_success "Prerequisites validated successfully"
    log "Current project: $project_id"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_success "All required APIs enabled successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get current project ID
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffix
    export TEMPLATES_BUCKET="${PROJECT_ID}-templates-${random_suffix}"
    export CLIENT_DATA_BUCKET="${PROJECT_ID}-client-data-${random_suffix}"
    export OUTPUT_BUCKET="${PROJECT_ID}-generated-proposals-${random_suffix}"
    export FUNCTION_NAME="proposal-generator-${random_suffix}"
    
    # Create temporary environment file for cleanup script
    cat > .env.deployment << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
TEMPLATES_BUCKET=${TEMPLATES_BUCKET}
CLIENT_DATA_BUCKET=${CLIENT_DATA_BUCKET}
OUTPUT_BUCKET=${OUTPUT_BUCKET}
FUNCTION_NAME=${FUNCTION_NAME}
DEPLOYMENT_TIMESTAMP=$(date +%s)
EOF
    
    log_success "Environment variables configured"
    log "Project: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Function: ${FUNCTION_NAME}"
    log "Templates bucket: ${TEMPLATES_BUCKET}"
    log "Client data bucket: ${CLIENT_DATA_BUCKET}"
    log "Output bucket: ${OUTPUT_BUCKET}"
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    local buckets=("$TEMPLATES_BUCKET" "$CLIENT_DATA_BUCKET" "$OUTPUT_BUCKET")
    
    for bucket in "${buckets[@]}"; do
        log "Creating bucket: $bucket"
        
        if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$bucket" 2>/dev/null; then
            log_success "Created bucket: $bucket"
        else
            if gsutil ls "gs://$bucket" >/dev/null 2>&1; then
                log_warning "Bucket $bucket already exists"
            else
                log_error "Failed to create bucket: $bucket"
                exit 1
            fi
        fi
        
        # Enable uniform bucket-level access for better security
        gsutil uniformbucketlevelaccess set on "gs://$bucket" >/dev/null 2>&1 || true
    done
    
    log_success "All storage buckets created successfully"
}

# Function to upload sample proposal template
upload_sample_template() {
    log "Creating and uploading sample proposal template..."
    
    local template_file="proposal-template.txt"
    
    cat > "$template_file" << 'EOF'
BUSINESS PROPOSAL TEMPLATE

Dear {{CLIENT_NAME}},

Thank you for considering our services for {{PROJECT_TYPE}}. Based on our understanding of your requirements, we propose the following solution:

PROJECT OVERVIEW:
{{PROJECT_OVERVIEW}}

SOLUTION APPROACH:
{{SOLUTION_APPROACH}}

TIMELINE:
{{TIMELINE}}

INVESTMENT:
{{INVESTMENT}}

NEXT STEPS:
{{NEXT_STEPS}}

We look forward to partnering with you to achieve your business objectives.

Best regards,
Business Development Team
EOF
    
    if gsutil cp "$template_file" "gs://$TEMPLATES_BUCKET/"; then
        log_success "Uploaded proposal template to $TEMPLATES_BUCKET"
        rm -f "$template_file"
    else
        log_error "Failed to upload proposal template"
        exit 1
    fi
}

# Function to create sample client data
create_sample_client_data() {
    log "Creating sample client data file..."
    
    local client_data_file="client-data.json"
    
    cat > "$client_data_file" << 'EOF'
{
  "client_name": "TechCorp Solutions",
  "industry": "Financial Services",
  "project_type": "Digital Transformation Initiative",
  "requirements": [
    "Modernize legacy banking systems",
    "Implement cloud-native architecture",
    "Enhance mobile banking experience",
    "Ensure regulatory compliance"
  ],
  "timeline": "6-month implementation",
  "budget_range": "$500K - $1M",
  "key_stakeholders": [
    "CTO - Technology Strategy",
    "Head of Digital - User Experience",
    "Compliance Officer - Regulatory Requirements"
  ],
  "success_metrics": [
    "50% reduction in system response time",
    "90% customer satisfaction score",
    "100% regulatory compliance"
  ],
  "deployment_preferences": [
    "Cloud-first approach",
    "Phased rollout strategy",
    "Minimal operational disruption"
  ]
}
EOF
    
    log_success "Sample client data file created: $client_data_file"
    echo "$client_data_file"
}

# Function to prepare Cloud Function source code
prepare_function_source() {
    log "Preparing Cloud Function source code..."
    
    local function_dir="proposal-function"
    mkdir -p "$function_dir"
    
    # Create package.json
    cat > "$function_dir/package.json" << 'EOF'
{
  "name": "proposal-generator",
  "version": "1.0.0",
  "description": "AI-powered business proposal generator",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/vertexai": "^1.0.0",
    "@google-cloud/storage": "^7.0.0",
    "@google-cloud/functions-framework": "^3.0.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create main function implementation
    cat > "$function_dir/index.js" << 'EOF'
const { Storage } = require('@google-cloud/storage');
const { VertexAI } = require('@google-cloud/vertexai');
const functions = require('@google-cloud/functions-framework');

const storage = new Storage();

functions.cloudEvent('generateProposal', async (cloudEvent) => {
  try {
    console.log('Proposal generation triggered by:', cloudEvent.data.name);
    
    const bucketName = cloudEvent.data.bucket;
    const fileName = cloudEvent.data.name;
    
    // Skip if not a client data file
    if (!fileName.endsWith('.json')) {
      console.log('Skipping non-JSON file:', fileName);
      return;
    }
    
    // Download client data
    console.log('Downloading client data from:', bucketName, fileName);
    const clientDataFile = storage.bucket(bucketName).file(fileName);
    const [clientDataContent] = await clientDataFile.download();
    const clientData = JSON.parse(clientDataContent.toString());
    
    // Download proposal template
    const templateBucket = process.env.TEMPLATES_BUCKET;
    const templateFile = storage.bucket(templateBucket).file('proposal-template.txt');
    const [templateContent] = await templateFile.download();
    const template = templateContent.toString();
    
    // Initialize Vertex AI
    const projectId = process.env.GOOGLE_CLOUD_PROJECT;
    const location = process.env.REGION || 'us-central1';
    
    const vertexAI = new VertexAI({
      project: projectId,
      location: location
    });
    
    const generativeModel = vertexAI.getGenerativeModel({
      model: 'gemini-1.5-flash',
      generationConfig: {
        maxOutputTokens: 2048,
        temperature: 0.3,
        topP: 0.8,
        topK: 40
      }
    });
    
    // Generate proposal using Vertex AI
    const prompt = `You are a professional business proposal writer. Based on the following client data, 
    generate specific content for each section of the proposal template.
    
    Client Data:
    ${JSON.stringify(clientData, null, 2)}
    
    Template:
    ${template}
    
    Please provide specific, professional content for each placeholder ({{...}}) in the template.
    Make the content relevant to the client's industry, requirements, and objectives.
    Ensure the tone is professional and persuasive.
    Return the complete proposal with all placeholders filled in.
    
    Guidelines:
    - PROJECT_OVERVIEW: Summarize the client's challenge and our understanding
    - SOLUTION_APPROACH: Detail our technical and strategic approach
    - TIMELINE: Provide realistic milestones based on their timeline preference
    - INVESTMENT: Reference their budget range and provide value justification
    - NEXT_STEPS: Outline concrete steps for moving forward`;
    
    const request = {
      contents: [{
        role: 'user',
        parts: [{ text: prompt }]
      }]
    };
    
    console.log('Generating proposal content with Vertex AI...');
    const result = await generativeModel.generateContent(request);
    const response = result.response;
    const generatedContent = response.candidates[0].content.parts[0].text;
    
    // Save generated proposal
    const outputBucket = process.env.OUTPUT_BUCKET;
    const outputFileName = `proposal-${clientData.client_name.replace(/\s+/g, '-').toLowerCase()}-${Date.now()}.txt`;
    
    await storage.bucket(outputBucket).file(outputFileName).save(generatedContent);
    
    console.log(`✅ Generated proposal saved as: ${outputFileName}`);
    console.log('Proposal generation completed successfully');
    
  } catch (error) {
    console.error('Error generating proposal:', error);
    throw error;
  }
});
EOF
    
    log_success "Cloud Function source code prepared in $function_dir/"
    echo "$function_dir"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function..."
    
    local function_dir="$1"
    
    # Deploy function with Cloud Storage trigger
    log "Deploying function: $FUNCTION_NAME"
    if gcloud functions deploy "$FUNCTION_NAME" \
        --runtime nodejs20 \
        --trigger-bucket "$CLIENT_DATA_BUCKET" \
        --source "$function_dir" \
        --entry-point generateProposal \
        --memory 512MB \
        --timeout 540s \
        --set-env-vars "TEMPLATES_BUCKET=$TEMPLATES_BUCKET,OUTPUT_BUCKET=$OUTPUT_BUCKET,REGION=$REGION" \
        --region "$REGION" \
        --quiet; then
        
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Wait for function to be ready
    log "Waiting for function to be ready..."
    sleep 30
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    local client_data_file="$1"
    
    # Upload client data to trigger the function
    log "Uploading client data to trigger proposal generation..."
    if gsutil cp "$client_data_file" "gs://$CLIENT_DATA_BUCKET/"; then
        log_success "Client data uploaded successfully"
    else
        log_error "Failed to upload client data"
        exit 1
    fi
    
    # Wait for function execution
    log "Waiting for proposal generation (this may take up to 2 minutes)..."
    sleep 45
    
    # Check function logs
    log "Checking function execution logs..."
    gcloud functions logs read "$FUNCTION_NAME" --limit 10 --region "$REGION" || true
    
    # Check if proposal was generated
    log "Checking for generated proposals..."
    local proposal_count
    proposal_count=$(gsutil ls "gs://$OUTPUT_BUCKET/" 2>/dev/null | wc -l || echo "0")
    
    if [[ $proposal_count -gt 0 ]]; then
        log_success "Proposal generation test completed successfully!"
        log "Generated proposals:"
        gsutil ls "gs://$OUTPUT_BUCKET/" | sed 's|gs://[^/]*/||' | while read -r file; do
            log "  - $file"
        done
    else
        log_warning "No proposals were generated yet. This might be normal if the function is still processing."
        log "You can check the status later with:"
        log "  gsutil ls gs://$OUTPUT_BUCKET/"
        log "  gcloud functions logs read $FUNCTION_NAME --region $REGION"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Business Proposal Generator deployment completed!"
    echo
    echo "==============================================="
    echo "DEPLOYMENT SUMMARY"
    echo "==============================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo
    echo "📦 Storage Buckets:"
    echo "  • Templates: gs://$TEMPLATES_BUCKET"
    echo "  • Client Data: gs://$CLIENT_DATA_BUCKET"
    echo "  • Generated Proposals: gs://$OUTPUT_BUCKET"
    echo
    echo "🔧 How to use:"
    echo "1. Upload client data JSON files to: gs://$CLIENT_DATA_BUCKET"
    echo "2. Generated proposals will appear in: gs://$OUTPUT_BUCKET"
    echo "3. Monitor function logs with:"
    echo "   gcloud functions logs read $FUNCTION_NAME --region $REGION"
    echo
    echo "📝 Sample commands:"
    echo "  # Upload client data:"
    echo "  gsutil cp your-client-data.json gs://$CLIENT_DATA_BUCKET/"
    echo
    echo "  # Download generated proposal:"
    echo "  gsutil cp gs://$OUTPUT_BUCKET/proposal-*.txt ."
    echo
    echo "  # View function status:"
    echo "  gcloud functions describe $FUNCTION_NAME --region $REGION"
    echo
    echo "💰 Estimated costs: \$5-15/month for moderate usage"
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo "==============================================="
}

# Main deployment function
main() {
    log "🚀 Starting Business Proposal Generator deployment..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Set up environment
    setup_environment
    
    # Enable required APIs
    enable_apis
    
    # Create storage buckets
    create_storage_buckets
    
    # Upload sample template
    upload_sample_template
    
    # Create sample client data
    local client_data_file
    client_data_file=$(create_sample_client_data)
    
    # Prepare function source
    local function_dir
    function_dir=$(prepare_function_source)
    
    # Deploy Cloud Function
    deploy_cloud_function "$function_dir"
    
    # Test the deployment
    test_deployment "$client_data_file"
    
    # Clean up temporary files
    rm -rf "$function_dir" "$client_data_file"
    
    # Display summary
    display_summary
}

# Error handling
trap 'log_error "Deployment failed. Check the logs above for details."; exit 1' ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi