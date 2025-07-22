#!/bin/bash

set -euo pipefail

# Dynamic Content Delivery with Firebase Hosting and Cloud CDN - Deployment Script
# This script deploys the complete infrastructure for global content delivery
# using Firebase Hosting, Cloud CDN, Cloud Functions, and Cloud Storage

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if Firebase CLI is installed
    if ! command -v firebase &> /dev/null; then
        error "Firebase CLI is not installed. Run: npm install -g firebase-tools"
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js v18+ first."
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'.' -f1 | sed 's/v//')
    if [ "$NODE_VERSION" -lt 18 ]; then
        error "Node.js version 18+ is required. Current version: $(node --version)"
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm first."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please install Google Cloud SDK."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        warning "curl is not available. Some validation tests may not work."
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not available. JSON output formatting may be limited."
    fi
    
    success "All prerequisites checked successfully"
}

# Function to authenticate with Google Cloud and Firebase
authenticate() {
    log "Checking authentication..."
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log "Authenticating with Google Cloud..."
        gcloud auth login
    fi
    
    # Check Firebase authentication
    if ! firebase projects:list &> /dev/null; then
        log "Authenticating with Firebase..."
        firebase login
    fi
    
    success "Authentication verified"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="content-delivery-$(date +%s)"
        log "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION:-us-central1}"
    export LOCATION="${LOCATION:-us-central}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 7)
    export SITE_ID="cdn-demo-${RANDOM_SUFFIX}"
    export STORAGE_BUCKET="${PROJECT_ID}-media"
    export FUNCTION_NAME="dynamic-content-${RANDOM_SUFFIX}"
    
    # Create temporary directory for deployment files
    export DEPLOY_DIR="${DEPLOY_DIR:-$(mktemp -d)}"
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  SITE_ID: ${SITE_ID}"
    log "  STORAGE_BUCKET: ${STORAGE_BUCKET}"
    log "  DEPLOY_DIR: ${DEPLOY_DIR}"
    
    success "Environment setup complete"
}

# Function to create and configure Google Cloud project
create_project() {
    log "Creating and configuring Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Project ${PROJECT_ID} already exists. Skipping creation."
    else
        log "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Dynamic Content Delivery Demo" || \
            error "Failed to create project ${PROJECT_ID}"
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}" || \
        error "Failed to set project ${PROJECT_ID}"
    
    gcloud config set compute/region "${REGION}" || \
        error "Failed to set region ${REGION}"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Billing is not enabled for project ${PROJECT_ID}. Please enable billing manually."
        log "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        read -p "Press Enter after enabling billing..."
    fi
    
    success "Project ${PROJECT_ID} configured successfully"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    REQUIRED_APIS=(
        "firebase.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${REQUIRED_APIS[@]}"; do
        log "Enabling ${api}..."
        if ! gcloud services enable "${api}"; then
            error "Failed to enable API: ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled successfully"
}

# Function to initialize Firebase project
initialize_firebase() {
    log "Initializing Firebase project..."
    
    # Add Firebase to the project
    log "Adding Firebase to project ${PROJECT_ID}..."
    if ! firebase projects:addfirebase "${PROJECT_ID}"; then
        warning "Firebase may already be added to this project, continuing..."
    fi
    
    success "Firebase project initialized"
}

# Function to create application structure
create_application() {
    log "Creating application structure..."
    
    # Create application directory
    mkdir -p "${DEPLOY_DIR}/dynamic-content-app"
    cd "${DEPLOY_DIR}/dynamic-content-app"
    
    # Create directory structure
    mkdir -p public functions media-assets/images
    
    # Create main HTML file
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dynamic E-commerce Demo</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>Global Marketplace</h1>
        <div id="user-info">Loading user data...</div>
    </header>
    
    <main>
        <section id="featured-products">
            <h2>Featured Products</h2>
            <div id="product-grid">Loading products...</div>
        </section>
        
        <section id="user-recommendations">
            <h2>Recommended for You</h2>
            <div id="recommendations">Loading recommendations...</div>
        </section>
    </main>
    
    <script src="app.js"></script>
</body>
</html>
EOF
    
    # Create CSS file
    cat > public/styles.css << 'EOF'
body {
    font-family: 'Segoe UI', sans-serif;
    margin: 0;
    padding: 0;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
}

header {
    background: rgba(255,255,255,0.1);
    padding: 1rem;
    backdrop-filter: blur(10px);
}

.product-card {
    background: white;
    border-radius: 8px;
    padding: 1rem;
    margin: 0.5rem;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    transition: transform 0.2s;
}

.product-card:hover {
    transform: translateY(-2px);
}

#product-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1rem;
    padding: 1rem;
}
EOF
    
    # Create JavaScript application
    cat > public/app.js << 'EOF'
