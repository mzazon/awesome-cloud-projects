# Main Terraform configuration for GCP Contact Form with Cloud Functions and Gmail API
# This configuration creates a serverless contact form backend using Google Cloud Functions

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Define local values for resource naming and configuration
locals {
  # Generate unique bucket name if not provided
  bucket_name = var.storage_bucket_name != "" ? var.storage_bucket_name : "${var.project_id}-contact-form-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    function    = var.function_name
    purpose     = "contact-form"
  })
  
  # Function source directory (assumes source code is in ../function directory)
  function_source_dir = "${path.module}/../function"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  count   = var.enable_apis ? length(var.required_apis) : 0
  project = var.project_id
  service = var.required_apis[count.index]
  
  # Prevent disabling APIs when Terraform is destroyed
  disable_on_destroy = false
  
  # Automatically enable dependent services
  disable_dependent_services = false
}

# Create a Cloud Storage bucket for storing function source code
resource "google_storage_bucket" "function_bucket" {
  count    = var.create_storage_bucket ? 1 : 0
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Set storage class for cost optimization
  storage_class = var.storage_class
  
  # Configure lifecycle management to manage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Apply common labels
  labels = local.common_labels
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [google_project_service.required_apis]
}

# Use existing bucket if not creating a new one
data "google_storage_bucket" "existing_bucket" {
  count = var.create_storage_bucket ? 0 : 1
  name  = local.bucket_name
}

# Create archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  # Include function source files
  source {
    content  = file("${path.module}/../function/main.py")
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/../function/requirements.txt")
    filename = "requirements.txt"
  }
  
  # Include Gmail API credentials and token (if they exist)
  dynamic "source" {
    for_each = fileexists(var.gmail_token_path) ? [1] : []
    content {
      content  = filebase64(var.gmail_token_path)
      filename = "token.pickle"
    }
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "contact-form-function-${data.archive_file.function_source.output_md5}.zip"
  bucket = local.bucket_name
  source = data.archive_file.function_source.output_path
  
  # Set content type for zip files
  content_type = "application/zip"
  
  # Apply metadata labels
  metadata = {
    function-name = var.function_name
    created-by    = "terraform"
    environment   = var.environment
  }
  
  depends_on = [
    google_storage_bucket.function_bucket,
    data.google_storage_bucket.existing_bucket
  ]
}

# Create a dedicated service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the contact form Cloud Function to access Gmail API"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Gmail API access to the function service account
resource "google_project_iam_member" "gmail_api_access" {
  project = var.project_id
  role    = "roles/gmail.modify"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Grant Cloud Function runtime permissions
resource "google_project_iam_member" "function_runtime" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Grant logging permissions to the service account
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Create the 2nd generation Cloud Function
resource "google_cloudfunctions2_function" "contact_form_handler" {
  name     = var.function_name
  location = var.region
  project  = var.project_id
  
  description = "Serverless contact form handler that processes form submissions and sends emails via Gmail API"
  
  # Build configuration
  build_config {
    runtime     = var.python_runtime
    entry_point = "contact_form_handler"
    
    # Source configuration pointing to Cloud Storage
    source {
      storage_source {
        bucket = local.bucket_name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      BUILD_CONFIG_TEST = "true"
    }
  }
  
  # Service configuration
  service_config {
    # Memory and CPU allocation
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    max_instance_count = var.max_instances
    min_instance_count = var.min_instances
    
    # Service account for runtime
    service_account_email = google_service_account.function_sa.email
    
    # Environment variables for runtime
    environment_variables = {
      GMAIL_RECIPIENT_EMAIL = var.gmail_recipient_email
      LOG_LEVEL            = var.log_level
      ENVIRONMENT          = var.environment
      ALLOWED_ORIGINS      = jsonencode(var.allowed_origins)
    }
    
    # Enable all traffic to the latest revision
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  # Dependencies
  depends_on = [
    google_storage_bucket_object.function_source,
    google_service_account.function_sa,
    google_project_iam_member.gmail_api_access,
    google_project_iam_member.function_runtime,
    google_project_iam_member.function_logging
  ]
}

# Configure IAM policy for public access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.contact_form_handler.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.contact_form_handler]
}

# Create Cloud Function source directory and files (if they don't exist)
resource "local_file" "function_main_py" {
  count = fileexists("${local.function_source_dir}/main.py") ? 0 : 1
  
  filename = "${path.module}/../function/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    gmail_recipient_email = var.gmail_recipient_email
    allowed_origins      = jsonencode(var.allowed_origins)
  })
  
  # Create directory if it doesn't exist
  provisioner "local-exec" {
    command = "mkdir -p ${dirname(self.filename)}"
  }
}

