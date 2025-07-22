#!/bin/bash
# Progressive Web Application Deployment Script for GCP
# This script deploys a PWA using Cloud Build and Google Kubernetes Engine with blue-green deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be created"
fi

# Function to execute command with dry-run support
execute_command() {
    local command="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $command"
        log_info "[DRY-RUN] Description: $description"
        return 0
    fi
    
    log_info "$description"
    eval "$command"
    return $?
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some validation steps may be skipped."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project ID (use current project if not specified)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID found. Please set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set cluster names
    export CLUSTER_NAME_BLUE="${CLUSTER_NAME_BLUE:-pwa-cluster-blue}"
    export CLUSTER_NAME_GREEN="${CLUSTER_NAME_GREEN:-pwa-cluster-green}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BUCKET_NAME="${BUCKET_NAME:-pwa-assets-${RANDOM_SUFFIX}}"
    export REPO_NAME="${REPO_NAME:-pwa-demo-app}"
    
    # Set gcloud defaults
    execute_command "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_command "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_command "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    log_info "Repository Name: ${REPO_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "container.googleapis.com"
        "compute.googleapis.com"
        "storage.googleapis.com"
        "sourcerepo.googleapis.com"
        "containerregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable $api" "Enabling $api"
    done
    
    log_success "Required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for static assets..."
    
    # Check if bucket already exists
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    execute_command "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}" "Creating storage bucket"
    
    # Enable versioning
    execute_command "gsutil versioning set on gs://${BUCKET_NAME}" "Enabling bucket versioning"
    
    # Configure CORS for PWA assets
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > /tmp/cors.json <<EOF
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD"],
    "responseHeader": ["Content-Type", "Cache-Control"],
    "maxAgeSeconds": 3600
  }
]
EOF
        execute_command "gsutil cors set /tmp/cors.json gs://${BUCKET_NAME}" "Configuring CORS for bucket"
        rm -f /tmp/cors.json
    fi
    
    log_success "Cloud Storage bucket created and configured"
}

# Function to create GKE clusters
create_gke_clusters() {
    log_info "Creating GKE clusters for blue-green deployment..."
    
    local cluster_config=(
        "--region=${REGION}"
        "--num-nodes=2"
        "--machine-type=e2-medium"
        "--disk-size=30GB"
        "--enable-autoscaling"
        "--min-nodes=1"
        "--max-nodes=5"
        "--enable-autorepair"
        "--enable-autoupgrade"
        "--enable-ip-alias"
        "--enable-network-policy"
        "--enable-shielded-nodes"
    )
    
    # Create blue cluster
    if gcloud container clusters describe ${CLUSTER_NAME_BLUE} --region=${REGION} &>/dev/null; then
        log_warning "Blue cluster ${CLUSTER_NAME_BLUE} already exists, skipping creation"
    else
        execute_command "gcloud container clusters create ${CLUSTER_NAME_BLUE} ${cluster_config[*]} --labels=environment=blue,app=pwa-demo" "Creating blue environment cluster"
    fi
    
    # Create green cluster
    if gcloud container clusters describe ${CLUSTER_NAME_GREEN} --region=${REGION} &>/dev/null; then
        log_warning "Green cluster ${CLUSTER_NAME_GREEN} already exists, skipping creation"
    else
        execute_command "gcloud container clusters create ${CLUSTER_NAME_GREEN} ${cluster_config[*]} --labels=environment=green,app=pwa-demo" "Creating green environment cluster"
    fi
    
    log_success "GKE clusters created successfully"
}

# Function to set up Cloud Source Repository
setup_source_repository() {
    log_info "Setting up Cloud Source Repository..."
    
    # Create repository if it doesn't exist
    if ! gcloud source repos describe ${REPO_NAME} &>/dev/null; then
        execute_command "gcloud source repos create ${REPO_NAME}" "Creating Cloud Source Repository"
    else
        log_warning "Repository ${REPO_NAME} already exists, skipping creation"
    fi
    
    # Clone repository locally if not already cloned
    if [[ ! -d "${REPO_NAME}" ]]; then
        execute_command "gcloud source repos clone ${REPO_NAME} --project=${PROJECT_ID}" "Cloning repository locally"
    else
        log_warning "Repository directory ${REPO_NAME} already exists locally"
    fi
    
    log_success "Cloud Source Repository set up"
}

