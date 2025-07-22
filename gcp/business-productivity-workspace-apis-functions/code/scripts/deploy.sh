#!/bin/bash

# Business Productivity Workflows with Google Workspace APIs and Cloud Functions
# Deployment Script
#
# This script deploys the complete infrastructure for automating business 
# productivity workflows using Google Workspace APIs and Cloud Functions.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if required tools are available
    local required_tools=("openssl" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites validated"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-productivity-automation-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export DATABASE_NAME="${DATABASE_NAME:-productivity_db}"
    export INSTANCE_NAME="${INSTANCE_NAME:-productivity-instance}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_PREFIX="productivity-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Prefix: ${FUNCTION_PREFIX}"
}

# Function to configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Project ${PROJECT_ID} does not exist. Creating it..."
        gcloud projects create "${PROJECT_ID}" --name="Productivity Automation"
        
        # Enable billing (user needs to do this manually)
        log_warning "Please enable billing for project ${PROJECT_ID} in the Google Cloud Console"
        read -p "Press Enter after enabling billing to continue..."
    fi
    
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configured"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "sqladmin.googleapis.com"
        "gmail.googleapis.com"
        "calendar.googleapis.com"
        "drive.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "Required APIs enabled"
}

# Function to create Cloud SQL database
create_cloud_sql() {
    log_info "Creating Cloud SQL instance and database..."
    
    # Check if instance already exists
    if gcloud sql instances describe "${INSTANCE_NAME}" >/dev/null 2>&1; then
        log_warning "Cloud SQL instance ${INSTANCE_NAME} already exists, skipping creation"
    else
        log_info "Creating Cloud SQL instance: ${INSTANCE_NAME}"
        gcloud sql instances create "${INSTANCE_NAME}" \
            --database-version=POSTGRES_15 \
            --tier=db-f1-micro \
            --region="${REGION}" \
            --storage-type=SSD \
            --storage-size=20GB \
            --backup-start-time=03:00 \
            --maintenance-window-day=SUN \
            --maintenance-window-hour=04
        
        log_success "Cloud SQL instance created"
    fi
    
    # Create database
    log_info "Creating database: ${DATABASE_NAME}"
    if ! gcloud sql databases describe "${DATABASE_NAME}" --instance="${INSTANCE_NAME}" >/dev/null 2>&1; then
        gcloud sql databases create "${DATABASE_NAME}" --instance="${INSTANCE_NAME}"
        log_success "Database created"
    else
        log_warning "Database ${DATABASE_NAME} already exists"
    fi
    
    # Set database password
    export DB_PASSWORD=$(openssl rand -base64 32)
    log_info "Setting database password..."
    gcloud sql users set-password postgres \
        --instance="${INSTANCE_NAME}" \
        --password="${DB_PASSWORD}"
    
    # Store password securely for cleanup script
    echo "${DB_PASSWORD}" > .db_password
    chmod 600 .db_password
    
    log_success "Cloud SQL setup completed"
    log_info "Database password stored in .db_password file"
}

# Function to create service account and credentials
setup_service_account() {
    log_info "Setting up service account for Google Workspace API access..."
    
    local service_account_name="workspace-automation"
    local service_account_email="${service_account_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if ! gcloud iam service-accounts describe "${service_account_email}" >/dev/null 2>&1; then
        log_info "Creating service account: ${service_account_name}"
        gcloud iam service-accounts create "${service_account_name}" \
            --display-name="Workspace Automation Service Account" \
            --description="Service account for Google Workspace API integration"
    else
        log_warning "Service account ${service_account_name} already exists"
    fi
    
    # Generate service account key if it doesn't exist
    if [[ ! -f "credentials.json" ]]; then
        log_info "Generating service account key..."
        gcloud iam service-accounts keys create credentials.json \
            --iam-account="${service_account_email}"
        log_success "Service account key generated"
    else
        log_warning "Service account key already exists"
    fi
    
    # Grant necessary IAM roles
    log_info "Granting IAM roles..."
    local roles=(
        "roles/cloudsql.client"
        "roles/storage.admin"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account_email}" \
            --role="${role}" \
            --quiet
    done
    
    log_success "Service account setup completed"
}

# Function to create and deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Creating and deploying Cloud Functions..."
    
    # Create function directories and deploy each function
    deploy_email_processor
    deploy_meeting_automation
    deploy_document_organization
    deploy_productivity_metrics
    
    log_success "All Cloud Functions deployed"
}

# Function to deploy email processor function
deploy_email_processor() {
    log_info "Deploying email processor function..."
    
    local function_dir="email-processor"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-auth==2.23.4
google-auth-oauthlib==1.1.0
google-api-python-client==2.108.0
google-cloud-sql-connector==1.4.3
pg8000==1.30.3
functions-framework==3.5.0
EOF
    
    # Create main.py with email processing logic
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from googleapiclient.discovery import build
from google.cloud.sql.connector import Connector
import os

def process_emails(request):
    """Process and analyze emails for productivity insights"""
    try:
        # Initialize Gmail API
        credentials = service_account.Credentials.from_service_account_file(
            'credentials.json',
            scopes=['https://www.googleapis.com/auth/gmail.readonly']
        )
        
        service = build('gmail', 'v1', credentials=credentials)
        
        # Get recent emails
        results = service.users().messages().list(
            userId='me', 
            maxResults=50,
            q='newer_than:1d'
        ).execute()
        
        messages = results.get('messages', [])
        
        # Process each email
        email_data = []
        for message in messages:
            msg = service.users().messages().get(
                userId='me', 
                id=message['id']
            ).execute()
            
            # Extract email metadata
            headers = msg['payload'].get('headers', [])
            subject = next((h['value'] for h in headers if h['name'] == 'Subject'), '')
            sender = next((h['value'] for h in headers if h['name'] == 'From'), '')
            date_received = datetime.fromtimestamp(int(msg['internalDate']) / 1000)
            
            # Categorize email
            category = categorize_email(subject, sender)
            
            email_data.append({
                'message_id': message['id'],
                'subject': subject,
                'sender': sender,
                'date_received': date_received,
                'category': category
            })
        
        # Store in database
        store_email_data(email_data)
        
        return {'status': 'success', 'processed': len(email_data)}
        
    except Exception as e:
        logging.error(f"Error processing emails: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def categorize_email(subject, sender):
    """Simple email categorization logic"""
    subject_lower = subject.lower()
    
    if any(word in subject_lower for word in ['urgent', 'asap', 'priority']):
        return 'urgent'
    elif any(word in subject_lower for word in ['meeting', 'schedule', 'calendar']):
        return 'meeting'
    elif any(word in subject_lower for word in ['report', 'analytics', 'metrics']):
        return 'report'
    else:
        return 'general'

def store_email_data(email_data):
    """Store email data in Cloud SQL"""
    connector = Connector()
    
    def getconn():
        conn = connector.connect(
            os.environ['INSTANCE_CONNECTION_NAME'],
            "pg8000",
            user="postgres",
            password=os.environ['DB_PASSWORD'],
            db=os.environ['DATABASE_NAME']
        )
        return conn
    
    with getconn() as conn:
        with conn.cursor() as cursor:
            # Create table if not exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS email_analytics (
                    id SERIAL PRIMARY KEY,
                    message_id VARCHAR(255) UNIQUE,
                    subject TEXT,
                    sender VARCHAR(255),
                    date_received TIMESTAMP,
                    category VARCHAR(50),
                    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Insert email data
            for email in email_data:
                cursor.execute("""
                    INSERT INTO email_analytics 
                    (message_id, subject, sender, date_received, category)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (message_id) DO NOTHING
                """, (
                    email['message_id'],
                    email['subject'],
                    email['sender'],
                    email['date_received'],
                    email['category']
                ))
            
        conn.commit()
EOF
    
    # Copy service account credentials
    cp ../credentials.json .
    
    # Deploy function
    gcloud functions deploy "${FUNCTION_PREFIX}-email-processor" \
        --gen2 \
        --runtime=python311 \
        --source=. \
        --entry-point=process_emails \
        --trigger=http \
        --region="${REGION}" \
        --service-account="workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="INSTANCE_CONNECTION_NAME=${PROJECT_ID}:${REGION}:${INSTANCE_NAME},DB_PASSWORD=${DB_PASSWORD},DATABASE_NAME=${DATABASE_NAME}" \
        --allow-unauthenticated
    
    cd ..
    log_success "Email processor function deployed"
}

# Function to deploy meeting automation function
deploy_meeting_automation() {
    log_info "Deploying meeting automation function..."
    
    local function_dir="meeting-automation"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Copy requirements.txt
    cp ../email-processor/requirements.txt .
    
    # Create main.py with meeting automation logic
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timedelta, timezone
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from googleapiclient.discovery import build
from google.cloud.sql.connector import Connector
import os

def automate_meetings(request):
    """Automate meeting scheduling and management"""
    try:
        # Initialize Calendar API
        credentials = service_account.Credentials.from_service_account_file(
            'credentials.json',
            scopes=['https://www.googleapis.com/auth/calendar']
        )
        
        service = build('calendar', 'v3', credentials=credentials)
        
        # Get calendar events for analysis
        now = datetime.utcnow().isoformat() + 'Z'
        week_from_now = (datetime.utcnow() + timedelta(days=7)).isoformat() + 'Z'
        
        events_result = service.events().list(
            calendarId='primary',
            timeMin=now,
            timeMax=week_from_now,
            singleEvents=True,
            orderBy='startTime'
        ).execute()
        
        events = events_result.get('items', [])
        
        # Analyze meeting patterns
        meeting_data = []
        for event in events:
            start = event['start'].get('dateTime', event['start'].get('date'))
            end = event['end'].get('dateTime', event['end'].get('date'))
            
            if 'dateTime' in event['start']:  # Skip all-day events
                meeting_data.append({
                    'event_id': event['id'],
                    'summary': event.get('summary', 'No title'),
                    'start_time': datetime.fromisoformat(start.replace('Z', '+00:00')),
                    'end_time': datetime.fromisoformat(end.replace('Z', '+00:00')),
                    'attendees': len(event.get('attendees', [])),
                    'duration': calculate_duration(start, end)
                })
        
        # Store meeting analytics
        store_meeting_data(meeting_data)
        
        # Suggest optimal meeting times
        optimal_times = suggest_meeting_times(meeting_data)
        
        return {
            'status': 'success',
            'meetings_analyzed': len(meeting_data),
            'optimal_times': optimal_times
        }
        
    except Exception as e:
        logging.error(f"Error in meeting automation: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def calculate_duration(start_time, end_time):
    """Calculate meeting duration in minutes"""
    start = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
    end = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
    duration = (end - start).total_seconds() / 60
    return int(duration)

def suggest_meeting_times(meeting_data):
    """Suggest optimal meeting times based on patterns"""
    # Simple algorithm - find least busy time slots
    busy_hours = {}
    
    for meeting in meeting_data:
        hour = meeting['start_time'].hour
        busy_hours[hour] = busy_hours.get(hour, 0) + 1
    
    # Suggest times during business hours with low activity
    business_hours = range(9, 17)  # 9 AM to 5 PM
    optimal_times = []
    
    for hour in business_hours:
        if busy_hours.get(hour, 0) <= 1:  # Less than 2 meetings
            optimal_times.append(f"{hour:02d}:00")
    
    return optimal_times[:3]  # Return top 3 suggestions

def store_meeting_data(meeting_data):
    """Store meeting analytics in Cloud SQL"""
    connector = Connector()
    
    def getconn():
        conn = connector.connect(
            os.environ['INSTANCE_CONNECTION_NAME'],
            "pg8000",
            user="postgres",
            password=os.environ['DB_PASSWORD'],
            db=os.environ['DATABASE_NAME']
        )
        return conn
    
    with getconn() as conn:
        with conn.cursor() as cursor:
            # Create table if not exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS meeting_analytics (
                    id SERIAL PRIMARY KEY,
                    event_id VARCHAR(255) UNIQUE,
                    summary TEXT,
                    start_time TIMESTAMP,
                    end_time TIMESTAMP,
                    attendees INTEGER,
                    duration_minutes INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Insert meeting data
            for meeting in meeting_data:
                cursor.execute("""
                    INSERT INTO meeting_analytics 
                    (event_id, summary, start_time, end_time, attendees, duration_minutes)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (event_id) DO NOTHING
                """, (
                    meeting['event_id'],
                    meeting['summary'],
                    meeting['start_time'],
                    meeting['end_time'],
                    meeting['attendees'],
                    meeting['duration']
                ))
            
        conn.commit()
EOF
    
    # Copy credentials
    cp ../credentials.json .
    
    # Deploy function
    gcloud functions deploy "${FUNCTION_PREFIX}-meeting-automation" \
        --gen2 \
        --runtime=python311 \
        --source=. \
        --entry-point=automate_meetings \
        --trigger=http \
        --region="${REGION}" \
        --service-account="workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="INSTANCE_CONNECTION_NAME=${PROJECT_ID}:${REGION}:${INSTANCE_NAME},DB_PASSWORD=${DB_PASSWORD},DATABASE_NAME=${DATABASE_NAME}" \
        --allow-unauthenticated
    
    cd ..
    log_success "Meeting automation function deployed"
}

# Function to deploy document organization function
deploy_document_organization() {
    log_info "Deploying document organization function..."
    
    local function_dir="document-organization"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Copy requirements.txt
    cp ../email-processor/requirements.txt .
    
    # Create main.py with document organization logic
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timedelta, timezone
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from googleapiclient.discovery import build
from google.cloud.sql.connector import Connector
import os

def organize_documents(request):
    """Organize and analyze Google Drive documents"""
    try:
        # Initialize Drive API
        credentials = service_account.Credentials.from_service_account_file(
            'credentials.json',
            scopes=['https://www.googleapis.com/auth/drive']
        )
        
        service = build('drive', 'v3', credentials=credentials)
        
        # Get recent documents
        results = service.files().list(
            pageSize=50,
            fields="nextPageToken, files(id, name, mimeType, createdTime, modifiedTime, owners, size)"
        ).execute()
        
        files = results.get('files', [])
        
        # Analyze documents
        document_data = []
        for file_info in files:
            # Skip folders
            if file_info['mimeType'] == 'application/vnd.google-apps.folder':
                continue
                
            # Categorize document
            category = categorize_document(file_info['name'], file_info['mimeType'])
            
            document_data.append({
                'file_id': file_info['id'],
                'name': file_info['name'],
                'mime_type': file_info['mimeType'],
                'created_time': datetime.fromisoformat(file_info['createdTime'].replace('Z', '+00:00')),
                'modified_time': datetime.fromisoformat(file_info['modifiedTime'].replace('Z', '+00:00')),
                'owner': file_info['owners'][0]['displayName'] if file_info.get('owners') else 'Unknown',
                'size': file_info.get('size', 0),
                'category': category
            })
        
        # Store document analytics
        store_document_data(document_data)
        
        # Generate organization insights
        insights = generate_organization_insights(document_data)
        
        return {
            'status': 'success',
            'documents_processed': len(document_data),
            'insights': insights
        }
        
    except Exception as e:
        logging.error(f"Error organizing documents: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def categorize_document(filename, mime_type):
    """Categorize document based on name and type"""
    filename_lower = filename.lower()
    
    # Document type categories
    if 'application/vnd.google-apps.spreadsheet' in mime_type or '.xlsx' in filename_lower:
        return 'spreadsheet'
    elif 'application/vnd.google-apps.document' in mime_type or '.docx' in filename_lower:
        return 'document'
    elif 'application/vnd.google-apps.presentation' in mime_type or '.pptx' in filename_lower:
        return 'presentation'
    elif 'application/pdf' in mime_type:
        return 'pdf'
    elif 'image/' in mime_type:
        return 'image'
    
    # Content-based categories
    if any(word in filename_lower for word in ['report', 'analysis', 'metrics']):
        return 'report'
    elif any(word in filename_lower for word in ['proposal', 'contract', 'agreement']):
        return 'business'
    elif any(word in filename_lower for word in ['template', 'form']):
        return 'template'
    else:
        return 'general'

def generate_organization_insights(document_data):
    """Generate insights about document organization"""
    total_docs = len(document_data)
    
    # Category distribution
    categories = {}
    for doc in document_data:
        categories[doc['category']] = categories.get(doc['category'], 0) + 1
    
    # Recent activity (last 7 days)
    recent_threshold = datetime.now(timezone.utc) - timedelta(days=7)
    recent_docs = [doc for doc in document_data if doc['modified_time'] > recent_threshold]
    
    return {
        'total_documents': total_docs,
        'categories': categories,
        'recent_activity': len(recent_docs),
        'most_active_category': max(categories, key=categories.get) if categories else 'none'
    }

def store_document_data(document_data):
    """Store document analytics in Cloud SQL"""
    connector = Connector()
    
    def getconn():
        conn = connector.connect(
            os.environ['INSTANCE_CONNECTION_NAME'],
            "pg8000",
            user="postgres",
            password=os.environ['DB_PASSWORD'],
            db=os.environ['DATABASE_NAME']
        )
        return conn
    
    with getconn() as conn:
        with conn.cursor() as cursor:
            # Create table if not exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS document_analytics (
                    id SERIAL PRIMARY KEY,
                    file_id VARCHAR(255) UNIQUE,
                    name TEXT,
                    mime_type VARCHAR(255),
                    created_time TIMESTAMP,
                    modified_time TIMESTAMP,
                    owner VARCHAR(255),
                    size_bytes BIGINT,
                    category VARCHAR(50),
                    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Insert document data
            for doc in document_data:
                cursor.execute("""
                    INSERT INTO document_analytics 
                    (file_id, name, mime_type, created_time, modified_time, owner, size_bytes, category)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (file_id) DO UPDATE SET
                        modified_time = EXCLUDED.modified_time,
                        size_bytes = EXCLUDED.size_bytes,
                        category = EXCLUDED.category
                """, (
                    doc['file_id'],
                    doc['name'],
                    doc['mime_type'],
                    doc['created_time'],
                    doc['modified_time'],
                    doc['owner'],
                    int(doc['size']),
                    doc['category']
                ))
            
        conn.commit()
EOF
    
    # Copy credentials
    cp ../credentials.json .
    
    # Deploy function
    gcloud functions deploy "${FUNCTION_PREFIX}-document-organization" \
        --gen2 \
        --runtime=python311 \
        --source=. \
        --entry-point=organize_documents \
        --trigger=http \
        --region="${REGION}" \
        --service-account="workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="INSTANCE_CONNECTION_NAME=${PROJECT_ID}:${REGION}:${INSTANCE_NAME},DB_PASSWORD=${DB_PASSWORD},DATABASE_NAME=${DATABASE_NAME}" \
        --allow-unauthenticated
    
    cd ..
    log_success "Document organization function deployed"
}

# Function to deploy productivity metrics function
deploy_productivity_metrics() {
    log_info "Deploying productivity metrics function..."
    
    local function_dir="productivity-metrics"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Copy requirements.txt
    cp ../email-processor/requirements.txt .
    
    # Create main.py with productivity metrics logic
    cat > main.py << 'EOF'
import json
import logging
from datetime import datetime, timedelta, timezone
from google.oauth2 import service_account
from google.cloud.sql.connector import Connector
import os

def calculate_productivity_metrics(request):
    """Calculate comprehensive productivity metrics from all data sources"""
    try:
        # Connect to database
        connector = Connector()
        
        def getconn():
            conn = connector.connect(
                os.environ['INSTANCE_CONNECTION_NAME'],
                "pg8000",
                user="postgres",
                password=os.environ['DB_PASSWORD'],
                db=os.environ['DATABASE_NAME']
            )
            return conn
        
        with getconn() as conn:
            with conn.cursor() as cursor:
                # Calculate email metrics
                email_metrics = calculate_email_metrics(cursor)
                
                # Calculate meeting metrics
                meeting_metrics = calculate_meeting_metrics(cursor)
                
                # Calculate document metrics
                document_metrics = calculate_document_metrics(cursor)
                
                # Generate overall productivity score
                productivity_score = calculate_productivity_score(
                    email_metrics, meeting_metrics, document_metrics
                )
                
                # Store comprehensive metrics
                store_productivity_metrics(cursor, {
                    'email_metrics': email_metrics,
                    'meeting_metrics': meeting_metrics,
                    'document_metrics': document_metrics,
                    'productivity_score': productivity_score,
                    'generated_at': datetime.now(timezone.utc)
                })
                
                conn.commit()
        
        return {
            'status': 'success',
            'email_metrics': email_metrics,
            'meeting_metrics': meeting_metrics,
            'document_metrics': document_metrics,
            'productivity_score': productivity_score
        }
        
    except Exception as e:
        logging.error(f"Error calculating metrics: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def calculate_email_metrics(cursor):
    """Calculate email-based productivity metrics"""
    # Email volume trends
    cursor.execute("""
        SELECT 
            DATE_TRUNC('day', date_received) as date,
            COUNT(*) as email_count,
            COUNT(CASE WHEN category = 'urgent' THEN 1 END) as urgent_count
        FROM email_analytics 
        WHERE date_received >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY DATE_TRUNC('day', date_received)
        ORDER BY date
    """)
    daily_emails = cursor.fetchall()
    
    # Response time analysis
    cursor.execute("""
        SELECT 
            category,
            COUNT(*) as count,
            AVG(EXTRACT(EPOCH FROM (processed_at - date_received))/3600) as avg_response_hours
        FROM email_analytics 
        WHERE date_received >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY category
    """)
    response_times = cursor.fetchall()
    
    return {
        'daily_volume': [{'date': str(row[0]), 'count': row[1], 'urgent': row[2]} for row in daily_emails],
        'response_analysis': [{'category': row[0], 'count': row[1], 'avg_hours': float(row[2] or 0)} for row in response_times],
        'total_emails_week': sum(row[1] for row in daily_emails)
    }

def calculate_meeting_metrics(cursor):
    """Calculate meeting-based productivity metrics"""
    # Meeting efficiency metrics
    cursor.execute("""
        SELECT 
            DATE_TRUNC('day', start_time) as date,
            COUNT(*) as meeting_count,
            SUM(duration_minutes) as total_minutes,
            AVG(duration_minutes) as avg_duration,
            AVG(attendees) as avg_attendees
        FROM meeting_analytics 
        WHERE start_time >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY DATE_TRUNC('day', start_time)
        ORDER BY date
    """)
    daily_meetings = cursor.fetchall()
    
    # Meeting patterns
    cursor.execute("""
        SELECT 
            EXTRACT(HOUR FROM start_time) as hour,
            COUNT(*) as meeting_count,
            AVG(duration_minutes) as avg_duration
        FROM meeting_analytics 
        WHERE start_time >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY EXTRACT(HOUR FROM start_time)
        ORDER BY hour
    """)
    hourly_patterns = cursor.fetchall()
    
    return {
        'daily_meetings': [{'date': str(row[0]), 'count': row[1], 'total_minutes': row[2], 'avg_duration': float(row[3] or 0)} for row in daily_meetings],
        'hourly_patterns': [{'hour': int(row[0]), 'count': row[1], 'avg_duration': float(row[2] or 0)} for row in hourly_patterns],
        'total_meeting_time_week': sum(row[2] or 0 for row in daily_meetings)
    }

def calculate_document_metrics(cursor):
    """Calculate document-based productivity metrics"""
    # Document activity metrics
    cursor.execute("""
        SELECT 
            category,
            COUNT(*) as total_docs,
            COUNT(CASE WHEN modified_time >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as recent_activity,
            AVG(size_bytes) as avg_size
        FROM document_analytics 
        GROUP BY category
    """)
    category_stats = cursor.fetchall()
    
    # Collaboration metrics
    cursor.execute("""
        SELECT 
            owner,
            COUNT(*) as documents_owned,
            COUNT(CASE WHEN modified_time >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as recent_updates
        FROM document_analytics 
        GROUP BY owner
        ORDER BY documents_owned DESC
        LIMIT 10
    """)
    collaboration_stats = cursor.fetchall()
    
    return {
        'category_breakdown': [{'category': row[0], 'total': row[1], 'recent': row[2], 'avg_size': float(row[3] or 0)} for row in category_stats],
        'collaboration_leaders': [{'owner': row[0], 'documents': row[1], 'recent_updates': row[2]} for row in collaboration_stats]
    }

def calculate_productivity_score(email_metrics, meeting_metrics, document_metrics):
    """Calculate overall productivity score (0-100)"""
    # Simple scoring algorithm
    score = 50  # Base score
    
    # Email responsiveness factor
    total_emails = email_metrics.get('total_emails_week', 0)
    if total_emails > 0:
        urgent_emails = sum(day.get('urgent', 0) for day in email_metrics.get('daily_volume', []))
        email_score = min(25, (1 - urgent_emails / total_emails) * 25)
        score += email_score
    
    # Meeting efficiency factor
    total_meeting_time = meeting_metrics.get('total_meeting_time_week', 0)
    if total_meeting_time > 0:
        # Optimal meeting time per week: 10-15 hours
        optimal_range = (600, 900)  # minutes
        if optimal_range[0] <= total_meeting_time <= optimal_range[1]:
            meeting_score = 25
        else:
            meeting_score = max(0, 25 - abs(total_meeting_time - 750) / 30)
        score += meeting_score
    
    # Document collaboration factor
    if document_metrics.get('collaboration_leaders'):
        active_contributors = len(document_metrics['collaboration_leaders'])
        collaboration_score = min(25, active_contributors * 5)
        score += collaboration_score
    
    return min(100, max(0, int(score)))

def store_productivity_metrics(cursor, metrics_data):
    """Store comprehensive productivity metrics"""
    # Create metrics table if not exists
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS productivity_metrics (
            id SERIAL PRIMARY KEY,
            email_metrics JSONB,
            meeting_metrics JSONB,
            document_metrics JSONB,
            productivity_score INTEGER,
            generated_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Insert metrics
    cursor.execute("""
        INSERT INTO productivity_metrics 
        (email_metrics, meeting_metrics, document_metrics, productivity_score, generated_at)
        VALUES (%s, %s, %s, %s, %s)
    """, (
        json.dumps(metrics_data['email_metrics']),
        json.dumps(metrics_data['meeting_metrics']),
        json.dumps(metrics_data['document_metrics']),
        metrics_data['productivity_score'],
        metrics_data['generated_at']
    ))
EOF
    
    # Copy credentials
    cp ../credentials.json .
    
    # Deploy function
    gcloud functions deploy "${FUNCTION_PREFIX}-productivity-metrics" \
        --gen2 \
        --runtime=python311 \
        --source=. \
        --entry-point=calculate_productivity_metrics \
        --trigger=http \
        --region="${REGION}" \
        --service-account="workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="INSTANCE_CONNECTION_NAME=${PROJECT_ID}:${REGION}:${INSTANCE_NAME},DB_PASSWORD=${DB_PASSWORD},DATABASE_NAME=${DATABASE_NAME}" \
        --timeout=300s \
        --memory=512MB \
        --allow-unauthenticated
    
    cd ..
    log_success "Productivity metrics function deployed"
}

# Function to configure Cloud Scheduler
configure_scheduler() {
    log_info "Configuring Cloud Scheduler for automated workflows..."
    
    # Create scheduler jobs for automated workflow execution
    
    # Email processing - every 2 hours during business hours
    if ! gcloud scheduler jobs describe email-processing-job >/dev/null 2>&1; then
        gcloud scheduler jobs create http email-processing-job \
            --schedule="0 */2 9-17 * * MON-FRI" \
            --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-email-processor" \
            --http-method=GET \
            --time-zone="America/New_York" \
            --description="Process emails every 2 hours during business hours"
    else
        log_warning "Scheduler job email-processing-job already exists"
    fi
    
    # Meeting automation - daily at 8 AM
    if ! gcloud scheduler jobs describe meeting-automation-job >/dev/null 2>&1; then
        gcloud scheduler jobs create http meeting-automation-job \
            --schedule="0 8 * * MON-FRI" \
            --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-meeting-automation" \
            --http-method=GET \
            --time-zone="America/New_York" \
            --description="Analyze meetings and suggest optimal times daily"
    else
        log_warning "Scheduler job meeting-automation-job already exists"
    fi
    
    # Document organization - every 4 hours
    if ! gcloud scheduler jobs describe document-organization-job >/dev/null 2>&1; then
        gcloud scheduler jobs create http document-organization-job \
            --schedule="0 */4 * * *" \
            --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-document-organization" \
            --http-method=GET \
            --time-zone="America/New_York" \
            --description="Organize and analyze documents every 4 hours"
    else
        log_warning "Scheduler job document-organization-job already exists"
    fi
    
    # Productivity metrics - daily at 6 PM
    if ! gcloud scheduler jobs describe productivity-metrics-job >/dev/null 2>&1; then
        gcloud scheduler jobs create http productivity-metrics-job \
            --schedule="0 18 * * MON-FRI" \
            --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-productivity-metrics" \
            --http-method=GET \
            --time-zone="America/New_York" \
            --description="Calculate daily productivity metrics"
    else
        log_warning "Scheduler job productivity-metrics-job already exists"
    fi
    
    log_success "Cloud Scheduler jobs configured for automated workflows"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Cloud SQL instance
    local sql_state=$(gcloud sql instances describe "${INSTANCE_NAME}" --format="value(state)" 2>/dev/null)
    if [[ "${sql_state}" == "RUNNABLE" ]]; then
        log_success "Cloud SQL instance is running"
    else
        log_error "Cloud SQL instance is not in RUNNABLE state: ${sql_state}"
        return 1
    fi
    
    # Check Cloud Functions
    local functions=(
        "${FUNCTION_PREFIX}-email-processor"
        "${FUNCTION_PREFIX}-meeting-automation"
        "${FUNCTION_PREFIX}-document-organization"
        "${FUNCTION_PREFIX}-productivity-metrics"
    )
    
    for func in "${functions[@]}"; do
        local func_state=$(gcloud functions describe "${func}" --region="${REGION}" --format="value(status)" 2>/dev/null)
        if [[ "${func_state}" == "ACTIVE" ]]; then
            log_success "Function ${func} is active"
        else
            log_error "Function ${func} is not active: ${func_state}"
            return 1
        fi
    done
    
    # Check Cloud Scheduler jobs
    local jobs=(
        "email-processing-job"
        "meeting-automation-job"
        "document-organization-job"
        "productivity-metrics-job"
    )
    
    for job in "${jobs[@]}"; do
        local job_state=$(gcloud scheduler jobs describe "${job}" --format="value(state)" 2>/dev/null)
        if [[ "${job_state}" == "ENABLED" ]]; then
            log_success "Scheduler job ${job} is enabled"
        else
            log_error "Scheduler job ${job} is not enabled: ${job_state}"
            return 1
        fi
    done
    
    log_success "Deployment validation completed successfully"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment_info.json << EOF
{
    "project_id": "${PROJECT_ID}",
    "region": "${REGION}",
    "zone": "${ZONE}",
    "database_instance": "${INSTANCE_NAME}",
    "database_name": "${DATABASE_NAME}",
    "function_prefix": "${FUNCTION_PREFIX}",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "cloud_functions": [
        "${FUNCTION_PREFIX}-email-processor",
        "${FUNCTION_PREFIX}-meeting-automation",
        "${FUNCTION_PREFIX}-document-organization",
        "${FUNCTION_PREFIX}-productivity-metrics"
    ],
    "scheduler_jobs": [
        "email-processing-job",
        "meeting-automation-job",
        "document-organization-job",
        "productivity-metrics-job"
    ]
}
EOF
    
    log_success "Deployment information saved to deployment_info.json"
}

# Main deployment function
main() {
    log_info "Starting Business Productivity Workflows deployment..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup environment
    setup_environment
    
    # Configure gcloud
    configure_gcloud
    
    # Enable APIs
    enable_apis
    
    # Create Cloud SQL database
    create_cloud_sql
    
    # Setup service account
    setup_service_account
    
    # Deploy Cloud Functions
    deploy_cloud_functions
    
    # Configure scheduler
    configure_scheduler
    
    # Validate deployment
    validate_deployment
    
    # Save deployment info
    save_deployment_info
    
    log_success "🎉 Business Productivity Workflows deployment completed successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Configure Google Workspace API OAuth consent screen"
    log_info "2. Set up domain-wide delegation for the service account"
    log_info "3. Test the functions manually before relying on scheduled execution"
    log_info ""
    log_info "Function URLs:"
    echo "  - Email Processor: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-email-processor"
    echo "  - Meeting Automation: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-meeting-automation"
    echo "  - Document Organization: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-document-organization"
    echo "  - Productivity Metrics: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-productivity-metrics"
    log_info ""
    log_info "Use './destroy.sh' to clean up all resources when done"
}

# Run main function
main "$@"