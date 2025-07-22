# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  vm_name         = "${var.resource_name_prefix}-vm-${local.resource_suffix}"
  repo_name       = "${var.resource_name_prefix}-repo-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    recipe      = "secure-remote-development-access-identity-proxy-cloud-code"
  })

  # IAP source ranges for firewall rules
  iap_source_ranges = ["35.235.240.0/20"]
  
  # VM metadata for security and development tools
  vm_metadata = merge(
    var.enable_os_login ? { enable-oslogin = "TRUE" } : {},
    {
      startup-script = templatefile("${path.module}/startup-script.sh", {
        project_id = var.project_id
        region     = var.region
        repo_name  = local.repo_name
      })
    }
  )
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of essential APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Artifact Registry repository for secure container storage
resource "google_artifact_registry_repository" "secure_dev_repo" {
  location      = var.region
  repository_id = local.repo_name
  description   = "Secure development container registry with vulnerability scanning"
  format        = var.artifact_registry_format
  
  # Enable vulnerability scanning for container security
  dynamic "docker_config" {
    for_each = var.artifact_registry_format == "DOCKER" && var.enable_vulnerability_scanning ? [1] : []
    content {
      immutable_tags = false
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create firewall rule to allow IAP access to development VM
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${var.resource_name_prefix}-allow-iap-ssh-${local.resource_suffix}"
  network     = var.network_name
  description = "Allow IAP SSH access to development environments"
  
  # Allow SSH traffic from IAP IP ranges
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  # IAP IP ranges for secure tunnel access
  source_ranges = local.iap_source_ranges
  
  # Target VMs with specific network tags
  target_tags = ["iap-access", "dev-environment"]
  
  # Security best practices
  direction = "INGRESS"
  priority  = 1000
  
  depends_on = [google_project_service.required_apis]
}

# Optional: Create firewall rule for Cloud Code development server
resource "google_compute_firewall" "allow_iap_dev_server" {
  name        = "${var.resource_name_prefix}-allow-iap-dev-server-${local.resource_suffix}"
  network     = var.network_name
  description = "Allow IAP access to development server ports for Cloud Code"
  
  allow {
    protocol = "tcp"
    ports    = ["8080", "8000", "3000", "4200", "5000"] # Common development server ports
  }
  
  source_ranges = local.iap_source_ranges
  target_tags   = ["iap-access", "dev-environment"]
  
  direction = "INGRESS"
  priority  = 1000
  
  depends_on = [google_project_service.required_apis]
}

# Create development VM without external IP for enhanced security
resource "google_compute_instance" "dev_vm" {
  name         = local.vm_name
  machine_type = var.vm_machine_type
  zone         = var.zone
  
  # Security configuration - no external IP
  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_name
    # Explicitly no external IP for security
    # access_config block is omitted
  }
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = var.vm_boot_disk_size
      type  = var.vm_boot_disk_type
    }
  }
  
  # VM metadata for security and configuration
  metadata = local.vm_metadata
  
  # Network tags for firewall rules and IAP access
  tags = ["iap-access", "dev-environment"]
  
  # Service account with minimal required permissions
  service_account {
    email = google_service_account.dev_vm_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  # Security and operational labels
  labels = local.common_labels
  
  # Ensure VM can be deleted cleanly
  allow_stopping_for_update = true
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_firewall.allow_iap_ssh,
    google_artifact_registry_repository.secure_dev_repo
  ]
}

# Create service account for development VM with minimal permissions
resource "google_service_account" "dev_vm_sa" {
  account_id   = "${var.resource_name_prefix}-vm-sa-${local.resource_suffix}"
  display_name = "Development VM Service Account"
  description  = "Service account for secure development VM with minimal required permissions"
}

# Grant Artifact Registry access to VM service account
resource "google_artifact_registry_repository_iam_member" "vm_registry_access" {
  location   = google_artifact_registry_repository.secure_dev_repo.location
  repository = google_artifact_registry_repository.secure_dev_repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.dev_vm_sa.email}"
}

# Grant logging permissions for audit and monitoring
resource "google_project_iam_member" "vm_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dev_vm_sa.email}"
}

