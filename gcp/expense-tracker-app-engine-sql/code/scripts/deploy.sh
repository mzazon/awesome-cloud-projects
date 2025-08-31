#!/bin/bash

# Personal Expense Tracker Deployment Script
# Deploys App Engine application with Cloud SQL backend
# Recipe: expense-tracker-app-engine-sql

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Exit on error with cleanup
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

trap cleanup_on_error ERR

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_DB_TIER="db-f1-micro"
DEFAULT_DB_VERSION="POSTGRES_17"

# Help function
show_help() {
    cat << EOF
Personal Expense Tracker Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    GCP project ID (required)
    -r, --region REGION           GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE               GCP zone (default: ${DEFAULT_ZONE})
    --db-tier TIER                Cloud SQL tier (default: ${DEFAULT_DB_TIER})
    --db-version VERSION          PostgreSQL version (default: ${DEFAULT_DB_VERSION})
    --dry-run                     Show what would be deployed without executing
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --region us-east1 --zone us-east1-a
    $0 --project-id my-project-123 --dry-run

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Billing enabled on the project
    - Appropriate IAM permissions for App Engine and Cloud SQL
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            --db-tier)
                DB_TIER="$2"
                shift 2
                ;;
            --db-version)
                DB_VERSION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud CLI"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id or -p flag"
        show_help
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project '${PROJECT_ID}' not found or not accessible"
        exit 1
    fi
    
    # Check billing
    if ! gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" | grep -q "True"; then
        log_error "Billing is not enabled for project '${PROJECT_ID}'"
        log_info "Enable billing at: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Initialize variables
initialize_variables() {
    log_info "Initializing deployment variables..."
    
    # Set defaults if not provided
    REGION="${REGION:-$DEFAULT_REGION}"
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    DB_TIER="${DB_TIER:-$DEFAULT_DB_TIER}"
    DB_VERSION="${DB_VERSION:-$DEFAULT_DB_VERSION}"
    DRY_RUN="${DRY_RUN:-false}"
    
    # Generate unique identifiers
    TIMESTAMP=$(date +%s)
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Resource names
    INSTANCE_NAME="expense-db-${RANDOM_SUFFIX}"
    DB_NAME="expenses"
    DB_USER="expense_user"
    DB_PASSWORD=$(openssl rand -base64 32)
    
    # Application settings
    APP_DIR="expense-tracker-app"
    SECRET_KEY=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
    
    log_info "Deployment Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  DB Instance: ${INSTANCE_NAME}"
    log_info "  DB Tier: ${DB_TIER}"
    log_info "  DB Version: ${DB_VERSION}"
    log_info "  Dry Run: ${DRY_RUN}"
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${cmd}"
        log_info "[DRY RUN] Description: ${description}"
    else
        log_info "Executing: ${description}"
        eval "${cmd}"
    fi
}

