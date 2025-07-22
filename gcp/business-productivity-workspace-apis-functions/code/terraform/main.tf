# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Generate unique resource names
  name_prefix = var.resource_prefix != "" ? "${var.resource_prefix}-" : ""
  name_suffix = "-${random_id.suffix.hex}"
  
  # Resource names
  instance_name = "${local.name_prefix}productivity-instance${local.name_suffix}"
  function_prefix = "${local.name_prefix}productivity${local.name_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    solution    = "workspace-productivity-automation"
  })
  
  # Function configuration
  function_source_dir = "${path.module}/function_code"
}

#==============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
#==============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com", 
    "sqladmin.googleapis.com",
    "gmail.googleapis.com",
    "calendar.googleapis.com",
    "drive.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Disable the service on destroy
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

#==============================================================================
# SERVICE ACCOUNT FOR WORKSPACE API ACCESS
#==============================================================================

# Service account for Google Workspace API access
resource "google_service_account" "workspace_automation" {
  account_id   = "${local.name_prefix}workspace-automation${local.name_suffix}"
  display_name = "Workspace Automation Service Account"
  description  = "Service account for Google Workspace API integration and Cloud SQL access"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "workspace_automation_roles" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workspace_automation.email}"
  
  depends_on = [google_service_account.workspace_automation]
}