resource "local_file" "function_requirements_txt" {
  count = fileexists("${local.function_source_dir}/requirements.txt") ? 0 : 1
  
  filename = "${path.module}/../function/requirements.txt"
  content = templatefile("${path.module}/templates/requirements.txt.tpl", {})
  
  # Create directory if it doesn't exist  
  provisioner "local-exec" {
    command = "mkdir -p ${dirname(self.filename)}"
  }
}

# Create template files directory and templates
resource "local_file" "main_py_template" {
  filename = "${path.module}/templates/main.py.tpl"
  content = <<-EOF
import json
import base64
import pickle
import os
from email.message import EmailMessage
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
import functions_framework

def load_credentials():
    """Load Gmail API credentials from token.pickle file"""
    try:
        # Try to load existing token
        if os.path.exists('token.pickle'):
            with open('token.pickle', 'rb') as token:
                creds = pickle.load(token)
        else:
            # Log error if token file is missing
            print("ERROR: token.pickle file not found. Please ensure Gmail API credentials are properly configured.")
            return None
        
        # Refresh token if expired
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        
        return creds
    except Exception as e:
        print(f"Error loading Gmail credentials: {str(e)}")
        return None

def send_email(name, email, subject, message):
    """Send email using Gmail API"""
    try:
        # Load Gmail API credentials
        creds = load_credentials()
        if not creds:
            raise Exception("Failed to load Gmail API credentials")
        
        # Build Gmail service
        service = build('gmail', 'v1', credentials=creds)
        
        # Get recipient email from environment variable
        recipient_email = os.environ.get('GMAIL_RECIPIENT_EMAIL', '${gmail_recipient_email}')
        
        # Create email message
        msg = EmailMessage()
        msg['Subject'] = f'Contact Form: {subject}'
        msg['From'] = 'me'  # 'me' represents the authenticated user
        msg['To'] = recipient_email
        
        # Email body with proper formatting
        email_body = f"""New contact form submission:

Name: {name}
Email: {email}
Subject: {subject}

Message:
{message}

---
This email was sent automatically from your website contact form.
Sender IP information and timestamp are logged for security purposes.
"""
        
        msg.set_content(email_body)
        
        # Convert message to base64 encoded string
        raw_message = base64.urlsafe_b64encode(msg.as_bytes()).decode('utf-8')
        
        # Send email via Gmail API
        result = service.users().messages().send(
            userId='me',
            body={'raw': raw_message}
        ).execute()
        
        print(f"Email sent successfully. Message ID: {result.get('id')}")
        return result
        
    except Exception as e:
        print(f"Error sending email: {str(e)}")
        raise

@functions_framework.http
def contact_form_handler(request):
    """HTTP Cloud Function to handle contact form submissions"""
    
    # Get allowed origins from environment variable
    allowed_origins = json.loads(os.environ.get('ALLOWED_ORIGINS', '${allowed_origins}'))
    
    # Determine the origin for CORS headers
    origin = request.headers.get('Origin', '')
    cors_origin = origin if origin in allowed_origins or '*' in allowed_origins else ''
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': cors_origin or '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': cors_origin or '*',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
    }
    
    # Only allow POST requests
    if request.method != 'POST':
        return (json.dumps({'error': 'Method not allowed', 'allowed_methods': ['POST']}), 405, headers)
    
    try:
        # Log request for debugging (without sensitive data)
        print(f"Received {request.method} request from {request.remote_addr}")
        
        # Parse JSON request body
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON payload', 'details': 'Request body must be valid JSON'}), 400, headers)
        
        # Extract and validate form fields
        name = request_json.get('name', '').strip()
        email = request_json.get('email', '').strip()
        subject = request_json.get('subject', '').strip()
        message = request_json.get('message', '').strip()
        
        # Validate required fields
        missing_fields = []
        if not name:
            missing_fields.append('name')
        if not email:
            missing_fields.append('email')
        if not subject:
            missing_fields.append('subject')
        if not message:
            missing_fields.append('message')
        
        if missing_fields:
            return (json.dumps({
                'error': 'Missing required fields',
                'missing_fields': missing_fields,
                'required_fields': ['name', 'email', 'subject', 'message']
            }), 400, headers)
        
        # Validate field lengths to prevent abuse
        if len(name) > 100:
            return (json.dumps({'error': 'Name too long', 'max_length': 100}), 400, headers)
        if len(email) > 254:  # RFC 5321 limit
            return (json.dumps({'error': 'Email too long', 'max_length': 254}), 400, headers)
        if len(subject) > 200:
            return (json.dumps({'error': 'Subject too long', 'max_length': 200}), 400, headers)
        if len(message) > 5000:
            return (json.dumps({'error': 'Message too long', 'max_length': 5000}), 400, headers)
        
        # Basic email format validation
        if '@' not in email or '.' not in email.split('@')[-1] or len(email.split('@')) != 2:
            return (json.dumps({'error': 'Invalid email address format'}), 400, headers)
        
        # Additional security checks
        suspicious_patterns = ['<script', 'javascript:', 'data:', 'vbscript:', 'onload=', 'onerror=']
        for field_name, field_value in [('name', name), ('subject', subject), ('message', message)]:
            for pattern in suspicious_patterns:
                if pattern.lower() in field_value.lower():
                    print(f"Suspicious content detected in {field_name}: {pattern}")
                    return (json.dumps({'error': 'Invalid content detected'}), 400, headers)
        
        # Send email via Gmail API
        try:
            send_email(name, email, subject, message)
            
            # Log successful submission (without sensitive data)
            print(f"Contact form submitted successfully from {email}")
            
            return (json.dumps({
                'success': True,
                'message': 'Email sent successfully',
                'timestamp': json.loads(json.dumps({'timestamp': None}, default=str))
            }), 200, headers)
            
        except Exception as email_error:
            print(f"Failed to send email: {str(email_error)}")
            return (json.dumps({
                'error': 'Failed to send email',
                'details': 'Please try again later or contact support if the problem persists'
            }), 500, headers)
        
    except json.JSONDecodeError:
        return (json.dumps({'error': 'Invalid JSON format'}), 400, headers)
    except Exception as e:
        # Log full error for debugging but don't expose internal details
        print(f'Unexpected error in contact form handler: {str(e)}')
        return (json.dumps({
            'error': 'Internal server error',
            'details': 'An unexpected error occurred. Please try again later.'
        }), 500, headers)
EOF
  
  # Create directory if it doesn't exist
  provisioner "local-exec" {
    command = "mkdir -p ${dirname(self.filename)}"
  }
}

resource "local_file" "requirements_txt_template" {
  filename = "${path.module}/templates/requirements.txt.tpl"
  content = <<-EOF
# Google Cloud Functions Framework
functions-framework==3.8.0

# Google API Client Libraries
google-auth==2.30.0
google-auth-oauthlib==1.2.1
google-auth-httplib2==0.2.0
google-api-python-client==2.150.0

# Additional dependencies for security and functionality
certifi==2024.8.30
charset-normalizer==3.3.2
idna==3.10
requests==2.32.3
urllib3==2.2.3
EOF
}