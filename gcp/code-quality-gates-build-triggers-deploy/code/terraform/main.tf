# Main Terraform configuration for Code Quality Gates with Cloud Build and Cloud Deploy

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Computed values used throughout the configuration
  suffix                    = random_id.suffix.hex
  repository_name_with_suffix = "${var.repository_name}-${local.suffix}"
  cluster_name_with_suffix    = "${var.cluster_name}-${local.suffix}"
  pipeline_name_with_suffix   = "${var.pipeline_name}-${local.suffix}"
  registry_name_with_suffix   = "${var.registry_name}-${local.suffix}"
  
  # Required APIs for the solution
  required_apis = [
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "sourcerepo.googleapis.com",
    "binaryauthorization.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "containeranalysis.googleapis.com"
  ]
  
  # Cloud Build service account email
  cloudbuild_sa_email = "${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    solution = "code-quality-gates"
    suffix   = local.suffix
  })
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "app_registry" {
  depends_on = [google_project_service.required_apis]
  
  location      = var.region
  repository_id = local.registry_name_with_suffix
  description   = "Container registry for code quality pipeline applications"
  format        = "DOCKER"
  
  labels = local.common_labels
}

# Create Cloud Source Repository
resource "google_sourcerepo_repository" "app_repo" {
  depends_on = [google_project_service.required_apis]
  
  name = local.repository_name_with_suffix
  
  # Initialize with a README to make the repository accessible
  provisioner "local-exec" {
    command = <<-EOT
      # Clone and initialize repository with sample content
      if ! gcloud source repos clone ${self.name} --project=${var.project_id} /tmp/${self.name} 2>/dev/null; then
        echo "Repository may already exist or be inaccessible, continuing..."
      fi
    EOT
  }
}

# Create GKE cluster for application deployments
resource "google_container_cluster" "quality_gates_cluster" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.cluster_name_with_suffix
  location = var.zone
  
  # Remove default node pool to use separately managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # Enable required features for security and monitoring
  enable_legacy_abac = false
  
  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled = true
    }
  }
  
  # IP allocation policy for VPC-native networking
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = ""
    services_ipv4_cidr_block = ""
  }
  
  # Binary Authorization configuration
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }
  
  # Workload Identity configuration
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }
  
  # Security and logging configuration
  enable_shielded_nodes = var.enable_shielded_nodes
  
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }
  
  # Master authentication configuration
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  resource_labels = local.common_labels
}

# Create separately managed node pool
resource "google_container_node_pool" "primary_nodes" {
  depends_on = [google_container_cluster.quality_gates_cluster]
  
  name       = "${local.cluster_name_with_suffix}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.quality_gates_cluster.name
  node_count = var.gke_node_count
  
  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.gke_machine_type
    disk_size_gb = var.gke_disk_size_gb
    disk_type    = "pd-standard"
    
    # OAuth scopes for node access to Google Cloud services
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
    
    # Enable shielded nodes features
    dynamic "shielded_instance_config" {
      for_each = var.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }
    }
    
    # Workload Identity configuration
    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
    
    labels = local.common_labels
    
    tags = ["gke-node", "code-quality-pipeline"]
  }
  
  # Node management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = 1
    max_node_count = var.gke_node_count * 2
  }
}

# Create Kubernetes namespaces for different environments
resource "kubernetes_namespace" "environments" {
  depends_on = [google_container_node_pool.primary_nodes]
  count      = length(var.environment_namespaces)
  
  metadata {
    name = var.environment_namespaces[count.index]
    
    labels = merge(local.common_labels, {
      environment = var.environment_namespaces[count.index]
    })
  }
}

# Configure Binary Authorization policy
resource "google_binary_authorization_policy" "policy" {
  depends_on = [google_project_service.required_apis]
  count      = var.enable_binary_authorization ? 1 : []
  
  # Allow specific Google-managed images
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "k8s.gcr.io/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-appengine/*"
  }
  
  # Default rule for other images
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = []
  }
  
  # Cluster-specific rules (more permissive for development)
  cluster_admission_rules {
    cluster                 = google_container_cluster.quality_gates_cluster.id
    evaluation_mode         = "ALWAYS_ALLOW"
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = []
  }
}