class DynamicContentLoader {
    constructor() {
        this.apiBase = window.location.origin;
        this.cache = new Map();
        this.init();
    }

    async init() {
        await this.loadProducts();
        await this.loadRecommendations();
        this.setupPerformanceMonitoring();
    }

    async loadProducts() {
        try {
            const startTime = performance.now();
            const response = await fetch(`${this.apiBase}/getProducts`);
            const data = await response.json();
            
            const productGrid = document.getElementById('product-grid');
            productGrid.innerHTML = data.products.map(product => `
                <div class="product-card">
                    <h3>${product.name}</h3>
                    <p class="price">${product.regionPrice || product.price}</p>
                    <p class="category">${product.category}</p>
                    <button onclick="this.addToCart(${product.id})">Add to Cart</button>
                </div>
            `).join('');
            
            const loadTime = performance.now() - startTime;
            console.log(`Products loaded in ${loadTime.toFixed(2)}ms from region: ${data.region}`);
            
        } catch (error) {
            console.error('Error loading products:', error);
            document.getElementById('product-grid').innerHTML = 
                '<p>Unable to load products. Please try again later.</p>';
        }
    }

    async loadRecommendations() {
        try {
            const userId = this.getUserId();
            const response = await fetch(`${this.apiBase}/getRecommendations?userId=${userId}`);
            const data = await response.json();
            
            const recommendationsDiv = document.getElementById('recommendations');
            recommendationsDiv.innerHTML = data.recommendations.map(rec => `
                <div class="recommendation-item">
                    <h4>${rec.title}</h4>
                    <p>${rec.count} items</p>
                </div>
            `).join('');
            
        } catch (error) {
            console.error('Error loading recommendations:', error);
        }
    }

    getUserId() {
        let userId = localStorage.getItem('userId');
        if (!userId) {
            userId = 'user_' + Math.random().toString(36).substr(2, 9);
            localStorage.setItem('userId', userId);
        }
        return userId;
    }

    setupPerformanceMonitoring() {
        // Monitor core web vitals if available
        if (window.console) {
            console.log('Performance monitoring initialized');
        }
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new DynamicContentLoader();
});
EOF
    
    success "Application structure created"
}

# Function to create Firebase hosting site
create_hosting_site() {
    log "Creating Firebase hosting site..."
    
    # Create Firebase hosting site
    if ! firebase hosting:sites:create "${SITE_ID}" --project="${PROJECT_ID}"; then
        warning "Site ${SITE_ID} may already exist, continuing..."
    fi
    
    success "Firebase hosting site configured"
}

# Function to create and deploy Cloud Functions
create_cloud_functions() {
    log "Creating Cloud Functions..."
    
    cd "${DEPLOY_DIR}/dynamic-content-app/functions"
    
    # Initialize package.json
    cat > package.json << EOF
{
  "name": "dynamic-content-functions",
  "version": "1.0.0",
  "description": "Cloud Functions for dynamic content delivery",
  "main": "index.js",
  "scripts": {
    "lint": "echo 'Linting skipped'",
    "build": "echo 'Build completed'"
  },
  "dependencies": {
    "firebase-functions": "^4.0.0",
    "firebase-admin": "^11.0.0",
    "cors": "^2.8.5"
  },
  "engines": {
    "node": "18"
  }
}
EOF
    
    # Install dependencies
    log "Installing function dependencies..."
    npm install || error "Failed to install function dependencies"
    
    # Create Cloud Functions
    cat > index.js << 'EOF'
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const cors = require('cors')({origin: true});

admin.initializeApp();

// Dynamic product catalog function
exports.getProducts = functions.https.onRequest((req, res) => {
    cors(req, res, () => {
        const products = [
            {
                id: 1,
                name: "Premium Headphones",
                price: "$299",
                image: "/images/headphones.jpg",
                category: "electronics"
            },
            {
                id: 2,
                name: "Smart Watch",
                price: "$399",
                image: "/images/smartwatch.jpg",
                category: "electronics"
            },
            {
                id: 3,
                name: "Designer Backpack",
                price: "$159",
                image: "/images/backpack.jpg",
                category: "fashion"
            }
        ];
        
        // Simulate personalization based on region
        const userRegion = req.headers['cf-ipcountry'] || 'US';
        const personalizedProducts = products.map(product => ({
            ...product,
            regionPrice: userRegion === 'EU' ? 
                `€${Math.floor(parseInt(product.price.slice(1)) * 0.85)}` : 
                product.price
        }));
        
        // Set caching headers for CDN optimization
        res.set('Cache-Control', 'public, max-age=300, s-maxage=600');
        res.json({ products: personalizedProducts, region: userRegion });
    });
});

// User recommendations function
exports.getRecommendations = functions.https.onRequest((req, res) => {
    cors(req, res, () => {
        const userId = req.query.userId || 'anonymous';
        
        // Simulate ML-based recommendations
        const recommendations = [
            { id: 'rec1', title: 'Similar items viewed', count: 5 },
            { id: 'rec2', title: 'Trending in your area', count: 8 },
            { id: 'rec3', title: 'Recently purchased', count: 3 }
        ];
        
        // Cache recommendations for 5 minutes
        res.set('Cache-Control', 'public, max-age=300');
        res.json({ recommendations, userId });
    });
});
EOF
    
    cd "${DEPLOY_DIR}/dynamic-content-app"
    success "Cloud Functions created"
}