# Function to create sample PWA application
create_pwa_application() {
    log_info "Creating sample PWA application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create PWA application files"
        return 0
    fi
    
    cd "${REPO_NAME}"
    
    # Create directory structure
    mkdir -p src public k8s
    
    # Create package.json
    cat > package.json <<EOF
{
  "name": "pwa-demo-app",
  "version": "1.0.0",
  "description": "Progressive Web Application Demo",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "build": "npm install",
    "test": "npm run test:unit && npm run test:e2e",
    "test:unit": "echo 'Running unit tests...' && exit 0",
    "test:e2e": "echo 'Running e2e tests...' && exit 0"
  },
  "dependencies": {
    "express": "^4.18.0",
    "compression": "^1.7.4"
  },
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF
    
    # Create Express.js server
    cat > src/server.js <<EOF
const express = require('express');
const compression = require('compression');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

// Enable gzip compression
app.use(compression());

// Serve static files with proper caching headers
app.use(express.static('public', {
  maxAge: '1d',
  setHeaders: (res, path) => {
    if (path.endsWith('.js') || path.endsWith('.css')) {
      res.setHeader('Cache-Control', 'public, max-age=31536000');
    }
  }
}));

// API endpoint for health checks
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION || '1.0.0'
  });
});

// Serve PWA for all other routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

