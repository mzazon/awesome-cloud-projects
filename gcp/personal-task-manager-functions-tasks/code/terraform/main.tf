# Main Terraform configuration for GCP Personal Task Manager
# This configuration deploys a serverless Cloud Function that integrates with Google Tasks API
# to provide REST API endpoints for task management operations

# Generate random suffix for unique resource naming
# This prevents conflicts when multiple deployments exist in the same project
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent resource naming and configuration
locals {
  # Unique resource names using the random suffix
  function_name_unique = "${var.function_name}-${random_string.suffix.result}"
  sa_name_unique      = "${var.service_account_name}-${random_string.suffix.result}"
  bucket_name_unique  = "${var.project_id}-function-source-${random_string.suffix.result}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    function = var.function_name
    suffix   = random_string.suffix.result
  })
}

# Enable required Google Cloud APIs for the task manager functionality
# These APIs must be enabled before creating dependent resources
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",  # Cloud Functions API
    "cloudbuild.googleapis.com",      # Cloud Build API (for function deployment)
    "tasks.googleapis.com",           # Google Tasks API
    "iam.googleapis.com",             # Identity and Access Management API
    "cloudresourcemanager.googleapis.com" # Cloud Resource Manager API
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental API disabling during terraform destroy
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for the Cloud Function
# This service account will be used to authenticate with Google Tasks API
resource "google_service_account" "task_manager_sa" {
  account_id   = local.sa_name_unique
  display_name = var.service_account_display_name
  description  = "Service account for accessing Google Tasks API from Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create service account key for authentication
# This key will be packaged with the function code for API access
resource "google_service_account_key" "task_manager_key" {
  service_account_id = google_service_account.task_manager_sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

# Create Cloud Storage bucket for storing function source code
# Cloud Functions requires source code to be stored in Cloud Storage
resource "google_storage_bucket" "function_source" {
  name                        = local.bucket_name_unique
  location                    = var.region
  project                     = var.project_id
  storage_class               = "REGIONAL"
  uniform_bucket_level_access = true
  
  # Lifecycle management to clean up old source code versions
  lifecycle_rule {
    condition {
      age = 30  # Delete source code older than 30 days
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code archive
# This data source creates a zip file from the local source directory
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  # Include Python source files
  source {
    content = templatefile("${path.module}/function-code/main.py", {
      # Template variables can be passed here if needed
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function-code/requirements.txt", {})
    filename = "requirements.txt"
  }
  
  # Include service account credentials
  source {
    content  = base64decode(google_service_account_key.task_manager_key.private_key)
    filename = "credentials.json"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Content type for zip files
  content_type = "application/zip"
  
  depends_on = [data.archive_file.function_source]
}

# Deploy the Cloud Function for task management
# This is the main serverless component that provides the REST API
resource "google_cloudfunctions_function" "task_manager" {
  name        = local.function_name_unique
  description = var.function_description
  project     = var.project_id
  region      = var.region
  runtime     = var.python_runtime
  
  # Function source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Entry point for the function
  entry_point = "task_manager"
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_OPTIONAL"  # Allow both HTTP and HTTPS
    }
  }
  
  # Resource allocation
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  max_instances         = var.max_instances
  min_instances         = var.min_instances
  
  # Service account for API access
  service_account_email = google_service_account.task_manager_sa.email
  
  # Environment variables
  environment_variables = merge(var.environment_variables, {
    GOOGLE_APPLICATION_CREDENTIALS = "credentials.json"
  })
  
  # VPC connector configuration (if enabled)
  dynamic "vpc_connector" {
    for_each = var.enable_vpc_connector ? [1] : []
    content {
      name = var.vpc_connector_name
    }
  }
  
  # Resource labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Configure IAM policy for public access (if enabled)
# This allows unauthenticated access to the Cloud Function
resource "google_cloudfunctions_function_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.task_manager.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create local files for the function source code
# These files contain the actual Python code for the task management API

# Main Python function code
resource "local_file" "main_py" {
  filename = "${path.module}/function-code/main.py"
  content  = <<-EOT
import json
import os
import functions_framework
from googleapiclient.discovery import build
from google.oauth2 import service_account
from flask import jsonify

# Initialize credentials and service
SCOPES = ['https://www.googleapis.com/auth/tasks']

def get_tasks_service():
    """Initialize Google Tasks API service with credentials."""
    credentials = service_account.Credentials.from_service_account_file(
        'credentials.json',
        scopes=SCOPES
    )
    return build('tasks', 'v1', credentials=credentials)

@functions_framework.http
def task_manager(request):
    """HTTP Cloud Function for managing Google Tasks."""
    
    # Enable CORS for web clients
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        service = get_tasks_service()
        
        if request.method == 'GET' and request.path == '/tasks':
            # List all tasks from default task list
            task_lists = service.tasklists().list().execute()
            if not task_lists.get('items'):
                return jsonify({'error': 'No task lists found'}), 404
            
            default_list = task_lists['items'][0]['id']
            tasks = service.tasks().list(tasklist=default_list).execute()
            return jsonify({
                'tasks': tasks.get('items', []),
                'task_list_id': default_list,
                'total_count': len(tasks.get('items', []))
            }), 200, headers
        
        elif request.method == 'POST' and request.path == '/tasks':
            # Create a new task
            request_json = request.get_json(silent=True)
            if not request_json or 'title' not in request_json:
                return jsonify({'error': 'Task title is required'}), 400
            
            task_lists = service.tasklists().list().execute()
            if not task_lists.get('items'):
                return jsonify({'error': 'No task lists found'}), 404
            
            default_list = task_lists['items'][0]['id']
            task = {
                'title': request_json['title'],
                'notes': request_json.get('notes', '')
            }
            
            # Add due date if provided
            if 'due' in request_json:
                task['due'] = request_json['due']
            
            result = service.tasks().insert(
                tasklist=default_list, 
                body=task
            ).execute()
            return jsonify({
                'task': result,
                'message': 'Task created successfully'
            }), 201, headers
        
        elif request.method == 'DELETE' and '/tasks/' in request.path:
            # Delete a specific task
            task_id = request.path.split('/tasks/')[-1]
            if not task_id:
                return jsonify({'error': 'Task ID is required'}), 400
            
            task_lists = service.tasklists().list().execute()
            if not task_lists.get('items'):
                return jsonify({'error': 'No task lists found'}), 404
            
            default_list = task_lists['items'][0]['id']
            
            try:
                service.tasks().delete(
                    tasklist=default_list, 
                    task=task_id
                ).execute()
                return jsonify({
                    'message': 'Task deleted successfully',
                    'task_id': task_id
                }), 200, headers
            except Exception as delete_error:
                return jsonify({
                    'error': f'Failed to delete task: {str(delete_error)}',
                    'task_id': task_id
                }), 404, headers
        
        elif request.method == 'GET' and request.path == '/health':
            # Health check endpoint
            return jsonify({
                'status': 'healthy',
                'service': 'task-manager',
                'timestamp': service.tasks().list().execute()  # Test API connectivity
            }), 200, headers
        
        else:
            return jsonify({
                'error': 'Endpoint not found',
                'available_endpoints': [
                    'GET /tasks - List all tasks',
                    'POST /tasks - Create a new task',
                    'DELETE /tasks/{task_id} - Delete a task',
                    'GET /health - Health check'
                ]
            }), 404, headers
            
    except Exception as e:
        return jsonify({
            'error': f'Internal server error: {str(e)}',
            'type': type(e).__name__
        }), 500, headers
EOT
}

# Requirements file for Python dependencies
resource "local_file" "requirements_txt" {
  filename = "${path.module}/function-code/requirements.txt"
  content  = <<-EOT
google-api-python-client==2.150.0
google-auth==2.35.0
google-auth-httplib2==0.2.0
functions-framework==3.8.1
flask==3.0.0
EOT
}

# Create function-code directory
resource "local_file" "function_code_dir" {
  filename = "${path.module}/function-code/.gitkeep"
  content  = ""
}