#!/bin/bash

# Deploy script for Code Review and Documentation Workflows with Google Workspace APIs and Cloud Run
# This script deploys the complete infrastructure for automated code review workflows

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Cleanup Cloud Run services if they exist
    if [ ! -z "${SERVICE_NAME:-}" ]; then
        gcloud run services delete "${SERVICE_NAME}" --region "${REGION}" --quiet 2>/dev/null || true
        gcloud run services delete "docs-service-${RANDOM_SUFFIX}" --region "${REGION}" --quiet 2>/dev/null || true
        gcloud run services delete "notification-service-${RANDOM_SUFFIX}" --region "${REGION}" --quiet 2>/dev/null || true
    fi
    
    # Cleanup Pub/Sub resources if they exist
    if [ ! -z "${TOPIC_NAME:-}" ]; then
        gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet 2>/dev/null || true
        gcloud pubsub topics delete "${TOPIC_NAME}" --quiet 2>/dev/null || true
    fi
    
    # Cleanup storage bucket if it exists
    if [ ! -z "${BUCKET_NAME:-}" ]; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
    
    log_warning "Partial cleanup completed"
}

# Trap errors and call cleanup
trap cleanup_on_error ERR

# Display banner
echo -e "${BLUE}"
echo "=================================================="
echo "  Code Review Workflow Deployment Script"
echo "  GCP Recipe: workspace-apis-cloud-run"
echo "=================================================="
echo -e "${NC}"

# Prerequisites validation
log_info "Validating prerequisites..."

# Check required tools
if ! command_exists gcloud; then
    error_exit "Google Cloud CLI (gcloud) is not installed or not in PATH"
fi

if ! command_exists gsutil; then
    error_exit "Google Cloud Storage utility (gsutil) is not installed or not in PATH"
fi

if ! command_exists curl; then
    error_exit "curl is not installed or not in PATH"
fi

if ! command_exists openssl; then
    error_exit "openssl is not installed or not in PATH"
fi

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
fi

log_success "Prerequisites validation completed"

# Configuration
log_info "Setting up configuration..."

# Set environment variables with defaults
PROJECT_ID="${PROJECT_ID:-code-review-automation-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
SERVICE_NAME="code-review-${RANDOM_SUFFIX}"
TOPIC_NAME="code-events-${RANDOM_SUFFIX}"
SUBSCRIPTION_NAME="code-processing-${RANDOM_SUFFIX}"
BUCKET_NAME="code-artifacts-${RANDOM_SUFFIX}"

# Display configuration
log_info "Deployment Configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Random Suffix: ${RANDOM_SUFFIX}"
echo "  Service Name: ${SERVICE_NAME}"
echo "  Topic Name: ${TOPIC_NAME}"
echo "  Bucket Name: ${BUCKET_NAME}"

# Confirmation prompt
if [ "${DEPLOY_CONFIRM:-}" != "yes" ]; then
    echo
    read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
fi

# Set gcloud defaults
log_info "Configuring gcloud defaults..."
gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"

# Enable APIs
log_info "Enabling required Google Cloud APIs..."
REQUIRED_APIS=(
    "run.googleapis.com"
    "pubsub.googleapis.com"
    "cloudscheduler.googleapis.com"
    "secretmanager.googleapis.com"
    "storage.googleapis.com"
    "monitoring.googleapis.com"
    "gmail.googleapis.com"
    "docs.googleapis.com"
    "drive.googleapis.com"
    "admin.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    log_info "Enabling ${api}..."
    gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
done

log_success "All required APIs enabled"

# Create Pub/Sub resources
log_info "Creating Pub/Sub topic and subscription..."
gcloud pubsub topics create "${TOPIC_NAME}" || error_exit "Failed to create Pub/Sub topic"

gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
    --topic "${TOPIC_NAME}" \
    --ack-deadline 600 \
    --message-retention-duration 7d || error_exit "Failed to create Pub/Sub subscription"

log_success "Pub/Sub resources created successfully"

# Create Cloud Storage bucket
log_info "Creating Cloud Storage bucket..."
gsutil mb -p "${PROJECT_ID}" \
    -c STANDARD \
    -l "${REGION}" \
    "gs://${BUCKET_NAME}" || error_exit "Failed to create storage bucket"

# Set lifecycle policy
log_info "Configuring bucket lifecycle policy..."
cat > lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
EOF

gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}" || error_exit "Failed to set lifecycle policy"
rm -f lifecycle.json

