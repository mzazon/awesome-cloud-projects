#!/bin/bash

# =============================================================================
# Team Collaboration Insights with Workspace Events API and Cloud Functions
# Deployment Script for GCP
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment-config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
DEFAULT_PROJECT_PREFIX="workspace-analytics"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# =============================================================================
# Utility Functions
# =============================================================================

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

check_command() {
    if ! command -v "${1}" &> /dev/null; then
        log_error "Required command '${1}' not found. Please install it and try again."
        exit 1
    fi
}

prompt_user() {
    local prompt="${1}"
    local default="${2:-}"
    local response

    if [[ -n "${default}" ]]; then
        read -p "${prompt} [${default}]: " response
        echo "${response:-${default}}"
    else
        read -p "${prompt}: " response
        echo "${response}"
    fi
}

generate_random_suffix() {
    openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)"
}

save_config() {
    cat > "${CONFIG_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    log_info "Configuration saved to ${CONFIG_FILE}"
}

load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
        log_info "Loaded existing configuration from ${CONFIG_FILE}"
        return 0
    fi
    return 1
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required commands
    check_command "gcloud"
    check_command "curl"
    check_command "jq"
    check_command "openssl"

    # Check gcloud authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1 &>/dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi

    # Check for active project
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "${current_project}" ]]; then
        log_warning "No default project set in gcloud config."
    else
        log_info "Current gcloud project: ${current_project}"
    fi

    log_success "Prerequisites check completed"
}

# =============================================================================
# Project Setup
# =============================================================================

setup_project() {
    log_info "Setting up Google Cloud project..."

    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        local project_prefix
        project_prefix=$(prompt_user "Enter project prefix" "${DEFAULT_PROJECT_PREFIX}")
        RANDOM_SUFFIX=$(generate_random_suffix)
        PROJECT_ID="${project_prefix}-${RANDOM_SUFFIX}"
    fi

    log_info "Project ID: ${PROJECT_ID}"

    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        
        # Get billing account
        local billing_accounts
        billing_accounts=$(gcloud billing accounts list --format="value(name,displayName)" --filter="open:true")
        
        if [[ -z "${billing_accounts}" ]]; then
            log_error "No active billing accounts found. Please ensure you have an active billing account."
            exit 1
        fi
        
        log_info "Available billing accounts:"
        echo "${billing_accounts}"
        
        local billing_account
        billing_account=$(prompt_user "Enter billing account ID")
        
        if [[ -z "${billing_account}" ]]; then
            log_error "Billing account ID is required"
            exit 1
        fi

        # Create project
        gcloud projects create "${PROJECT_ID}" --name="Workspace Analytics" || {
            log_error "Failed to create project ${PROJECT_ID}"
            exit 1
        }

        # Link billing account
        gcloud billing projects link "${PROJECT_ID}" --billing-account="${billing_account}" || {
            log_error "Failed to link billing account to project"
            exit 1
        }

        log_success "Project ${PROJECT_ID} created and linked to billing account"
    fi

    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"

    log_success "Project setup completed"
}

# =============================================================================
# API Enablement
# =============================================================================

enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "pubsub.googleapis.com"
        "workspaceevents.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "cloudbuild.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        if gcloud services enable "${api}" 2>>"${LOG_FILE}"; then
            log_success "✅ Enabled ${api}"
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

# =============================================================================
# IAM Setup
# =============================================================================

setup_iam() {
    log_info "Setting up IAM service accounts and permissions..."

    # Create service account for Workspace Events API
    local sa_email="workspace-events-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_info "Service account ${sa_email} already exists"
    else
        gcloud iam service-accounts create workspace-events-sa \
            --display-name="Workspace Events Service Account" \
            --description="Service account for Workspace Events API integration"
        
        log_success "✅ Created service account: ${sa_email}"
    fi

    # Grant necessary permissions
    local roles=(
        "roles/pubsub.publisher"
        "roles/datastore.user"
        "roles/cloudfunctions.invoker"
    )

    for role in "${roles[@]}"; do
        log_info "Granting role ${role} to service account"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}" \
            --quiet 2>>"${LOG_FILE}"
    done

    log_success "IAM setup completed"
}

# =============================================================================
# Infrastructure Deployment
# =============================================================================

