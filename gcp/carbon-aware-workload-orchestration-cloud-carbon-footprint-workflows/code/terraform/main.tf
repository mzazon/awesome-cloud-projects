# Local values for resource naming and configuration
locals {
  # Generate unique suffix for resource names
  random_suffix = random_id.suffix.hex
  
  # Common resource naming convention
  name_prefix = "${var.resource_prefix}-${var.environment}"
  
  # Resource names with unique suffix
  dataset_name          = "${local.name_prefix}-carbon-footprint-${local.random_suffix}"
  workflow_name         = "${local.name_prefix}-orchestrator-${local.random_suffix}"
  function_name         = "${local.name_prefix}-scheduler-${local.random_suffix}"
  instance_template     = "${local.name_prefix}-template-${local.random_suffix}"
  vpc_name             = "${local.name_prefix}-vpc-${local.random_suffix}"
  subnet_name          = "${local.name_prefix}-subnet-${local.random_suffix}"
  
  # Combined labels for all resources
  common_labels = merge(var.labels, {
    environment    = var.environment
    project       = var.project_id
    region        = var.region
    created-by    = "terraform"
    carbon-aware  = "true"
  })
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create VPC network for carbon-aware workload orchestration
resource "google_compute_network" "carbon_aware_vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for compute resources
resource "google_compute_subnetwork" "carbon_aware_subnet" {
  name          = local.subnet_name
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.carbon_aware_vpc.id
  
  # Enable private Google access for secure API communication
  private_ip_google_access = var.enable_private_google_access
  
  # Enable flow logs for monitoring if specified
  dynamic "log_config" {
    for_each = var.enable_vpc_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Firewall rule for SSH access to compute instances
resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.name_prefix}-allow-ssh-${local.random_suffix}"
  network = google_compute_network.carbon_aware_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.allowed_ingress_cidrs
  target_tags   = ["carbon-aware-workload"]
  
  description = "Allow SSH access to carbon-aware workload instances"
}

# Firewall rule for internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal-${local.random_suffix}"
  network = google_compute_network.carbon_aware_vpc.name
  
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
  
  source_ranges = ["10.0.0.0/24"]
  
  description = "Allow internal communication within carbon-aware VPC"
}

# Service account for carbon footprint data transfer operations
resource "google_service_account" "carbon_footprint_sa" {
  account_id   = "carbon-footprint-sa-${local.random_suffix}"
  display_name = "Carbon Footprint Data Transfer Service Account"
  description  = "Service account for automated carbon footprint data exports and analysis"
}

# IAM binding for BigQuery data transfer service agent role
resource "google_project_iam_member" "carbon_footprint_sa_data_transfer" {
  project = var.project_id
  role    = "roles/bigquery.dataTransfer.serviceAgent"
  member  = "serviceAccount:${google_service_account.carbon_footprint_sa.email}"
}

# IAM binding for BigQuery data editor role
resource "google_project_iam_member" "carbon_footprint_sa_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.carbon_footprint_sa.email}"
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "carbon-function-sa-${local.random_suffix}"
  display_name = "Carbon-Aware Scheduling Function Service Account"
  description  = "Service account for carbon-aware scheduling Cloud Function"
}

# IAM bindings for Cloud Function service account
resource "google_project_iam_member" "function_sa_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Service account for Cloud Workflows
resource "google_service_account" "workflow_sa" {
  account_id   = "carbon-workflow-sa-${local.random_suffix}"
  display_name = "Carbon-Aware Workflow Service Account"
  description  = "Service account for carbon-aware orchestration workflows"
}

