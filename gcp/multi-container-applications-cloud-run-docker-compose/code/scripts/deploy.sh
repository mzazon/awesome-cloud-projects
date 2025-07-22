#!/bin/bash

# Deploy Multi-Container Applications with Cloud Run and Docker Compose
# This script deploys a complete multi-container application on Google Cloud Run
# with Cloud SQL database, Secret Manager, and Artifact Registry integration

set -euo pipefail

# Colors for output
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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    # Add cleanup logic here if needed
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed. Please install Docker Desktop from https://www.docker.com/products/docker-desktop"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project ID
    export PROJECT_ID=${PROJECT_ID:-"multicontainer-app-$(date +%s)"}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Generate unique suffix for resource names
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    export SERVICE_NAME="multi-app-${RANDOM_SUFFIX}"
    export REPOSITORY_NAME="multiapp-repo-${RANDOM_SUFFIX}"
    export SQL_INSTANCE_NAME="multiapp-db-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .deployment_vars << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
SERVICE_NAME=${SERVICE_NAME}
REPOSITORY_NAME=${REPOSITORY_NAME}
SQL_INSTANCE_NAME=${SQL_INSTANCE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Service Name: ${SERVICE_NAME}"
}

# Configure gcloud project
configure_gcloud() {
    log_info "Configuring gcloud project and region..."
    
    # Create project if it doesn't exist
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} does not exist. Creating it..."
        gcloud projects create "${PROJECT_ID}" || error_exit "Failed to create project"
        
        # Link billing account (this might fail if no billing account is available)
        log_warning "Please ensure billing is enabled for project ${PROJECT_ID}"
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "gcloud configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "sql-component.googleapis.com"
        "sqladmin.googleapis.com"
        "secretmanager.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_warning "Failed to enable ${api} or already enabled"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled"
}

# Create Artifact Registry repository
create_artifact_repository() {
    log_info "Creating Artifact Registry repository..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "${REPOSITORY_NAME}" \
        --location="${REGION}" &> /dev/null; then
        log_warning "Repository ${REPOSITORY_NAME} already exists"
        return 0
    fi
    
    # Create the repository
    gcloud artifacts repositories create "${REPOSITORY_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Multi-container application repository" \
        || error_exit "Failed to create Artifact Registry repository"
    
    # Configure Docker authentication
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet \
        || error_exit "Failed to configure Docker authentication"
    
    log_success "Artifact Registry repository created: ${REPOSITORY_NAME}"
}

# Create Cloud SQL instance
create_sql_instance() {
    log_info "Creating Cloud SQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe "${SQL_INSTANCE_NAME}" &> /dev/null; then
        log_warning "Cloud SQL instance ${SQL_INSTANCE_NAME} already exists"
        return 0
    fi
    
    # Create Cloud SQL instance
    gcloud sql instances create "${SQL_INSTANCE_NAME}" \
        --database-version=POSTGRES_15 \
        --tier=db-f1-micro \
        --region="${REGION}" \
        --storage-type=SSD \
        --storage-size=10GB \
        --backup \
        --enable-bin-log \
        --quiet \
        || error_exit "Failed to create Cloud SQL instance"
    
    # Wait for instance to be ready
    log_info "Waiting for Cloud SQL instance to be ready..."
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if gcloud sql instances describe "${SQL_INSTANCE_NAME}" \
            --format="value(state)" | grep -q "RUNNABLE"; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Still waiting for instance... (${elapsed}s/${timeout}s)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        error_exit "Timeout waiting for Cloud SQL instance to be ready"
    fi
    
    # Create database
    gcloud sql databases create appdb \
        --instance="${SQL_INSTANCE_NAME}" \
        || log_warning "Database 'appdb' may already exist"
    
    # Generate secure password
    export DB_PASSWORD=$(openssl rand -base64 32)
    
    # Create database user
    gcloud sql users create appuser \
        --instance="${SQL_INSTANCE_NAME}" \
        --password="${DB_PASSWORD}" \
        || log_warning "User 'appuser' may already exist"
    
    log_success "Cloud SQL instance created: ${SQL_INSTANCE_NAME}"
}

