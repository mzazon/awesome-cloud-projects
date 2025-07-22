# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names
locals {
  bucket_name            = "scientific-video-data-${random_id.suffix.hex}"
  network_name          = "${var.network_name}-${random_id.suffix.hex}"
  subnet_name           = "${var.network_name}-subnet-${random_id.suffix.hex}"
  firewall_name         = "${var.network_name}-firewall-${random_id.suffix.hex}"
  service_account_email = "${var.service_account_id}-${random_id.suffix.hex}@${var.project_id}.iam.gserviceaccount.com"
  filestore_name        = "${var.cluster_name}-filestore-${random_id.suffix.hex}"
  
  # Common labels
  common_labels = merge(var.labels, {
    cluster-name = var.cluster_name
    created-by   = "terraform"
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "dataflow.googleapis.com",
    "bigquery.googleapis.com",
    "container.googleapis.com",
    "file.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Create VPC Network for the cluster
resource "google_compute_network" "vpc_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  mtu                     = 1460
  project                 = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Create subnet for the cluster
resource "google_compute_subnetwork" "cluster_subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.id
  project       = var.project_id

  # Enable private Google access for the subnet
  private_ip_google_access = true

  # Secondary IP ranges for potential GKE usage
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "192.168.0.0/18"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "192.168.64.0/18"
  }
}

# Firewall rules for HPC cluster communication
resource "google_compute_firewall" "cluster_internal" {
  name    = "${local.firewall_name}-internal"
  network = google_compute_network.vpc_network.name
  project = var.project_id

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

  source_ranges = [var.subnet_cidr]
  target_tags   = ["hpc-cluster"]
}

# Firewall rule for SSH access
resource "google_compute_firewall" "ssh_access" {
  name    = "${local.firewall_name}-ssh"
  network = google_compute_network.vpc_network.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["hpc-cluster"]
}

# Service Account for cluster nodes
resource "google_service_account" "cluster_service_account" {
  account_id   = "${var.service_account_id}-${random_id.suffix.hex}"
  display_name = "HPC Cluster Service Account"
  description  = "Service account for video analysis HPC cluster nodes"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "cluster_sa_compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

resource "google_project_iam_member" "cluster_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

resource "google_project_iam_member" "cluster_sa_ai_platform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

resource "google_project_iam_member" "cluster_sa_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

resource "google_project_iam_member" "cluster_sa_dataflow" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

resource "google_project_iam_member" "cluster_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

resource "google_project_iam_member" "cluster_sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cluster_service_account.email}"
}

# Cloud Storage bucket for video data and results
resource "google_storage_bucket" "video_data_bucket" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.bucket_storage_class
  project       = var.project_id

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create bucket folders structure
resource "google_storage_bucket_object" "raw_videos_folder" {
  name   = "raw-videos/"
  bucket = google_storage_bucket.video_data_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "processed_results_folder" {
  name   = "processed-results/"
  bucket = google_storage_bucket.video_data_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "model_artifacts_folder" {
  name   = "model-artifacts/"
  bucket = google_storage_bucket.video_data_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "temp_folder" {
  name   = "temp/"
  bucket = google_storage_bucket.video_data_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "staging_folder" {
  name   = "staging/"
  bucket = google_storage_bucket.video_data_bucket.name
  content = " "
}

# Filestore instance for shared storage
resource "google_filestore_instance" "cluster_filestore" {
  name     = local.filestore_name
  location = var.zone
  tier     = var.filestore_tier
  project  = var.project_id

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "shared"
  }

  networks {
    network = google_compute_network.vpc_network.name
    modes   = ["MODE_IPV4"]
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# BigQuery dataset for analysis results
resource "google_bigquery_dataset" "video_analysis_dataset" {
  dataset_id  = var.dataset_id
  location    = var.dataset_location
  project     = var.project_id
  description = "Dataset for storing video analysis results"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# BigQuery table for video analysis results
resource "google_bigquery_table" "video_analysis_results" {
  dataset_id = google_bigquery_dataset.video_analysis_dataset.dataset_id
  table_id   = "video_analysis_results"
  project    = var.project_id

  schema = jsonencode([
    {
      name = "video_file"
      type = "STRING"
      mode = "REQUIRED"
      description = "Path to the video file"
    },
    {
      name = "job_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Slurm job ID"
    },
    {
      name = "analysis_results"
      type = "STRING"
      mode = "NULLABLE"
      description = "JSON string containing analysis results"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Analysis completion timestamp"
    },
    {
      name = "processing_duration"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Processing time in seconds"
    },
    {
      name = "frame_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of frames processed"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Analysis confidence score"
    }
  ])

  labels = local.common_labels
}

# Vertex AI Dataset for model training
resource "google_vertex_ai_dataset" "scientific_video_dataset" {
  provider     = google-beta
  project      = var.project_id
  region       = var.ai_region
  display_name = "scientific-video-dataset"
  
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/text_1.0.0.yaml"
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create sample training data file for Gemini fine-tuning
resource "google_storage_bucket_object" "training_data" {
  name   = "model-artifacts/training-data/scientific-video-training.jsonl"
  bucket = google_storage_bucket.video_data_bucket.name
  content = jsonencode({
    input_text  = "Analyze this microscopy video for cellular division patterns"
    output_text = "This video shows metaphase alignment of chromosomes during mitosis. The spindle apparatus is clearly visible, indicating normal cell division progression. Key features include: 1) Chromosome condensation and alignment at the metaphase plate, 2) Spindle fiber attachment to kinetochores, 3) Cell cycle checkpoint activation prior to anaphase onset."
  })
}

# HPC Cluster Template Instance for Compute Nodes
resource "google_compute_instance_template" "compute_node_template" {
  name_prefix = "${var.cluster_name}-compute-"
  project     = var.project_id

  machine_type = var.cluster_machine_type

  disk {
    source_image = "projects/schedmd-slurm-public/global/images/family/schedmd-slurm-22-05-8-hpc-rocky-linux-8"
    auto_delete  = true
    boot         = true
    disk_size_gb = 100
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.cluster_subnet.id
    
    # No external IP for security
    access_config {
      // Ephemeral external IP
    }
  }

  service_account {
    email  = google_service_account.cluster_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  tags = ["hpc-cluster", "compute-node"]

  labels = local.common_labels

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/scripts/compute-startup.sh", {
      filestore_ip = google_filestore_instance.cluster_filestore.networks[0].ip_addresses[0]
      bucket_name  = google_storage_bucket.video_data_bucket.name
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HPC Cluster Template Instance for GPU Nodes
resource "google_compute_instance_template" "gpu_node_template" {
  name_prefix = "${var.cluster_name}-gpu-"
  project     = var.project_id

  machine_type = var.gpu_machine_type

  guest_accelerator {
    type  = var.gpu_type
    count = 1
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
  }

  disk {
    source_image = "projects/schedmd-slurm-public/global/images/family/schedmd-slurm-22-05-8-hpc-rocky-linux-8"
    auto_delete  = true
    boot         = true
    disk_size_gb = 100
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.cluster_subnet.id
    
    access_config {
      // Ephemeral external IP
    }
  }

  service_account {
    email  = google_service_account.cluster_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  tags = ["hpc-cluster", "gpu-node"]

  labels = local.common_labels

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/scripts/gpu-startup.sh", {
      filestore_ip = google_filestore_instance.cluster_filestore.networks[0].ip_addresses[0]
      bucket_name  = google_storage_bucket.video_data_bucket.name
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Slurm Controller Instance
resource "google_compute_instance" "slurm_controller" {
  name         = "${var.cluster_name}-controller"
  machine_type = "n1-standard-4"
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "projects/schedmd-slurm-public/global/images/family/schedmd-slurm-22-05-8-hpc-rocky-linux-8"
      size  = 100
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.cluster_subnet.id
    
    access_config {
      // Ephemeral external IP
    }
  }

  service_account {
    email  = google_service_account.cluster_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  tags = ["hpc-cluster", "slurm-controller"]

  labels = local.common_labels

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/scripts/controller-startup.sh", {
      filestore_ip      = google_filestore_instance.cluster_filestore.networks[0].ip_addresses[0]
      bucket_name       = google_storage_bucket.video_data_bucket.name
      compute_template  = google_compute_instance_template.compute_node_template.name
      gpu_template      = google_compute_instance_template.gpu_node_template.name
      max_compute_nodes = var.max_compute_nodes
      max_gpu_nodes     = var.max_gpu_nodes
      project_id        = var.project_id
      zone              = var.zone
    })
  }

  depends_on = [
    google_compute_instance_template.compute_node_template,
    google_compute_instance_template.gpu_node_template
  ]
}

# Login Node Instance
resource "google_compute_instance" "slurm_login" {
  name         = "${var.cluster_name}-login-0"
  machine_type = "n1-standard-2"
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "projects/schedmd-slurm-public/global/images/family/schedmd-slurm-22-05-8-hpc-rocky-linux-8"
      size  = 50
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.cluster_subnet.id
    
    access_config {
      // Ephemeral external IP
    }
  }

  service_account {
    email  = google_service_account.cluster_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  tags = ["hpc-cluster", "slurm-login"]

  labels = local.common_labels

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/scripts/login-startup.sh", {
      filestore_ip    = google_filestore_instance.cluster_filestore.networks[0].ip_addresses[0]
      bucket_name     = google_storage_bucket.video_data_bucket.name
      controller_name = google_compute_instance.slurm_controller.name
    })
  }

  depends_on = [google_compute_instance.slurm_controller]
}

# Cloud Monitoring Alert Policy for cluster health
resource "google_monitoring_alert_policy" "cluster_health" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "HPC Cluster Health"
  project      = var.project_id
  
  conditions {
    display_name = "Instance down"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"${var.cluster_name}.*\""
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# Create startup scripts directory and files
resource "local_file" "compute_startup_script" {
  filename = "${path.module}/scripts/compute-startup.sh"
  content = templatefile("${path.module}/templates/compute-startup.sh.tpl", {
    filestore_ip = "FILESTORE_IP_PLACEHOLDER"
    bucket_name  = "BUCKET_NAME_PLACEHOLDER"
  })
}

resource "local_file" "gpu_startup_script" {
  filename = "${path.module}/scripts/gpu-startup.sh"
  content = templatefile("${path.module}/templates/gpu-startup.sh.tpl", {
    filestore_ip = "FILESTORE_IP_PLACEHOLDER"
    bucket_name  = "BUCKET_NAME_PLACEHOLDER"
  })
}

resource "local_file" "controller_startup_script" {
  filename = "${path.module}/scripts/controller-startup.sh"
  content = templatefile("${path.module}/templates/controller-startup.sh.tpl", {
    filestore_ip      = "FILESTORE_IP_PLACEHOLDER"
    bucket_name       = "BUCKET_NAME_PLACEHOLDER"
    compute_template  = "COMPUTE_TEMPLATE_PLACEHOLDER"
    gpu_template      = "GPU_TEMPLATE_PLACEHOLDER"
    max_compute_nodes = "MAX_COMPUTE_NODES_PLACEHOLDER"
    max_gpu_nodes     = "MAX_GPU_NODES_PLACEHOLDER"
    project_id        = "PROJECT_ID_PLACEHOLDER"
    zone              = "ZONE_PLACEHOLDER"
  })
}

resource "local_file" "login_startup_script" {
  filename = "${path.module}/scripts/login-startup.sh"
  content = templatefile("${path.module}/templates/login-startup.sh.tpl", {
    filestore_ip    = "FILESTORE_IP_PLACEHOLDER"
    bucket_name     = "BUCKET_NAME_PLACEHOLDER"
    controller_name = "CONTROLLER_NAME_PLACEHOLDER"
  })
}