deploy_pubsub() {
    log_info "Deploying Cloud Pub/Sub infrastructure..."

    # Create Pub/Sub topic
    if gcloud pubsub topics describe workspace-events-topic &>/dev/null; then
        log_info "Pub/Sub topic 'workspace-events-topic' already exists"
    else
        gcloud pubsub topics create workspace-events-topic
        log_success "✅ Created Pub/Sub topic: workspace-events-topic"
    fi

    # Create subscription
    if gcloud pubsub subscriptions describe workspace-events-subscription &>/dev/null; then
        log_info "Pub/Sub subscription 'workspace-events-subscription' already exists"
    else
        gcloud pubsub subscriptions create workspace-events-subscription \
            --topic=workspace-events-topic \
            --ack-deadline=600 \
            --message-retention-duration=7d \
            --expiration-period=never
        
        log_success "✅ Created Pub/Sub subscription: workspace-events-subscription"
    fi

    log_success "Pub/Sub infrastructure deployed"
}

deploy_firestore() {
    log_info "Deploying Cloud Firestore database..."

    # Check if Firestore database exists
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_info "Firestore database already exists"
    else
        log_info "Creating Firestore database in native mode..."
        gcloud firestore databases create \
            --location="${REGION}" \
            --type=firestore-native
        
        log_success "✅ Created Firestore database"
    fi

    # Deploy security rules
    log_info "Deploying Firestore security rules..."
    
    cat > "${SCRIPT_DIR}/firestore.rules" << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read access to collaboration events for authenticated users
    match /collaboration_events/{document} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions can write
    }
    
    // Allow read access to team metrics
    match /team_metrics/{document} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions can write
    }
    
    // Allow service account access for Cloud Functions
    match /{path=**} {
      allow read, write: if request.auth != null && 
        request.auth.token.email.matches('.*@' + resource.data.project_id + '.iam.gserviceaccount.com');
    }
  }
}
EOF

    if gcloud firestore deploy --rules="${SCRIPT_DIR}/firestore.rules" --quiet; then
        log_success "✅ Deployed Firestore security rules"
    else
        log_warning "Failed to deploy Firestore security rules, but continuing..."
    fi

    log_success "Firestore infrastructure deployed"
}

deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."

    # Create Cloud Function source directory
    local function_dir="${SCRIPT_DIR}/workspace-analytics-function"
    mkdir -p "${function_dir}"
    
    # Create main function file
    cat > "${function_dir}/main.py" << 'EOF'
import json
import base64
from google.cloud import firestore
from datetime import datetime
import functions_framework
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Firestore client
db = firestore.Client()

@functions_framework.cloud_event
def process_workspace_event(cloud_event):
    """Process Google Workspace events and store analytics data."""
    try:
        logger.info(f"Processing cloud event: {cloud_event.data}")
        
        # Decode event data
        message_data = cloud_event.data.get('message', {})
        event_data_b64 = message_data.get('data', '')
        event_attributes = message_data.get('attributes', {})
        
        if event_data_b64:
            event_data = json.loads(base64.b64decode(event_data_b64).decode('utf-8'))
        else:
            event_data = {}
        
        event_type = event_attributes.get('ce-type', 'unknown')
        event_time = event_attributes.get('ce-time', datetime.utcnow().isoformat())
        
        logger.info(f"Processing event type: {event_type}")
        
        # Extract collaboration insights
        insights = extract_collaboration_insights(event_data, event_type)
        
        # Store in Firestore
        doc_ref = db.collection('collaboration_events').document()
        doc_data = {
            'event_type': event_type,
            'timestamp': datetime.fromisoformat(event_time.replace('Z', '+00:00')),
            'insights': insights,
            'raw_event': event_data,
            'processed_at': datetime.utcnow()
        }
        
        doc_ref.set(doc_data)
        logger.info(f"Stored event data with document ID: {doc_ref.id}")
        
        # Update team metrics
        update_team_metrics(insights)
        
        logger.info(f"Successfully processed {event_type} event")
        return {'status': 'success', 'event_type': event_type}
        
    except Exception as e:
        logger.error(f"Error processing workspace event: {str(e)}")
        raise