# IAM bindings for Workflow service account
resource "google_project_iam_member" "workflow_sa_compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_sa_pubsub_admin" {
  project = var.project_id
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_sa_scheduler_admin" {
  project = var.project_id
  role    = "roles/cloudscheduler.admin"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_sa_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# BigQuery dataset for carbon footprint data
resource "google_bigquery_dataset" "carbon_footprint" {
  dataset_id  = replace(local.dataset_name, "-", "_")
  description = "Dataset for carbon footprint data analysis and carbon-aware scheduling"
  location    = var.dataset_location
  
  # Set data retention policy
  default_table_expiration_ms = var.carbon_footprint_retention_days * 24 * 60 * 60 * 1000
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery view for hourly carbon intensity analysis
resource "google_bigquery_table" "hourly_carbon_intensity" {
  dataset_id = google_bigquery_dataset.carbon_footprint.dataset_id
  table_id   = "hourly_carbon_intensity"
  
  view {
    query = <<-EOT
      SELECT
        EXTRACT(HOUR FROM usage_month) as hour_of_day,
        EXTRACT(DAYOFWEEK FROM usage_month) as day_of_week,
        region,
        AVG(carbon_footprint_total_kgCO2e) as avg_carbon_intensity,
        COUNT(*) as sample_count,
        STDDEV(carbon_footprint_total_kgCO2e) as carbon_variance
      FROM `${var.project_id}.${google_bigquery_dataset.carbon_footprint.dataset_id}.carbon_footprint`
      WHERE usage_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
      GROUP BY hour_of_day, day_of_week, region
      ORDER BY avg_carbon_intensity ASC
    EOT
    
    use_legacy_sql = false
  }
  
  description = "Hourly carbon intensity analysis for carbon-aware scheduling optimization"
  labels      = local.common_labels
}

# BigQuery view for optimal scheduling recommendations
resource "google_bigquery_table" "optimal_scheduling_windows" {
  dataset_id = google_bigquery_dataset.carbon_footprint.dataset_id
  table_id   = "optimal_scheduling_windows"
  
  view {
    query = <<-EOT
      SELECT
        hour_of_day,
        day_of_week,
        region,
        avg_carbon_intensity,
        CASE 
          WHEN avg_carbon_intensity < (
            SELECT PERCENTILE_CONT(avg_carbon_intensity, 0.25) OVER()
            FROM `${var.project_id}.${google_bigquery_dataset.carbon_footprint.dataset_id}.hourly_carbon_intensity`
          ) THEN 'GREEN'
          WHEN avg_carbon_intensity < (
            SELECT PERCENTILE_CONT(avg_carbon_intensity, 0.75) OVER()
            FROM `${var.project_id}.${google_bigquery_dataset.carbon_footprint.dataset_id}.hourly_carbon_intensity`
          ) THEN 'YELLOW'
          ELSE 'RED'
        END as carbon_tier
      FROM `${var.project_id}.${google_bigquery_dataset.carbon_footprint.dataset_id}.hourly_carbon_intensity`
      WHERE sample_count > 5
    EOT
    
    use_legacy_sql = false
  }
  
  description = "Optimal scheduling windows based on carbon intensity analysis"
  labels      = local.common_labels
}

# Pub/Sub topic for carbon-aware scheduling decisions
resource "google_pubsub_topic" "carbon_aware_decisions" {
  name = "${local.name_prefix}-decisions-${local.random_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for workflow consumption
resource "google_pubsub_subscription" "carbon_aware_workflow_sub" {
  name  = "${local.name_prefix}-workflow-sub-${local.random_suffix}"
  topic = google_pubsub_topic.carbon_aware_decisions.name
  
  ack_deadline_seconds = 60
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

# Pub/Sub topic for workload execution status updates
resource "google_pubsub_topic" "workload_execution_status" {
  name = "${local.name_prefix}-execution-status-${local.random_suffix}"
  
  labels = local.common_labels
}

# Pub/Sub subscription for monitoring workload status
resource "google_pubsub_subscription" "workload_status_monitoring" {
  name  = "${local.name_prefix}-status-monitoring-${local.random_suffix}"
  topic = google_pubsub_topic.workload_execution_status.name
  
  ack_deadline_seconds = 300
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source-${local.random_suffix}"
  location = var.region
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Archive Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/carbon-aware-function-${local.random_suffix}.zip"
  
  source {
    content = <<-EOT
import json
import logging
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import compute_v1
from google.cloud import pubsub_v1

# Initialize clients
bq_client = bigquery.Client()
compute_client = compute_v1.InstancesClient()
publisher = pubsub_v1.PublisherClient()

def carbon_aware_scheduler(request):
    """Main function for carbon-aware workload scheduling"""
    try:
        request_json = request.get_json()
        workload_type = request_json.get('workload_type', 'standard')
        urgency = request_json.get('urgency', 'normal')
        region = request_json.get('region', '${var.region}')
        
        # Query current carbon intensity
        carbon_intensity = get_current_carbon_intensity(region)
        
        # Make scheduling decision based on carbon awareness
        decision = make_scheduling_decision(carbon_intensity, urgency, workload_type)
        
        # Log the decision for monitoring
        logging.info(f"Carbon-aware decision: {decision}")
        
        # Publish decision to Pub/Sub for workflow consumption
        publish_scheduling_decision(decision)
        
        return json.dumps(decision)
        
    except Exception as e:
        logging.error(f"Error in carbon-aware scheduling: {str(e)}")
        return json.dumps({"error": str(e)}), 500

def get_current_carbon_intensity(region):
    """Query BigQuery for current carbon intensity in the specified region"""
    current_hour = datetime.now().hour
    current_day = datetime.now().isoweekday()
    
    query = f"""
    SELECT avg_carbon_intensity, carbon_tier
    FROM `{bq_client.project}.${google_bigquery_dataset.carbon_footprint.dataset_id}.optimal_scheduling_windows`
    WHERE hour_of_day = {current_hour}
      AND day_of_week = {current_day}
      AND region = '{region}'
    LIMIT 1
    """
    
    try:
        results = bq_client.query(query)
        for row in results:
            return {
                'intensity': float(row.avg_carbon_intensity),
                'tier': row.carbon_tier
            }
    except Exception as e:
        logging.warning(f"Could not retrieve carbon data: {e}")
        
    return {'intensity': ${var.carbon_intensity_threshold}, 'tier': 'YELLOW'}  # Default fallback

def make_scheduling_decision(carbon_intensity, urgency, workload_type):
    """Determine optimal scheduling based on carbon intensity and business requirements"""
    decision = {
        'timestamp': datetime.now().isoformat(),
        'carbon_intensity': carbon_intensity,
        'urgency': urgency,
        'workload_type': workload_type
    }
    
    # Business logic for carbon-aware scheduling
    if urgency == 'critical':
        decision['action'] = 'execute_immediately'
        decision['reason'] = 'Critical workload override'
    elif carbon_intensity['tier'] == 'GREEN':
        decision['action'] = 'execute_immediately'
        decision['reason'] = 'Low carbon intensity - optimal execution window'
    elif carbon_intensity['tier'] == 'YELLOW' and urgency == 'high':
        decision['action'] = 'execute_immediately'
        decision['reason'] = 'Moderate carbon intensity with high business urgency'
    else:
        # Calculate optimal delay based on carbon forecast
        delay_hours = calculate_optimal_delay(carbon_intensity)
        decision['action'] = 'schedule_delayed'
        decision['delay_hours'] = delay_hours
        decision['reason'] = f'High carbon intensity - delay {delay_hours} hours for better conditions'
    
    return decision

def calculate_optimal_delay(carbon_intensity):
    """Calculate optimal delay based on carbon intensity forecasting"""
    # Simplified logic - in production, this would use ML models
    if carbon_intensity['tier'] == 'RED':
        return min(${var.max_delay_hours}, 4)  # Wait 4 hours for better carbon conditions
    return min(${var.max_delay_hours}, 2)  # Wait 2 hours for moderate improvement

def publish_scheduling_decision(decision):
    """Publish scheduling decision to Pub/Sub for workflow consumption"""
    topic_path = publisher.topic_path(bq_client.project, '${google_pubsub_topic.carbon_aware_decisions.name}')
    message_data = json.dumps(decision).encode('utf-8')
    publisher.publish(topic_path, message_data)
    EOT
    filename = "main.py"
  }
  
  source {
    content = <<-EOT
google-cloud-bigquery==3.13.0
google-cloud-compute==1.14.1
google-cloud-pubsub==2.18.4
google-cloud-logging==3.8.0
functions-framework==3.4.0
    EOT
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "carbon-aware-function-${local.random_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for carbon-aware scheduling logic
resource "google_cloudfunctions_function" "carbon_aware_scheduler" {
  name        = local.function_name
  description = "Carbon-aware workload scheduling function with BigQuery integration"
  region      = var.region
  
  runtime     = var.function_runtime
  entry_point = "carbon_aware_scheduler"
  
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    PROJECT_ID              = var.project_id
    REGION                  = var.region
    DATASET_ID              = google_bigquery_dataset.carbon_footprint.dataset_id
    CARBON_DECISIONS_TOPIC  = google_pubsub_topic.carbon_aware_decisions.name
    MAX_DELAY_HOURS         = var.max_delay_hours
    CARBON_THRESHOLD        = var.carbon_intensity_threshold
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# IAM binding to allow unauthenticated invocation of the function
resource "google_cloudfunctions_function_iam_member" "function_invoker" {
  project        = var.project_id
  region         = google_cloudfunctions_function.carbon_aware_scheduler.region
  cloud_function = google_cloudfunctions_function.carbon_aware_scheduler.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Compute Engine instance template for carbon-optimized workloads
resource "google_compute_instance_template" "carbon_optimized" {
  name_prefix = "${local.instance_template}-"
  description = "Instance template for carbon-aware workload execution"
  
  machine_type = var.machine_type
  
  # Use regional persistent disk for availability
  disk {
    source_image = "projects/debian-cloud/global/images/family/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size
    disk_type    = var.boot_disk_type
  }
  
  network_interface {
    network    = google_compute_network.carbon_aware_vpc.id
    subnetwork = google_compute_subnetwork.carbon_aware_subnet.id
    
    access_config {
      # Ephemeral public IP
    }
  }
  
  # Use preemptible instances for cost optimization if enabled
  scheduling {
    preemptible                 = var.enable_preemptible_instances
    automatic_restart           = !var.enable_preemptible_instances
    on_host_maintenance         = var.enable_preemptible_instances ? "TERMINATE" : "MIGRATE"
    provisioning_model          = var.enable_preemptible_instances ? "SPOT" : "STANDARD"
  }
  
  service_account {
    email  = google_service_account.workflow_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      echo "Starting carbon-aware workload execution..."
      
      # Install monitoring agent
      curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
      sudo bash add-google-cloud-ops-agent-repo.sh --also-install
      
      # Log carbon-aware execution start
      logger "Carbon-aware workload started with template: ${local.instance_template}"
      
      # Workload-specific execution logic would go here
      # This is a placeholder for actual workload implementation
      sleep 300  # Simulate 5-minute workload
      
      logger "Carbon-aware workload execution completed"
      echo "Workload execution completed"
      
      # Signal completion and trigger shutdown
      shutdown -h +1
    EOT
  }
  
  tags = ["carbon-aware-workload"]
  
  labels = merge(local.common_labels, {
    workload-type = "carbon-optimized"
    instance-type = "template"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Cloud Workflows definition for carbon-aware orchestration
resource "google_workflows_workflow" "carbon_aware_orchestration" {
  name        = local.workflow_name
  region      = var.region
  description = "Carbon-aware workload orchestration workflow with intelligent scheduling"
  
  service_account = google_service_account.workflow_sa.email
  
  source_contents = <<-EOT
main:
  params: [args]
  steps:
    - initialize:
        assign:
          - project_id: "${var.project_id}"
          - workload_id: $${args.workload_id}
          - workload_type: $${default(args.workload_type, "standard")}
          - urgency: $${default(args.urgency, "normal")}
          - region: $${default(args.region, "${var.region}")}
          - max_delay_hours: $${default(args.max_delay_hours, ${var.max_delay_hours})}
    
    - log_workflow_start:
        call: sys.log
        args:
          data: $${"Starting carbon-aware orchestration for workload: " + workload_id}
          severity: "INFO"
    
    - get_carbon_decision:
        call: http.post
        args:
          url: "${google_cloudfunctions_function.carbon_aware_scheduler.https_trigger_url}"
          headers:
            Content-Type: "application/json"
          body:
            workload_type: $${workload_type}
            urgency: $${urgency}
            region: $${region}
            workload_id: $${workload_id}
        result: carbon_decision_response
    
    - parse_carbon_decision:
        assign:
          - carbon_decision: $${json.decode(carbon_decision_response.body)}
    
    - evaluate_scheduling_action:
        switch:
          - condition: $${carbon_decision.action == "execute_immediately"}
            next: execute_workload_immediately
          - condition: $${carbon_decision.action == "schedule_delayed"}
            next: schedule_delayed_execution
          - condition: true
            next: handle_scheduling_error
    
    - execute_workload_immediately:
        steps:
          - log_immediate_execution:
              call: sys.log
              args:
                data: $${"Executing workload immediately - " + carbon_decision.reason}
                severity: "INFO"
          
          - create_compute_resources:
              call: create_carbon_optimized_instance
              args:
                workload_id: $${workload_id}
                workload_type: $${workload_type}
                region: $${region}
              result: instance_details
          
          - publish_execution_status:
              call: gcp.pubsub.publish
              args:
                topic: "projects/${var.project_id}/topics/${google_pubsub_topic.workload_execution_status.name}"
                message:
                  data: $${base64.encode(json.encode({
                    "workload_id": workload_id,
                    "status": "executing",
                    "instance_name": instance_details.name,
                    "carbon_tier": carbon_decision.carbon_intensity.tier,
                    "timestamp": sys.now()
                  }))}
          
          - wait_for_completion:
              call: monitor_workload_execution
              args:
                instance_name: $${instance_details.name}
                workload_id: $${workload_id}
              result: execution_result
          
          - cleanup_resources:
              call: cleanup_compute_resources
              args:
                instance_name: $${instance_details.name}
                region: $${region}
        
        next: workflow_completion
    
    - schedule_delayed_execution:
        steps:
          - log_delayed_execution:
              call: sys.log
              args:
                data: $${"Delaying workload execution by " + string(carbon_decision.delay_hours) + " hours - " + carbon_decision.reason}
                severity: "INFO"
          
          - validate_delay_acceptable:
              switch:
                - condition: $${carbon_decision.delay_hours > max_delay_hours}
                  next: override_delay_for_sla
                - condition: true
                  next: schedule_future_execution
          
          - override_delay_for_sla:
              steps:
                - log_sla_override:
                    call: sys.log
                    args:
                      data: "SLA requirements override carbon optimization - executing with higher emissions"
                      severity: "WARNING"
                - assign_override:
                    assign:
                      - carbon_decision.action: "execute_immediately"
                      - carbon_decision.reason: "SLA override - maximum delay exceeded"
              next: execute_workload_immediately
          
          - schedule_future_execution:
              call: sys.log
              args:
                data: $${"Scheduling future execution for workload: " + workload_id}
                severity: "INFO"
        
        next: workflow_completion
    
    - handle_scheduling_error:
        steps:
          - log_error:
              call: sys.log
              args:
                data: $${"Unknown scheduling action: " + carbon_decision.action}
                severity: "ERROR"
          - return_error:
              return: $${"Error: Unknown scheduling action"}
    
    - workflow_completion:
        steps:
          - log_completion:
              call: sys.log
              args:
                data: $${"Carbon-aware orchestration completed for workload: " + workload_id}
                severity: "INFO"
          - return_result:
              return: $${"Workflow completed successfully for workload: " + workload_id}

create_carbon_optimized_instance:
  params: [workload_id, workload_type, region]
  steps:
    - determine_instance_specs:
        assign:
          - machine_type: "${var.machine_type}"
          - instance_name: $${"carbon-workload-" + workload_id}
    
    - create_instance:
        call: gcp.compute.instances.insert
        args:
          project: "${var.project_id}"
          zone: "${var.zone}"
          body:
            name: $${instance_name}
            machine_type: $${"zones/${var.zone}/machineTypes/" + machine_type}
            disks:
              - boot: true
                auto_delete: true
                initialize_params:
                  source_image: "projects/debian-cloud/global/images/family/debian-11"
                  disk_size_gb: "${var.boot_disk_size}"
                  disk_type: "${var.boot_disk_type}"
            network_interfaces:
              - network: "${google_compute_network.carbon_aware_vpc.self_link}"
                subnetwork: "${google_compute_subnetwork.carbon_aware_subnet.self_link}"
                access_configs:
                  - type: "ONE_TO_ONE_NAT"
            labels:
              workload-id: $${workload_id}
              carbon-aware: "true"
              workload-type: $${workload_type}
            metadata:
              items:
                - key: "startup-script"
                  value: |
                    #!/bin/bash
                    echo "Starting carbon-aware workload execution..."
                    logger "Carbon-aware workload started for ID: $${workload_id}"
                    # Workload-specific execution logic would go here
                    sleep 300  # Simulate 5-minute workload
                    logger "Carbon-aware workload completed for ID: $${workload_id}"
                    echo "Workload execution completed"
                    shutdown -h +1
            scheduling:
              preemptible: ${var.enable_preemptible_instances}
            service_accounts:
              - email: "${google_service_account.workflow_sa.email}"
                scopes:
                  - "https://www.googleapis.com/auth/cloud-platform"
            tags:
              items:
                - "carbon-aware-workload"
        result: create_response
    
    - return_instance_details:
        return:
          name: $${instance_name}
          machine_type: $${machine_type}
          status: "creating"

monitor_workload_execution:
  params: [instance_name, workload_id]
  steps:
    - wait_loop:
        for:
          value: attempt
          range: [1, 20]  # Maximum 20 attempts (10 minutes)
          steps:
            - check_instance_status:
                call: gcp.compute.instances.get
                args:
                  project: "${var.project_id}"
                  zone: "${var.zone}"
                  instance: $${instance_name}
                result: instance_status
            
            - evaluate_status:
                switch:
                  - condition: $${instance_status.status == "RUNNING"}
                    next: continue_monitoring
                  - condition: $${instance_status.status == "TERMINATED"}
                    next: workload_completed
                  - condition: true
                    next: wait_and_retry
            
            - continue_monitoring:
                call: sys.sleep
                args:
                  seconds: 30
            
            - wait_and_retry:
                call: sys.sleep
                args:
                  seconds: 30
    
    - workload_completed:
        return:
          status: "completed"
          workload_id: $${workload_id}

cleanup_compute_resources:
  params: [instance_name, region]
  steps:
    - delete_instance:
        call: gcp.compute.instances.delete
        args:
          project: "${var.project_id}"
          zone: "${var.zone}"
          instance: $${instance_name}
    
    - log_cleanup:
        call: sys.log
        args:
          data: $${"Cleaned up compute resources for instance: " + instance_name}
          severity: "INFO"
  EOT
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.carbon_aware_scheduler
  ]
}

# Cloud Scheduler job for daily batch processing during low-carbon hours
resource "google_cloud_scheduler_job" "daily_batch_carbon_aware" {
  name        = "${local.name_prefix}-daily-batch-${local.random_suffix}"
  description = "Daily batch processing with carbon-aware scheduling"
  schedule    = "0 2 * * *"
  time_zone   = "America/New_York"
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.carbon_aware_orchestration.name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        workload_id      = "daily-batch-${formatdate("YYYY-MM-DD", timestamp())}"
        workload_type    = "batch_processing"
        urgency          = "normal"
        region           = var.region
        max_delay_hours  = 6
      })
    }))
    
    oauth_token {
      service_account_email = google_service_account.workflow_sa.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.carbon_aware_orchestration
  ]
}

# Cloud Scheduler job for weekly analytics workload
resource "google_cloud_scheduler_job" "weekly_analytics_carbon_aware" {
  name        = "${local.name_prefix}-weekly-analytics-${local.random_suffix}"
  description = "Weekly analytics processing optimized for low carbon periods"
  schedule    = "0 1 * * 0"
  time_zone   = "UTC"
  region      = var.region
  
  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.carbon_aware_orchestration.name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        workload_id      = "weekly-analytics-${formatdate("YYYY-week-WW", timestamp())}"
        workload_type    = "analytics"
        urgency          = "low"
        region           = var.region
        max_delay_hours  = 24
      })
    }))
    
    oauth_token {
      service_account_email = google_service_account.workflow_sa.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.carbon_aware_orchestration
  ]
}

