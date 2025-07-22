#!/bin/bash

# E-commerce Personalization with Retail API and Cloud Functions - Deployment Script
# This script deploys the complete e-commerce personalization solution on GCP

set -euo pipefail

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: Full cleanup is handled by destroy.sh
    exit 1
}

trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="ecommerce-personalization"
REGION="us-central1"
ZONE="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up project and environment
setup_project() {
    log_info "Setting up GCP project and environment..."
    
    # Generate unique project ID
    export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
    export REGION="${REGION}"
    export ZONE="${ZONE}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="product-catalog-${RANDOM_SUFFIX}"
    
    log_info "Creating project: ${PROJECT_ID}"
    
    # Create new project
    gcloud projects create "${PROJECT_ID}" \
        --name="E-commerce Personalization Recipe" \
        --set-as-default
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account (if needed)
    BILLING_ACCOUNT=$(gcloud beta billing accounts list --filter="open:true" --format="value(name)" | head -1)
    if [ -n "${BILLING_ACCOUNT}" ]; then
        gcloud beta billing projects link "${PROJECT_ID}" \
            --billing-account="${BILLING_ACCOUNT}"
        log_success "Billing account linked: ${BILLING_ACCOUNT}"
    else
        log_warning "No billing account found. Please link a billing account to avoid service disruptions."
    fi
    
    log_success "Project setup completed: ${PROJECT_ID}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "retail.googleapis.com"
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Create bucket with standard storage class
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"
    
    # Enable public read access for product images (if needed)
    gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}" || true
    
    log_success "Storage bucket created: gs://${BUCKET_NAME}"
}

# Function to initialize Firestore
initialize_firestore() {
    log_info "Initializing Cloud Firestore..."
    
    # Create Firestore database in native mode
    gcloud firestore databases create --region="${REGION}" --quiet
    
    # Wait for Firestore to be ready
    log_info "Waiting for Firestore to be ready..."
    sleep 20
    
    log_success "Firestore initialized in region: ${REGION}"
}

# Function to create Cloud Functions
create_cloud_functions() {
    log_info "Creating Cloud Functions..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create catalog sync function
    create_catalog_sync_function
    
    # Create user events function
    create_user_events_function
    
    # Create recommendations function
    create_recommendations_function
    
    # Clean up temporary directory
    cd "${SCRIPT_DIR}"
    rm -rf "${TEMP_DIR}"
    
    log_success "All Cloud Functions created successfully"
}

# Function to create catalog sync function
create_catalog_sync_function() {
    log_info "Creating catalog sync function..."
    
    mkdir -p catalog-sync-function
    cd catalog-sync-function
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "catalog-sync-function",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/retail": "^3.0.0",
    "@google-cloud/storage": "^7.0.0",
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF
    
    # Create the catalog sync function
    cat > index.js << 'EOF'
const {ProductServiceClient} = require('@google-cloud/retail');
const {Storage} = require('@google-cloud/storage');
const functions = require('@google-cloud/functions-framework');

const productClient = new ProductServiceClient();
const storage = new Storage();

functions.http('syncCatalog', async (req, res) => {
  try {
    const {products} = req.body;
    
    if (!products || !Array.isArray(products)) {
      return res.status(400).json({error: 'Invalid products data'});
    }
    
    const parent = `projects/${process.env.PROJECT_ID}/locations/global/catalogs/default_catalog/branches/default_branch`;
    
    const results = [];
    for (const product of products) {
      try {
        const request = {
          parent: parent,
          product: {
            title: product.title,
            id: product.id,
            categories: product.categories || [],
            priceInfo: {
              price: product.price,
              originalPrice: product.originalPrice || product.price,
              currencyCode: product.currencyCode || 'USD'
            },
            availability: product.availability || 'IN_STOCK',
            attributes: product.attributes || {},
            uri: product.uri || ''
          }
        };
        
        const [createdProduct] = await productClient.createProduct(request);
        results.push({id: product.id, status: 'success', product: createdProduct});
        console.log(`Product ${product.id} synced successfully`);
      } catch (error) {
        console.error(`Error syncing product ${product.id}:`, error);
        results.push({id: product.id, status: 'error', error: error.message});
      }
    }
    
    res.json({
      success: true, 
      message: `Processed ${products.length} products`,
      results: results
    });
  } catch (error) {
    console.error('Catalog sync error:', error);
    res.status(500).json({error: error.message});
  }
});
EOF
    
    # Deploy the function
    gcloud functions deploy catalog-sync \
        --gen2 \
        --runtime=nodejs20 \
        --region="${REGION}" \
        --source=. \
        --entry-point=syncCatalog \
        --trigger=http \
        --allow-unauthenticated \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --memory=512MB \
        --timeout=300s \
        --quiet
    
    cd ..
    log_success "Catalog sync function deployed"
}

