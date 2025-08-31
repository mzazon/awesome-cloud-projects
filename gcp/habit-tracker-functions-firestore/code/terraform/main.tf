# Main Terraform configuration for Habit Tracker with Cloud Functions and Firestore
# This creates a serverless REST API for habit tracking using GCP managed services

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Combine function name with random suffix for uniqueness
  function_name_unique = "${var.function_name}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment_name
    created-by  = "terraform"
    recipe      = "habit-tracker-functions-firestore"
  })
  
  # Firestore collection name used by the application
  firestore_collection = "habits"
}

# Enable required Google Cloud APIs
# These APIs are necessary for Cloud Functions and Firestore functionality
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Keep services enabled even if this resource is deleted
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Firestore database in Native mode
# Native mode provides real-time updates, ACID transactions, and strong consistency
resource "google_firestore_database" "habit_tracker_db" {
  name        = "(default)"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  # Ensure APIs are enabled before creating the database
  depends_on = [google_project_service.required_apis]
  
  # Prevent accidental deletion of the database
  lifecycle {
    prevent_destroy = true
  }
}

# Create a Cloud Storage bucket for Cloud Function source code
# This stores the deployment package for the Cloud Function
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-${local.function_name_unique}-source"
  location = var.region
  
  # Apply common labels
  labels = local.common_labels
  
  # Configure lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      age = 30  # Delete objects older than 30 days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for source code history
  versioning {
    enabled = true
  }
  
  # Block public access for security
  public_access_prevention = "enforced"
  
  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code files
# This generates the Python code and requirements for the habit tracking API
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content = <<-EOF
import json
from datetime import datetime, timezone
from flask import Request
import functions_framework
from google.cloud import firestore

# Initialize Firestore client
db = firestore.Client()
COLLECTION_NAME = '${local.firestore_collection}'

@functions_framework.http
def habit_tracker(request: Request):
    """HTTP Cloud Function for habit tracking CRUD operations."""
    
    # Set CORS headers for web client compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        if request.method == 'POST':
            return create_habit(request, headers)
        elif request.method == 'GET':
            return get_habits(request, headers)
        elif request.method == 'PUT':
            return update_habit(request, headers)
        elif request.method == 'DELETE':
            return delete_habit(request, headers)
        else:
            return (json.dumps({'error': 'Method not allowed'}), 405, headers)
    
    except Exception as e:
        return (json.dumps({'error': str(e)}), 500, headers)

def create_habit(request: Request, headers):
    """Create a new habit record."""
    data = request.get_json()
    
    if not data or 'name' not in data:
        return (json.dumps({'error': 'Habit name is required'}), 400, headers)
    
    habit_data = {
        'name': data['name'],
        'description': data.get('description', ''),
        'completed': data.get('completed', False),
        'created_at': datetime.now(timezone.utc),
        'updated_at': datetime.now(timezone.utc)
    }
    
    # Create new document with auto-generated ID
    doc_ref, doc_id = db.collection(COLLECTION_NAME).add(habit_data)
    
    habit_data['id'] = doc_id.id
    habit_data['created_at'] = habit_data['created_at'].isoformat()
    habit_data['updated_at'] = habit_data['updated_at'].isoformat()
    
    return (json.dumps(habit_data), 201, headers)

def get_habits(request: Request, headers):
    """Retrieve all habit records or a specific habit by ID."""
    habit_id = request.args.get('id')
    
    if habit_id:
        # Get specific habit
        doc_ref = db.collection(COLLECTION_NAME).document(habit_id)
        doc = doc_ref.get()
        
        if not doc.exists:
            return (json.dumps({'error': 'Habit not found'}), 404, headers)
        
        habit = doc.to_dict()
        habit['id'] = doc.id
        habit['created_at'] = habit['created_at'].isoformat()
        habit['updated_at'] = habit['updated_at'].isoformat()
        
        return (json.dumps(habit), 200, headers)
    else:
        # Get all habits
        habits = []
        docs = db.collection(COLLECTION_NAME).order_by('created_at').stream()
        
        for doc in docs:
            habit = doc.to_dict()
            habit['id'] = doc.id
            habit['created_at'] = habit['created_at'].isoformat()
            habit['updated_at'] = habit['updated_at'].isoformat()
            habits.append(habit)
        
        return (json.dumps(habits), 200, headers)