def extract_collaboration_insights(event_data, event_type):
    """Extract meaningful collaboration insights from workspace events."""
    insights = {
        'processed_timestamp': datetime.utcnow().isoformat(),
        'event_category': 'unknown'
    }
    
    try:
        if 'chat.message' in event_type:
            insights.update({
                'interaction_type': 'chat',
                'event_category': 'communication',
                'participants': event_data.get('sender', {}).get('name', 'unknown'),
                'space_id': event_data.get('space', {}).get('name', 'unknown'),
                'message_type': event_data.get('messageType', 'unknown')
            })
        elif 'drive.file' in event_type:
            insights.update({
                'interaction_type': 'file_collaboration',
                'event_category': 'document_management',
                'file_type': event_data.get('mimeType', 'unknown'),
                'sharing_activity': event_type.split('.')[-1] if '.' in event_type else 'unknown',
                'file_name': event_data.get('name', 'unknown')
            })
        elif 'meet.conference' in event_type or 'meet.participant' in event_type:
            insights.update({
                'interaction_type': 'meeting',
                'event_category': 'virtual_collaboration',
                'conference_id': event_data.get('conferenceRecord', {}).get('name', 'unknown'),
                'activity_type': event_type.split('.')[-1] if '.' in event_type else 'unknown'
            })
            
            if 'duration' in event_data.get('conferenceRecord', {}):
                insights['duration'] = event_data['conferenceRecord']['duration']
        else:
            insights.update({
                'interaction_type': 'other',
                'event_category': 'general',
                'raw_event_type': event_type
            })
            
    except Exception as e:
        logger.warning(f"Error extracting insights: {str(e)}")
        insights['extraction_error'] = str(e)
    
    return insights

def update_team_metrics(insights):
    """Update aggregated team collaboration metrics."""
    try:
        metrics_ref = db.collection('team_metrics').document('daily_summary')
        
        # Use Firestore transactions for atomic updates
        from google.cloud.firestore import Increment
        
        interaction_type = insights.get('interaction_type', 'unknown')
        event_category = insights.get('event_category', 'unknown')
        
        update_data = {
            f"{interaction_type}_count": Increment(1),
            f"{event_category}_count": Increment(1),
            'total_events': Increment(1),
            'last_updated': datetime.utcnow(),
            'last_event_type': insights.get('interaction_type', 'unknown')
        }
        
        metrics_ref.set(update_data, merge=True)
        logger.info(f"Updated team metrics for {interaction_type}")
        
    except Exception as e:
        logger.error(f"Error updating team metrics: {str(e)}")
EOF

    # Create requirements file
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-firestore>=2.16.0
functions-framework>=3.5.0
EOF

    # Deploy event processing Cloud Function
    log_info "Deploying event processing Cloud Function..."
    
    (cd "${function_dir}" && \
     gcloud functions deploy process-workspace-events \
         --runtime python311 \
         --trigger-topic workspace-events-topic \
         --source . \
         --entry-point process_workspace_event \
         --memory 256MB \
         --timeout 60s \
         --max-instances 10 \
         --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
         --quiet) 2>>"${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log_success "✅ Deployed process-workspace-events function"
    else
        log_error "Failed to deploy process-workspace-events function"
        exit 1
    fi

    # Deploy analytics dashboard function
    deploy_analytics_function

    log_success "Cloud Functions deployed"
}

deploy_analytics_function() {
    log_info "Deploying analytics dashboard function..."

    local dashboard_dir="${SCRIPT_DIR}/analytics-dashboard"
    mkdir -p "${dashboard_dir}"
    
    # Create dashboard API function
    cat > "${dashboard_dir}/main.py" << 'EOF'
import json
from google.cloud import firestore
from datetime import datetime, timedelta
import functions_framework
from flask import jsonify
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Firestore client
db = firestore.Client()

@functions_framework.http
def get_collaboration_analytics(request):
    """HTTP endpoint for retrieving collaboration analytics."""
    try:
        # Enable CORS
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)

        # Parse query parameters
        days = int(request.args.get('days', 7))
        team_id = request.args.get('team_id', 'all')
        
        logger.info(f"Analytics request for {days} days, team: {team_id}")
        
        # Calculate date range
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days)
        
        # Query collaboration events
        events_ref = db.collection('collaboration_events')
        query = events_ref.where('timestamp', '>=', start_date) \
                         .where('timestamp', '<=', end_date) \
                         .limit(1000)  # Limit for performance
        
        events = []
        for doc in query.stream():
            event_data = doc.to_dict()
            # Convert timestamp to string for JSON serialization
            if 'timestamp' in event_data:
                event_data['timestamp'] = event_data['timestamp'].isoformat()
            if 'processed_at' in event_data:
                event_data['processed_at'] = event_data['processed_at'].isoformat()
            events.append(event_data)
        
        logger.info(f"Retrieved {len(events)} events")
        
        # Calculate analytics
        analytics = calculate_team_analytics(events)
        
        # Get team metrics summary
        team_metrics = get_team_metrics_summary()
        
        response_data = {
            'period': f'{days} days',
            'total_events': len(events),
            'analytics': analytics,
            'team_metrics': team_metrics,
            'generated_at': datetime.utcnow().isoformat(),
            'status': 'success'
        }
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return (jsonify(response_data), 200, headers)
        
    except Exception as e:
        logger.error(f"Error in analytics endpoint: {str(e)}")
        error_response = {
            'error': str(e),
            'status': 'error',
            'generated_at': datetime.utcnow().isoformat()
        }
        headers = {'Access-Control-Allow-Origin': '*'}
        return (jsonify(error_response), 500, headers)