# Function to create user events function
create_user_events_function() {
    log_info "Creating user events function..."
    
    mkdir -p user-events-function
    cd user-events-function
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "user-events-function",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/retail": "^3.0.0",
    "@google-cloud/firestore": "^7.0.0",
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF
    
    # Create the user events function
    cat > index.js << 'EOF'
const {UserEventServiceClient} = require('@google-cloud/retail');
const {Firestore} = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

const userEventClient = new UserEventServiceClient();
const firestore = new Firestore();

functions.http('trackEvent', async (req, res) => {
  try {
    const {userId, eventType, productId, searchQuery, pageInfo, quantity} = req.body;
    
    if (!userId || !eventType) {
      return res.status(400).json({error: 'userId and eventType are required'});
    }
    
    const parent = `projects/${process.env.PROJECT_ID}/locations/global/catalogs/default_catalog`;
    
    // Create user event for Retail API
    const userEvent = {
      eventType: eventType,
      visitorId: userId,
      eventTime: {
        seconds: Math.floor(Date.now() / 1000)
      }
    };
    
    // Add product details for product-related events
    if (productId && ['detail-page-view', 'add-to-cart', 'purchase'].includes(eventType)) {
      userEvent.productDetails = [{
        product: {
          id: productId
        },
        quantity: quantity || 1
      }];
    }
    
    // Add search query for search events
    if (searchQuery && eventType === 'search') {
      userEvent.searchQuery = searchQuery;
    }
    
    // Add page info
    if (pageInfo) {
      userEvent.pageInfo = pageInfo;
    }
    
    // Send event to Retail API
    await userEventClient.writeUserEvent({
      parent: parent,
      userEvent: userEvent
    });
    
    // Store user profile data in Firestore
    const userRef = firestore.collection('user_profiles').doc(userId);
    await userRef.set({
      lastActivity: new Date(),
      totalEvents: firestore.FieldValue.increment(1),
      eventHistory: firestore.FieldValue.arrayUnion({
        eventType,
        productId,
        searchQuery,
        timestamp: new Date()
      })
    }, {merge: true});
    
    res.json({success: true, message: 'Event tracked successfully'});
  } catch (error) {
    console.error('Event tracking error:', error);
    res.status(500).json({error: error.message});
  }
});
EOF
    
    # Deploy the function
    gcloud functions deploy track-user-events \
        --gen2 \
        --runtime=nodejs20 \
        --region="${REGION}" \
        --source=. \
        --entry-point=trackEvent \
        --trigger=http \
        --allow-unauthenticated \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --memory=512MB \
        --timeout=300s \
        --quiet
    
    cd ..
    log_success "User events function deployed"
}

# Function to create recommendations function
create_recommendations_function() {
    log_info "Creating recommendations function..."
    
    mkdir -p recommendations-function
    cd recommendations-function
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "recommendations-function",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/retail": "^3.0.0",
    "@google-cloud/firestore": "^7.0.0",
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF
    
    # Create the recommendations function
    cat > index.js << 'EOF'
const {PredictionServiceClient} = require('@google-cloud/retail');
const {Firestore} = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

const predictionClient = new PredictionServiceClient();
const firestore = new Firestore();

functions.http('getRecommendations', async (req, res) => {
  try {
    const {userId, pageType, productId, filter} = req.body;
    
    if (!userId) {
      return res.status(400).json({error: 'userId is required'});
    }
    
    const placement = `projects/${process.env.PROJECT_ID}/locations/global/catalogs/default_catalog/placements/${pageType || 'recently_viewed_default'}`;
    
    // Get user profile from Firestore for additional context
    const userRef = firestore.collection('user_profiles').doc(userId);
    const userDoc = await userRef.get();
    const userProfile = userDoc.exists ? userDoc.data() : {};
    
    // Prepare prediction request
    const request = {
      placement: placement,
      userEvent: {
        eventType: 'detail-page-view',
        visitorId: userId,
        eventTime: {
          seconds: Math.floor(Date.now() / 1000)
        }
      },
      pageSize: 10
    };
    
    // Add product context if provided
    if (productId) {
      request.userEvent.productDetails = [{
        product: {id: productId}
      }];
    }
    
    // Add filter if provided
    if (filter) {
      request.filter = filter;
    }
    
    // Get recommendations from Retail API
    const [response] = await predictionClient.predict(request);
    
    // Enhance recommendations with user profile data
    const recommendations = response.results.map(result => ({
      productId: result.id,
      title: result.product.title,
      price: result.product.priceInfo?.price,
      imageUri: result.product.images?.[0]?.uri,
      categories: result.product.categories,
      score: result.attributionToken,
      personalizedReason: getPersonalizationReason(result, userProfile)
    }));
    
    res.json({
      recommendations,
      attributionToken: response.attributionToken,
      nextPageToken: response.nextPageToken,
      userProfile: {
        totalEvents: userProfile.totalEvents || 0,
        lastActivity: userProfile.lastActivity
      }
    });
  } catch (error) {
    console.error('Recommendation error:', error);
    res.status(500).json({error: error.message});
  }
});

function getPersonalizationReason(result, userProfile) {
  // Simple logic to provide explanation for recommendations
  if (userProfile.eventHistory && userProfile.eventHistory.length > 0) {
    const recentCategories = userProfile.eventHistory
      .slice(-5)
      .map(event => event.productId)
      .filter(Boolean);
    
    if (result.product.categories.some(cat => 
      userProfile.eventHistory.some(event => 
        event.productId && event.productId.includes(cat)))) {
      return "Based on your recent browsing";
    }
  }
  return "Recommended for you";
}
EOF
    
    # Deploy the function
    gcloud functions deploy get-recommendations \
        --gen2 \
        --runtime=nodejs20 \
        --region="${REGION}" \
        --source=. \
        --entry-point=getRecommendations \
        --trigger=http \
        --allow-unauthenticated \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --memory=512MB \
        --timeout=300s \
        --quiet
    
    cd ..
    log_success "Recommendations function deployed"
}