# Function to configure Firebase
configure_firebase() {
    log "Configuring Firebase hosting..."
    
    # Create Firebase configuration
    cat > firebase.json << EOF
{
  "hosting": {
    "site": "${SITE_ID}",
    "public": "public",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "/getProducts",
        "function": "getProducts"
      },
      {
        "source": "/getRecommendations",
        "function": "getRecommendations"
      },
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(css|js)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=31536000, immutable"
          }
        ]
      },
      {
        "source": "**/*.@(jpg|jpeg|gif|png|svg|webp)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=604800"
          }
        ]
      },
      {
        "source": "/",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=300"
          },
          {
            "key": "X-Content-Type-Options",
            "value": "nosniff"
          },
          {
            "key": "X-Frame-Options",
            "value": "DENY"
          }
        ]
      }
    ],
    "cleanUrls": true,
    "trailingSlash": false
  },
  "functions": {
    "predeploy": [
      "npm --prefix \"\$RESOURCE_DIR\" run lint",
      "npm --prefix \"\$RESOURCE_DIR\" run build"
    ],
    "source": "functions"
  }
}
EOF
    
    success "Firebase configuration created"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    if ! firebase deploy --only functions --project="${PROJECT_ID}"; then
        error "Failed to deploy Cloud Functions"
    fi
    
    # Wait for functions to be ready
    log "Waiting for functions to be ready..."
    sleep 30
    
    success "Cloud Functions deployed successfully"
}

# Function to deploy Firebase Hosting
deploy_hosting() {
    log "Deploying Firebase Hosting..."
    
    if ! firebase deploy --only hosting --project="${PROJECT_ID}"; then
        error "Failed to deploy Firebase Hosting"
    fi
    
    # Get hosting URL
    HOSTING_URL=$(firebase hosting:sites:get "${SITE_ID}" \
        --project="${PROJECT_ID}" \
        --format="value(defaultUrl)" 2>/dev/null || echo "")
    
    if [ -n "${HOSTING_URL}" ]; then
        export HOSTING_URL
        log "Hosting URL: ${HOSTING_URL}"
    else
        warning "Could not retrieve hosting URL automatically"
    fi
    
    success "Firebase Hosting deployed successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for media assets..."
    
    # Create bucket
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${STORAGE_BUCKET}"; then
        warning "Bucket ${STORAGE_BUCKET} may already exist, continuing..."
    fi
    
    # Configure bucket for web serving
    gsutil web set -m index.html -e 404.html "gs://${STORAGE_BUCKET}" || \
        warning "Failed to set web configuration for bucket"
    
    # Create sample images
    cd "${DEPLOY_DIR}/dynamic-content-app"
    echo "Sample product image content" > media-assets/images/headphones.jpg
    echo "Sample smartwatch image content" > media-assets/images/smartwatch.jpg
    echo "Sample backpack image content" > media-assets/images/backpack.jpg
    
    # Upload media assets
    log "Uploading media assets..."
    if ! gsutil -m cp -r media-assets/images "gs://${STORAGE_BUCKET}/"; then
        error "Failed to upload media assets"
    fi
    
    # Set caching headers
    gsutil -m setmeta -h "Cache-Control:public, max-age=604800" \
        "gs://${STORAGE_BUCKET}/images/*" || \
        warning "Failed to set caching headers"
    
    # Make bucket publicly readable
    gsutil iam ch allUsers:objectViewer "gs://${STORAGE_BUCKET}" || \
        warning "Failed to set public access on bucket"
    
    success "Cloud Storage bucket configured with CDN optimization"
}