def calculate_team_analytics(events):
    """Calculate team collaboration analytics from events."""
    analytics = {
        'interaction_types': {},
        'event_categories': {},
        'daily_activity': {},
        'collaboration_score': 0,
        'trends': {}
    }
    
    try:
        for event in events:
            insights = event.get('insights', {})
            timestamp = event.get('timestamp', '')
            
            # Count interaction types
            interaction_type = insights.get('interaction_type', 'unknown')
            analytics['interaction_types'][interaction_type] = \
                analytics['interaction_types'].get(interaction_type, 0) + 1
            
            # Count event categories
            event_category = insights.get('event_category', 'unknown')
            analytics['event_categories'][event_category] = \
                analytics['event_categories'].get(event_category, 0) + 1
            
            # Group by day
            if timestamp:
                try:
                    if isinstance(timestamp, str):
                        event_date = datetime.fromisoformat(timestamp.replace('Z', '+00:00')).date().isoformat()
                    else:
                        event_date = timestamp.date().isoformat()
                    
                    analytics['daily_activity'][event_date] = \
                        analytics['daily_activity'].get(event_date, 0) + 1
                except Exception as e:
                    logger.warning(f"Error parsing timestamp {timestamp}: {e}")
        
        # Calculate collaboration score (weighted metric)
        total_interactions = sum(analytics['interaction_types'].values())
        unique_types = len(analytics['interaction_types'])
        daily_consistency = len(analytics['daily_activity'])
        
        if total_interactions > 0:
            analytics['collaboration_score'] = min(100, 
                (total_interactions * 0.4) + 
                (unique_types * 10) + 
                (daily_consistency * 5))
        
        # Calculate trends
        analytics['trends'] = calculate_trends(analytics['daily_activity'])
        
    except Exception as e:
        logger.error(f"Error calculating analytics: {str(e)}")
        analytics['calculation_error'] = str(e)
    
    return analytics

def calculate_trends(daily_activity):
    """Calculate trend information from daily activity."""
    trends = {
        'total_days': len(daily_activity),
        'avg_daily_events': 0,
        'peak_day': None,
        'peak_events': 0
    }
    
    if daily_activity:
        total_events = sum(daily_activity.values())
        trends['avg_daily_events'] = round(total_events / len(daily_activity), 2)
        
        # Find peak day
        peak_day = max(daily_activity.items(), key=lambda x: x[1])
        trends['peak_day'] = peak_day[0]
        trends['peak_events'] = peak_day[1]
    
    return trends

def get_team_metrics_summary():
    """Get current team metrics summary."""
    try:
        metrics_ref = db.collection('team_metrics').document('daily_summary')
        doc = metrics_ref.get()
        
        if doc.exists:
            data = doc.to_dict()
            # Convert timestamp to string for JSON serialization
            if 'last_updated' in data:
                data['last_updated'] = data['last_updated'].isoformat()
            return data
        else:
            return {'status': 'no_data', 'message': 'No team metrics available yet'}
            
    except Exception as e:
        logger.error(f"Error getting team metrics: {str(e)}")
        return {'error': str(e)}
EOF

    # Create requirements file for dashboard function
    cat > "${dashboard_dir}/requirements.txt" << 'EOF'
google-cloud-firestore>=2.16.0
functions-framework>=3.5.0
flask>=2.3.0
EOF

    # Deploy analytics dashboard function
    (cd "${dashboard_dir}" && \
     gcloud functions deploy collaboration-analytics \
         --runtime python311 \
         --trigger-http \
         --allow-unauthenticated \
         --source . \
         --entry-point get_collaboration_analytics \
         --memory 512MB \
         --timeout 120s \
         --max-instances 5 \
         --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
         --quiet) 2>>"${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log_success "✅ Deployed collaboration-analytics function"
    else
        log_error "Failed to deploy collaboration-analytics function"
        exit 1
    fi
}