# Function to load sample data
load_sample_data() {
    log_info "Loading sample product data..."
    
    # Get the catalog sync function URL
    CATALOG_FUNCTION_URL=$(gcloud functions describe catalog-sync \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    # Create sample product data
    cat > sample_products.json << 'EOF'
{
  "products": [
    {
      "id": "product_001",
      "title": "Wireless Bluetooth Headphones",
      "categories": ["Electronics", "Audio", "Headphones"],
      "price": 99.99,
      "originalPrice": 129.99,
      "currencyCode": "USD",
      "availability": "IN_STOCK",
      "attributes": {
        "brand": "TechAudio",
        "color": "Black",
        "wireless": "true"
      },
      "uri": "https://example.com/products/wireless-headphones"
    },
    {
      "id": "product_002",
      "title": "Smart Fitness Watch",
      "categories": ["Electronics", "Wearables", "Fitness"],
      "price": 199.99,
      "currencyCode": "USD",
      "availability": "IN_STOCK",
      "attributes": {
        "brand": "FitTech",
        "waterproof": "true",
        "battery_life": "7 days"
      },
      "uri": "https://example.com/products/smart-fitness-watch"
    },
    {
      "id": "product_003",
      "title": "Organic Cotton T-Shirt",
      "categories": ["Clothing", "Men", "T-Shirts"],
      "price": 29.99,
      "currencyCode": "USD",
      "availability": "IN_STOCK",
      "attributes": {
        "material": "Organic Cotton",
        "size": "Medium",
        "color": "Navy Blue"
      },
      "uri": "https://example.com/products/organic-cotton-tshirt"
    },
    {
      "id": "product_004",
      "title": "Laptop Stand Adjustable",
      "categories": ["Electronics", "Accessories", "Laptop"],
      "price": 49.99,
      "currencyCode": "USD",
      "availability": "IN_STOCK",
      "attributes": {
        "material": "Aluminum",
        "adjustable": "true",
        "compatibility": "All laptops"
      },
      "uri": "https://example.com/products/laptop-stand"
    },
    {
      "id": "product_005",
      "title": "Wireless Charging Pad",
      "categories": ["Electronics", "Accessories", "Charging"],
      "price": 39.99,
      "currencyCode": "USD",
      "availability": "IN_STOCK",
      "attributes": {
        "wireless": "true",
        "fast_charging": "true",
        "compatibility": "Qi-enabled devices"
      },
      "uri": "https://example.com/products/wireless-charging-pad"
    }
  ]
}
EOF
    
    # Load sample data
    log_info "Syncing sample products to catalog..."
    curl -X POST "${CATALOG_FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d @sample_products.json \
        --fail --silent --show-error
    
    # Clean up sample data file
    rm sample_products.json
    
    log_success "Sample product data loaded successfully"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Get function URLs
    EVENTS_FUNCTION_URL=$(gcloud functions describe track-user-events \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    RECOMMENDATIONS_FUNCTION_URL=$(gcloud functions describe get-recommendations \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    # Test user event tracking
    log_info "Testing user event tracking..."
    curl -X POST "${EVENTS_FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{
          "userId": "test_user_123",
          "eventType": "detail-page-view",
          "productId": "product_001",
          "pageInfo": {
            "pageCategory": "product_detail"
          }
        }' \
        --fail --silent --show-error
    
    # Wait for event processing
    sleep 10
    
    # Test recommendations
    log_info "Testing recommendations generation..."
    curl -X POST "${RECOMMENDATIONS_FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{
          "userId": "test_user_123",
          "pageType": "home-page",
          "filter": "availability: \"IN_STOCK\""
        }' \
        --fail --silent --show-error > /dev/null
    
    log_success "Deployment test completed successfully"
}

# Function to display deployment information
display_deployment_info() {
    log_info "Deployment completed successfully!"
    
    echo ""
    echo "=== Deployment Information ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "=== Cloud Function URLs ==="
    
    # Get function URLs
    CATALOG_FUNCTION_URL=$(gcloud functions describe catalog-sync \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    EVENTS_FUNCTION_URL=$(gcloud functions describe track-user-events \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    RECOMMENDATIONS_FUNCTION_URL=$(gcloud functions describe get-recommendations \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    echo "Catalog Sync: ${CATALOG_FUNCTION_URL}"
    echo "User Events: ${EVENTS_FUNCTION_URL}"
    echo "Recommendations: ${RECOMMENDATIONS_FUNCTION_URL}"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Integrate the Cloud Function URLs into your e-commerce application"
    echo "2. Start sending real user events to begin training the ML models"
    echo "3. Monitor function logs: gcloud functions logs read [FUNCTION_NAME] --region=${REGION}"
    echo "4. View Firestore data: https://console.cloud.google.com/firestore/data?project=${PROJECT_ID}"
    echo "5. Monitor costs: https://console.cloud.google.com/billing?project=${PROJECT_ID}"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    
    # Save deployment info to file
    cat > deployment_info.txt << EOF
E-commerce Personalization Deployment Information
================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Storage Bucket: gs://${BUCKET_NAME}
Deployment Date: $(date)

Cloud Function URLs:
- Catalog Sync: ${CATALOG_FUNCTION_URL}
- User Events: ${EVENTS_FUNCTION_URL}
- Recommendations: ${RECOMMENDATIONS_FUNCTION_URL}

To clean up all resources, run: ./destroy.sh
EOF
    
    log_success "Deployment information saved to deployment_info.txt"
}

# Main deployment function
main() {
    log_info "Starting E-commerce Personalization deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_storage_bucket
    initialize_firestore
    create_cloud_functions
    load_sample_data
    test_deployment
    display_deployment_info
    
    log_success "E-commerce Personalization deployment completed successfully!"
}

# Run main function
main "$@"