resource "google_project_iam_member" "vm_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.dev_vm_sa.email}"
}

# Create IAP OAuth consent screen brand (requires manual configuration in console)
resource "google_iap_brand" "dev_environment_brand" {
  count = var.oauth_support_email != "" ? 1 : 0
  
  support_email     = var.oauth_support_email
  application_title = var.oauth_application_title
  project           = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant IAP access to specified users
resource "google_iap_tunnel_instance_iam_member" "dev_access" {
  for_each = toset(var.allowed_users)
  
  project  = var.project_id
  zone     = google_compute_instance.dev_vm.zone
  instance = google_compute_instance.dev_vm.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "user:${each.value}"
}

# Grant OS Login access to specified users (if OS Login is enabled)
resource "google_compute_instance_iam_member" "dev_os_login" {
  for_each = var.enable_os_login ? toset(var.allowed_users) : toset([])
  
  project       = var.project_id
  zone          = google_compute_instance.dev_vm.zone
  instance_name = google_compute_instance.dev_vm.name
  role          = "roles/compute.osLogin"
  member        = "user:${each.value}"
}

# Create Cloud Logging sink for IAP audit logs
resource "google_logging_project_sink" "iap_audit_sink" {
  name        = "${var.resource_name_prefix}-iap-audit-sink-${local.resource_suffix}"
  description = "Audit logs for IAP access to development environment"
  
  # Export to Cloud Logging (can be configured to export to BigQuery, Pub/Sub, etc.)
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/iap-audit"
  
  # Filter for IAP and Compute Engine audit logs
  filter = <<-EOT
    protoPayload.serviceName="iap.googleapis.com" OR 
    (protoPayload.serviceName="compute.googleapis.com" AND 
     protoPayload.resourceName=~"${google_compute_instance.dev_vm.name}")
  EOT
  
  # Use unique writer identity for the sink
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Create startup script for VM initialization
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    project_id = var.project_id
    region     = var.region
    repo_name  = local.repo_name
  })
}

# Startup script template file content
resource "local_file" "startup_script_template" {
  filename = "${path.module}/startup-script.tpl"
  content  = <<-EOT
#!/bin/bash
set -e

# Log all output for debugging
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "Starting secure development environment setup..."

# Update system packages
apt-get update && apt-get upgrade -y

# Install Docker for container development
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker $(logname 2>/dev/null || echo "root")

# Install Google Cloud CLI
curl https://sdk.cloud.google.com | bash
source /root/.bashrc

# Install development tools
apt-get install -y git vim curl wget unzip \
    python3 python3-pip nodejs npm \
    build-essential software-properties-common

# Configure Docker for Artifact Registry
gcloud auth configure-docker ${region}-docker.pkg.dev --quiet

# Create development workspace
mkdir -p /home/developer/workspace
chown -R $(logname 2>/dev/null || echo "root"):$(logname 2>/dev/null || echo "root") /home/developer/workspace 2>/dev/null || true

# Install VS Code Server (for remote development)
wget -O- https://aka.ms/install-vscode-server/setup.sh | sh

# Create sample application structure
cat > /home/developer/workspace/Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask
COPY . .
EXPOSE 8080
CMD ["python", "app.py"]
EOF

cat > /home/developer/workspace/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Secure Development Environment - IAP Protected'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

# Set permissions
chown -R $(logname 2>/dev/null || echo "root"):$(logname 2>/dev/null || echo "root") /home/developer 2>/dev/null || true

echo "✅ Secure development environment setup complete"
echo "Access via: gcloud compute ssh ${vm_name} --zone=${zone} --tunnel-through-iap"
EOT
}

# Create Cloud Monitoring dashboard for IAP security monitoring
resource "google_monitoring_dashboard" "iap_security_dashboard" {
  dashboard_json = jsonencode({
    displayName = "IAP Security Dashboard - ${var.resource_name_prefix}"
    gridLayout = {
      widgets = [
        {
          title = "IAP Access Attempts"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"iap_tunnel\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        },
        {
          title = "Development VM CPU Usage"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${google_compute_instance.dev_vm.name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}