# =============================================================================
# Workspace Events Configuration
# =============================================================================

configure_workspace_events() {
    log_info "Configuring Google Workspace Events subscriptions..."

    # Note: This section provides the configuration files that need to be
    # manually configured with proper Workspace domain delegation
    
    local config_dir="${SCRIPT_DIR}/workspace-config"
    mkdir -p "${config_dir}"

    # Create configuration templates
    create_workspace_config_templates "${config_dir}"

    log_warning "Workspace Events API requires manual domain-wide delegation setup."
    log_warning "Please follow these steps:"
    log_warning "1. Enable domain-wide delegation for the service account"
    log_warning "2. Add required OAuth scopes in Google Workspace Admin Console"
    log_warning "3. Use the configuration files in ${config_dir} to create subscriptions"
    
    log_info "Required OAuth scopes for domain-wide delegation:"
    log_info "- https://www.googleapis.com/auth/chat.messages.readonly"
    log_info "- https://www.googleapis.com/auth/drive.readonly"
    log_info "- https://www.googleapis.com/auth/meetings.space.readonly"

    log_success "Workspace Events configuration templates created"
}

create_workspace_config_templates() {
    local config_dir="${1}"

    # Chat subscription template
    cat > "${config_dir}/chat-subscription.json" << EOF
{
  "name": "projects/${PROJECT_ID}/subscriptions/chat-collaboration-events",
  "targetResource": "//chat.googleapis.com/spaces/-",
  "eventTypes": [
    "google.workspace.chat.message.v1.created",
    "google.workspace.chat.space.v1.updated",
    "google.workspace.chat.membership.v1.created"
  ],
  "notificationEndpoint": {
    "pubsubTopic": "projects/${PROJECT_ID}/topics/workspace-events-topic"
  },
  "payloadOptions": {
    "includeResource": true
  }
}
EOF

    # Drive subscription template
    cat > "${config_dir}/drive-subscription.json" << EOF
{
  "name": "projects/${PROJECT_ID}/subscriptions/drive-collaboration-events",
  "targetResource": "//drive.googleapis.com/files/-",
  "eventTypes": [
    "google.workspace.drive.file.v1.created",
    "google.workspace.drive.file.v1.updated",
    "google.workspace.drive.file.v1.accessProposalCreated"
  ],
  "notificationEndpoint": {
    "pubsubTopic": "projects/${PROJECT_ID}/topics/workspace-events-topic"
  },
  "payloadOptions": {
    "includeResource": false
  }
}
EOF

    # Meet subscription template
    cat > "${config_dir}/meet-subscription.json" << EOF
{
  "name": "projects/${PROJECT_ID}/subscriptions/meet-collaboration-events",
  "targetResource": "//meet.googleapis.com/conferenceRecords/-",
  "eventTypes": [
    "google.workspace.meet.conference.v2.started",
    "google.workspace.meet.conference.v2.ended",
    "google.workspace.meet.participant.v2.joined",
    "google.workspace.meet.participant.v2.left"
  ],
  "notificationEndpoint": {
    "pubsubTopic": "projects/${PROJECT_ID}/topics/workspace-events-topic"
  },
  "payloadOptions": {
    "includeResource": true
  }
}
EOF

    # Configuration script
    cat > "${config_dir}/create-subscriptions.sh" << EOF
#!/bin/bash
# Script to create Workspace Events subscriptions
# Run this after completing domain-wide delegation setup

set -e

PROJECT_ID="${PROJECT_ID}"

echo "Creating Workspace Events subscriptions for project: \${PROJECT_ID}"

# Create Chat subscription
echo "Creating Chat events subscription..."
curl -X POST \\
  "https://workspaceevents.googleapis.com/v1/subscriptions" \\
  -H "Authorization: Bearer \$(gcloud auth print-access-token)" \\
  -H "Content-Type: application/json" \\
  -d @chat-subscription.json

# Create Drive subscription
echo "Creating Drive events subscription..."
curl -X POST \\
  "https://workspaceevents.googleapis.com/v1/subscriptions" \\
  -H "Authorization: Bearer \$(gcloud auth print-access-token)" \\
  -H "Content-Type: application/json" \\
  -d @drive-subscription.json

# Create Meet subscription
echo "Creating Meet events subscription..."
curl -X POST \\
  "https://workspaceevents.googleapis.com/v1/subscriptions" \\
  -H "Authorization: Bearer \$(gcloud auth print-access-token)" \\
  -H "Content-Type: application/json" \\
  -d @meet-subscription.json

echo "Workspace Events subscriptions created successfully!"
EOF

    chmod +x "${config_dir}/create-subscriptions.sh"

    log_info "Configuration templates created in ${config_dir}/"
}