# Configure GCP project and enable APIs
configure_project() {
    log_info "Configuring GCP project and enabling APIs..."
    
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Set default project"
    execute_cmd "gcloud config set compute/region ${REGION}" "Set default region"
    execute_cmd "gcloud config set compute/zone ${ZONE}" "Set default zone"
    
    # Enable required APIs
    local apis=(
        "appengine.googleapis.com"
        "sql.googleapis.com"
        "sqladmin.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable ${api}" "Enable ${api}"
    done
    
    log_success "Project configuration completed"
}

# Initialize App Engine
initialize_app_engine() {
    log_info "Initializing App Engine application..."
    
    # Check if App Engine is already initialized
    if gcloud app describe &>/dev/null; then
        log_warning "App Engine application already exists"
        return 0
    fi
    
    execute_cmd "gcloud app create --region=${REGION}" "Initialize App Engine application"
    
    log_success "App Engine application initialized"
}

# Create Cloud SQL instance
create_cloud_sql() {
    log_info "Creating Cloud SQL PostgreSQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe "${INSTANCE_NAME}" &>/dev/null; then
        log_warning "Cloud SQL instance '${INSTANCE_NAME}' already exists"
        return 0
    fi
    
    local create_cmd="gcloud sql instances create ${INSTANCE_NAME} \
        --database-version=${DB_VERSION} \
        --tier=${DB_TIER} \
        --region=${REGION} \
        --root-password='${DB_PASSWORD}' \
        --storage-type=SSD \
        --storage-size=10GB \
        --authorized-networks=0.0.0.0/0"
    
    execute_cmd "${create_cmd}" "Create Cloud SQL instance"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "Waiting for Cloud SQL instance to be ready..."
        while [[ "$(gcloud sql instances describe ${INSTANCE_NAME} --format='value(state)')" != "RUNNABLE" ]]; do
            log_info "Instance state: $(gcloud sql instances describe ${INSTANCE_NAME} --format='value(state)')"
            sleep 10
        done
    fi
    
    log_success "Cloud SQL instance created: ${INSTANCE_NAME}"
}

# Configure database
configure_database() {
    log_info "Configuring database and user..."
    
    execute_cmd "gcloud sql databases create ${DB_NAME} --instance=${INSTANCE_NAME}" "Create application database"
    execute_cmd "gcloud sql users create ${DB_USER} --instance=${INSTANCE_NAME} --password='${DB_PASSWORD}'" "Create database user"
    
    log_success "Database configuration completed"
}

# Create database schema
create_schema() {
    log_info "Creating database schema..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create database schema with expenses table"
        return 0
    fi
    
    # Create a temporary SQL file
    local sql_file=$(mktemp)
    cat > "${sql_file}" << EOF
\c ${DB_NAME}

CREATE TABLE IF NOT EXISTS expenses (
    id SERIAL PRIMARY KEY,
    description VARCHAR(255) NOT NULL,
    amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
    category VARCHAR(100) NOT NULL,
    date_created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_date_created ON expenses (date_created DESC);
CREATE INDEX IF NOT EXISTS idx_category ON expenses (category);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE expenses TO ${DB_USER};
GRANT USAGE, SELECT ON SEQUENCE expenses_id_seq TO ${DB_USER};

INSERT INTO expenses (description, amount, category) VALUES 
    ('Coffee at local cafe', 4.50, 'Food & Dining'),
    ('Bus fare to work', 2.25, 'Transportation'),
    ('Monthly Netflix subscription', 15.99, 'Entertainment');
EOF
    
    gcloud sql connect "${INSTANCE_NAME}" --user=postgres < "${sql_file}"
    rm -f "${sql_file}"
    
    log_success "Database schema created with sample data"
}

# Create application structure
create_application() {
    log_info "Creating Flask application structure..."
    
    if [[ -d "${APP_DIR}" ]]; then
        log_warning "Application directory already exists. Removing..."
        execute_cmd "rm -rf ${APP_DIR}" "Remove existing application directory"
    fi
    
    execute_cmd "mkdir -p ${APP_DIR}/{templates,static/css}" "Create application directories"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Flask application files"
        return 0
    fi
    
    # Change to application directory
    cd "${APP_DIR}"
    
    # Create main.py
    cat > main.py << 'EOF'
import os
from flask import Flask, render_template, request, redirect, url_for, flash
import sqlalchemy
from sqlalchemy import create_engine, text
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key')

# Database configuration
def get_db_connection():
    if os.environ.get('GAE_ENV', '').startswith('standard'):
        # Production environment - use Unix socket
        db_socket_dir = "/cloudsql"
        cloud_sql_connection_name = os.environ.get('CLOUD_SQL_CONNECTION_NAME')
        db_url = f"postgresql://{os.environ.get('DB_USER')}:{os.environ.get('DB_PASSWORD')}@/{os.environ.get('DB_NAME')}?host={db_socket_dir}/{cloud_sql_connection_name}"
    else:
        # Development environment - use TCP connection
        db_host = os.environ.get('DB_HOST', 'localhost')
        db_url = f"postgresql://{os.environ.get('DB_USER')}:{os.environ.get('DB_PASSWORD')}@{db_host}/{os.environ.get('DB_NAME')}"
    
    return create_engine(db_url, echo=True)

@app.route('/')
def index():
    try:
        engine = get_db_connection()
        with engine.connect() as conn:
            result = conn.execute(text("""
                SELECT id, description, amount, category, date_created 
                FROM expenses 
                ORDER BY date_created DESC 
                LIMIT 10
            """))
            expenses = [dict(row._mapping) for row in result]
            
            # Calculate total expenses
            total_result = conn.execute(text(
                "SELECT COALESCE(SUM(amount), 0) as total FROM expenses"
            ))
            total = total_result.fetchone()[0]
        
        return render_template('index.html', expenses=expenses, total=float(total))
    except Exception as e:
        app.logger.error(f"Database error: {e}")
        return render_template('index.html', expenses=[], total=0, error=str(e))

@app.route('/add', methods=['POST'])
def add_expense():
    description = request.form.get('description', '').strip()
    amount_str = request.form.get('amount', '0')
    category = request.form.get('category', '').strip()
    
    try:
        amount = float(amount_str)
        if not description or amount <= 0 or not category:
            flash('Please provide valid expense details.', 'error')
            return redirect(url_for('index'))
        
        engine = get_db_connection()
        with engine.connect() as conn:
            conn.execute(text("""
                INSERT INTO expenses (description, amount, category, date_created)
                VALUES (:description, :amount, :category, :date_created)
            """), {
                'description': description,
                'amount': amount,
                'category': category,
                'date_created': datetime.now()
            })
            conn.commit()
        
        flash('Expense added successfully!', 'success')
    except ValueError:
        flash('Please enter a valid amount.', 'error')
    except Exception as e:
        app.logger.error(f"Error adding expense: {e}")
        flash('Failed to add expense. Please try again.', 'error')
    
    return redirect(url_for('index'))

@app.route('/delete/<int:expense_id>')
def delete_expense(expense_id):
    try:
        engine = get_db_connection()
        with engine.connect() as conn:
            result = conn.execute(text(
                "DELETE FROM expenses WHERE id = :id"
            ), {'id': expense_id})
            conn.commit()
            
            if result.rowcount == 0:
                flash('Expense not found.', 'error')
            else:
                flash('Expense deleted successfully!', 'success')
    except Exception as e:
        app.logger.error(f"Error deleting expense: {e}")
        flash('Failed to delete expense. Please try again.', 'error')
    
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8080)
EOF
    
    # Create HTML template
    cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Personal Expense Tracker</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css" rel="stylesheet">
</head>
<body class="bg-light">
    <div class="container mt-4">
        <div class="row justify-content-center">
            <div class="col-md-10">
                <h1 class="text-center mb-4 text-primary">
                    <i class="bi bi-wallet2"></i> Personal Expense Tracker
                </h1>
                
                <!-- Flash messages -->
                {% with messages = get_flashed_messages(with_categories=true) %}
                    {% if messages %}
                        {% for category, message in messages %}
                            <div class="alert alert-{{ 'danger' if category == 'error' else 'success' }} alert-dismissible fade show" role="alert">
                                <i class="bi bi-{{ 'exclamation-triangle' if category == 'error' else 'check-circle' }}"></i>
                                {{ message }}
                                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                            </div>
                        {% endfor %}
                    {% endif %}
                {% endwith %}
                
                <!-- Add expense form -->
                <div class="card shadow-sm mb-4">
                    <div class="card-header bg-primary text-white">
                        <h3 class="mb-0"><i class="bi bi-plus-circle"></i> Add New Expense</h3>
                    </div>
                    <div class="card-body">
                        <form method="POST" action="/add" class="needs-validation" novalidate>
                            <div class="row">
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        <label for="description" class="form-label">Description</label>
                                        <input type="text" class="form-control" id="description" name="description" 
                                               placeholder="Enter expense description" maxlength="255" required>
                                        <div class="invalid-feedback">
                                            Please provide a valid description.
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-3">
                                    <div class="mb-3">
                                        <label for="amount" class="form-label">Amount ($)</label>
                                        <input type="number" step="0.01" min="0.01" class="form-control" 
                                               id="amount" name="amount" placeholder="0.00" required>
                                        <div class="invalid-feedback">
                                            Please enter a valid amount.
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-3">
                                    <div class="mb-3">
                                        <label for="category" class="form-label">Category</label>
                                        <select class="form-select" id="category" name="category" required>
                                            <option value="">Select Category</option>
                                            <option value="Food & Dining">Food & Dining</option>
                                            <option value="Transportation">Transportation</option>
                                            <option value="Entertainment">Entertainment</option>
                                            <option value="Shopping">Shopping</option>
                                            <option value="Bills & Utilities">Bills & Utilities</option>
                                            <option value="Healthcare">Healthcare</option>
                                            <option value="Education">Education</option>
                                            <option value="Other">Other</option>
                                        </select>
                                        <div class="invalid-feedback">
                                            Please select a category.
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <button type="submit" class="btn btn-primary">
                                <i class="bi bi-plus-lg"></i> Add Expense
                            </button>
                        </form>
                    </div>
                </div>
                
                <!-- Expenses summary -->
                <div class="card shadow-sm mb-4">
                    <div class="card-header bg-success text-white">
                        <h3 class="mb-0">
                            <i class="bi bi-graph-up"></i> Total Expenses: ${{ "%.2f"|format(total) }}
                        </h3>
                    </div>
                </div>
                
                <!-- Recent expenses -->
                <div class="card shadow-sm">
                    <div class="card-header bg-info text-white">
                        <h3 class="mb-0"><i class="bi bi-list-ul"></i> Recent Expenses</h3>
                    </div>
                    <div class="card-body">
                        {% if expenses %}
                            <div class="table-responsive">
                                <table class="table table-striped table-hover">
                                    <thead class="table-dark">
                                        <tr>
                                            <th><i class="bi bi-calendar"></i> Date</th>
                                            <th><i class="bi bi-file-text"></i> Description</th>
                                            <th><i class="bi bi-tag"></i> Category</th>
                                            <th><i class="bi bi-currency-dollar"></i> Amount</th>
                                            <th><i class="bi bi-gear"></i> Actions</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {% for expense in expenses %}
                                        <tr>
                                            <td>{{ expense.date_created.strftime('%Y-%m-%d %H:%M') }}</td>
                                            <td>{{ expense.description }}</td>
                                            <td>
                                                <span class="badge bg-secondary">{{ expense.category }}</span>
                                            </td>
                                            <td class="text-end fw-bold">${{ "%.2f"|format(expense.amount) }}</td>
                                            <td>
                                                <a href="/delete/{{ expense.id }}" class="btn btn-sm btn-outline-danger" 
                                                   onclick="return confirm('Are you sure you want to delete this expense?')">
                                                    <i class="bi bi-trash"></i> Delete
                                                </a>
                                            </td>
                                        </tr>
                                        {% endfor %}
                                    </tbody>
                                </table>
                            </div>
                        {% else %}
                            <div class="text-center py-5">
                                <i class="bi bi-inbox display-1 text-muted"></i>
                                <p class="text-muted mt-3">No expenses recorded yet. Add your first expense above!</p>
                            </div>
                        {% endif %}
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Form validation
        (function() {
            'use strict';
            window.addEventListener('load', function() {
                var forms = document.getElementsByClassName('needs-validation');
                Array.prototype.filter.call(forms, function(form) {
                    form.addEventListener('submit', function(event) {
                        if (form.checkValidity() === false) {
                            event.preventDefault();
                            event.stopPropagation();
                        }
                        form.classList.add('was-validated');
                    }, false);
                });
            }, false);
        })();
    </script>
</body>
</html>
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
Flask==3.0.0
SQLAlchemy==2.0.25
psycopg2-binary==2.9.9
Werkzeug==3.0.1
EOF
    
    # Get Cloud SQL connection name
    local connection_name
    if [[ "${DRY_RUN}" != "true" ]]; then
        connection_name=$(gcloud sql instances describe "${INSTANCE_NAME}" --format="value(connectionName)")
    else
        connection_name="PROJECT_ID:REGION:INSTANCE_NAME"
    fi
    
    # Create app.yaml
    cat > app.yaml << EOF
runtime: python39

env_variables:
  SECRET_KEY: "${SECRET_KEY}"
  DB_NAME: "${DB_NAME}"
  DB_USER: "${DB_USER}"
  DB_PASSWORD: "${DB_PASSWORD}"
  CLOUD_SQL_CONNECTION_NAME: "${connection_name}"

automatic_scaling:
  min_instances: 0
  max_instances: 2
  target_cpu_utilization: 0.6

handlers:
- url: /static
  static_dir: static
- url: /.*
  script: auto
EOF
    
    # Return to parent directory
    cd ..
    
    log_success "Flask application structure created"
}

# Deploy to App Engine
deploy_application() {
    log_info "Deploying application to App Engine..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy application to App Engine"
        return 0
    fi
    
    cd "${APP_DIR}"
    
    gcloud app deploy app.yaml --quiet --promote
    
    local app_url
    app_url=$(gcloud app describe --format="value(defaultHostname)")
    
    cd ..
    
    log_success "Application deployed successfully"
    log_success "Application URL: https://${app_url}"
    
    # Store deployment info
    cat > deployment-info.txt << EOF
Deployment Information
=====================
Project ID: ${PROJECT_ID}
Region: ${REGION}
App Engine URL: https://${app_url}
Cloud SQL Instance: ${INSTANCE_NAME}
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Deployment Date: $(date)

To manage your application:
- View logs: gcloud app logs tail -s default
- View in console: https://console.cloud.google.com/appengine?project=${PROJECT_ID}
- Manage database: https://console.cloud.google.com/sql/instances?project=${PROJECT_ID}
EOF
    
    log_info "Deployment information saved to deployment-info.txt"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check App Engine service status
    local service_status
    service_status=$(gcloud app services list --format="value(id)" | head -1)
    
    if [[ -n "${service_status}" ]]; then
        log_success "App Engine service is active: ${service_status}"
    else
        log_error "App Engine service not found"
        return 1
    fi
    
    # Check Cloud SQL instance status
    local instance_status
    instance_status=$(gcloud sql instances describe "${INSTANCE_NAME}" --format="value(state)")
    
    if [[ "${instance_status}" == "RUNNABLE" ]]; then
        log_success "Cloud SQL instance is running: ${INSTANCE_NAME}"
    else
        log_error "Cloud SQL instance is not running. Status: ${instance_status}"
        return 1
    fi
    
    # Test application URL
    local app_url
    app_url=$(gcloud app describe --format="value(defaultHostname)")
    
    if curl -I -s "https://${app_url}" | grep -q "HTTP/2 200"; then
        log_success "Application is responding: https://${app_url}"
    else
        log_warning "Application may not be fully ready yet. Check the URL manually: https://${app_url}"
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log_info "Starting Personal Expense Tracker deployment..."
    log_info "Timestamp: $(date)"
    
    parse_args "$@"
    check_prerequisites
    initialize_variables
    configure_project
    initialize_app_engine
    create_cloud_sql
    configure_database
    create_schema
    create_application
    deploy_application
    validate_deployment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed. No resources were created."
        log_info "Run without --dry-run to execute the actual deployment."
    else
        log_success "Deployment completed successfully!"
        log_info "Your Personal Expense Tracker is now available."
        log_info "Check deployment-info.txt for detailed information."
        log_info "To clean up resources, run the destroy.sh script."
    fi
}

# Run main function with all arguments
main "$@"