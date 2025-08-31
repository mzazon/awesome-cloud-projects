# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Generate secure random password for database user if not provided
resource "random_password" "db_password" {
  count   = var.database_password == "" ? 1 : 0
  length  = 32
  special = true
}

# Local values for resource naming and configuration
locals {
  # Use provided password or generated one
  db_password = var.database_password != "" ? var.database_password : random_password.db_password[0].result
  
  # Generate unique resource names
  instance_name = "${var.resource_prefix}-db-${random_id.suffix.hex}"
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    recipe     = "expense-tracker-app-engine-sql"
  })
  
  # App Engine environment variables
  app_env_vars = merge({
    DB_NAME                     = var.database_name
    DB_USER                     = var.database_user
    DB_PASSWORD                 = local.db_password
    CLOUD_SQL_CONNECTION_NAME   = google_sql_database_instance.expense_db.connection_name
    SECRET_KEY                  = random_password.app_secret_key.result
  }, var.app_environment_variables)
}

# Generate secret key for Flask application
resource "random_password" "app_secret_key" {
  length  = 64
  special = true
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.key
  
  # Prevent disabling services on destroy to avoid issues
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create App Engine application
resource "google_app_engine_application" "expense_app" {
  project       = var.project_id
  location_id   = var.app_engine_location
  database_type = "CLOUD_DATASTORE_COMPATIBILITY"
  
  # Ensure APIs are enabled before creating App Engine app
  depends_on = [
    google_project_service.apis
  ]
}

# Create Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "expense_db" {
  name             = local.instance_name
  database_version = var.database_version
  region          = var.region
  project         = var.project_id
  
  # Prevent accidental deletion in production
  deletion_protection = var.deletion_protection
  
  settings {
    tier                        = var.database_tier
    availability_type          = "ZONAL"  # Use REGIONAL for high availability
    disk_type                  = var.database_storage_type
    disk_size                  = var.database_storage_size
    disk_autoresize           = true
    disk_autoresize_limit     = 0  # No limit on auto-resize
    
    # Enable deletion protection and maintenance settings
    deletion_protection_enabled = var.deletion_protection
    
    # Database flags for optimal performance
    database_flags {
      name  = "max_connections"
      value = "100"
    }
    
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    
    # Backup configuration
    backup_configuration {
      enabled                        = var.database_backup_enabled
      start_time                    = var.database_backup_time
      location                      = var.region
      binary_log_enabled           = false  # Not applicable for PostgreSQL
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
      point_in_time_recovery_enabled = true
    }
    
    # IP configuration for App Engine access
    ip_configuration {
      ipv4_enabled                                  = true
      private_network                              = null
      enable_private_path_for_google_cloud_services = false
      
      # Authorized networks for external access
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    # Maintenance window (updates applied during this time)
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM UTC
      update_track = "stable"
    }
    
    # Insights configuration for monitoring
    insights_config {
      query_insights_enabled  = true
      query_string_length    = 1024
      record_application_tags = false
      record_client_address  = false
    }
    
    # User labels for resource management
    user_labels = local.common_labels
  }
  
  # Ensure APIs are enabled before creating database instance
  depends_on = [
    google_project_service.apis
  ]
  
  lifecycle {
    # Prevent accidental deletion
    prevent_destroy = false  # Set to true for production
  }
}

# Create the application database
resource "google_sql_database" "expense_database" {
  name     = var.database_name
  instance = google_sql_database_instance.expense_db.name
  project  = var.project_id
  
  # Character set and collation for international support
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Create database user for the application
resource "google_sql_user" "expense_user" {
  name     = var.database_user
  instance = google_sql_database_instance.expense_db.name
  project  = var.project_id
  password = local.db_password
  type     = "BUILT_IN"
  
  # Deletion policy
  deletion_policy = "ABANDON"  # Keep user data on deletion
}

# Create IAM service account for App Engine application
resource "google_service_account" "app_engine_sa" {
  account_id   = "${var.resource_prefix}-appengine-sa"
  display_name = "App Engine Service Account for Expense Tracker"
  description  = "Service account used by App Engine for accessing Cloud SQL and other GCP services"
  project      = var.project_id
}

# Grant Cloud SQL Client role to the service account
resource "google_project_iam_member" "app_engine_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app_engine_sa.email}"
}