# Function to configure Load Balancer with Cloud CDN
configure_load_balancer() {
    log "Configuring Load Balancer with Cloud CDN..."
    
    # Create backend bucket
    if ! gcloud compute backend-buckets create "${STORAGE_BUCKET}-backend" \
        --gcs-bucket-name="${STORAGE_BUCKET}" \
        --enable-cdn \
        --cache-mode=CACHE_ALL_STATIC \
        --default-ttl=3600 \
        --max-ttl=86400; then
        warning "Backend bucket may already exist, continuing..."
    fi
    
    # Create URL map
    if ! gcloud compute url-maps create cdn-url-map \
        --default-backend-bucket="${STORAGE_BUCKET}-backend"; then
        warning "URL map may already exist, continuing..."
    fi
    
    # Create HTTP target proxy
    if ! gcloud compute target-http-proxies create cdn-http-proxy \
        --url-map=cdn-url-map; then
        warning "HTTP proxy may already exist, continuing..."
    fi
    
    # Create forwarding rule
    if ! gcloud compute forwarding-rules create cdn-forwarding-rule \
        --global \
        --target-http-proxy=cdn-http-proxy \
        --ports=80; then
        warning "Forwarding rule may already exist, continuing..."
    fi
    
    # Get load balancer IP
    LB_IP=$(gcloud compute forwarding-rules describe cdn-forwarding-rule \
        --global --format="value(IPAddress)" 2>/dev/null || echo "")
    
    if [ -n "${LB_IP}" ]; then
        log "Load Balancer IP: ${LB_IP}"
    fi
    
    success "Cloud CDN configured with custom load balancer"
}

# Function to run validation tests
validate_deployment() {
    log "Running deployment validation..."
    
    if [ -n "${HOSTING_URL:-}" ]; then
        log "Testing main application..."
        if curl -f -s "${HOSTING_URL}" > /dev/null; then
            success "Main application is accessible"
        else
            warning "Main application may not be fully ready yet"
        fi
        
        log "Testing CSS loading..."
        if curl -f -s "${HOSTING_URL}/styles.css" > /dev/null; then
            success "Static assets are loading correctly"
        else
            warning "Static assets may not be fully deployed"
        fi
        
        log "Testing dynamic content..."
        sleep 10  # Wait for functions to be ready
        if curl -f -s "${HOSTING_URL}/getProducts" > /dev/null; then
            success "Dynamic content endpoints are working"
        else
            warning "Dynamic content may still be initializing"
        fi
    else
        warning "Hosting URL not available for validation"
    fi
    
    success "Validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Site ID: ${SITE_ID}"
    echo "Storage Bucket: gs://${STORAGE_BUCKET}"
    
    if [ -n "${HOSTING_URL:-}" ]; then
        echo "Hosting URL: ${HOSTING_URL}"
    fi
    
    if [ -n "${LB_IP:-}" ]; then
        echo "Load Balancer IP: ${LB_IP}"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Visit your application at: ${HOSTING_URL:-'Check Firebase console'}"
    echo "2. Monitor performance in Google Cloud Console"
    echo "3. Check Firebase Analytics for user metrics"
    echo "4. Configure custom domain if needed"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Dynamic Content Delivery deployment..."
    
    check_prerequisites
    authenticate
    setup_environment
    create_project
    enable_apis
    initialize_firebase
    create_application
    create_hosting_site
    create_cloud_functions
    configure_firebase
    deploy_functions
    deploy_hosting
    create_storage_bucket
    configure_load_balancer
    validate_deployment
    display_summary
    
    # Save environment variables for cleanup script
    cat > "${DEPLOY_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
SITE_ID=${SITE_ID}
STORAGE_BUCKET=${STORAGE_BUCKET}
FUNCTION_NAME=${FUNCTION_NAME}
HOSTING_URL=${HOSTING_URL:-}
DEPLOY_DIR=${DEPLOY_DIR}
EOF
    
    log "Environment variables saved to ${DEPLOY_DIR}/.env"
    log "Keep this file for cleanup operations"
}

# Handle script interruption
cleanup_on_error() {
    error "Deployment interrupted. Some resources may have been created."
    log "You may need to clean up manually or run the destroy script."
    exit 1
}

trap cleanup_on_error INT TERM

# Run main function
main "$@"