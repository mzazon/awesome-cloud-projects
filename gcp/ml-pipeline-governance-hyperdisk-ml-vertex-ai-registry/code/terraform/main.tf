# Main Terraform configuration for ML Pipeline Governance
# This file creates the complete infrastructure for ML governance with Hyperdisk ML and Vertex AI

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention for all resources
  name_prefix = "${var.resource_prefix}-${var.environment}"
  
  # Resource-specific names with random suffix
  hyperdisk_name          = "${local.name_prefix}-hyperdisk-${random_id.suffix.hex}"
  instance_name           = "${local.name_prefix}-instance-${random_id.suffix.hex}"
  bucket_name             = "${local.name_prefix}-data-${random_id.suffix.hex}"
  service_account_name    = "${local.name_prefix}-sa"
  workflow_name           = "${local.name_prefix}-workflow-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    created-by  = "ml-governance-recipe"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "aiplatform.googleapis.com",
    "workflows.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent APIs from being disabled when the resource is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for ML governance operations
resource "google_service_account" "ml_governance" {
  account_id   = local.service_account_name
  display_name = "ML Governance Service Account"
  description  = "Service account for ML pipeline governance operations"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Assign IAM roles to the service account
resource "google_project_iam_member" "ml_governance_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/workflows.invoker",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/storage.objectAdmin",
    "roles/compute.instanceAdmin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ml_governance.email}"
  
  depends_on = [google_service_account.ml_governance]
}

# Create Cloud Storage bucket for training data
resource "google_storage_bucket" "training_data" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Storage configuration
  storage_class                 = var.storage_class
  uniform_bucket_level_access   = true
  public_access_prevention      = "enforced"
  
  # Versioning configuration
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Lifecycle rule to delete objects after 1 year
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }
  
  # Labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create a network for the ML training infrastructure (if using default network)
# Using default network for simplicity, but production should use custom VPC
data "google_compute_network" "default" {
  name    = "default"
  project = var.project_id
}

# Create Hyperdisk ML volume for high-performance training data storage
resource "google_compute_disk" "hyperdisk_ml" {
  name = local.hyperdisk_name
  type = "hyperdisk-ml"
  zone = var.zone
  size = var.hyperdisk_size_gb
  
  # Hyperdisk ML specific configuration
  provisioned_throughput = var.hyperdisk_provisioned_throughput
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create compute instance for ML training with Hyperdisk ML attachment
resource "google_compute_instance" "ml_training" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "${var.instance_image_project}/${var.instance_image_family}"
      size  = 100
      type  = "pd-standard"
    }
  }
  
  # Attach Hyperdisk ML volume
  attached_disk {
    source      = google_compute_disk.hyperdisk_ml.self_link
    device_name = "hyperdisk-ml-data"
    mode        = "READ_ONLY"
  }
  
  # Network configuration
  network_interface {
    network = data.google_compute_network.default.self_link
    
    # Assign external IP for internet access (remove for production)
    access_config {
      // Ephemeral public IP
    }
  }
  
  # Service account configuration
  service_account {
    email  = google_service_account.ml_governance.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  
  # Metadata and startup script
  metadata = {
    startup-script = templatefile("${path.module}/scripts/startup.sh", {
      bucket_name = google_storage_bucket.training_data.name
      project_id  = var.project_id
      region      = var.region
    })
  }
  
  # Network tags for firewall rules
  tags = var.network_tags
  
  # Labels
  labels = local.common_labels
  
  # Allow stopping for updates
  allow_stopping_for_update = true
  
  depends_on = [
    google_compute_disk.hyperdisk_ml,
    google_service_account.ml_governance,
    google_project_iam_member.ml_governance_roles
  ]
}

# Create startup script for the ML training instance
resource "local_file" "startup_script" {
  filename = "${path.module}/scripts/startup.sh"
  content = templatefile("${path.module}/startup-script.tftpl", {
    bucket_name = google_storage_bucket.training_data.name
    project_id  = var.project_id
    region      = var.region
  })
  
  # Ensure scripts directory exists
  depends_on = [local_file.scripts_directory]
}

# Create scripts directory
resource "local_file" "scripts_directory" {
  filename = "${path.module}/scripts/.gitkeep"
  content  = "# Directory for scripts"
}