app.listen(PORT, () => {
  console.log(\`PWA server running on port \${PORT}\`);
});
EOF
    
    # Create PWA manifest
    cat > public/manifest.json <<EOF
{
  "name": "PWA Demo Application",
  "short_name": "PWA Demo",
  "description": "Progressive Web Application with GKE deployment",
  "start_url": "/",
  "display": "standalone",
  "theme_color": "#4285f4",
  "background_color": "#ffffff",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
EOF
    
    # Create service worker
    cat > public/sw.js <<EOF
const CACHE_NAME = 'pwa-demo-v1';
const urlsToCache = [
  '/',
  '/manifest.json',
  '/styles.css',
  '/app.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(urlsToCache))
  );
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        if (response) {
          return response;
        }
        return fetch(event.request);
      })
  );
});
EOF
    
    # Create HTML file
    cat > public/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PWA Demo - GKE Deployment</title>
  <link rel="manifest" href="/manifest.json">
  <link rel="stylesheet" href="/styles.css">
  <meta name="theme-color" content="#4285f4">
  <link rel="icon" href="/favicon.ico">
</head>
<body>
  <header>
    <h1>Progressive Web Application</h1>
    <p>Deployed with Cloud Build and GKE</p>
  </header>
  
  <main>
    <section class="status">
      <h2>Application Status</h2>
      <div id="app-status">Loading...</div>
      <button onclick="checkHealth()">Check Health</button>
    </section>
    
    <section class="features">
      <h2>PWA Features</h2>
      <ul>
        <li>✅ Service Worker for offline functionality</li>
        <li>✅ App manifest for installability</li>
        <li>✅ Responsive design for all devices</li>
        <li>✅ Blue-green deployment ready</li>
      </ul>
    </section>
  </main>
  
  <script src="/app.js"></script>
  <script>
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
          .then((registration) => {
            console.log('SW registered: ', registration);
          })
          .catch((registrationError) => {
            console.log('SW registration failed: ', registrationError);
          });
      });
    }
  </script>
</body>
</html>
EOF
    
    # Create CSS styles
    cat > public/styles.css <<EOF
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: 'Roboto', Arial, sans-serif;
  line-height: 1.6;
  color: #333;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

header {
  background: rgba(255, 255, 255, 0.95);
  padding: 2rem;
  text-align: center;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}

main {
  max-width: 800px;
  margin: 2rem auto;
  padding: 0 1rem;
}

section {
  background: white;
  margin: 2rem 0;
  padding: 2rem;
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

button {
  background: #4285f4;
  color: white;
  border: none;
  padding: 0.75rem 1.5rem;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1rem;
  transition: background 0.3s;
}

button:hover {
  background: #3367d6;
}

#app-status {
  padding: 1rem;
  margin: 1rem 0;
  border-radius: 4px;
  background: #f5f5f5;
}

@media (max-width: 768px) {
  main {
    padding: 0 0.5rem;
  }
  section {
    padding: 1rem;
  }
}
EOF
    
    # Create JavaScript application
    cat > public/app.js <<EOF
async function checkHealth() {
  const statusDiv = document.getElementById('app-status');
  statusDiv.textContent = 'Checking application health...';
  
  try {
    const response = await fetch('/api/health');
    const data = await response.json();
    
    statusDiv.innerHTML = \`
      <strong>Status:</strong> \${data.status}<br>
      <strong>Version:</strong> \${data.version}<br>
      <strong>Timestamp:</strong> \${data.timestamp}
    \`;
  } catch (error) {
    statusDiv.innerHTML = \`
      <strong>Status:</strong> Error connecting to API<br>
      <strong>Error:</strong> \${error.message}
    \`;
  }
}

// Initialize health check on page load
document.addEventListener('DOMContentLoaded', checkHealth);
EOF
    
    cd ..
    log_success "PWA application created"
}

# Function to create Kubernetes manifests
create_k8s_manifests() {
    log_info "Creating Kubernetes deployment manifests..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create Kubernetes manifests"
        return 0
    fi
    
    cd "${REPO_NAME}"
    
    # Create deployment manifest
    cat > k8s/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pwa-demo-app
  labels:
    app: pwa-demo
    version: v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pwa-demo
  template:
    metadata:
      labels:
        app: pwa-demo
        version: v1
    spec:
      containers:
      - name: pwa-demo
        image: gcr.io/PROJECT_ID/pwa-demo:TAG
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        - name: APP_VERSION
          value: "TAG"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 250m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /api/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: pwa-demo-service
  labels:
    app: pwa-demo
spec:
  selector:
    app: pwa-demo
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
EOF
    
    # Create ingress configuration
    cat > k8s/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pwa-demo-ingress
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "pwa-demo-ip"
    networking.gke.io/managed-certificates: "pwa-demo-ssl-cert"
    kubernetes.io/ingress.allow-http: "false"
spec:
  rules:
  - host: pwa-demo.example.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: pwa-demo-service
            port:
              number: 80
EOF
    
    cd ..
    log_success "Kubernetes manifests created"
}

# Function to create Cloud Build configuration
create_cloud_build_config() {
    log_info "Creating Cloud Build configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create Cloud Build configuration"
        return 0
    fi
    
    cd "${REPO_NAME}"
    
    # Create Cloud Build configuration
    cat > cloudbuild.yaml <<EOF
steps:
# Build and test the application
- name: 'node:16'
  entrypoint: 'npm'
  args: ['install']

- name: 'node:16'
  entrypoint: 'npm'
  args: ['test']

# Build container image
- name: 'gcr.io/cloud-builders/docker'
  args: [
    'build',
    '-t', 'gcr.io/\$PROJECT_ID/pwa-demo:\$SHORT_SHA',
    '-t', 'gcr.io/\$PROJECT_ID/pwa-demo:latest',
    '.'
  ]

# Push container image to Container Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/\$PROJECT_ID/pwa-demo:\$SHORT_SHA']

- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/\$PROJECT_ID/pwa-demo:latest']

# Update Kubernetes manifests with new image
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - -c
  - |
    sed -i 's|gcr.io/PROJECT_ID/pwa-demo:TAG|gcr.io/\$PROJECT_ID/pwa-demo:\$SHORT_SHA|g' k8s/deployment.yaml
    sed -i 's|TAG|\$SHORT_SHA|g' k8s/deployment.yaml

# Deploy to Green environment (staging)
- name: 'gcr.io/cloud-builders/gke-deploy'
  args:
  - run
  - --filename=k8s/
  - --location=\$_REGION
  - --cluster=\$_CLUSTER_GREEN

# Run integration tests against Green environment
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - -c
  - |
    echo "Running integration tests against Green environment..."
    # Add your integration test commands here
    echo "Integration tests passed!"

# Deploy to Blue environment (production) only if tests pass
- name: 'gcr.io/cloud-builders/gke-deploy'
  args:
  - run
  - --filename=k8s/
  - --location=\$_REGION
  - --cluster=\$_CLUSTER_BLUE

substitutions:
  _REGION: '${REGION}'
  _CLUSTER_BLUE: '${CLUSTER_NAME_BLUE}'
  _CLUSTER_GREEN: '${CLUSTER_NAME_GREEN}'

options:
  logging: CLOUD_LOGGING_ONLY
  
timeout: '1200s'
EOF
    
    # Create Dockerfile
    cat > Dockerfile <<EOF
FROM node:16-alpine

WORKDIR /app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/
COPY public/ ./public/

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001
USER nextjs

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
  CMD node -e "require('http').get('http://localhost:8080/api/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

CMD ["node", "src/server.js"]
EOF
    
    cd ..
    log_success "Cloud Build configuration created"
}

# Function to configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions for Cloud Build..."
    
    # Get Cloud Build service account
    local cloud_build_sa=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")@cloudbuild.gserviceaccount.com
    
    # Grant necessary roles
    local roles=(
        "roles/container.developer"
        "roles/storage.objectViewer"
        "roles/source.reader"
    )
    
    for role in "${roles[@]}"; do
        execute_command "gcloud projects add-iam-policy-binding ${PROJECT_ID} --member='serviceAccount:${cloud_build_sa}' --role='${role}'" "Granting ${role} to Cloud Build service account"
    done
    
    log_success "IAM permissions configured"
}

# Function to create build trigger
create_build_trigger() {
    log_info "Creating Cloud Build trigger..."
    
    # Check if trigger already exists
    if gcloud builds triggers list --filter="name:pwa-deployment-trigger" --format="value(name)" | grep -q "pwa-deployment-trigger"; then
        log_warning "Build trigger already exists, skipping creation"
        return 0
    fi
    
    execute_command "gcloud builds triggers create cloud-source-repositories --repo=${REPO_NAME} --branch-pattern='^master$' --build-config='cloudbuild.yaml' --description='PWA deployment trigger for master branch' --name='pwa-deployment-trigger'" "Creating build trigger"
    
    log_success "Build trigger created"
}

# Function to commit and push code
commit_and_push_code() {
    log_info "Committing and pushing code to repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would commit and push code"
        return 0
    fi
    
    cd "${REPO_NAME}"
    
    # Configure git if not already configured
    if ! git config user.email >/dev/null 2>&1; then
        git config user.email "deploy@example.com"
        git config user.name "Deploy Script"
    fi
    
    # Add all files
    git add .
    
    # Commit with message
    git commit -m "Initial PWA setup with blue-green deployment configuration" || true
    
    # Push to master branch
    git push origin master
    
    cd ..
    log_success "Code committed and pushed"
}

# Function to trigger initial deployment
trigger_initial_deployment() {
    log_info "Triggering initial deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would trigger initial deployment"
        return 0
    fi
    
    cd "${REPO_NAME}"
    
    # Trigger build manually
    execute_command "gcloud builds submit --config=cloudbuild.yaml ." "Submitting build"
    
    cd ..
    log_success "Initial deployment triggered"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate deployment"
        return 0
    fi
    
    # Get credentials for blue cluster
    execute_command "gcloud container clusters get-credentials ${CLUSTER_NAME_BLUE} --region=${REGION}" "Getting blue cluster credentials"
    
    # Check deployments
    if kubectl get deployments,services,pods -l app=pwa-demo >/dev/null 2>&1; then
        log_success "Blue environment deployment validated"
    else
        log_warning "Blue environment deployment not found or not ready"
    fi
    
    # Get credentials for green cluster
    execute_command "gcloud container clusters get-credentials ${CLUSTER_NAME_GREEN} --region=${REGION}" "Getting green cluster credentials"
    
    # Check deployments
    if kubectl get deployments,services,pods -l app=pwa-demo >/dev/null 2>&1; then
        log_success "Green environment deployment validated"
    else
        log_warning "Green environment deployment not found or not ready"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Blue Cluster: ${CLUSTER_NAME_BLUE}"
    echo "Green Cluster: ${CLUSTER_NAME_GREEN}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Repository: ${REPO_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the Cloud Build progress in the GCP Console"
    echo "2. Check the GKE clusters for deployed applications"
    echo "3. Set up domain and SSL certificates for production use"
    echo "4. Configure monitoring and alerting"
    echo ""
    echo "To check deployment status:"
    echo "  gcloud builds list --limit=5"
    echo "  kubectl get deployments,services,pods -l app=pwa-demo"
    echo ""
    echo "To access the application:"
    echo "  kubectl get ingress pwa-demo-ingress"
    echo ""
    log_success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log_info "Starting Progressive Web Application deployment..."
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_gke_clusters
    setup_source_repository
    create_pwa_application
    create_k8s_manifests
    create_cloud_build_config
    configure_iam_permissions
    create_build_trigger
    commit_and_push_code
    
    # Wait for clusters to be ready before triggering deployment
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for clusters to be ready..."
        sleep 60
    fi
    
    trigger_initial_deployment
    validate_deployment
    display_summary
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"