# Main Terraform configuration for threat detection pipeline
# This file creates a comprehensive threat detection infrastructure using Cloud IDS, BigQuery Data Canvas, and Cloud Functions

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create VPC network for threat detection infrastructure
resource "google_compute_network" "threat_detection_vpc" {
  name                    = "${var.resource_prefix}-vpc-${local.resource_suffix}"
  description             = "VPC network for threat detection pipeline infrastructure"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
  
  labels = local.common_labels
}

# Create subnet for compute resources
resource "google_compute_subnetwork" "threat_detection_subnet" {
  name          = "${var.resource_prefix}-subnet-${local.resource_suffix}"
  description   = "Subnet for threat detection infrastructure"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.threat_detection_vpc.id
  
  # Enable private Google access for accessing Google APIs
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Reserve IP range for private services access (required for Cloud IDS)
resource "google_compute_global_address" "private_services_range" {
  name          = "${var.resource_prefix}-private-services-${local.resource_suffix}"
  description   = "Private IP range for Google managed services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.threat_detection_vpc.id
  
  depends_on = [google_project_service.required_apis]
}

# Create private connection for Google managed services
resource "google_service_networking_connection" "private_services_connection" {
  network                 = google_compute_network.threat_detection_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_range.name]
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery dataset for threat detection analytics
resource "google_bigquery_dataset" "threat_detection" {
  dataset_id    = "threat_detection_${local.resource_suffix}"
  friendly_name = "Threat Detection Analytics Dataset"
  description   = "Dataset for storing and analyzing threat detection data from Cloud IDS"
  location      = var.bigquery_location
  
  # Access control and security settings
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.current.email
  }
  
  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  # Data governance settings
  default_table_expiration_ms = 2592000000 # 30 days
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery table for Cloud IDS findings
resource "google_bigquery_table" "ids_findings" {
  dataset_id = google_bigquery_dataset.threat_detection.dataset_id
  table_id   = "ids_findings"
  
  description = "Table for storing Cloud IDS threat detection findings"
  
  schema = jsonencode([
    {
      name = "finding_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the security finding"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the threat was detected"
    },
    {
      name = "severity"
      type = "STRING"
      mode = "REQUIRED"
      description = "Severity level of the detected threat"
    },
    {
      name = "threat_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of threat detected (e.g., Malware, Port Scan)"
    },
    {
      name = "source_ip"
      type = "STRING"
      mode = "NULLABLE"
      description = "Source IP address of the threat"
    },
    {
      name = "destination_ip"
      type = "STRING"
      mode = "NULLABLE"
      description = "Destination IP address targeted by the threat"
    },
    {
      name = "protocol"
      type = "STRING"
      mode = "NULLABLE"
      description = "Network protocol used in the threat"
    },
    {
      name = "details"
      type = "STRING"
      mode = "NULLABLE"
      description = "Additional details about the threat in JSON format"
    },
    {
      name = "raw_data"
      type = "STRING"
      mode = "NULLABLE"
      description = "Raw threat detection data from Cloud IDS"
    }
  ])
  
  # Partitioning for better query performance
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for optimized queries
  clustering = ["severity", "threat_type"]
  
  labels = local.common_labels
}

# Create BigQuery table for aggregated threat metrics
resource "google_bigquery_table" "threat_metrics" {
  dataset_id = google_bigquery_dataset.threat_detection.dataset_id
  table_id   = "threat_metrics"
  
  description = "Table for storing aggregated threat detection metrics"
  
  schema = jsonencode([
    {
      name = "metric_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp for the metric aggregation period"
    },
    {
      name = "threat_count"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Total number of threats detected in the period"
    },
    {
      name = "severity_high"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of high severity threats"
    },
    {
      name = "severity_medium"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of medium severity threats"
    },
    {
      name = "severity_low"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of low severity threats"
    },
    {
      name = "top_source_ips"
      type = "STRING"
      mode = "NULLABLE"
      description = "JSON array of top source IPs generating threats"
    },
    {
      name = "top_threat_types"
      type = "STRING"
      mode = "NULLABLE"
      description = "JSON array of most common threat types"
    }
  ])
  
  # Partitioning for better query performance
  time_partitioning {
    type  = "DAY"
    field = "metric_time"
  }
  
  labels = local.common_labels
}

# Create BigQuery view for threat analysis
resource "google_bigquery_table" "threat_summary_view" {
  dataset_id = google_bigquery_dataset.threat_detection.dataset_id
  table_id   = "threat_summary"
  
  description = "View for aggregated threat detection analysis"
  
  view {
    query = <<-EOT
      SELECT 
        DATE(timestamp) as threat_date,
        COUNT(*) as total_findings,
        COUNTIF(severity = 'HIGH') as high_severity,
        COUNTIF(severity = 'MEDIUM') as medium_severity,
        COUNTIF(severity = 'LOW') as low_severity,
        ARRAY_AGG(DISTINCT threat_type LIMIT 5) as top_threat_types,
        ARRAY_AGG(DISTINCT source_ip LIMIT 10) as top_source_ips
      FROM `${var.project_id}.${google_bigquery_dataset.threat_detection.dataset_id}.${google_bigquery_table.ids_findings.table_id}`
      GROUP BY DATE(timestamp)
      ORDER BY threat_date DESC
    EOT
    use_legacy_sql = false
  }
  
  labels = local.common_labels
}

# Create Pub/Sub topic for Cloud IDS findings
resource "google_pubsub_topic" "threat_detection_findings" {
  name = "${var.resource_prefix}-findings-${local.resource_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Functions processing
resource "google_pubsub_subscription" "process_findings_sub" {
  name  = "${var.resource_prefix}-process-findings-${local.resource_suffix}"
  topic = google_pubsub_topic.threat_detection_findings.name
  
  message_retention_duration = var.pubsub_message_retention_duration
  ack_deadline_seconds       = var.pubsub_ack_deadline
  
  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  labels = local.common_labels
}

# Create Pub/Sub topic for security alerts
resource "google_pubsub_topic" "security_alerts" {
  name = "${var.resource_prefix}-alerts-${local.resource_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name = "${var.resource_prefix}-dead-letter-${local.resource_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.resource_prefix}-functions-${local.resource_suffix}"
  location = var.region
  
  # Security and lifecycle settings
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create archive for threat processing function source code
data "archive_file" "threat_processor_source" {
  type        = "zip"
  output_path = "${path.module}/threat-processor-source.zip"
  
  source {
    content = file("${path.module}/function_code/threat_processor_main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/threat_processor_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload threat processing function source to Cloud Storage
resource "google_storage_bucket_object" "threat_processor_source" {
  name   = "threat-processor-${data.archive_file.threat_processor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.threat_processor_source.output_path
  
  depends_on = [data.archive_file.threat_processor_source]
}

# Create Cloud Function for processing threat findings
resource "google_cloudfunctions_function" "process_threat_finding" {
  name        = "${var.resource_prefix}-process-threat-${local.resource_suffix}"
  description = "Process Cloud IDS findings and store in BigQuery"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "process_threat_finding"
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.threat_processor_source.name
  
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.threat_detection_findings.name
  }
  
  environment_variables = {
    PROJECT_ID = var.project_id
    DATASET_ID = google_bigquery_dataset.threat_detection.dataset_id
    ALERTS_TOPIC = google_pubsub_topic.security_alerts.name
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.threat_processor_source
  ]
}

# Create archive for alert processing function source code
data "archive_file" "alert_processor_source" {
  type        = "zip"
  output_path = "${path.module}/alert-processor-source.zip"
  
  source {
    content = file("${path.module}/function_code/alert_processor_main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/alert_processor_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload alert processing function source to Cloud Storage
resource "google_storage_bucket_object" "alert_processor_source" {
  name   = "alert-processor-${data.archive_file.alert_processor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.alert_processor_source.output_path
  
  depends_on = [data.archive_file.alert_processor_source]
}

# Create Cloud Function for processing security alerts
resource "google_cloudfunctions_function" "process_security_alert" {
  name        = "${var.resource_prefix}-process-alert-${local.resource_suffix}"
  description = "Process high-severity security alerts and trigger responses"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = 256
  timeout               = 60
  entry_point          = "process_security_alert"
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.alert_processor_source.name
  
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.security_alerts.name
  }
  
  environment_variables = {
    PROJECT_ID = var.project_id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.alert_processor_source
  ]
}

# Create Cloud IDS endpoint for network threat detection
resource "google_ids_endpoint" "threat_detection_endpoint" {
  name     = "${var.resource_prefix}-endpoint-${local.resource_suffix}"
  location = var.zone
  network  = google_compute_network.threat_detection_vpc.id
  severity = var.ids_severity_level
  
  description = "Cloud IDS endpoint for comprehensive network threat detection"
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.private_services_connection
  ]
}

# Create firewall rules for the VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.resource_prefix}-allow-internal-${local.resource_suffix}"
  network = google_compute_network.threat_detection_vpc.name
  
  description = "Allow internal communication within the VPC"
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.vpc_cidr]
  
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.resource_prefix}-allow-ssh-${local.resource_suffix}"
  network = google_compute_network.threat_detection_vpc.name
  
  description = "Allow SSH access to VMs for management"
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-access"]
  
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "${var.resource_prefix}-allow-http-https-${local.resource_suffix}"
  network = google_compute_network.threat_detection_vpc.name
  
  description = "Allow HTTP and HTTPS traffic to web servers"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
  
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Create test VMs for traffic generation and monitoring (optional)
resource "google_compute_instance" "web_server" {
  count        = var.create_test_vms ? 1 : 0
  name         = "${var.resource_prefix}-web-server-${local.resource_suffix}"
  machine_type = var.vm_machine_type
  zone         = var.zone
  
  description = "Web server VM for testing threat detection capabilities"
  
  boot_disk {
    initialize_params {
      image = "${var.vm_image_project}/${var.vm_image_family}"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  network_interface {
    network    = google_compute_network.threat_detection_vpc.name
    subnetwork = google_compute_subnetwork.threat_detection_subnet.name
    
    access_config {
      # Ephemeral public IP
    }
  }
  
  tags = ["web-server", "mirrored-vm", "ssh-access"]
  
  labels = merge(local.common_labels, {
    purpose = "test-web-server"
  })
  
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Threat Detection Test Web Server</h1>" > /var/www/html/index.html
  EOT
  
  depends_on = [google_project_service.required_apis]
}

resource "google_compute_instance" "app_server" {
  count        = var.create_test_vms ? 1 : 0
  name         = "${var.resource_prefix}-app-server-${local.resource_suffix}"
  machine_type = var.vm_machine_type
  zone         = var.zone
  
  description = "Application server VM for testing threat detection capabilities"
  
  boot_disk {
    initialize_params {
      image = "${var.vm_image_project}/${var.vm_image_family}"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  network_interface {
    network    = google_compute_network.threat_detection_vpc.name
    subnetwork = google_compute_subnetwork.threat_detection_subnet.name
  }
  
  tags = ["app-server", "mirrored-vm", "ssh-access"]
  
  labels = merge(local.common_labels, {
    purpose = "test-app-server"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create packet mirroring policy for traffic analysis
resource "google_compute_packet_mirroring" "threat_detection_mirroring" {
  count = var.enable_packet_mirroring ? 1 : 0
  
  name        = "${var.resource_prefix}-mirroring-${local.resource_suffix}"
  description = "Packet mirroring for Cloud IDS threat detection"
  region      = var.region
  
  network {
    url = google_compute_network.threat_detection_vpc.id
  }
  
  collector_ilb {
    url = google_ids_endpoint.threat_detection_endpoint.endpoint_forwarding_rule
  }
  
  mirrored_resources {
    tags = ["mirrored-vm"]
  }
  
  filter {
    cidr_ranges  = [var.subnet_cidr]
    ip_protocols = ["tcp", "udp", "icmp"]
  }
  
  depends_on = [
    google_ids_endpoint.threat_detection_endpoint,
    google_compute_instance.web_server,
    google_compute_instance.app_server
  ]
}

# Get current user information for BigQuery access control
data "google_client_openid_userinfo" "current" {}

# Insert sample threat detection data for testing BigQuery Data Canvas
resource "google_bigquery_job" "sample_data_insert" {
  job_id = "sample-threat-data-${local.resource_suffix}"
  
  query {
    query = <<-EOT
      INSERT INTO `${var.project_id}.${google_bigquery_dataset.threat_detection.dataset_id}.${google_bigquery_table.ids_findings.table_id}` 
      (finding_id, timestamp, severity, threat_type, source_ip, destination_ip, protocol, details, raw_data)
      VALUES 
      ('finding-001-${local.resource_suffix}', CURRENT_TIMESTAMP(), 'HIGH', 'Malware Detection', '203.0.113.1', '10.0.1.5', 'TCP', '{"port": 80, "payload": "suspicious"}', '{"full_details": "sample"}'),
      ('finding-002-${local.resource_suffix}', CURRENT_TIMESTAMP(), 'MEDIUM', 'Port Scan', '198.51.100.1', '10.0.1.0/24', 'TCP', '{"ports": [22, 80, 443]}', '{"scan_type": "stealth"}'),
      ('finding-003-${local.resource_suffix}', CURRENT_TIMESTAMP(), 'LOW', 'DNS Tunneling', '192.0.2.1', '8.8.8.8', 'UDP', '{"domain": "suspicious.example.com"}', '{"queries": 150}')
    EOT
    use_legacy_sql = false
  }
  
  depends_on = [
    google_bigquery_table.ids_findings
  ]
}