# Template file for startup script
resource "local_file" "startup_script_template" {
  filename = "${path.module}/startup-script.tftpl"
  content  = <<-EOF
#!/bin/bash
set -e

# Update system packages
apt-get update
apt-get install -y python3 python3-pip google-cloud-sdk

# Install Python dependencies for ML
pip3 install google-cloud-aiplatform google-cloud-storage google-cloud-monitoring

# Mount Hyperdisk ML volume
mkdir -p /mnt/hyperdisk-ml
mount -o ro /dev/disk/by-id/google-hyperdisk-ml-data /mnt/hyperdisk-ml

# Set up environment variables
export PROJECT_ID="${project_id}"
export REGION="${region}"
export BUCKET_NAME="${bucket_name}"

# Configure gcloud
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION

# Create ML governance scripts
cat > /opt/ml-governance.py << 'PYTHON_EOF'
import json
import logging
from google.cloud import aiplatform
from google.cloud import monitoring_v3
from datetime import datetime

class MLGovernanceTracker:
    def __init__(self, project_id, region):
        self.project_id = project_id
        self.region = region
        aiplatform.init(project=project_id, location=region)
        
    def track_training_metrics(self, model_name, metrics):
        """Track training metrics for governance"""
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{self.project_id}"
        
        # Create custom metric for model performance
        series = monitoring_v3.TimeSeries()
        series.resource.type = "global"
        series.metric.type = "custom.googleapis.com/ml/model_accuracy"
        series.metric.labels["model_name"] = model_name
        
        # Add data point
        point = monitoring_v3.Point()
        point.value.double_value = metrics.get("accuracy", 0.0)
        point.interval.end_time.seconds = int(datetime.now().timestamp())
        series.points = [point]
        
        # Write time series data
        client.create_time_series(name=project_name, time_series=[series])
        print(f"Tracked metrics for model: {model_name}")

# Initialize governance tracker
tracker = MLGovernanceTracker("${project_id}", "${region}")

# Log successful setup
print("ML governance instance setup completed successfully")
PYTHON_EOF

chmod +x /opt/ml-governance.py

# Log completion
echo "Startup script completed at $(date)" >> /var/log/ml-governance-startup.log
EOF
}

# Create Vertex AI Model in Model Registry
resource "google_vertex_ai_model" "governance_model" {
  name         = var.model_display_name
  display_name = "${var.model_display_name}-${random_id.suffix.hex}"
  description  = var.model_description
  
  # Model metadata
  labels = merge(local.common_labels, {
    governance-enabled = "true"
    compliance-status  = "pending"
  })
  
  # Version aliases for deployment management
  version_aliases = ["staging", "governance-enabled"]
  
  # Container specification for model serving
  container_spec {
    image_uri = var.model_container_image_uri
    
    # Environment variables for governance
    env {
      name  = "PROJECT_ID"
      value = var.project_id
    }
    env {
      name  = "REGION"
      value = var.region
    }
    env {
      name  = "GOVERNANCE_ENABLED"
      value = "true"
    }
  }
  
  # Artifact URI pointing to model artifacts in Cloud Storage
  artifact_uri = "${google_storage_bucket.training_data.url}/models/"
  
  region = var.region
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.training_data
  ]
}

# Create Cloud Workflow for ML governance automation
resource "google_workflows_workflow" "ml_governance" {
  name        = local.workflow_name
  region      = var.region
  description = "Automated ML governance workflow for model validation and compliance"
  
  # Workflow definition in YAML format
  source_contents = templatefile("${path.module}/workflow-definition.yaml.tftpl", {
    project_id = var.project_id
    region     = var.region
    model_id   = google_vertex_ai_model.governance_model.name
  })
  
  # Service account for workflow execution
  service_account = google_service_account.ml_governance.email
  
  # Labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_vertex_ai_model.governance_model,
    google_service_account.ml_governance,
    google_project_iam_member.ml_governance_roles
  ]
}