# Create Cloud Build trigger for automated CI/CD
resource "google_cloudbuild_trigger" "main_trigger" {
  depends_on = [google_project_service.required_apis, google_sourcerepo_repository.app_repo]
  
  name        = "${local.pipeline_name_with_suffix}-trigger"
  description = "Automated quality pipeline trigger for main branch"
  
  # Trigger configuration for Cloud Source Repository
  trigger_template {
    branch_name = var.build_trigger_branch_pattern
    repo_name   = google_sourcerepo_repository.app_repo.name
  }
  
  # Cloud Build configuration file
  filename = "cloudbuild.yaml"
  
  # Substitution variables passed to Cloud Build
  substitutions = {
    _REGION        = var.region
    _PIPELINE_NAME = local.pipeline_name_with_suffix
    _REGISTRY_NAME = local.registry_name_with_suffix
    _CLUSTER_NAME  = local.cluster_name_with_suffix
    _ZONE          = var.zone
  }
  
  # Include all files in the trigger
  included_files = ["**"]
  
  tags = [local.common_labels.solution, "automated-trigger"]
}

# Grant Cloud Build service account necessary permissions
resource "google_project_iam_member" "cloudbuild_sa_permissions" {
  depends_on = [google_project_service.required_apis]
  
  for_each = toset([
    "roles/clouddeploy.developer",
    "roles/container.developer", 
    "roles/artifactregistry.writer",
    "roles/binaryauthorization.attestorsViewer",
    "roles/containeranalysis.admin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.cloudbuild_sa_email}"
}

# Create Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "quality_pipeline" {
  depends_on = [google_project_service.required_apis]
  
  location = var.region
  name     = local.pipeline_name_with_suffix
  
  description = "Automated code quality pipeline with progressive delivery"
  
  serial_pipeline {
    # Development stage
    stages {
      target_id = google_clouddeploy_target.development.name
      profiles  = ["development"]
      
      strategy {
        standard {
          verify = false
        }
      }
    }
    
    # Staging stage  
    stages {
      target_id = google_clouddeploy_target.staging.name
      profiles  = ["staging"]
      
      strategy {
        standard {
          verify = true
        }
      }
    }
    
    # Production stage with canary deployment
    stages {
      target_id = google_clouddeploy_target.production.name
      profiles  = ["production"]
      
      strategy {
        canary {
          runtime_config {
            kubernetes {
              service_networking {
                service = "code-quality-service"
              }
            }
          }
          
          canary_deployment {
            percentages = [25, 50, 100]
            verify      = true
          }
        }
      }
    }
  }
  
  labels = local.common_labels
}

# Create Cloud Deploy targets for each environment
resource "google_clouddeploy_target" "development" {
  depends_on = [google_container_node_pool.primary_nodes]
  
  location = var.region
  name     = "development"
  
  description = "Development environment"
  
  gke {
    cluster = google_container_cluster.quality_gates_cluster.id
  }
  
  execution_configs {
    usages = ["RENDER", "DEPLOY"]
    
    service_account = local.cloudbuild_sa_email
  }
  
  labels = merge(local.common_labels, {
    environment = "development"
  })
}

resource "google_clouddeploy_target" "staging" {
  depends_on = [google_container_node_pool.primary_nodes]
  
  location = var.region
  name     = "staging"
  
  description = "Staging environment with approval gates"
  
  gke {
    cluster = google_container_cluster.quality_gates_cluster.id
  }
  
  execution_configs {
    usages = ["RENDER", "DEPLOY"]
    
    service_account = local.cloudbuild_sa_email
  }
  
  require_approval = false
  
  labels = merge(local.common_labels, {
    environment = "staging"
  })
}

resource "google_clouddeploy_target" "production" {
  depends_on = [google_container_node_pool.primary_nodes]
  
  location = var.region
  name     = "production"
  
  description = "Production environment with manual approval"
  
  gke {
    cluster = google_container_cluster.quality_gates_cluster.id
  }
  
  execution_configs {
    usages = ["RENDER", "DEPLOY"]
    
    service_account = local.cloudbuild_sa_email
  }
  
  require_approval = true
  
  labels = merge(local.common_labels, {
    environment = "production"
  })
}

# Enable Container Analysis API for vulnerability scanning
resource "google_project_service" "container_analysis" {
  count = var.enable_vulnerability_scanning ? 1 : 0
  
  project = var.project_id
  service = "containeranalysis.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create sample application files (optional - for demonstration)
resource "null_resource" "create_sample_app" {
  depends_on = [google_sourcerepo_repository.app_repo]
  
  triggers = {
    repo_name   = google_sourcerepo_repository.app_repo.name
    project_id  = var.project_id
    always_run  = timestamp()
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary directory for sample application
      TEMP_DIR="/tmp/${local.repository_name_with_suffix}"
      rm -rf "$TEMP_DIR"
      mkdir -p "$TEMP_DIR"
      cd "$TEMP_DIR"
      
      # Initialize git repository
      git init
      git config user.email "terraform@example.com"
      git config user.name "Terraform"
      
      # Create sample Node.js application
      cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({
    message: 'Code Quality Pipeline Demo',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

module.exports = app;
EOF
      
      # Create package.json
      cat > package.json << 'EOF'
{
  "name": "code-quality-demo",
  "version": "1.0.0",
  "description": "Demo app for code quality pipeline",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "test": "jest",
    "lint": "eslint .",
    "security": "audit-ci --config audit-ci.json"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "jest": "^29.5.0",
    "supertest": "^6.3.3",
    "eslint": "^8.41.0",
    "audit-ci": "^6.6.1"
  }
}
EOF
      
      # Create Dockerfile
      cat > Dockerfile << 'EOF'
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine AS runtime
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .
USER nodejs
EXPOSE 8080
CMD ["npm", "start"]
EOF
      
      # Create Cloud Build configuration
      cat > cloudbuild.yaml << 'EOF'
steps:
  - name: 'node:18-alpine'
    entrypoint: 'npm'
    args: ['ci']
    id: 'install-deps'

  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'build',
      '-t', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REGISTRY_NAME}/code-quality-app:$COMMIT_SHA',
      '-t', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REGISTRY_NAME}/code-quality-app:latest',
      '.'
    ]
    id: 'docker-build'
    waitFor: ['install-deps']

  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REGISTRY_NAME}/code-quality-app:$COMMIT_SHA']
    id: 'docker-push'
    waitFor: ['docker-build']

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: E2_STANDARD_4

timeout: 1200s
EOF
      
      # Create skaffold configuration
      cat > skaffold.yaml << 'EOF'
apiVersion: skaffold/v4beta1
kind: Config
metadata:
  name: code-quality-app
manifests:
  rawYaml:
  - k8s/deployment.yaml
EOF
      
      # Create Kubernetes manifests directory
      mkdir -p k8s
      
      cat > k8s/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: code-quality-app
  labels:
    app: code-quality-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: code-quality-app
  template:
    metadata:
      labels:
        app: code-quality-app
    spec:
      containers:
      - name: app
        image: code-quality-app
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          runAsNonRoot: true
          runAsUser: 1001
---
apiVersion: v1
kind: Service
metadata:
  name: code-quality-service
spec:
  selector:
    app: code-quality-app
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF
      
      # Add all files to git
      git add .
      git commit -m "Initial commit: Add sample application and CI/CD configuration"
      
      # Set up remote and push (if repository is accessible)
      git remote add origin https://source.developers.google.com/p/${var.project_id}/r/${local.repository_name_with_suffix}
      echo "Sample application files created. Repository setup complete."
      
      # Cleanup
      cd /
      rm -rf "$TEMP_DIR"
    EOT
  }
}