# Grant Cloud SQL Editor role for database operations
resource "google_project_iam_member" "app_engine_sql_editor" {
  project = var.project_id
  role    = "roles/cloudsql.editor"
  member  = "serviceAccount:${google_service_account.app_engine_sa.email}"
}

# Create App Engine service for the web application
resource "google_app_engine_standard_app_version" "expense_app_v1" {
  project     = var.project_id
  service     = "default"
  version_id  = "v1"
  runtime     = var.app_engine_runtime
  
  # Source code deployment (placeholder - in practice, you'd deploy from source)
  deployment {
    files {
      name = "main.py"
      source_url = "https://storage.googleapis.com/${google_storage_bucket.app_source.name}/${google_storage_bucket_object.app_source.name}"
    }
    files {
      name = "app.yaml"
      source_url = "https://storage.googleapis.com/${google_storage_bucket.app_source.name}/${google_storage_bucket_object.app_config.name}"
    }
    files {
      name = "requirements.txt"
      source_url = "https://storage.googleapis.com/${google_storage_bucket.app_source.name}/${google_storage_bucket_object.requirements.name}"
    }
  }
  
  # Environment variables for database connection
  env_variables = local.app_env_vars
  
  # Automatic scaling configuration
  automatic_scaling {
    min_instances = var.app_scaling_settings.min_instances
    max_instances = var.app_scaling_settings.max_instances
    
    cpu_utilization {
      target_utilization = var.app_scaling_settings.target_cpu_utilization
    }
  }
  
  # Resource allocation
  instance_class = "F1"  # Free tier eligible
  
  # Service account configuration
  service_account = google_service_account.app_engine_sa.email
  
  # Handlers for static files and application routing
  handlers {
    url_regex        = "/static/.*"
    static_files {
      path = "static/"
      upload_path_regex = "static/.*"
    }
  }
  
  handlers {
    url_regex = ".*"
    script {
      script_path = "auto"
    }
  }
  
  # Delete previous versions on new deployment
  delete_service_on_destroy = false
  noop_on_destroy          = true
  
  depends_on = [
    google_app_engine_application.expense_app,
    google_sql_database_instance.expense_db,
    google_sql_database.expense_database,
    google_sql_user.expense_user,
    google_storage_bucket_object.app_source,
    google_storage_bucket_object.app_config,
    google_storage_bucket_object.requirements
  ]
}

# Create Cloud Storage bucket for application source code
resource "google_storage_bucket" "app_source" {
  name          = "${var.resource_prefix}-source-${random_id.suffix.hex}"
  location      = var.region
  project       = var.project_id
  force_destroy = true
  
  # Bucket configuration
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  
  # Versioning for source code management
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
}