# Cloud Monitoring custom metrics (requires beta provider)
resource "google_monitoring_metric_descriptor" "carbon_workload_emissions" {
  count = var.enable_monitoring ? 1 : 0
  
  provider = google-beta
  
  type         = "custom.googleapis.com/carbon-workload-emissions"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  display_name = "Carbon Workload Emissions"
  description  = "Carbon emissions for executed workloads in kgCO2e"
  
  labels {
    key         = "workload_type"
    value_type  = "STRING"
    description = "Type of workload executed"
  }
  
  labels {
    key         = "region"
    value_type  = "STRING"
    description = "Region where workload was executed"
  }
}

resource "google_monitoring_metric_descriptor" "workload_delay_hours" {
  count = var.enable_monitoring ? 1 : 0
  
  provider = google-beta
  
  type         = "custom.googleapis.com/workload-delay-hours"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  display_name = "Workload Delay for Carbon Optimization"
  description  = "Hours delayed for carbon optimization"
  
  labels {
    key         = "workload_type"
    value_type  = "STRING"
    description = "Type of workload delayed"
  }
}

# Cloud Monitoring alert policy for high carbon intensity
resource "google_monitoring_alert_policy" "high_carbon_intensity" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Carbon Intensity Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Carbon Intensity High"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"custom.googleapis.com/carbon-workload-emissions\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.carbon_intensity_threshold * 1.5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.alert_notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "Alert when carbon intensity is consistently high, indicating suboptimal scheduling conditions"
  }
  
  enabled = true
}

# Cloud Monitoring dashboard for carbon-aware orchestration
resource "google_monitoring_dashboard" "carbon_aware_orchestration" {
  count = var.enable_monitoring && var.monitoring_dashboard_enabled ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Carbon-Aware Workload Orchestration Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Carbon Emissions by Workload"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/carbon-workload-emissions\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Workload Execution Delays"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/workload-delay-hours\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_SUM"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Cloud Function Executions"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
}