# =============================================================================
# Validation and Testing
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."

    # Check Pub/Sub resources
    if gcloud pubsub topics describe workspace-events-topic &>/dev/null; then
        log_success "✅ Pub/Sub topic exists"
    else
        log_error "❌ Pub/Sub topic not found"
        return 1
    fi

    if gcloud pubsub subscriptions describe workspace-events-subscription &>/dev/null; then
        log_success "✅ Pub/Sub subscription exists"
    else
        log_error "❌ Pub/Sub subscription not found"
        return 1
    fi

    # Check Firestore database
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_success "✅ Firestore database exists"
    else
        log_error "❌ Firestore database not found"
        return 1
    fi

    # Check Cloud Functions
    if gcloud functions describe process-workspace-events &>/dev/null; then
        log_success "✅ Event processing function deployed"
    else
        log_error "❌ Event processing function not found"
        return 1
    fi

    if gcloud functions describe collaboration-analytics &>/dev/null; then
        log_success "✅ Analytics function deployed"
        
        # Get analytics function URL
        local analytics_url
        analytics_url=$(gcloud functions describe collaboration-analytics \
            --format="value(httpsTrigger.url)" 2>/dev/null)
        
        if [[ -n "${analytics_url}" ]]; then
            log_info "Analytics API URL: ${analytics_url}"
            
            # Test analytics endpoint
            log_info "Testing analytics endpoint..."
            local response_code
            response_code=$(curl -s -o /dev/null -w "%{http_code}" "${analytics_url}?days=1" || echo "000")
            
            if [[ "${response_code}" == "200" ]]; then
                log_success "✅ Analytics endpoint responding"
            else
                log_warning "⚠️  Analytics endpoint returned code: ${response_code}"
            fi
        fi
    else
        log_error "❌ Analytics function not found"
        return 1
    fi

    log_success "Deployment validation completed"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Remove temporary directories
    rm -rf "${SCRIPT_DIR}/workspace-analytics-function" 2>/dev/null || true
    rm -rf "${SCRIPT_DIR}/analytics-dashboard" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/firestore.rules" 2>/dev/null || true
    
    log_info "Partial cleanup completed. Run ./destroy.sh for full cleanup."
}

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    # Initialize log file
    echo "=== Team Collaboration Insights Deployment - $(date) ===" > "${LOG_FILE}"
    
    log_info "Starting deployment of Team Collaboration Insights with Workspace Events API"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Load existing configuration or prompt for new values
    if ! load_config; then
        log_info "Starting new deployment configuration..."
        
        # Get deployment parameters
        PROJECT_ID=$(prompt_user "Enter Google Cloud Project ID (leave empty to create new)")
        REGION=$(prompt_user "Enter deployment region" "${DEFAULT_REGION}")
        ZONE=$(prompt_user "Enter deployment zone" "${DEFAULT_ZONE}")
        
        # Generate random suffix for unique resource names
        RANDOM_SUFFIX=$(generate_random_suffix)
        
        # Save configuration
        save_config
    fi
    
    # Export variables for use in functions
    export PROJECT_ID REGION ZONE RANDOM_SUFFIX
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    setup_iam
    deploy_pubsub
    deploy_firestore
    deploy_cloud_functions
    configure_workspace_events
    validate_deployment
    
    # Display deployment summary
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "=== Deployment Summary ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    echo
    log_info "=== Next Steps ==="
    log_info "1. Complete Google Workspace domain-wide delegation setup"
    log_info "2. Run the subscription creation script in workspace-config/"
    log_info "3. Monitor Cloud Functions logs for event processing"
    echo
    log_info "=== Analytics Dashboard ==="
    local analytics_url
    analytics_url=$(gcloud functions describe collaboration-analytics \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    log_info "Analytics API URL: ${analytics_url}"
    echo
    log_info "Deployment log saved to: ${LOG_FILE}"
    log_info "Configuration saved to: ${CONFIG_FILE}"
    
    # Clean up temporary files
    rm -rf "${SCRIPT_DIR}/workspace-analytics-function" 2>/dev/null || true
    rm -rf "${SCRIPT_DIR}/analytics-dashboard" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/firestore.rules" 2>/dev/null || true
}

# =============================================================================
# Script Entry Point
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi