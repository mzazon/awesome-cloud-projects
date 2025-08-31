# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.app_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Resource names
  bucket_name           = "${var.project_id}-product-data-${local.name_suffix}"
  datastore_id         = "products-${local.name_suffix}"
  search_engine_id     = "catalog-search-${local.name_suffix}"
  cloud_run_service    = "${local.name_prefix}-${local.name_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    recipe      = "smart-product-catalog"
  })
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Firestore database
resource "google_firestore_database" "product_database" {
  provider = google-beta
  
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location_id
  type        = var.firestore_type
  
  # Ensure APIs are enabled first
  depends_on = [
    google_project_service.apis
  ]
  
  lifecycle {
    prevent_destroy = true
  }
}

# Cloud Storage bucket for product data
resource "google_storage_bucket" "product_data" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable versioning if specified
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for old versions if versioning is enabled
  dynamic "lifecycle_rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      condition {
        age                   = var.lifecycle_age_days
        with_state           = "ARCHIVED"
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis
  ]
}

# Create sample product data file
resource "local_file" "sample_products" {
  count = var.create_sample_data ? 1 : 0
  
  filename = "${path.module}/products.jsonl"
  content = jsonencode({
    id      = "prod-001"
    content = "Wireless Bluetooth Headphones - Premium noise-cancelling over-ear headphones with 30-hour battery life. Perfect for music lovers and professionals."
    category = "Electronics"
    brand   = "AudioTech"
    price   = 199.99
    rating  = 4.5
    tags    = ["wireless", "bluetooth", "noise-cancelling", "headphones"]
  })
  
  # Note: This creates only one product for demonstration
  # In practice, you would use a template or external data source
}

# Upload sample data to Cloud Storage (if enabled)
resource "google_storage_bucket_object" "sample_data" {
  count = var.create_sample_data && var.sample_data_file == "" ? 1 : 0
  
  name   = "products.jsonl"
  bucket = google_storage_bucket.product_data.name
  
  # Create comprehensive sample data
  content = <<-EOT
{"id": "prod-001", "content": "Wireless Bluetooth Headphones - Premium noise-cancelling over-ear headphones with 30-hour battery life. Perfect for music lovers and professionals.", "category": "Electronics", "brand": "AudioTech", "price": 199.99, "rating": 4.5, "tags": ["wireless", "bluetooth", "noise-cancelling", "headphones"]}
{"id": "prod-002", "content": "Organic Cotton T-Shirt - Soft, comfortable, and sustainably made t-shirt available in multiple colors. Made from 100% organic cotton.", "category": "Clothing", "brand": "EcoWear", "price": 29.99, "rating": 4.3, "tags": ["organic", "cotton", "sustainable", "t-shirt"]}
{"id": "prod-003", "content": "Smart Fitness Tracker - Advanced health monitoring with heart rate, sleep tracking, and GPS. Water-resistant with 7-day battery life.", "category": "Fitness", "brand": "HealthTech", "price": 149.99, "rating": 4.7, "tags": ["fitness", "tracker", "health", "gps", "waterproof"]}
{"id": "prod-004", "content": "Professional Coffee Maker - Programmable drip coffee maker with thermal carafe and built-in grinder. Makes perfect coffee every time.", "category": "Kitchen", "brand": "BrewMaster", "price": 299.99, "rating": 4.4, "tags": ["coffee", "maker", "programmable", "grinder"]}
{"id": "prod-005", "content": "Wireless Gaming Mouse - High-precision gaming mouse with customizable RGB lighting and ergonomic design. Perfect for competitive gaming.", "category": "Electronics", "brand": "GameGear", "price": 79.99, "rating": 4.6, "tags": ["gaming", "mouse", "wireless", "rgb", "ergonomic"]}
EOT
  
  content_type = "application/x-ndjson"
}

# Upload custom sample data (if provided)
resource "google_storage_bucket_object" "custom_sample_data" {
  count = var.create_sample_data && var.sample_data_file != "" ? 1 : 0
  
  name   = "products.jsonl"
  bucket = google_storage_bucket.product_data.name
  source = var.sample_data_file
  
  content_type = "application/x-ndjson"
}

# Create Vertex AI Search data store
resource "google_discovery_engine_data_store" "product_datastore" {
  provider = google-beta
  
  location          = "global"
  data_store_id     = local.datastore_id
  display_name      = "Product Catalog Data Store"
  industry_vertical = var.search_industry_vertical
  solution_types    = ["SOLUTION_TYPE_SEARCH"]
  content_config    = var.search_content_config
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.sample_data,
    google_storage_bucket_object.custom_sample_data
  ]
}

# Import data into Vertex AI Search
resource "null_resource" "import_search_data" {
  count = var.create_sample_data ? 1 : 0
  
  # Trigger re-run if data changes
  triggers = {
    data_store_id = google_discovery_engine_data_store.product_datastore.data_store_id
    bucket_name   = google_storage_bucket.product_data.name
    data_file     = var.sample_data_file != "" ? filemd5(var.sample_data_file) : "default"
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      gcloud alpha discovery-engine documents import \
        --data-store=${google_discovery_engine_data_store.product_datastore.data_store_id} \
        --location=global \
        --gcs-uri="gs://${google_storage_bucket.product_data.name}/products.jsonl" \
        --reconciliation-mode=INCREMENTAL \
        --project=${var.project_id}
    EOT
  }
  
  depends_on = [
    google_discovery_engine_data_store.product_datastore,
    google_storage_bucket_object.sample_data,
    google_storage_bucket_object.custom_sample_data
  ]
}

# Create Vertex AI Search engine
resource "google_discovery_engine_search_engine" "product_search" {
  provider = google-beta
  
  engine_id         = local.search_engine_id
  collection_id     = "default_collection"
  location          = "global"
  display_name      = "Product Catalog Search Engine"
  industry_vertical = var.search_industry_vertical
  
  data_store_ids = [google_discovery_engine_data_store.product_datastore.data_store_id]
  
  search_engine_config {
    search_tier    = "SEARCH_TIER_STANDARD"
    search_add_ons = ["SEARCH_ADD_ON_LLM"]
  }
  
  depends_on = [
    google_discovery_engine_data_store.product_datastore,
    null_resource.import_search_data
  ]
}

# Service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${local.name_prefix}-run-sa-${local.name_suffix}"
  display_name = "Cloud Run Service Account for Product Catalog"
  description  = "Service account for Cloud Run service to access Vertex AI Search and Firestore"
}