# Upload application source files to Cloud Storage
resource "google_storage_bucket_object" "app_source" {
  name   = "main.py"
  bucket = google_storage_bucket.app_source.name
  
  # Simple Flask application code (in practice, you'd upload actual source)
  content = <<-EOT
import os
from flask import Flask, render_template, request, redirect, url_for, flash
import sqlalchemy
from sqlalchemy import create_engine, text
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key')

def get_db_connection():
    if os.environ.get('GAE_ENV', '').startswith('standard'):
        db_socket_dir = "/cloudsql"
        cloud_sql_connection_name = os.environ.get('CLOUD_SQL_CONNECTION_NAME')
        db_url = f"postgresql://{os.environ.get('DB_USER')}:{os.environ.get('DB_PASSWORD')}@/{os.environ.get('DB_NAME')}?host={db_socket_dir}/{cloud_sql_connection_name}"
    else:
        db_host = os.environ.get('DB_HOST', 'localhost')
        db_url = f"postgresql://{os.environ.get('DB_USER')}:{os.environ.get('DB_PASSWORD')}@{db_host}/{os.environ.get('DB_NAME')}"
    
    return create_engine(db_url, echo=True)

@app.route('/')
def index():
    try:
        engine = get_db_connection()
        with engine.connect() as conn:
            result = conn.execute(text("SELECT id, description, amount, category, date_created FROM expenses ORDER BY date_created DESC LIMIT 10"))
            expenses = [dict(row._mapping) for row in result]
            
            total_result = conn.execute(text("SELECT COALESCE(SUM(amount), 0) as total FROM expenses"))
            total = total_result.fetchone()[0]
        
        return render_template('index.html', expenses=expenses, total=float(total))
    except Exception as e:
        app.logger.error(f"Database error: {e}")
        return f"Database connection error: {e}", 500

@app.route('/add', methods=['POST'])
def add_expense():
    description = request.form.get('description', '').strip()
    amount_str = request.form.get('amount', '0')
    category = request.form.get('category', '').strip()
    
    try:
        amount = float(amount_str)
        if not description or amount <= 0 or not category:
            return "Invalid input", 400
        
        engine = get_db_connection()
        with engine.connect() as conn:
            conn.execute(text("INSERT INTO expenses (description, amount, category, date_created) VALUES (:description, :amount, :category, :date_created)"), {
                'description': description,
                'amount': amount,
                'category': category,
                'date_created': datetime.now()
            })
            conn.commit()
        
        return redirect(url_for('index'))
    except Exception as e:
        app.logger.error(f"Error adding expense: {e}")
        return f"Error adding expense: {e}", 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8080)
EOT
  
  content_type = "text/plain"
}

resource "google_storage_bucket_object" "app_config" {
  name   = "app.yaml"
  bucket = google_storage_bucket.app_source.name
  
  content = <<-EOT
runtime: ${var.app_engine_runtime}

env_variables:
  SECRET_KEY: "${random_password.app_secret_key.result}"
  DB_NAME: "${var.database_name}"
  DB_USER: "${var.database_user}"
  DB_PASSWORD: "${local.db_password}"
  CLOUD_SQL_CONNECTION_NAME: "${google_sql_database_instance.expense_db.connection_name}"

automatic_scaling:
  min_instances: ${var.app_scaling_settings.min_instances}
  max_instances: ${var.app_scaling_settings.max_instances}
  target_cpu_utilization: ${var.app_scaling_settings.target_cpu_utilization}

handlers:
- url: /static
  static_dir: static
- url: /.*
  script: auto
EOT
  
  content_type = "text/plain"
}

resource "google_storage_bucket_object" "requirements" {
  name   = "requirements.txt"
  bucket = google_storage_bucket.app_source.name
  
  content = <<-EOT
Flask==3.0.0
SQLAlchemy==2.0.25
psycopg2-binary==2.9.9
Werkzeug==3.0.1
EOT
  
  content_type = "text/plain"
}

# Create database schema using Cloud SQL Proxy
resource "null_resource" "database_schema" {
  # This resource creates the database schema after the database is ready
  depends_on = [
    google_sql_database.expense_database,
    google_sql_user.expense_user
  ]
  
  triggers = {
    instance_id = google_sql_database_instance.expense_db.id
    database_id = google_sql_database.expense_database.id
    user_id     = google_sql_user.expense_user.id
  }
  
  provisioner "local-exec" {
    # Note: This requires gcloud CLI and cloud_sql_proxy to be installed
    # In practice, you might want to use a separate script or configuration management tool
    command = <<-EOT
      echo "Database schema creation would be executed here"
      echo "Instance: ${google_sql_database_instance.expense_db.name}"
      echo "Database: ${google_sql_database.expense_database.name}"
      echo "Connection: ${google_sql_database_instance.expense_db.connection_name}"
    EOT
  }
}