def update_habit(request: Request, headers):
    """Update an existing habit record."""
    habit_id = request.args.get('id')
    
    if not habit_id:
        return (json.dumps({'error': 'Habit ID is required'}), 400, headers)
    
    data = request.get_json()
    if not data:
        return (json.dumps({'error': 'Request body is required'}), 400, headers)
    
    doc_ref = db.collection(COLLECTION_NAME).document(habit_id)
    doc = doc_ref.get()
    
    if not doc.exists:
        return (json.dumps({'error': 'Habit not found'}), 404, headers)
    
    # Update allowed fields
    update_data = {}
    if 'name' in data:
        update_data['name'] = data['name']
    if 'description' in data:
        update_data['description'] = data['description']
    if 'completed' in data:
        update_data['completed'] = data['completed']
    
    update_data['updated_at'] = datetime.now(timezone.utc)
    
    # Update the document
    doc_ref.update(update_data)
    
    # Return updated document
    updated_doc = doc_ref.get()
    habit = updated_doc.to_dict()
    habit['id'] = updated_doc.id
    habit['created_at'] = habit['created_at'].isoformat()
    habit['updated_at'] = habit['updated_at'].isoformat()
    
    return (json.dumps(habit), 200, headers)

def delete_habit(request: Request, headers):
    """Delete a habit record."""
    habit_id = request.args.get('id')
    
    if not habit_id:
        return (json.dumps({'error': 'Habit ID is required'}), 400, headers)
    
    doc_ref = db.collection(COLLECTION_NAME).document(habit_id)
    doc = doc_ref.get()
    
    if not doc.exists:
        return (json.dumps({'error': 'Habit not found'}), 404, headers)
    
    # Delete the document
    doc_ref.delete()
    
    return (json.dumps({'message': 'Habit deleted successfully'}), 200, headers)
EOF
}

# Create the requirements.txt file for Python dependencies
resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<-EOF
google-cloud-firestore==2.21.0
functions-framework==3.8.3
EOF
}

# Create a ZIP archive of the function source code
# This packages the Python code and dependencies for deployment
data "archive_file" "function_zip" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  
  source {
    content  = local_file.function_main.content
    filename = "main.py"
  }
  
  source {
    content  = local_file.function_requirements.content
    filename = "requirements.txt"
  }
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload the function source code to Cloud Storage
# This makes the code available for Cloud Functions deployment
resource "google_storage_bucket_object" "function_archive" {
  name   = "function-source-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_zip.output_path
  
  # Use MD5 hash to detect changes and trigger redeployment
  content_type = "application/zip"
  
  depends_on = [data.archive_file.function_zip]
}

# Create the Cloud Function for habit tracking API
# This deploys a serverless HTTP endpoint with automatic scaling
resource "google_cloudfunctions_function" "habit_tracker" {
  name        = local.function_name_unique
  description = "Serverless REST API for habit tracking with Firestore backend"
  region      = var.region
  
  # Configure function runtime and resource allocation
  runtime               = "python312"
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "habit_tracker"
  max_instances        = 10  # Limit concurrent instances to control costs
  
  # Configure source code location
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  
  # Configure HTTP trigger for REST API access
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"  # Force HTTPS
    }
  }
  
  # Apply labels for resource management
  labels = local.common_labels
  
  # Set environment variables for the function
  environment_variables = {
    FIRESTORE_COLLECTION = local.firestore_collection
    GCP_PROJECT         = var.project_id
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.habit_tracker_db,
    google_storage_bucket_object.function_archive
  ]
}

# Configure IAM policy for the Cloud Function
# This allows unauthenticated access if specified in variables
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.habit_tracker.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create a service account for the Cloud Function (optional enhancement)
# This provides a dedicated identity for the function with minimal permissions
resource "google_service_account" "function_sa" {
  account_id   = "${local.function_name_unique}-sa"
  display_name = "Service Account for ${local.function_name_unique}"
  description  = "Service account used by the habit tracker Cloud Function"
}

# Grant the service account access to Firestore
# This follows the principle of least privilege
resource "google_project_iam_member" "function_firestore_access" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Firestore security rules (as a local file for reference)
# Note: Terraform doesn't directly support Firestore security rules deployment
resource "local_file" "firestore_rules" {
  filename = "${path.module}/firestore.rules"
  content = <<-EOF
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write access to habits collection
    // In production, add proper authentication rules
    match /${local.firestore_collection}/{document=**} {
      allow read, write: if true;  // Replace with proper auth rules
    }
  }
}
EOF
}