log_success "Cloud Storage bucket configured with lifecycle policy"

# Create service account and configure Google Workspace access
log_info "Creating service account for Google Workspace APIs..."
gcloud iam service-accounts create workspace-automation \
    --display-name "Workspace Automation Service Account" \
    --description "Service account for automated code review workflows" || error_exit "Failed to create service account"

log_info "Generating service account key..."
gcloud iam service-accounts keys create workspace-key.json \
    --iam-account "workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" || error_exit "Failed to generate service account key"

log_info "Storing service account key in Secret Manager..."
gcloud secrets create workspace-credentials \
    --data-file workspace-key.json || error_exit "Failed to create secret"

# Grant IAM roles
log_info "Granting necessary IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/secretmanager.secretAccessor" || error_exit "Failed to grant Secret Manager access"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/storage.objectAdmin" || error_exit "Failed to grant Storage access"

rm -f workspace-key.json
log_success "Service account configured for Workspace APIs"

# Deploy Cloud Run services
log_info "Deploying Cloud Run services..."

# Create temporary directories for service code
mkdir -p code-review-service docs-service notification-service

# Deploy Code Review Service
log_info "Deploying Code Review Analysis Service..."
cd code-review-service

# Create main application file for code review service
cat > main.py << 'EOF'
import os
import json
import logging
from flask import Flask, request, jsonify
from google.cloud import secretmanager
from google.cloud import storage
from google.cloud import pubsub_v1
from googleapiclient.discovery import build
from google.oauth2 import service_account
import requests
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Google Cloud clients
secret_client = secretmanager.SecretManagerServiceClient()
storage_client = storage.Client()
publisher = pubsub_v1.PublisherClient()

def get_workspace_credentials():
    """Retrieve Google Workspace credentials from Secret Manager"""
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    secret_name = f"projects/{project_id}/secrets/workspace-credentials/versions/latest"
    response = secret_client.access_secret_version(request={"name": secret_name})
    credentials_info = json.loads(response.payload.data.decode('UTF-8'))
    credentials = service_account.Credentials.from_service_account_info(
        credentials_info,
        scopes=['https://www.googleapis.com/auth/documents',
                'https://www.googleapis.com/auth/drive',
                'https://www.googleapis.com/auth/gmail.send']
    )
    return credentials

def analyze_code_changes(payload):
    """Analyze code changes and generate review summary"""
    changes = payload.get('commits', [])
    analysis = {
        'total_commits': len(changes),
        'files_changed': set(),
        'lines_added': 0,
        'lines_removed': 0,
        'review_summary': [],
        'quality_metrics': {}
    }
    
    for commit in changes:
        if 'added' in commit:
            analysis['files_changed'].update(commit['added'])
            analysis['lines_added'] += len(commit.get('added', []))
        if 'removed' in commit:
            analysis['files_changed'].update(commit['removed'])
            analysis['lines_removed'] += len(commit.get('removed', []))
    
    analysis['files_changed'] = list(analysis['files_changed'])
    
    # Generate quality metrics
    analysis['quality_metrics'] = {
        'complexity_score': min(len(analysis['files_changed']) * 2, 100),
        'test_coverage_impact': 'Medium' if analysis['lines_added'] > 50 else 'Low',
        'documentation_needed': len(analysis['files_changed']) > 5
    }
    
    return analysis

def create_review_document(analysis, project_name):
    """Create Google Doc with code review summary"""
    try:
        credentials = get_workspace_credentials()
        docs_service = build('docs', 'v1', credentials=credentials)
        
        # Create new document
        doc = docs_service.documents().create(body={
            'title': f'Code Review Summary - {project_name} - {datetime.now().strftime("%Y-%m-%d")}'
        }).execute()
        
        doc_id = doc['documentId']
        
        # Add content to document
        content = f"""
# Code Review Summary

**Project:** {project_name}
**Date:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
**Total Commits:** {analysis['total_commits']}
**Files Changed:** {len(analysis['files_changed'])}
**Lines Added:** {analysis['lines_added']}
**Lines Removed:** {analysis['lines_removed']}

## Quality Metrics
**Complexity Score:** {analysis['quality_metrics']['complexity_score']}/100
**Test Coverage Impact:** {analysis['quality_metrics']['test_coverage_impact']}
**Documentation Update Needed:** {'Yes' if analysis['quality_metrics']['documentation_needed'] else 'No'}

## Files Modified
{chr(10).join(f"- {file}" for file in analysis['files_changed'][:10])}

## Recommendations
- Review test coverage for modified components
- Update technical documentation if architectural changes were made
- Consider code review checklist for complex changes
"""
        
        # Insert content into document
        requests_body = [
            {
                'insertText': {
                    'location': {'index': 1},
                    'text': content
                }
            }
        ]
        
        docs_service.documents().batchUpdate(
            documentId=doc_id,
            body={'requests': requests_body}
        ).execute()
        
        return doc_id
        
    except Exception as e:
        logging.error(f"Error creating review document: {str(e)}")
        return None

