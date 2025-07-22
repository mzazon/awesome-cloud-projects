#!/bin/bash

# Dynamic Email Campaign Workflows - Deployment Script
# This script deploys the complete email campaign automation infrastructure on GCP

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    success "All prerequisites are installed"
}

# Check if user is authenticated
check_authentication() {
    log "Checking authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    success "Authentication verified"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-email-campaigns-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-email-campaigns-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-email-campaign-${RANDOM_SUFFIX}}"
    
    log "Environment variables set:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  FUNCTION_NAME: ${FUNCTION_NAME}"
}

# Create GCP project
create_project() {
    log "Creating GCP project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        warning "Project ${PROJECT_ID} already exists. Skipping creation."
    else
        if gcloud projects create "${PROJECT_ID}"; then
            success "Project ${PROJECT_ID} created successfully"
        else
            error "Failed to create project ${PROJECT_ID}"
            exit 1
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
        "gmail.googleapis.com"
        "bigquery.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}"; then
            success "${api} enabled"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        warning "Bucket ${BUCKET_NAME} already exists. Skipping creation."
    else
        if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
            success "Bucket ${BUCKET_NAME} created successfully"
        else
            error "Failed to create bucket ${BUCKET_NAME}"
            exit 1
        fi
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Create folder structure
    echo "Campaign data structure initialized" | gsutil cp - "gs://${BUCKET_NAME}/templates/welcome.txt"
    echo "User behavior tracking enabled" | gsutil cp - "gs://${BUCKET_NAME}/analytics/metrics.json"
    
    success "Storage bucket configured with folder structure"
}

# Create service account for Gmail API
create_service_account() {
    log "Creating service account for Gmail API..."
    
    local sa_name="gmail-automation-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        warning "Service account ${sa_email} already exists. Skipping creation."
    else
        if gcloud iam service-accounts create "${sa_name}" \
            --display-name="Gmail Automation Service Account" \
            --description="Service account for automated email campaigns"; then
            success "Service account ${sa_email} created successfully"
        else
            error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Generate service account key
    local key_file="./gmail-automation-key.json"
    if [ ! -f "${key_file}" ]; then
        if gcloud iam service-accounts keys create "${key_file}" \
            --iam-account="${sa_email}"; then
            success "Service account key generated"
        else
            error "Failed to generate service account key"
            exit 1
        fi
    fi
    
    # Store credentials in Cloud Storage
    gsutil cp "${key_file}" "gs://${BUCKET_NAME}/credentials/"
    
    # Clean up local key file for security
    rm -f "${key_file}"
    
    success "Service account configured and credentials stored securely"
}

# Create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset..."
    
    local dataset_name="email_campaigns"
    
    # Check if dataset already exists
    if bq ls -d "${PROJECT_ID}:${dataset_name}" &>/dev/null; then
        warning "Dataset ${dataset_name} already exists. Skipping creation."
    else
        if bq mk --dataset \
            --description="Email campaign analytics and user behavior data" \
            --location="${REGION}" \
            "${PROJECT_ID}:${dataset_name}"; then
            success "BigQuery dataset ${dataset_name} created"
        else
            error "Failed to create BigQuery dataset"
            exit 1
        fi
    fi
    
    # Create user behavior table
    if ! bq ls "${PROJECT_ID}:${dataset_name}.user_behavior" &>/dev/null; then
        if bq mk --table \
            --description="User behavior tracking for email personalization" \
            "${PROJECT_ID}:${dataset_name}.user_behavior" \
            user_id:STRING,email:STRING,last_activity:TIMESTAMP,purchase_history:STRING,preferences:STRING; then
            success "User behavior table created"
        else
            error "Failed to create user behavior table"
            exit 1
        fi
    fi
    
    # Create campaign metrics table
    if ! bq ls "${PROJECT_ID}:${dataset_name}.campaign_metrics" &>/dev/null; then
        if bq mk --table \
            --description="Campaign performance metrics and analytics" \
            "${PROJECT_ID}:${dataset_name}.campaign_metrics" \
            campaign_id:STRING,sent_count:INTEGER,delivered_count:INTEGER,opened_count:INTEGER,clicked_count:INTEGER,timestamp:TIMESTAMP; then
            success "Campaign metrics table created"
        else
            error "Failed to create campaign metrics table"
            exit 1
        fi
    fi
    
    # Insert sample data
    log "Inserting sample user data..."
    bq query --use_legacy_sql=false \
        "INSERT INTO \`${PROJECT_ID}.${dataset_name}.user_behavior\` (user_id, email, last_activity, purchase_history, preferences) VALUES 
        ('user_001', 'user1@example.com', CURRENT_TIMESTAMP(), 'electronics', 'product_updates'),
        ('user_002', 'user2@example.com', CURRENT_TIMESTAMP(), 'books', 'promotions'),
        ('user_003', 'user3@example.com', CURRENT_TIMESTAMP(), 'clothing', 'newsletter')"
    
    success "BigQuery dataset and tables configured with sample data"
}

# Deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/email-campaign-functions"
    mkdir -p "${temp_dir}"
    
    # Deploy Campaign Generator Function
    deploy_campaign_generator "${temp_dir}"
    
    # Deploy Email Sender Function
    deploy_email_sender "${temp_dir}"
    
    # Deploy Analytics Function
    deploy_analytics_function "${temp_dir}"
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    success "All Cloud Functions deployed successfully"
}

# Deploy Campaign Generator Function
deploy_campaign_generator() {
    local temp_dir="$1"
    local function_dir="${temp_dir}/campaign-generator"
    
    log "Deploying Campaign Generator function..."
    
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create main.py
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import storage
from google.cloud import bigquery
from datetime import datetime, timedelta
import functions_framework

# Get bucket name from environment
bucket_name = os.environ.get('BUCKET_NAME', 'email-campaigns-bucket')

@functions_framework.http
def generate_campaign(request):
    """Generate personalized email campaigns based on user behavior"""
    
    # Initialize Google Cloud clients
    storage_client = storage.Client()
    bq_client = bigquery.Client()
    
    try:
        # Fetch user behavior data from BigQuery
        query = """
        SELECT user_id, email, last_activity, purchase_history, preferences
        FROM `email_campaigns.user_behavior`
        WHERE last_activity >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
        """
        
        query_job = bq_client.query(query)
        users = query_job.result()
        
        # Generate personalized campaigns
        campaigns = []
        for user in users:
            campaign = {
                'user_id': user.user_id,
                'email': user.email,
                'template': select_template(user.preferences),
                'send_time': calculate_optimal_time(user.last_activity),
                'personalization': generate_personalization(user.purchase_history)
            }
            campaigns.append(campaign)
        
        # Store campaigns in Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        blob = bucket.blob(f'campaigns/{timestamp}_generated.json')
        blob.upload_from_string(json.dumps(campaigns))
        
        return {
            'status': 'success',
            'campaigns_generated': len(campaigns),
            'storage_path': f'campaigns/{timestamp}_generated.json'
        }
        
    except Exception as e:
        logging.error(f"Campaign generation failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def select_template(preferences):
    """Select appropriate email template based on user preferences"""
    if 'product_updates' in preferences:
        return 'product_announcement'
    elif 'promotions' in preferences:
        return 'promotional_offer'
    else:
        return 'newsletter'

def calculate_optimal_time(last_activity):
    """Calculate optimal send time based on user activity patterns"""
    # Simple logic - can be enhanced with ML predictions
    activity_hour = last_activity.hour
    if 9 <= activity_hour <= 17:
        return 'morning'
    elif 18 <= activity_hour <= 22:
        return 'evening'
    else:
        return 'afternoon'

def generate_personalization(purchase_history):
    """Generate personalized content based on purchase history"""
    if not purchase_history:
        return {'greeting': 'Hello!', 'recommendation': 'Check out our latest products'}
    
    return {
        'greeting': f'Hello valued customer!',
        'recommendation': f'Based on your recent purchase, you might like...'
    }
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
google-cloud-bigquery==3.11.4
functions-framework==3.4.0
EOF
    
    # Deploy the function
    if gcloud functions deploy "${FUNCTION_NAME}-generator" \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars BUCKET_NAME="${BUCKET_NAME}"; then
        success "Campaign Generator function deployed"
    else
        error "Failed to deploy Campaign Generator function"
        exit 1
    fi
    
    cd - > /dev/null
}

# Deploy Email Sender Function
deploy_email_sender() {
    local temp_dir="$1"
    local function_dir="${temp_dir}/email-sender"
    
    log "Deploying Email Sender function..."
    
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create main.py
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import storage
from google.oauth2 import service_account
from googleapiclient.discovery import build
import email.mime.text
import email.mime.multipart
import base64
import functions_framework

# Get bucket name from environment
bucket_name = os.environ.get('BUCKET_NAME', 'email-campaigns-bucket')

@functions_framework.http
def send_emails(request):
    """Send personalized emails using Gmail API"""
    
    # Initialize clients
    storage_client = storage.Client()
    
    try:
        # Get campaign data from request
        request_json = request.get_json()
        campaign_file = request_json.get('campaign_file', 'campaigns/latest_generated.json')
        
        # Load campaign data from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(campaign_file)
        campaigns = json.loads(blob.download_as_string())
        
        # Initialize Gmail API client
        gmail_service = initialize_gmail_client()
        
        # Send emails
        sent_count = 0
        failed_count = 0
        
        for campaign in campaigns:
            try:
                # Generate email content
                email_body = generate_email_content(campaign)
                
                # Create email message
                message = create_email_message(
                    to=campaign['email'],
                    subject=get_subject_line(campaign['template']),
                    body=email_body
                )
                
                # Send email
                result = gmail_service.users().messages().send(
                    userId='me',
                    body=message
                ).execute()
                
                sent_count += 1
                logging.info(f"Email sent to {campaign['email']}: {result['id']}")
                
            except Exception as e:
                failed_count += 1
                logging.error(f"Failed to send email to {campaign['email']}: {str(e)}")
        
        # Update analytics
        update_analytics(sent_count, failed_count)
        
        return {
            'status': 'success',
            'emails_sent': sent_count,
            'emails_failed': failed_count
        }
        
    except Exception as e:
        logging.error(f"Email sending failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def initialize_gmail_client():
    """Initialize Gmail API client with service account credentials"""
    # Load credentials from Cloud Storage
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob('credentials/gmail-automation-key.json')
    credentials_json = json.loads(blob.download_as_string())
    
    credentials = service_account.Credentials.from_service_account_info(
        credentials_json,
        scopes=['https://www.googleapis.com/auth/gmail.send']
    )
    
    return build('gmail', 'v1', credentials=credentials)

def generate_email_content(campaign):
    """Generate personalized email content"""
    template = campaign['template']
    personalization = campaign['personalization']
    
    # Load template from Cloud Storage
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(f'templates/{template}.html')
    template_content = blob.download_as_string().decode('utf-8')
    
    # Replace placeholders with personalized content
    content = template_content.replace('{{greeting}}', personalization['greeting'])
    content = content.replace('{{recommendation}}', personalization['recommendation'])
    
    return content

def create_email_message(to, subject, body):
    """Create email message in Gmail API format"""
    message = email.mime.multipart.MIMEMultipart()
    message['to'] = to
    message['subject'] = subject
    
    msg = email.mime.text.MIMEText(body, 'html')
    message.attach(msg)
    
    return {
        'raw': base64.urlsafe_b64encode(message.as_bytes()).decode()
    }

def get_subject_line(template):
    """Get appropriate subject line for template"""
    subjects = {
        'product_announcement': 'Exciting New Product Updates!',
        'promotional_offer': 'Special Offer Just for You!',
        'newsletter': 'Your Weekly Newsletter'
    }
    return subjects.get(template, 'Important Update')

def update_analytics(sent_count, failed_count):
    """Update campaign analytics"""
    # This would typically update BigQuery or Cloud Monitoring
    logging.info(f"Campaign analytics: {sent_count} sent, {failed_count} failed")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
google-auth==2.21.0
google-auth-oauthlib==1.0.0
google-auth-httplib2==0.1.0
google-api-python-client==2.88.0
functions-framework==3.4.0
EOF
    
    # Deploy the function
    if gcloud functions deploy "${FUNCTION_NAME}-sender" \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=512MB \
        --timeout=300s \
        --set-env-vars BUCKET_NAME="${BUCKET_NAME}"; then
        success "Email Sender function deployed"
    else
        error "Failed to deploy Email Sender function"
        exit 1
    fi
    
    cd - > /dev/null
}

# Deploy Analytics Function
deploy_analytics_function() {
    local temp_dir="$1"
    local function_dir="${temp_dir}/analytics-function"
    
    log "Deploying Analytics function..."
    
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create main.py
    cat > main.py << 'EOF'
import json
import logging
import os
from google.cloud import bigquery
from google.cloud import monitoring_v3
from datetime import datetime, timedelta
import functions_framework

# Get project ID from environment
project_id = os.environ.get('PROJECT_ID', 'email-campaigns-project')

@functions_framework.http
def analyze_campaigns(request):
    """Analyze email campaign performance and generate insights"""
    
    # Initialize clients
    bq_client = bigquery.Client()
    monitoring_client = monitoring_v3.MetricServiceClient()
    
    try:
        # Query recent campaign metrics
        query = """
        SELECT 
            campaign_id,
            sent_count,
            delivered_count,
            opened_count,
            clicked_count,
            timestamp,
            SAFE_DIVIDE(opened_count, delivered_count) as open_rate,
            SAFE_DIVIDE(clicked_count, opened_count) as click_rate
        FROM `email_campaigns.campaign_metrics`
        WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
        ORDER BY timestamp DESC
        """
        
        query_job = bq_client.query(query)
        results = query_job.result()
        
        # Calculate aggregated metrics
        total_sent = 0
        total_delivered = 0
        total_opened = 0
        total_clicked = 0
        
        for row in results:
            total_sent += row.sent_count or 0
            total_delivered += row.delivered_count or 0
            total_opened += row.opened_count or 0
            total_clicked += row.clicked_count or 0
        
        # Calculate overall rates
        overall_delivery_rate = total_delivered / total_sent if total_sent > 0 else 0
        overall_open_rate = total_opened / total_delivered if total_delivered > 0 else 0
        overall_click_rate = total_clicked / total_opened if total_opened > 0 else 0
        
        # Send metrics to Cloud Monitoring
        project_name = f"projects/{project_id}"
        
        # Create time series data
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/email_campaigns/open_rate"
        series.resource.type = "global"
        
        point = monitoring_v3.Point()
        point.value.double_value = overall_open_rate
        point.interval.end_time.seconds = int(datetime.now().timestamp())
        series.points = [point]
        
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        # Generate insights
        insights = generate_insights(overall_open_rate, overall_click_rate)
        
        analytics_result = {
            'status': 'success',
            'period': '7_days',
            'metrics': {
                'total_sent': total_sent,
                'total_delivered': total_delivered,
                'total_opened': total_opened,
                'total_clicked': total_clicked,
                'delivery_rate': overall_delivery_rate,
                'open_rate': overall_open_rate,
                'click_rate': overall_click_rate
            },
            'insights': insights,
            'timestamp': datetime.now().isoformat()
        }
        
        return analytics_result
        
    except Exception as e:
        logging.error(f"Analytics processing failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def generate_insights(open_rate, click_rate):
    """Generate actionable insights based on campaign performance"""
    insights = []
    
    if open_rate < 0.15:
        insights.append({
            'type': 'warning',
            'message': 'Open rate is below industry average (15%). Consider improving subject lines.',
            'recommendation': 'A/B test different subject lines and send times'
        })
    
    if click_rate < 0.02:
        insights.append({
            'type': 'warning',
            'message': 'Click rate is below industry average (2%). Review email content and CTAs.',
            'recommendation': 'Optimize email content and call-to-action buttons'
        })
    
    if open_rate > 0.25:
        insights.append({
            'type': 'success',
            'message': 'Excellent open rate! Continue current subject line strategy.',
            'recommendation': 'Document successful subject line patterns for future campaigns'
        })
    
    return insights
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.11.4
google-cloud-monitoring==2.15.1
functions-framework==3.4.0
EOF
    
    # Deploy the function
    if gcloud functions deploy "${FUNCTION_NAME}-analytics" \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --region="${REGION}" \
        --memory=256MB \
        --timeout=180s \
        --set-env-vars PROJECT_ID="${PROJECT_ID}"; then
        success "Analytics function deployed"
    else
        error "Failed to deploy Analytics function"
        exit 1
    fi
    
    cd - > /dev/null
}

# Create email templates
create_email_templates() {
    log "Creating email templates..."
    
    local temp_dir="/tmp/email-templates"
    mkdir -p "${temp_dir}"
    
    # Create product announcement template
    cat > "${temp_dir}/product_announcement.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        .header { background-color: #4285f4; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background-color: #f9f9f9; }
        .button { background-color: #4285f4; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Product Update</h1>
        </div>
        <div class="content">
            <p>{{greeting}}</p>
            <p>We're excited to announce new features that will enhance your experience:</p>
            <ul>
                <li>Enhanced personalization capabilities</li>
                <li>Improved user interface</li>
                <li>Better performance and reliability</li>
            </ul>
            <p>{{recommendation}}</p>
            <a href="#" class="button">Learn More</a>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create promotional offer template
    cat > "${temp_dir}/promotional_offer.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        .header { background-color: #ea4335; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background-color: #f9f9f9; }
        .offer { background-color: #fff; padding: 15px; border-left: 4px solid #ea4335; margin: 20px 0; }
        .button { background-color: #ea4335; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Special Offer</h1>
        </div>
        <div class="content">
            <p>{{greeting}}</p>
            <div class="offer">
                <h3>Limited Time: 20% Off!</h3>
                <p>Use code SAVE20 at checkout</p>
            </div>
            <p>{{recommendation}}</p>
            <a href="#" class="button">Shop Now</a>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create newsletter template
    cat > "${temp_dir}/newsletter.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        .header { background-color: #34a853; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background-color: #f9f9f9; }
        .article { background-color: #fff; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .button { background-color: #34a853; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Weekly Newsletter</h1>
        </div>
        <div class="content">
            <p>{{greeting}}</p>
            <div class="article">
                <h3>This Week's Highlights</h3>
                <p>Stay updated with the latest news and insights from our team.</p>
            </div>
            <p>{{recommendation}}</p>
            <a href="#" class="button">Read More</a>
        </div>
    </div>
</body>
</html>
EOF
    
    # Upload templates to Cloud Storage
    if gsutil -m cp "${temp_dir}/*.html" "gs://${BUCKET_NAME}/templates/"; then
        success "Email templates uploaded to Cloud Storage"
    else
        error "Failed to upload email templates"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
}

# Configure Cloud Scheduler jobs
configure_scheduler() {
    log "Configuring Cloud Scheduler jobs..."
    
    local generator_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-generator"
    local sender_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-sender"
    
    # Create scheduler job for daily campaign generation
    if gcloud scheduler jobs create http campaign-generator-daily \
        --schedule="0 8 * * *" \
        --uri="${generator_url}" \
        --http-method=POST \
        --message-body='{"trigger": "daily_campaign"}' \
        --time-zone="America/New_York" \
        --location="${REGION}" \
        --description="Daily email campaign generation"; then
        success "Daily campaign generator job created"
    else
        warning "Failed to create daily campaign generator job (may already exist)"
    fi
    
    # Create scheduler job for weekly newsletter
    if gcloud scheduler jobs create http newsletter-weekly \
        --schedule="0 10 * * 1" \
        --uri="${generator_url}" \
        --http-method=POST \
        --message-body='{"trigger": "weekly_newsletter"}' \
        --time-zone="America/New_York" \
        --location="${REGION}" \
        --description="Weekly newsletter campaign"; then
        success "Weekly newsletter job created"
    else
        warning "Failed to create weekly newsletter job (may already exist)"
    fi
    
    # Create scheduler job for promotional campaigns
    if gcloud scheduler jobs create http promotional-campaigns \
        --schedule="0 14 * * 3,6" \
        --uri="${sender_url}" \
        --http-method=POST \
        --message-body='{"campaign_file": "campaigns/latest_promotional.json"}' \
        --time-zone="America/New_York" \
        --location="${REGION}" \
        --description="Promotional email campaigns"; then
        success "Promotional campaigns job created"
    else
        warning "Failed to create promotional campaigns job (may already exist)"
    fi
    
    success "Cloud Scheduler jobs configured"
}

# Run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Test Campaign Generator Function
    log "Testing Campaign Generator function..."
    local generator_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-generator"
    
    if response=$(curl -s -X POST "${generator_url}" \
        -H "Content-Type: application/json" \
        -d '{"trigger": "test_campaign"}' \
        --max-time 30); then
        
        if echo "${response}" | grep -q '"status": "success"'; then
            success "Campaign Generator function test passed"
        else
            warning "Campaign Generator function test returned unexpected response: ${response}"
        fi
    else
        warning "Campaign Generator function test failed (may need more time to initialize)"
    fi
    
    # Verify BigQuery data
    log "Verifying BigQuery data..."
    if user_count=$(bq query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) as user_count FROM \`${PROJECT_ID}.email_campaigns.user_behavior\`" | tail -1); then
        
        if [ "${user_count}" -gt 0 ]; then
            success "BigQuery data verification passed (${user_count} users)"
        else
            warning "No users found in BigQuery table"
        fi
    else
        warning "BigQuery data verification failed"
    fi
    
    # Verify Cloud Storage structure
    log "Verifying Cloud Storage structure..."
    if gsutil ls -r "gs://${BUCKET_NAME}" | grep -q "templates/"; then
        success "Cloud Storage structure verification passed"
    else
        warning "Cloud Storage structure verification failed"
    fi
    
    # List scheduler jobs
    log "Listing Cloud Scheduler jobs..."
    if gcloud scheduler jobs list --location="${REGION}" --format="value(name)" | grep -q "campaign"; then
        success "Cloud Scheduler jobs verification passed"
    else
        warning "Cloud Scheduler jobs verification failed"
    fi
    
    success "Validation tests completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary:"
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: ${BUCKET_NAME}"
    echo "Function Name Prefix: ${FUNCTION_NAME}"
    echo
    echo "Deployed Resources:"
    echo "  ✅ Cloud Storage bucket with templates and folder structure"
    echo "  ✅ BigQuery dataset with user behavior and campaign metrics tables"
    echo "  ✅ Gmail API service account with secure credential storage"
    echo "  ✅ Three Cloud Functions (generator, sender, analytics)"
    echo "  ✅ Cloud Scheduler jobs for automated campaign execution"
    echo
    echo "Function URLs:"
    echo "  Campaign Generator: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-generator"
    echo "  Email Sender: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-sender"
    echo "  Analytics: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-analytics"
    echo
    echo "Next Steps:"
    echo "  1. Configure OAuth 2.0 credentials in Google Cloud Console"
    echo "  2. Set up Gmail API domain verification"
    echo "  3. Test email sending functionality"
    echo "  4. Monitor campaign performance in BigQuery"
    echo
    success "Email Campaign Automation deployment completed successfully!"
}

# Main execution
main() {
    log "Starting Dynamic Email Campaign Workflows deployment..."
    
    # Run all deployment steps
    check_prerequisites
    check_authentication
    setup_environment
    create_project
    enable_apis
    create_storage_bucket
    create_service_account
    create_bigquery_dataset
    deploy_functions
    create_email_templates
    configure_scheduler
    run_validation
    print_summary
    
    log "Deployment completed successfully!"
}

# Run main function
main "$@"