# Create workflow definition template
resource "local_file" "workflow_definition_template" {
  filename = "${path.module}/workflow-definition.yaml.tftpl"
  content  = <<-EOF
# ML Governance Workflow Definition
# This workflow automates model validation, compliance checking, and registry updates

main:
  params: [args]
  steps:
  - initializeWorkflow:
      assign:
      - project_id: "${project_id}"
      - region: "${region}"
      - model_id: "${model_id}"
      - workflow_start_time: $${sys.now()}
  
  - logWorkflowStart:
      call: sys.log
      args:
        text: $${"Starting ML governance workflow for model: " + model_id}
        severity: "INFO"
  
  - validateModelQuality:
      call: validateModel
      args:
        project_id: $${project_id}
        region: $${region}
        model_id: $${model_id}
      result: validation_result
  
  - checkComplianceRules:
      call: checkCompliance
      args:
        project_id: $${project_id}
        model_id: $${model_id}
        validation_result: $${validation_result}
      result: compliance_result
  
  - conditionalUpdateRegistry:
      switch:
      - condition: $${compliance_result.passed}
        next: updateModelRegistry
      - condition: true
        next: logComplianceFailure
  
  - updateModelRegistry:
      call: updateRegistry
      args:
        project_id: $${project_id}
        region: $${region}
        model_id: $${model_id}
        status: "approved"
        compliance_result: $${compliance_result}
      result: update_result
      next: notifySuccess
  
  - logComplianceFailure:
      call: sys.log
      args:
        text: $${"Compliance check failed for model: " + model_id}
        severity: "WARNING"
      next: notifyFailure
  
  - notifySuccess:
      call: sendNotification
      args:
        message: $${"Model governance validation completed successfully for: " + model_id}
        status: "success"
        project_id: $${project_id}
      next: completeWorkflow
  
  - notifyFailure:
      call: sendNotification
      args:
        message: $${"Model governance validation failed for: " + model_id}
        status: "failure"
        project_id: $${project_id}
  
  - completeWorkflow:
      call: sys.log
      args:
        text: $${"ML governance workflow completed for model: " + model_id}
        severity: "INFO"
      return:
        status: "completed"
        model_id: $${model_id}
        workflow_duration: $${sys.now() - workflow_start_time}

# Subworkflow: Validate Model Quality
validateModel:
  params: [project_id, region, model_id]
  steps:
  - logValidationStart:
      call: sys.log
      args:
        text: $${"Starting model quality validation for: " + model_id}
        severity: "INFO"
  
  - performValidation:
      assign:
      - validation_checks:
          accuracy_threshold: 0.85
          bias_threshold: 0.1
          drift_threshold: 0.05
      - mock_metrics:
          accuracy: 0.92
          bias_score: 0.08
          drift_score: 0.03
  
  - evaluateMetrics:
      assign:
      - validation_passed: $${
          mock_metrics.accuracy >= validation_checks.accuracy_threshold and
          mock_metrics.bias_score <= validation_checks.bias_threshold and
          mock_metrics.drift_score <= validation_checks.drift_threshold
        }
  
  - returnValidationResult:
      return:
        passed: $${validation_passed}
        metrics: $${mock_metrics}
        thresholds: $${validation_checks}
        timestamp: $${sys.now()}

# Subworkflow: Check Compliance Rules
checkCompliance:
  params: [project_id, model_id, validation_result]
  steps:
  - logComplianceStart:
      call: sys.log
      args:
        text: $${"Starting compliance check for model: " + model_id}
        severity: "INFO"
  
  - checkSecurityRequirements:
      assign:
      - security_checks:
          encryption_enabled: true
          access_controls_verified: true
          audit_logging_enabled: true
  
  - checkGovernanceLabels:
      assign:
      - required_labels: ["governance", "compliance"]
      - labels_present: true  # Mock check - in real implementation, query model labels
  
  - evaluateCompliance:
      assign:
      - compliance_passed: $${
          validation_result.passed and
          security_checks.encryption_enabled and
          security_checks.access_controls_verified and
          security_checks.audit_logging_enabled and
          labels_present
        }
  
  - returnComplianceResult:
      return:
        passed: $${compliance_passed}
        security_checks: $${security_checks}
        labels_verified: $${labels_present}
        validation_input: $${validation_result}
        timestamp: $${sys.now()}

# Subworkflow: Update Model Registry
updateRegistry:
  params: [project_id, region, model_id, status, compliance_result]
  steps:
  - logUpdateStart:
      call: sys.log
      args:
        text: $${"Updating model registry for: " + model_id + " with status: " + status}
        severity: "INFO"
  
  - updateModelMetadata:
      assign:
      - update_timestamp: $${sys.now()}
      - governance_metadata:
          status: $${status}
          last_validated: $${update_timestamp}
          compliance_verified: $${compliance_result.passed}
          governance_version: "1.0"
  
  - returnUpdateResult:
      return:
        updated: true
        metadata: $${governance_metadata}
        timestamp: $${update_timestamp}

# Subworkflow: Send Notification
sendNotification:
  params: [message, status, project_id]
  steps:
  - logNotification:
      call: sys.log
      args:
        text: $${"Governance Notification (" + status + "): " + message}
        severity: $${if(status == "success", "INFO", "WARNING")}
  
  - createNotificationRecord:
      assign:
      - notification_record:
          message: $${message}
          status: $${status}
          project_id: $${project_id}
          timestamp: $${sys.now()}
  
  - returnNotificationResult:
      return:
        sent: true
        record: $${notification_record}
EOF
}

# Create Cloud Monitoring dashboard for ML governance metrics
resource "google_monitoring_dashboard" "ml_governance" {
  count = var.enable_advanced_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "ML Governance Metrics Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Model Training Performance"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                }
                unitOverride = "1"
              }
              gaugeView = {
                lowerBound = 0.0
                upperBound = 1.0
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Workflow Execution Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"workflows.googleapis.com/Workflow\""
                }
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Storage Performance Metrics"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gcs_bucket\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Operations per second"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create firewall rule for ML training instances (if needed)
resource "google_compute_firewall" "ml_training_access" {
  name    = "${local.name_prefix}-ml-training-firewall"
  network = data.google_compute_network.default.name
  
  description = "Firewall rule for ML training instances"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "8888"] # SSH, HTTP, Jupyter
  }
  
  source_ranges = var.allowed_source_ranges
  target_tags   = var.network_tags
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Scheduler job for periodic governance workflow execution (optional)
resource "google_cloud_scheduler_job" "governance_scheduler" {
  count = var.enable_workflow_scheduling ? 1 : 0
  
  name        = "${local.name_prefix}-governance-scheduler"
  description = "Scheduled execution of ML governance workflow"
  schedule    = var.workflow_schedule
  time_zone   = "UTC"
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.ml_governance.name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        project_id = var.project_id
        region     = var.region
        model_id   = google_vertex_ai_model.governance_model.name
      })
    }))
    
    oauth_token {
      service_account_email = google_service_account.ml_governance.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.ml_governance
  ]
}