@app.route('/webhook', methods=['POST'])
def handle_webhook():
    """Process code repository webhook events"""
    try:
        payload = request.get_json()
        
        if not payload:
            return jsonify({'error': 'No payload received'}), 400
        
        # Analyze code changes
        analysis = analyze_code_changes(payload)
        
        # Create review document
        project_name = payload.get('repository', {}).get('name', 'Unknown Project')
        doc_id = create_review_document(analysis, project_name)
        
        # Store analysis results
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(f"reviews/{datetime.now().strftime('%Y/%m/%d')}/{project_name}-analysis.json")
            blob.upload_from_string(json.dumps(analysis, indent=2))
        
        # Publish event for notification service
        topic_name = os.environ.get('TOPIC_NAME')
        if topic_name and doc_id:
            topic_path = publisher.topic_path(os.environ.get('GOOGLE_CLOUD_PROJECT'), topic_name)
            notification_data = {
                'type': 'review_completed',
                'project': project_name,
                'doc_id': doc_id,
                'analysis': analysis
            }
            publisher.publish(topic_path, json.dumps(notification_data).encode('utf-8'))
        
        return jsonify({
            'status': 'success',
            'doc_id': doc_id,
            'analysis_summary': analysis
        })
        
    except Exception as e:
        logging.error(f"Error processing webhook: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

# Create requirements file
cat > requirements.txt << 'EOF'
flask==2.3.3
google-cloud-secret-manager==2.16.4
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.1
google-api-python-client==2.95.0
google-auth==2.22.0
google-auth-oauthlib==1.0.0
google-auth-httplib2==0.1.0
requests==2.31.0
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080
CMD ["python", "main.py"]
EOF

# Deploy Code Review Service
gcloud run deploy "${SERVICE_NAME}" \
    --source . \
    --platform managed \
    --region "${REGION}" \
    --allow-unauthenticated \
    --set-env-vars "BUCKET_NAME=${BUCKET_NAME},TOPIC_NAME=${TOPIC_NAME}" \
    --memory 1Gi \
    --cpu 1 \
    --timeout 300 \
    --max-instances 10 || error_exit "Failed to deploy code review service"

cd ..

# Deploy Documentation Service
log_info "Deploying Documentation Service..."
cd docs-service

# Create documentation service application
cat > main.py << 'EOF'
import os
import json
import logging
from flask import Flask, request, jsonify
from google.cloud import pubsub_v1
from google.cloud import secretmanager
from google.cloud import storage
from googleapiclient.discovery import build
from google.oauth2 import service_account
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize clients
secret_client = secretmanager.SecretManagerServiceClient()
storage_client = storage.Client()
subscriber = pubsub_v1.SubscriberClient()

def get_workspace_credentials():
    """Get Google Workspace API credentials"""
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    secret_name = f"projects/{project_id}/secrets/workspace-credentials/versions/latest"
    response = secret_client.access_secret_version(request={"name": secret_name})
    credentials_info = json.loads(response.payload.data.decode('UTF-8'))
    credentials = service_account.Credentials.from_service_account_info(
        credentials_info,
        scopes=['https://www.googleapis.com/auth/documents',
                'https://www.googleapis.com/auth/drive']
    )
    return credentials

def find_project_documentation(project_name):
    """Find existing project documentation in Google Drive"""
    try:
        credentials = get_workspace_credentials()
        drive_service = build('drive', 'v3', credentials=credentials)
        
        # Search for existing documentation
        query = f"name contains '{project_name}' and mimeType='application/vnd.google-apps.document'"
        results = drive_service.files().list(q=query, pageSize=10).execute()
        files = results.get('files', [])
        
        if files:
            return files[0]['id']
        else:
            # Create new documentation
            docs_service = build('docs', 'v1', credentials=credentials)
            doc = docs_service.documents().create(body={
                'title': f'{project_name} - Technical Documentation'
            }).execute()
            return doc['documentId']
            
    except Exception as e:
        logging.error(f"Error finding documentation: {str(e)}")
        return None

def update_documentation(doc_id, analysis_data):
    """Update project documentation with latest changes"""
    try:
        credentials = get_workspace_credentials()
        docs_service = build('docs', 'v1', credentials=credentials)
        
        # Get current document content
        doc = docs_service.documents().get(documentId=doc_id).execute()
        doc_content = doc.get('body', {}).get('content', [])
        
        # Find insertion point or append
        insertion_index = 1
        for element in doc_content:
            if 'paragraph' in element:
                insertion_index = element['endIndex']
        
        # Create update content
        update_content = f"""

## Latest Changes - {datetime.now().strftime("%Y-%m-%d")}

**Files Modified:** {len(analysis_data.get('files_changed', []))}
**Complexity Score:** {analysis_data.get('quality_metrics', {}).get('complexity_score', 'N/A')}
**Documentation Review Required:** {'Yes' if analysis_data.get('quality_metrics', {}).get('documentation_needed', False) else 'No'}

### Recent File Changes:
{chr(10).join(f"- {file}" for file in analysis_data.get('files_changed', [])[:5])}

"""
        
        # Update document
        requests_body = [
            {
                'insertText': {
                    'location': {'index': insertion_index},
                    'text': update_content
                }
            }
        ]
        
        docs_service.documents().batchUpdate(
            documentId=doc_id,
            body={'requests': requests_body}
        ).execute()
        
        return True
        
    except Exception as e:
        logging.error(f"Error updating documentation: {str(e)}")
        return False

@app.route('/update-docs', methods=['POST'])
def handle_documentation_update():
    """Handle documentation update requests"""
    try:
        data = request.get_json()
        project_name = data.get('project', 'Unknown')
        analysis_data = data.get('analysis', {})
        
        # Find or create documentation
        doc_id = find_project_documentation(project_name)
        
        if doc_id:
            success = update_documentation(doc_id, analysis_data)
            if success:
                return jsonify({
                    'status': 'success',
                    'doc_id': doc_id,
                    'message': 'Documentation updated successfully'
                })
        
        return jsonify({'error': 'Failed to update documentation'}), 500
        
    except Exception as e:
        logging.error(f"Error handling documentation update: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

# Copy requirements and Dockerfile
cp ../code-review-service/requirements.txt .
cp ../code-review-service/Dockerfile .

# Deploy documentation service
gcloud run deploy "docs-service-${RANDOM_SUFFIX}" \
    --source . \
    --platform managed \
    --region "${REGION}" \
    --allow-unauthenticated \
    --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
    --memory 512Mi \
    --cpu 1 \
    --timeout 300 \
    --max-instances 5 || error_exit "Failed to deploy documentation service"

cd ..

# Deploy Notification Service
log_info "Deploying Notification Service..."
cd notification-service

# Create notification service application
cat > main.py << 'EOF'
import os
import json
import logging
from flask import Flask, request, jsonify
from google.cloud import secretmanager
from google.cloud import pubsub_v1
from googleapiclient.discovery import build
from google.oauth2 import service_account
import base64
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize clients
secret_client = secretmanager.SecretManagerServiceClient()
subscriber = pubsub_v1.SubscriberClient()

def get_workspace_credentials():
    """Get Google Workspace API credentials"""
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    secret_name = f"projects/{project_id}/secrets/workspace-credentials/versions/latest"
    response = secret_client.access_secret_version(request={"name": secret_name})
    credentials_info = json.loads(response.payload.data.decode('UTF-8'))
    credentials = service_account.Credentials.from_service_account_info(
        credentials_info,
        scopes=['https://www.googleapis.com/auth/gmail.send']
    )
    return credentials

def create_email_message(to, subject, body_text, body_html=None):
    """Create email message"""
    message = MIMEMultipart('alternative')
    message['to'] = to
    message['subject'] = subject
    
    # Add text part
    text_part = MIMEText(body_text, 'plain')
    message.attach(text_part)
    
    # Add HTML part if provided
    if body_html:
        html_part = MIMEText(body_html, 'html')
        message.attach(html_part)
    
    return {'raw': base64.urlsafe_b64encode(message.as_bytes()).decode()}

def send_notification_email(recipients, project_name, doc_id, analysis):
    """Send notification email to team members"""
    try:
        credentials = get_workspace_credentials()
        gmail_service = build('gmail', 'v1', credentials=credentials)
        
        subject = f"Code Review Complete: {project_name}"
        
        # Create email content
        text_body = f"""
Code Review Summary for {project_name}

A new code review has been completed and documentation has been updated.

Summary:
- Total Commits: {analysis.get('total_commits', 0)}
- Files Changed: {len(analysis.get('files_changed', []))}
- Complexity Score: {analysis.get('quality_metrics', {}).get('complexity_score', 'N/A')}/100

View the complete review document: https://docs.google.com/document/d/{doc_id}

This is an automated message from the Code Review Automation System.
"""
        
        html_body = f"""
<html>
<body>
<h2>Code Review Summary for {project_name}</h2>

<p>A new code review has been completed and documentation has been updated.</p>

<h3>Summary:</h3>
<ul>
<li><strong>Total Commits:</strong> {analysis.get('total_commits', 0)}</li>
<li><strong>Files Changed:</strong> {len(analysis.get('files_changed', []))}</li>
<li><strong>Complexity Score:</strong> {analysis.get('quality_metrics', {}).get('complexity_score', 'N/A')}/100</li>
</ul>

<p><a href="https://docs.google.com/document/d/{doc_id}">View the complete review document</a></p>

<p><em>This is an automated message from the Code Review Automation System.</em></p>
</body>
</html>
"""
        
        # Send to each recipient
        for recipient in recipients:
            message = create_email_message(recipient, subject, text_body, html_body)
            
            gmail_service.users().messages().send(
                userId='me',
                body=message
            ).execute()
            
        return True
        
    except Exception as e:
        logging.error(f"Error sending notification email: {str(e)}")
        return False

@app.route('/send-notification', methods=['POST'])
def handle_notification():
    """Handle notification requests"""
    try:
        data = request.get_json()
        
        # Extract notification data
        project_name = data.get('project', 'Unknown Project')
        doc_id = data.get('doc_id')
        analysis = data.get('analysis', {})
        recipients = data.get('recipients', ['admin@example.com'])  # Default recipient
        
        if not doc_id:
            return jsonify({'error': 'Document ID required'}), 400
        
        # Send notification
        success = send_notification_email(recipients, project_name, doc_id, analysis)
        
        if success:
            return jsonify({
                'status': 'success',
                'message': f'Notifications sent to {len(recipients)} recipients'
            })
        else:
            return jsonify({'error': 'Failed to send notifications'}), 500
        
    except Exception as e:
        logging.error(f"Error handling notification: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

# Copy requirements and Dockerfile
cp ../code-review-service/requirements.txt .
cp ../code-review-service/Dockerfile .

# Deploy notification service
gcloud run deploy "notification-service-${RANDOM_SUFFIX}" \
    --source . \
    --platform managed \
    --region "${REGION}" \
    --allow-unauthenticated \
    --memory 512Mi \
    --cpu 1 \
    --timeout 180 \
    --max-instances 5 || error_exit "Failed to deploy notification service"

cd ..

log_success "All Cloud Run services deployed successfully"

# Configure Cloud Scheduler
log_info "Configuring Cloud Scheduler jobs..."

# Create scheduled job for weekly documentation review
gcloud scheduler jobs create http weekly-doc-review \
    --location "${REGION}" \
    --schedule "0 9 * * 1" \
    --uri "https://docs-service-${RANDOM_SUFFIX}-uc.a.run.app/health" \
    --http-method GET \
    --description "Weekly documentation review trigger" || error_exit "Failed to create weekly scheduler job"

# Create scheduled job for monthly cleanup
gcloud scheduler jobs create http monthly-cleanup \
    --location "${REGION}" \
    --schedule "0 2 1 * *" \
    --uri "https://${SERVICE_NAME}-uc.a.run.app/health" \
    --http-method GET \
    --description "Monthly cleanup and maintenance" || error_exit "Failed to create monthly scheduler job"

# Create Pub/Sub message for maintenance tasks
gcloud scheduler jobs create pubsub maintenance-trigger \
    --location "${REGION}" \
    --schedule "0 3 * * 0" \
    --topic "${TOPIC_NAME}" \
    --message-body '{"type":"maintenance","action":"weekly_summary"}' \
    --description "Weekly maintenance trigger" || error_exit "Failed to create maintenance scheduler job"

log_success "Cloud Scheduler jobs configured"

# Set up monitoring
log_info "Setting up monitoring and alerting..."

# Create monitoring dashboard configuration
cat > dashboard-config.json << 'EOF'
{
  "displayName": "Code Review Automation Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cloud Run Request Count",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

# Create monitoring dashboard
gcloud monitoring dashboards create --config-from-file dashboard-config.json || log_warning "Failed to create monitoring dashboard"

# Create alerting policy for service errors
cat > alert-policy.json << 'EOF'
{
  "displayName": "Code Review Service Errors",
  "conditions": [
    {
      "displayName": "Cloud Run Error Rate",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.1,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF

gcloud alpha monitoring policies create --policy-from-file alert-policy.json || log_warning "Failed to create alert policy"

# Cleanup temporary files
rm -f dashboard-config.json alert-policy.json

log_success "Monitoring and alerting configured"

# Cleanup service directories
log_info "Cleaning up temporary files..."
rm -rf code-review-service docs-service notification-service

# Get service URLs for validation
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format="value(status.url)")
DOCS_SERVICE_URL=$(gcloud run services describe "docs-service-${RANDOM_SUFFIX}" --region "${REGION}" --format="value(status.url)")
NOTIFICATION_SERVICE_URL=$(gcloud run services describe "notification-service-${RANDOM_SUFFIX}" --region "${REGION}" --format="value(status.url)")

# Save deployment information
cat > deployment-info.txt << EOF
Code Review Automation Deployment Information
===========================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Deployment Date: $(date)

Resources Created:
- Service Name: ${SERVICE_NAME}
- Topic Name: ${TOPIC_NAME}
- Subscription Name: ${SUBSCRIPTION_NAME}
- Bucket Name: ${BUCKET_NAME}

Service URLs:
- Code Review Service: ${SERVICE_URL}
- Documentation Service: ${DOCS_SERVICE_URL}
- Notification Service: ${NOTIFICATION_SERVICE_URL}

Next Steps:
1. Configure Google Workspace domain-wide delegation for the service account
2. Set up webhook URLs in your code repositories
3. Configure email recipients for notifications
4. Test the workflow with a sample webhook payload

For cleanup, run: ./destroy.sh
EOF

log_success "Deployment information saved to deployment-info.txt"

# Final validation
log_info "Running deployment validation..."

# Test service health endpoints
if curl -f -s "${SERVICE_URL}/health" > /dev/null; then
    log_success "Code Review Service health check passed"
else
    log_warning "Code Review Service health check failed"
fi

if curl -f -s "${DOCS_SERVICE_URL}/health" > /dev/null; then
    log_success "Documentation Service health check passed"
else
    log_warning "Documentation Service health check failed"
fi

if curl -f -s "${NOTIFICATION_SERVICE_URL}/health" > /dev/null; then
    log_success "Notification Service health check passed"
else
    log_warning "Notification Service health check failed"
fi

# Display deployment summary
echo
echo -e "${GREEN}=================================================="
echo "  Deployment Completed Successfully!"
echo "==================================================${NC}"
echo
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo
echo "Services deployed:"
echo "✅ Code Review Service: ${SERVICE_URL}"
echo "✅ Documentation Service: ${DOCS_SERVICE_URL}"
echo "✅ Notification Service: ${NOTIFICATION_SERVICE_URL}"
echo
echo "Resources created:"
echo "✅ Pub/Sub Topic: ${TOPIC_NAME}"
echo "✅ Storage Bucket: gs://${BUCKET_NAME}"
echo "✅ Service Account: workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com"
echo "✅ Scheduled Jobs: weekly-doc-review, monthly-cleanup, maintenance-trigger"
echo
echo -e "${YELLOW}Important Next Steps:${NC}"
echo "1. Configure Google Workspace domain-wide delegation"
echo "2. Set up webhook URLs in your repositories"
echo "3. Configure notification email recipients"
echo "4. Test the workflow with sample data"
echo
echo "For detailed instructions, see: deployment-info.txt"
echo "To clean up resources, run: ./destroy.sh"
echo
echo -e "${GREEN}Deployment completed successfully!${NC}"