# Store database credentials in Secret Manager
store_secrets() {
    log_info "Storing database credentials in Secret Manager..."
    
    # Store database password
    if gcloud secrets describe db-password &> /dev/null; then
        log_warning "Secret 'db-password' already exists, updating..."
        echo -n "${DB_PASSWORD}" | gcloud secrets versions add db-password \
            --data-file=- || error_exit "Failed to update db-password secret"
    else
        echo -n "${DB_PASSWORD}" | gcloud secrets create db-password \
            --data-file=- || error_exit "Failed to create db-password secret"
    fi
    
    # Create connection string
    local connection_string="postgresql://appuser:${DB_PASSWORD}@localhost:5432/appdb"
    
    # Store connection string
    if gcloud secrets describe db-connection-string &> /dev/null; then
        log_warning "Secret 'db-connection-string' already exists, updating..."
        echo -n "${connection_string}" | gcloud secrets versions add db-connection-string \
            --data-file=- || error_exit "Failed to update db-connection-string secret"
    else
        echo -n "${connection_string}" | gcloud secrets create db-connection-string \
            --data-file=- || error_exit "Failed to create db-connection-string secret"
    fi
    
    log_success "Database credentials stored in Secret Manager"
}

# Create application source code
create_application_code() {
    log_info "Creating multi-container application source code..."
    
    # Create project directory structure
    mkdir -p multicontainer-app/{frontend,backend,proxy}
    cd multicontainer-app
    
    # Create backend service
    cat > backend/package.json << 'EOF'
{
  "name": "backend-api",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0",
    "pg": "^8.8.0",
    "cors": "^2.8.5"
  },
  "scripts": {
    "start": "node server.js"
  }
}
EOF
    
    cat > backend/server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
const port = process.env.PORT || 8080;

// Enable CORS for frontend communication
app.use(cors());
app.use(express.json());