# Generate service account key for function authentication
resource "google_service_account_key" "workspace_automation_key" {
  service_account_id = google_service_account.workspace_automation.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

#==============================================================================
# CLOUD SQL DATABASE INSTANCE
#==============================================================================

# Generate random password for Cloud SQL
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Cloud SQL PostgreSQL instance for productivity analytics
resource "google_sql_database_instance" "productivity_instance" {
  name             = local.instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id
  
  # Prevent accidental deletion
  deletion_protection = false
  
  settings {
    tier                        = var.db_instance_tier
    availability_type          = "ZONAL"
    disk_type                  = "PD_SSD"
    disk_size                  = var.db_storage_size
    disk_autoresize            = true
    disk_autoresize_limit      = var.db_storage_size * 2
    
    # Backup configuration
    backup_configuration {
      enabled                        = var.enable_backup
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration
    ip_configuration {
      ipv4_enabled    = !var.enable_private_ip
      private_network = var.enable_private_ip ? "projects/${var.project_id}/global/networks/default" : null
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    # Database flags for performance
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
    
    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM
      update_track = "stable"
    }
    
    user_labels = local.common_labels
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create the productivity database
resource "google_sql_database" "productivity_db" {
  name     = var.database_name
  instance = google_sql_database_instance.productivity_instance.name
  project  = var.project_id
}

# Set the root user password
resource "google_sql_user" "postgres_user" {
  name     = "postgres"
  instance = google_sql_database_instance.productivity_instance.name
  password = random_password.db_password.result
  project  = var.project_id
}

#==============================================================================
# CLOUD STORAGE BUCKET FOR FUNCTION SOURCE CODE
#==============================================================================

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.name_prefix}function-source${local.name_suffix}"
  location      = var.region
  project       = var.project_id
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

#==============================================================================
# CLOUD FUNCTION SOURCE CODE PREPARATION
#==============================================================================

# Create function source code directory structure
resource "local_file" "requirements_txt" {
  filename = "${local.function_source_dir}/requirements.txt"
  content = <<-EOF
google-auth==2.23.4
google-auth-oauthlib==1.1.0
google-api-python-client==2.108.0
google-cloud-sql-connector==1.4.3
pg8000==1.30.3
functions-framework==3.5.0
EOF
}

# Email processing function
resource "local_file" "email_processor" {
  filename = "${local.function_source_dir}/email_processor/main.py"
  content = <<-EOF
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
        credentials = service_account.Credentials.from_service_account_info(
            json.loads(os.environ['SERVICE_ACCOUNT_JSON']),
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
}

# Meeting automation function
resource "local_file" "meeting_automation" {
  filename = "${local.function_source_dir}/meeting_automation/main.py"
  content = <<-EOF
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
        credentials = service_account.Credentials.from_service_account_info(
            json.loads(os.environ['SERVICE_ACCOUNT_JSON']),
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
}

# Document organization function
resource "local_file" "document_organization" {
  filename = "${local.function_source_dir}/document_organization/main.py"
  content = <<-EOF
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
        credentials = service_account.Credentials.from_service_account_info(
            json.loads(os.environ['SERVICE_ACCOUNT_JSON']),
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
}

# Productivity metrics function
resource "local_file" "productivity_metrics" {
  filename = "${local.function_source_dir}/productivity_metrics/main.py"
  content = <<-EOF
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
}

# Archive source code for each function
data "archive_file" "email_processor_zip" {
  type        = "zip"
  output_path = "${local.function_source_dir}/email_processor.zip"
  source_dir  = "${local.function_source_dir}/email_processor"
  
  depends_on = [
    local_file.email_processor,
    local_file.requirements_txt
  ]
}

data "archive_file" "meeting_automation_zip" {
  type        = "zip"
  output_path = "${local.function_source_dir}/meeting_automation.zip"
  source_dir  = "${local.function_source_dir}/meeting_automation"
  
  depends_on = [
    local_file.meeting_automation,
    local_file.requirements_txt
  ]
}

data "archive_file" "document_organization_zip" {
  type        = "zip"
  output_path = "${local.function_source_dir}/document_organization.zip"
  source_dir  = "${local.function_source_dir}/document_organization"
  
  depends_on = [
    local_file.document_organization,
    local_file.requirements_txt
  ]
}

data "archive_file" "productivity_metrics_zip" {
  type        = "zip"
  output_path = "${local.function_source_dir}/productivity_metrics.zip"
  source_dir  = "${local.function_source_dir}/productivity_metrics"
  
  depends_on = [
    local_file.productivity_metrics,
    local_file.requirements_txt
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "email_processor_source" {
  name   = "email_processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.email_processor_zip.output_path
}

resource "google_storage_bucket_object" "meeting_automation_source" {
  name   = "meeting_automation-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.meeting_automation_zip.output_path
}

resource "google_storage_bucket_object" "document_organization_source" {
  name   = "document_organization-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.document_organization_zip.output_path
}

resource "google_storage_bucket_object" "productivity_metrics_source" {
  name   = "productivity_metrics-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.productivity_metrics_zip.output_path
}

#==============================================================================
# CLOUD FUNCTIONS FOR WORKSPACE AUTOMATION
#==============================================================================

# Email Processing Cloud Function
resource "google_cloudfunctions2_function" "email_processor" {
  name        = "${local.function_prefix}-email-processor"
  location    = var.region
  project     = var.project_id
  description = "Process and analyze emails for productivity insights"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_emails"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.email_processor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.workspace_automation.email
    
    environment_variables = {
      INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${google_sql_database_instance.productivity_instance.name}"
      DB_PASSWORD             = random_password.db_password.result
      DATABASE_NAME           = var.database_name
      SERVICE_ACCOUNT_JSON    = base64decode(google_service_account_key.workspace_automation_key.private_key)
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.email_processor_source
  ]
}

# Meeting Automation Cloud Function
resource "google_cloudfunctions2_function" "meeting_automation" {
  name        = "${local.function_prefix}-meeting-automation"
  location    = var.region
  project     = var.project_id
  description = "Automate meeting scheduling and analysis"
  
  build_config {
    runtime     = "python311"
    entry_point = "automate_meetings"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.meeting_automation_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.workspace_automation.email
    
    environment_variables = {
      INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${google_sql_database_instance.productivity_instance.name}"
      DB_PASSWORD             = random_password.db_password.result
      DATABASE_NAME           = var.database_name
      SERVICE_ACCOUNT_JSON    = base64decode(google_service_account_key.workspace_automation_key.private_key)
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.meeting_automation_source
  ]
}

# Document Organization Cloud Function
resource "google_cloudfunctions2_function" "document_organization" {
  name        = "${local.function_prefix}-document-organization"
  location    = var.region
  project     = var.project_id
  description = "Organize and analyze Google Drive documents"
  
  build_config {
    runtime     = "python311"
    entry_point = "organize_documents"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.document_organization_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.workspace_automation.email
    
    environment_variables = {
      INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${google_sql_database_instance.productivity_instance.name}"
      DB_PASSWORD             = random_password.db_password.result
      DATABASE_NAME           = var.database_name
      SERVICE_ACCOUNT_JSON    = base64decode(google_service_account_key.workspace_automation_key.private_key)
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.document_organization_source
  ]
}

# Productivity Metrics Cloud Function
resource "google_cloudfunctions2_function" "productivity_metrics" {
  name        = "${local.function_prefix}-productivity-metrics"
  location    = var.region
  project     = var.project_id
  description = "Calculate comprehensive productivity metrics"
  
  build_config {
    runtime     = "python311"
    entry_point = "calculate_productivity_metrics"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.productivity_metrics_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.workspace_automation.email
    
    environment_variables = {
      INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${google_sql_database_instance.productivity_instance.name}"
      DB_PASSWORD             = random_password.db_password.result
      DATABASE_NAME           = var.database_name
      SERVICE_ACCOUNT_JSON    = base64decode(google_service_account_key.workspace_automation_key.private_key)
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.productivity_metrics_source
  ]
}

#==============================================================================
# CLOUD SCHEDULER JOBS FOR AUTOMATION WORKFLOWS
#==============================================================================

# Email processing job - every 2 hours during business hours
resource "google_cloud_scheduler_job" "email_processing" {
  count = var.enable_scheduler_jobs ? 1 : 0
  
  name        = "email-processing-job-${random_id.suffix.hex}"
  description = "Process emails every 2 hours during business hours"
  schedule    = "0 */2 9-17 * * MON-FRI"
  time_zone   = var.scheduler_timezone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.email_processor.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.workspace_automation.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.email_processor
  ]
}

# Meeting automation job - daily at 8 AM
resource "google_cloud_scheduler_job" "meeting_automation" {
  count = var.enable_scheduler_jobs ? 1 : 0
  
  name        = "meeting-automation-job-${random_id.suffix.hex}"
  description = "Analyze meetings and suggest optimal times daily"
  schedule    = "0 8 * * MON-FRI"
  time_zone   = var.scheduler_timezone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.meeting_automation.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.workspace_automation.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.meeting_automation
  ]
}

# Document organization job - every 4 hours
resource "google_cloud_scheduler_job" "document_organization" {
  count = var.enable_scheduler_jobs ? 1 : 0
  
  name        = "document-organization-job-${random_id.suffix.hex}"
  description = "Organize and analyze documents every 4 hours"
  schedule    = "0 */4 * * *"
  time_zone   = var.scheduler_timezone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.document_organization.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.workspace_automation.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.document_organization
  ]
}

# Productivity metrics job - daily at 6 PM
resource "google_cloud_scheduler_job" "productivity_metrics" {
  count = var.enable_scheduler_jobs ? 1 : 0
  
  name        = "productivity-metrics-job-${random_id.suffix.hex}"
  description = "Calculate daily productivity metrics"
  schedule    = "0 18 * * MON-FRI"
  time_zone   = var.scheduler_timezone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.productivity_metrics.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.workspace_automation.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.productivity_metrics
  ]
}

#==============================================================================
# MONITORING AND LOGGING CONFIGURATION
#==============================================================================

# Log sink for function logs
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "productivity-function-logs-${random_id.suffix.hex}"
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name=~"${local.function_prefix}.*"
  EOT
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant the log writer identity access to the bucket
resource "google_storage_bucket_iam_member" "log_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Productivity Function Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=~\"${local.function_prefix}.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}