# IAM roles for service account
resource "google_project_iam_member" "cloud_run_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_discoveryengine" {
  project = var.project_id
  role    = "roles/discoveryengine.editor"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_monitoring" {
  count = var.enable_monitoring ? 1 : 0
  
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create application source code files
resource "local_file" "main_py" {
  filename = "${path.module}/app/main.py"
  content = <<-EOT
import os
from flask import Flask, request, jsonify
from google.cloud import discoveryengine
from google.cloud import firestore
import json

app = Flask(__name__)

# Initialize clients
search_client = discoveryengine.SearchServiceClient()
db = firestore.Client()

PROJECT_ID = os.environ.get('PROJECT_ID')
SEARCH_ENGINE_ID = os.environ.get('SEARCH_ENGINE_ID')
DATASTORE_ID = os.environ.get('DATASTORE_ID')

@app.route('/health')
def health_check():
    return jsonify({"status": "healthy", "service": "product-catalog"})

@app.route('/search')
def search_products():
    query = request.args.get('q', '')
    page_size = int(request.args.get('page_size', 10))
    
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400
    
    try:
        # Configure search request
        serving_config = f"projects/{PROJECT_ID}/locations/global/collections/default_collection/engines/{SEARCH_ENGINE_ID}/servingConfigs/default_config"
        
        search_request = discoveryengine.SearchRequest(
            serving_config=serving_config,
            query=query,
            page_size=page_size,
            content_search_spec=discoveryengine.SearchRequest.ContentSearchSpec(
                snippet_spec=discoveryengine.SearchRequest.ContentSearchSpec.SnippetSpec(
                    return_snippet=True
                ),
                summary_spec=discoveryengine.SearchRequest.ContentSearchSpec.SummarySpec(
                    summary_result_count=3
                )
            )
        )
        
        # Execute search
        response = search_client.search(search_request)
        
        # Process results
        results = []
        for result in response.results:
            doc_data = {}
            if hasattr(result.document, 'derived_struct_data'):
                doc_data = dict(result.document.derived_struct_data)
            
            results.append({
                "id": result.document.id,
                "content": doc_data.get('content', ''),
                "category": doc_data.get('category', ''),
                "brand": doc_data.get('brand', ''),
                "price": doc_data.get('price', 0),
                "rating": doc_data.get('rating', 0),
                "snippet": getattr(result.document, 'snippet', {}).get('snippet', '')
            })
        
        return jsonify({
            "query": query,
            "results": results,
            "total_results": len(results)
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/recommend')
def get_recommendations():
    product_id = request.args.get('product_id', '')
    page_size = int(request.args.get('page_size', 5))
    
    if not product_id:
        return jsonify({"error": "Parameter 'product_id' is required"}), 400
    
    try:
        # Simple recommendation based on category similarity
        product_ref = db.collection('products').document(product_id)
        product_doc = product_ref.get()
        
        if not product_doc.exists:
            return jsonify({"error": "Product not found"}), 404
        
        product_data = product_doc.to_dict()
        category = product_data.get('category', '')
        
        # Find similar products in the same category
        similar_products = db.collection('products').where('category', '==', category).limit(page_size + 1).stream()
        
        recommendations = []
        for doc in similar_products:
            if doc.id != product_id:  # Exclude the current product
                recommendations.append({
                    "id": doc.id,
                    **doc.to_dict()
                })
        
        return jsonify({
            "product_id": product_id,
            "recommendations": recommendations[:page_size]
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOT
}

resource "local_file" "requirements_txt" {
  filename = "${path.module}/app/requirements.txt"
  content = <<-EOT
Flask==3.0.3
google-cloud-discoveryengine==0.13.10
google-cloud-firestore==2.19.0
gunicorn==22.0.0
EOT
}

resource "local_file" "dockerfile" {
  filename = "${path.module}/app/Dockerfile"
  content = <<-EOT
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOT
}

# Create Cloud Build configuration for building container
resource "local_file" "cloudbuild_yaml" {
  filename = "${path.module}/app/cloudbuild.yaml"
  content = <<-EOT
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - '$_IMAGE_NAME'
      - '.'
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '$_IMAGE_NAME'

substitutions:
  _IMAGE_NAME: '${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-repo/${local.cloud_run_service}:latest'

options:
  logging: CLOUD_LOGGING_ONLY
EOT
}

# Create Artifact Registry repository
resource "google_artifact_registry_repository" "container_repo" {
  location      = var.region
  repository_id = "${local.name_prefix}-repo"
  description   = "Container repository for product catalog application"
  format        = "DOCKER"
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis
  ]
}

# Build and push container image
resource "null_resource" "build_and_push" {
  # Trigger rebuild when source code changes
  triggers = {
    main_py_hash         = md5(local_file.main_py.content)
    requirements_hash    = md5(local_file.requirements_txt.content)
    dockerfile_hash      = md5(local_file.dockerfile.content)
    cloudbuild_hash      = md5(local_file.cloudbuild_yaml.content)
  }
  
  provisioner "local-exec" {
    working_dir = "${path.module}/app"
    command = <<-EOT
      gcloud builds submit \
        --config=cloudbuild.yaml \
        --substitutions=_IMAGE_NAME=${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-repo/${local.cloud_run_service}:latest \
        --project=${var.project_id}
    EOT
  }
  
  depends_on = [
    google_artifact_registry_repository.container_repo,
    local_file.main_py,
    local_file.requirements_txt,
    local_file.dockerfile,
    local_file.cloudbuild_yaml
  ]
}

# Deploy Cloud Run service
resource "google_cloud_run_v2_service" "product_catalog" {
  name     = local.cloud_run_service
  location = var.region
  
  template {
    service_account = google_service_account.cloud_run_sa.email
    
    # Set maximum instances
    scaling {
      max_instance_count = var.cloud_run_max_instances
    }
    
    # VPC connector (if specified)
    dynamic "vpc_access" {
      for_each = var.vpc_connector_name != "" ? [1] : []
      content {
        connector = var.vpc_connector_name
      }
    }
    
    containers {
      image = var.container_image != "" ? var.container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-repo/${local.cloud_run_service}:latest"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "SEARCH_ENGINE_ID"
        value = google_discovery_engine_search_engine.product_search.engine_id
      }
      env {
        name  = "DATASTORE_ID"
        value = google_discovery_engine_data_store.product_datastore.data_store_id
      }
      env {
        name  = "LOG_LEVEL"
        value = var.log_level
      }
      
      # Health check and startup configuration
      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
    
    # Request timeout
    timeout = "${var.cloud_run_timeout}s"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_service_account.cloud_run_sa,
    google_project_iam_member.cloud_run_firestore,
    google_project_iam_member.cloud_run_discoveryengine,
    google_project_iam_member.cloud_run_logging,
    google_discovery_engine_search_engine.product_search,
    null_resource.build_and_push
  ]
}

# IAM policy for public access (if enabled)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_v2_service.product_catalog.location
  service  = google_cloud_run_v2_service.product_catalog.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Add sample products to Firestore
resource "null_resource" "add_sample_products" {
  count = var.create_sample_data ? 1 : 0
  
  # Trigger when Firestore is ready
  triggers = {
    firestore_ready = google_firestore_database.product_database.name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      python3 -c "
import json
from google.cloud import firestore

# Initialize Firestore client
db = firestore.Client(project='${var.project_id}')

# Sample product data
products = [
    {'id': 'prod-001', 'content': 'Wireless Bluetooth Headphones', 'category': 'Electronics', 'brand': 'AudioTech', 'price': 199.99, 'rating': 4.5},
    {'id': 'prod-002', 'content': 'Organic Cotton T-Shirt', 'category': 'Clothing', 'brand': 'EcoWear', 'price': 29.99, 'rating': 4.3},
    {'id': 'prod-003', 'content': 'Smart Fitness Tracker', 'category': 'Fitness', 'brand': 'HealthTech', 'price': 149.99, 'rating': 4.7},
    {'id': 'prod-004', 'content': 'Professional Coffee Maker', 'category': 'Kitchen', 'brand': 'BrewMaster', 'price': 299.99, 'rating': 4.4},
    {'id': 'prod-005', 'content': 'Wireless Gaming Mouse', 'category': 'Electronics', 'brand': 'GameGear', 'price': 79.99, 'rating': 4.6}
]

# Add products to Firestore
for product in products:
    doc_ref = db.collection('products').document(product['id'])
    doc_ref.set(product)
    print(f'Added product: {product[\"id\"]}')

print('✅ All products added to Firestore')
"
    EOT
  }
  
  depends_on = [
    google_firestore_database.product_database,
    google_project_service.apis
  ]
}