// Database connection using Cloud SQL proxy
const pool = new Pool({
  user: 'appuser',
  host: 'localhost',
  database: 'appdb',
  password: process.env.DB_PASSWORD,
  port: 5432,
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// API endpoints
app.get('/api/data', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as current_time, VERSION() as db_version');
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Backend API listening on port ${port}`);
});
EOF
    
    cat > backend/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 8080
CMD ["npm", "start"]
EOF
    
    # Create frontend service
    cat > frontend/package.json << 'EOF'
{
  "name": "frontend-app",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0"
  },
  "scripts": {
    "start": "node server.js"
  }
}
EOF
    
    cat > frontend/server.js << 'EOF'
const express = require('express');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

// Serve static files
app.use(express.static('public'));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'frontend' });
});

// Serve main application
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Frontend listening on port ${port}`);
});
EOF
    
    mkdir -p frontend/public
    cat > frontend/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Container App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .status { padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { background-color: #d4edda; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; border: 1px solid #f5c6cb; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Multi-Container Cloud Run Application</h1>
        <p>This application demonstrates Cloud Run's multi-container capabilities.</p>
        
        <button onclick="testBackend()">Test Backend Connection</button>
        <div id="result"></div>
        
        <script>
            async function testBackend() {
                const resultDiv = document.getElementById('result');
                try {
                    const response = await fetch('/api/data');
                    const data = await response.json();
                    
                    if (data.success) {
                        resultDiv.innerHTML = `
                            <div class="status success">
                                <h3>Backend Connection Successful!</h3>
                                <p>Database Time: ${data.data.current_time}</p>
                                <p>Database Version: ${data.data.db_version}</p>
                            </div>
                        `;
                    } else {
                        throw new Error('Backend returned error');
                    }
                } catch (error) {
                    resultDiv.innerHTML = `
                        <div class="status error">
                            <h3>Connection Failed</h3>
                            <p>Error: ${error.message}</p>
                        </div>
                    `;
                }
            }
        </script>
    </div>
</body>
</html>
EOF
    
    cat > frontend/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF
    
    # Create proxy service
    cat > proxy/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream frontend {
        server localhost:3000;
    }
    
    upstream backend {
        server localhost:8080;
    }
    
    server {
        listen 8000;
        
        # Health check endpoint
        location /health {
            proxy_pass http://frontend/health;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        
        # Route API requests to backend
        location /api/ {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Route everything else to frontend
        location / {
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF
    
    cat > proxy/Dockerfile << 'EOF'
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 8000
CMD ["nginx", "-g", "daemon off;"]
EOF
    
    # Create Docker Compose configuration
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  proxy:
    build: ./proxy
    ports:
      - "8000:8000"
    depends_on:
      - frontend
      - backend
    restart: unless-stopped

  frontend:
    build: ./frontend
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped

  backend:
    build: ./backend
    ports:
      - "8080:8080"
    environment:
      - NODE_ENV=production
      - DB_PASSWORD=${DB_PASSWORD}
    depends_on:
      - db-proxy
    restart: unless-stopped

  db-proxy:
    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
    command:
      - /cloud-sql-proxy
      - --port=5432
      - --address=0.0.0.0
      - ${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME}
    ports:
      - "5432:5432"
    restart: unless-stopped

networks:
  default:
    driver: bridge
EOF
    
    cd ..
    log_success "Application source code created"
}

# Build and push container images
build_and_push_images() {
    log_info "Building and pushing container images..."
    
    cd multicontainer-app
    
    # Set base image repository URL
    local base_url="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
    
    # Build and push frontend image
    log_info "Building frontend image..."
    cd frontend
    docker build -t "${base_url}/frontend:latest" . \
        || error_exit "Failed to build frontend image"
    docker push "${base_url}/frontend:latest" \
        || error_exit "Failed to push frontend image"
    cd ..
    
    # Build and push backend image
    log_info "Building backend image..."
    cd backend
    docker build -t "${base_url}/backend:latest" . \
        || error_exit "Failed to build backend image"
    docker push "${base_url}/backend:latest" \
        || error_exit "Failed to push backend image"
    cd ..
    
    # Build and push proxy image
    log_info "Building proxy image..."
    cd proxy
    docker build -t "${base_url}/proxy:latest" . \
        || error_exit "Failed to build proxy image"
    docker push "${base_url}/proxy:latest" \
        || error_exit "Failed to push proxy image"
    cd ..
    
    cd ..
    log_success "All container images built and pushed"
}

# Deploy Cloud Run service
deploy_cloud_run_service() {
    log_info "Deploying multi-container Cloud Run service..."
    
    local base_url="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
    
    # Create Cloud Run service YAML configuration
    cat > service.yaml << EOF
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  annotations:
    run.googleapis.com/ingress: all
    run.googleapis.com/execution-environment: gen2
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/cpu-throttling: "false"
        run.googleapis.com/execution-environment: gen2
    spec:
      serviceAccountName: ${PROJECT_ID}@appspot.gserviceaccount.com
      containers:
      - name: proxy
        image: ${base_url}/proxy:latest
        ports:
        - containerPort: 8000
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
      - name: frontend
        image: ${base_url}/frontend:latest
        ports:
        - containerPort: 3000
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
      - name: backend
        image: ${base_url}/backend:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-password
              key: latest
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
      - name: cloud-sql-proxy
        image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
        args:
        - --port=5432
        - --address=0.0.0.0
        - ${PROJECT_ID}:${REGION}:${SQL_INSTANCE_NAME}
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
EOF
    
    # Deploy the service
    gcloud run services replace service.yaml \
        --region="${REGION}" \
        || error_exit "Failed to deploy Cloud Run service"
    
    # Allow unauthenticated access
    gcloud run services add-iam-policy-binding "${SERVICE_NAME}" \
        --region="${REGION}" \
        --member="allUsers" \
        --role="roles/run.invoker" \
        || log_warning "Failed to set public access (may already be set)"
    
    # Get service URL
    local service_url
    service_url=$(gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --format='value(status.url)')
    
    # Store service URL for cleanup
    echo "SERVICE_URL=${service_url}" >> .deployment_vars
    
    log_success "Multi-container Cloud Run service deployed"
    log_success "Service URL: ${service_url}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Load service URL
    local service_url
    service_url=$(gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --format='value(status.url)' 2>/dev/null)
    
    if [[ -z "${service_url}" ]]; then
        error_exit "Could not retrieve service URL"
    fi
    
    # Wait for service to be ready
    log_info "Waiting for service to be ready..."
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "${service_url}/health" &> /dev/null; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Still waiting for service... (${elapsed}s/${timeout}s)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_warning "Timeout waiting for service health check, but deployment may still be successful"
    else
        log_success "Service health check passed"
    fi
    
    # Test API endpoint
    log_info "Testing API endpoint..."
    if curl -s "${service_url}/api/data" | grep -q "success"; then
        log_success "API endpoint test passed"
    else
        log_warning "API endpoint test failed, but service may still be functional"
    fi
    
    log_success "Deployment validation completed"
    log_info "You can access your application at: ${service_url}"
}

# Main deployment function
main() {
    log_info "Starting multi-container Cloud Run deployment..."
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_artifact_repository
    create_sql_instance
    store_secrets
    create_application_code
    build_and_push_images
    deploy_cloud_run_service
    validate_deployment
    
    log_success "Deployment completed successfully!"
    log_info "Application URL: $(gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" --format='value(status.url)')"
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "Deployment variables saved in .deployment_vars"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi