# Performance Testing Pipeline Infrastructure
# This file defines the complete infrastructure for automated performance testing
# including load balancers, compute instances, Cloud Functions, and monitoring

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  resource_prefix = "${var.application_name}-${var.environment}"
  resource_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.resource_labels, {
    environment = var.environment
    application = var.application_name
    terraform   = "true"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service Account for Performance Testing Functions
resource "google_service_account" "perf_test_sa" {
  account_id   = "${local.resource_prefix}-sa-${local.resource_suffix}"
  display_name = "Performance Testing Service Account"
  description  = "Service account for automated performance testing pipeline"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "perf_test_sa_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudfunctions.invoker"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.perf_test_sa.email}"

  depends_on = [google_service_account.perf_test_sa]
}

# Cloud Storage bucket for test results
resource "google_storage_bucket" "test_results" {
  name     = "${var.project_id}-${local.resource_prefix}-results-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  # Storage class optimization for cost
  storage_class = "STANDARD"

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  # Versioning for data protection
  versioning {
    enabled = true
  }

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Instance template for application servers
resource "google_compute_instance_template" "app_template" {
  name_prefix  = "${local.resource_prefix}-template-"
  description  = "Template for performance test target application instances"
  machine_type = var.instance_machine_type
  project      = var.project_id

  # Boot disk configuration
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-standard"
  }

  # Network interface configuration
  network_interface {
    network = "default"
    access_config {
      # Ephemeral public IP
    }
  }

  # Service account and scopes
  service_account {
    email = google_service_account.perf_test_sa.email
    scopes = [
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/logging.write"
    ]
  }

  # Startup script to configure web server
  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    hostname_prefix = local.resource_prefix
  })

  # Network tags for firewall rules
  tags = ["http-server", "performance-test-target"]

  # Labels for resource management
  labels = local.common_labels

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_service_account.perf_test_sa]
}

# Create startup script file
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content  = <<-EOF
#!/bin/bash
set -e

# Update system packages
apt-get update
apt-get install -y nginx

# Create custom HTML page for performance testing
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Performance Test Target Application</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { color: #4285f4; border-bottom: 2px solid #4285f4; padding-bottom: 10px; }
        .info { margin: 20px 0; padding: 15px; background-color: #e8f0fe; border-radius: 4px; }
        .metric { margin: 10px 0; }
        .timestamp { color: #5f6368; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">Performance Test Target Application</h1>
        <div class="info">
            <div class="metric"><strong>Instance:</strong> $(hostname)</div>
            <div class="metric"><strong>Timestamp:</strong> <span class="timestamp">$(date)</span></div>
            <div class="metric"><strong>Zone:</strong> $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)</div>
            <div class="metric"><strong>Machine Type:</strong> $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/machine-type | cut -d/ -f4)</div>
        </div>
        <p>This application is ready for performance testing. Response generated successfully.</p>
        <div style="margin-top: 30px; padding: 15px; background-color: #f8f9fa; border-left: 4px solid #34a853;">
            <strong>Status:</strong> Application is healthy and responding to requests.
        </div>
    </div>
</body>
</html>
HTML

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Configure nginx for better performance testing
cat > /etc/nginx/sites-available/default << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name _;
    
    # Performance optimizations for testing
    keepalive_timeout 65;
    keepalive_requests 1000;
    
    location / {
        try_files $uri $uri/ =404;
        
        # Add headers for debugging
        add_header X-Instance-Name $hostname;
        add_header X-Response-Time $request_time;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
NGINX

# Restart nginx to apply configuration
systemctl restart nginx

# Install monitoring agent (optional)
curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
bash add-logging-agent-repo.sh --also-install

echo "Application server setup completed successfully"
EOF
}

# Managed instance group
resource "google_compute_region_instance_group_manager" "app_group" {
  name     = "${local.resource_prefix}-group-${local.resource_suffix}"
  region   = var.region
  project  = var.project_id

  base_instance_name = "${local.resource_prefix}-instance"

  version {
    instance_template = google_compute_instance_template.app_template.id
  }

  target_size = var.min_replicas

  # Auto-healing policy
  auto_healing_policies {
    health_check      = google_compute_health_check.app_health_check.id
    initial_delay_sec = 300
  }

  # Update policy for rolling updates
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
  }

  depends_on = [google_compute_instance_template.app_template]
}

# Autoscaler for the managed instance group
resource "google_compute_region_autoscaler" "app_autoscaler" {
  name   = "${local.resource_prefix}-autoscaler-${local.resource_suffix}"
  region = var.region
  target = google_compute_region_instance_group_manager.app_group.id

  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = 60

    cpu_utilization {
      target = var.target_cpu_utilization
    }

    # Scale based on load balancer utilization
    load_balancing_utilization {
      target = 0.8
    }
  }
}

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.resource_prefix}-allow-health-check-${local.resource_suffix}"
  network = "default"
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # Google Cloud health check source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-server"]

  description = "Allow health check access to HTTP servers"
}

# Firewall rule for HTTP traffic
resource "google_compute_firewall" "allow_http" {
  name    = "${local.resource_prefix}-allow-http-${local.resource_suffix}"
  network = "default"
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]

  description = "Allow HTTP traffic to web servers"
}

# Health check for load balancer
resource "google_compute_health_check" "app_health_check" {
  name        = "${local.resource_prefix}-health-check-${local.resource_suffix}"
  description = "Health check for performance test application"
  project     = var.project_id

  timeout_sec         = var.health_check_timeout
  check_interval_sec  = var.health_check_interval
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = var.health_check_path
  }
}

# Backend service for load balancer
resource "google_compute_backend_service" "app_backend" {
  name        = "${local.resource_prefix}-backend-${local.resource_suffix}"
  description = "Backend service for performance test application"
  project     = var.project_id

  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  health_checks = [google_compute_health_check.app_health_check.id]

  backend {
    group           = google_compute_region_instance_group_manager.app_group.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }

  # Load balancing configuration
  load_balancing_scheme = "EXTERNAL"

  # Session affinity (optional)
  session_affinity = "NONE"

  depends_on = [
    google_compute_region_instance_group_manager.app_group,
    google_compute_health_check.app_health_check
  ]
}

# URL map for load balancer
resource "google_compute_url_map" "app_url_map" {
  name            = "${local.resource_prefix}-url-map-${local.resource_suffix}"
  description     = "URL map for performance test application"
  default_service = google_compute_backend_service.app_backend.id
  project         = var.project_id
}

# HTTP proxy for load balancer
resource "google_compute_target_http_proxy" "app_http_proxy" {
  name    = "${local.resource_prefix}-http-proxy-${local.resource_suffix}"
  url_map = google_compute_url_map.app_url_map.id
  project = var.project_id
}

# Global forwarding rule for load balancer
resource "google_compute_global_forwarding_rule" "app_forwarding_rule" {
  name        = "${local.resource_prefix}-forwarding-rule-${local.resource_suffix}"
  target      = google_compute_target_http_proxy.app_http_proxy.id
  port_range  = "80"
  ip_protocol = "TCP"
  project     = var.project_id

  depends_on = [google_compute_target_http_proxy.app_http_proxy]
}

# Archive for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source {
    content = templatefile("${path.module}/function_code.py", {
      project_id  = var.project_id
      bucket_name = google_storage_bucket.test_results.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create function source files
resource "local_file" "function_code" {
  filename = "${path.module}/function_code.py"
  content  = <<-EOF
import json
import time
import requests
import concurrent.futures
from datetime import datetime
from google.cloud import monitoring_v3
from google.cloud import storage
import functions_framework
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def execute_load_test(target_url, duration_seconds, concurrent_users, requests_per_second):
    """Execute load test against target URL with detailed metrics collection"""
    results = {
        'start_time': datetime.utcnow().isoformat(),
        'target_url': target_url,
        'duration_seconds': duration_seconds,
        'concurrent_users': concurrent_users,
        'requests_per_second': requests_per_second,
        'total_requests': 0,
        'successful_requests': 0,
        'failed_requests': 0,
        'response_times': [],
        'error_details': [],
        'status_codes': {},
        'bytes_transferred': 0
    }
    
    start_time = time.time()
    request_interval = 1.0 / requests_per_second if requests_per_second > 0 else 0.1
    
    def make_request():
        """Execute a single HTTP request with detailed metrics"""
        try:
            response_start = time.time()
            response = requests.get(
                target_url, 
                timeout=30,
                headers={'User-Agent': 'GCP-Performance-Test/1.0'}
            )
            response_time = time.time() - response_start
            
            # Track status codes
            status_code = response.status_code
            content_length = len(response.content) if response.content else 0
            
            if response.status_code == 200:
                return {
                    'success': True, 
                    'response_time': response_time,
                    'status_code': status_code,
                    'content_length': content_length
                }
            else:
                return {
                    'success': False, 
                    'error': f'HTTP {response.status_code}', 
                    'response_time': response_time,
                    'status_code': status_code,
                    'content_length': content_length
                }
        except requests.exceptions.Timeout:
            return {'success': False, 'error': 'Request timeout', 'response_time': 30, 'status_code': 0, 'content_length': 0}
        except requests.exceptions.ConnectionError:
            return {'success': False, 'error': 'Connection error', 'response_time': 0, 'status_code': 0, 'content_length': 0}
        except Exception as e:
            return {'success': False, 'error': str(e), 'response_time': 0, 'status_code': 0, 'content_length': 0}
    
    logger.info(f"Starting load test: {concurrent_users} users, {requests_per_second} req/s, {duration_seconds}s duration")
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_users) as executor:
        while time.time() - start_time < duration_seconds:
            future = executor.submit(make_request)
            try:
                result = future.result(timeout=35)
                results['total_requests'] += 1
                
                if result['success']:
                    results['successful_requests'] += 1
                    results['response_times'].append(result['response_time'])
                    results['bytes_transferred'] += result.get('content_length', 0)
                else:
                    results['failed_requests'] += 1
                    results['error_details'].append(result['error'])
                
                # Track status codes
                status_code = result.get('status_code', 0)
                results['status_codes'][status_code] = results['status_codes'].get(status_code, 0) + 1
                
                time.sleep(request_interval)
            except concurrent.futures.TimeoutError:
                results['failed_requests'] += 1
                results['error_details'].append('Request timeout')
                results['status_codes'][0] = results['status_codes'].get(0, 0) + 1
    
    results['end_time'] = datetime.utcnow().isoformat()
    results['actual_duration'] = time.time() - start_time
    
    # Calculate summary statistics
    if results['response_times']:
        results['avg_response_time'] = sum(results['response_times']) / len(results['response_times'])
        results['min_response_time'] = min(results['response_times'])
        results['max_response_time'] = max(results['response_times'])
        results['median_response_time'] = sorted(results['response_times'])[len(results['response_times']) // 2]
    else:
        results['avg_response_time'] = 0
        results['min_response_time'] = 0
        results['max_response_time'] = 0
        results['median_response_time'] = 0
    
    results['success_rate'] = results['successful_requests'] / results['total_requests'] if results['total_requests'] > 0 else 0
    results['requests_per_second_actual'] = results['total_requests'] / results['actual_duration'] if results['actual_duration'] > 0 else 0
    
    logger.info(f"Load test completed: {results['total_requests']} requests, {results['success_rate']:.2%} success rate")
    return results

def publish_metrics(results, project_id):
    """Publish performance metrics to Cloud Monitoring"""
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        now = time.time()
        
        # Prepare time series data
        series_data = [
            {
                'metric_type': 'custom.googleapis.com/performance_test/response_time_avg',
                'value': results.get('avg_response_time', 0),
                'description': 'Average response time for performance test'
            },
            {
                'metric_type': 'custom.googleapis.com/performance_test/requests_per_second',
                'value': results.get('requests_per_second_actual', 0),
                'description': 'Actual requests per second achieved'
            },
            {
                'metric_type': 'custom.googleapis.com/performance_test/success_rate',
                'value': results.get('success_rate', 0),
                'description': 'Success rate of performance test'
            },
            {
                'metric_type': 'custom.googleapis.com/performance_test/total_requests',
                'value': results.get('total_requests', 0),
                'description': 'Total number of requests in test'
            }
        ]
        
        time_series_list = []
        for metric_data in series_data:
            series = monitoring_v3.TimeSeries()
            series.metric.type = metric_data['metric_type']
            series.resource.type = "global"
            
            point = series.points.add()
            point.value.double_value = float(metric_data['value'])
            point.interval.end_time.seconds = int(now)
            point.interval.end_time.nanos = int((now - int(now)) * 10**9)
            
            time_series_list.append(series)
        
        # Publish metrics in batch
        if time_series_list:
            client.create_time_series(name=project_name, time_series=time_series_list)
            logger.info(f"Published {len(time_series_list)} metrics to Cloud Monitoring")
        
    except Exception as e:
        logger.error(f"Failed to publish metrics: {str(e)}")

def store_results(results, bucket_name):
    """Store test results in Cloud Storage"""
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        
        # Generate unique filename with timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        blob_name = f"test-results/{timestamp}_performance_test_results.json"
        
        blob = bucket.blob(blob_name)
        blob.upload_from_string(
            json.dumps(results, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Test results stored to gs://{bucket_name}/{blob_name}")
        return f"gs://{bucket_name}/{blob_name}"
        
    except Exception as e:
        logger.error(f"Failed to store results: {str(e)}")
        return None

@functions_framework.http
def load_test_function(request):
    """Cloud Function entry point for load testing"""
    try:
        # Parse request
        if request.method != 'POST':
            return {'error': 'Only POST method is supported'}, 405
            
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Request must contain JSON payload'}, 400
        
        # Extract and validate parameters
        target_url = request_json.get('target_url', '')
        duration_seconds = int(request_json.get('duration_seconds', ${var.default_test_duration}))
        concurrent_users = int(request_json.get('concurrent_users', ${var.default_concurrent_users}))
        requests_per_second = int(request_json.get('requests_per_second', ${var.default_requests_per_second}))
        project_id = request_json.get('project_id', '${var.project_id}')
        bucket_name = request_json.get('bucket_name', '${google_storage_bucket.test_results.name}')
        
        if not target_url:
            return {'error': 'target_url is required'}, 400
            
        if not target_url.startswith(('http://', 'https://')):
            return {'error': 'target_url must be a valid HTTP/HTTPS URL'}, 400
        
        # Validate parameter ranges
        if duration_seconds < 1 or duration_seconds > 3600:
            return {'error': 'duration_seconds must be between 1 and 3600'}, 400
            
        if concurrent_users < 1 or concurrent_users > 1000:
            return {'error': 'concurrent_users must be between 1 and 1000'}, 400
            
        if requests_per_second < 1 or requests_per_second > 10000:
            return {'error': 'requests_per_second must be between 1 and 10000'}, 400
        
        logger.info(f"Starting load test for {target_url}")
        
        # Execute load test
        results = execute_load_test(target_url, duration_seconds, concurrent_users, requests_per_second)
        
        # Publish metrics to Cloud Monitoring
        if project_id:
            publish_metrics(results, project_id)
        
        # Store results in Cloud Storage
        storage_path = None
        if bucket_name:
            storage_path = store_results(results, bucket_name)
        
        # Prepare response summary
        response_data = {
            'status': 'completed',
            'test_parameters': {
                'target_url': target_url,
                'duration_seconds': duration_seconds,
                'concurrent_users': concurrent_users,
                'requests_per_second': requests_per_second
            },
            'results_summary': {
                'total_requests': results['total_requests'],
                'successful_requests': results['successful_requests'],
                'failed_requests': results['failed_requests'],
                'success_rate': results['success_rate'],
                'average_response_time': results['avg_response_time'],
                'min_response_time': results['min_response_time'],
                'max_response_time': results['max_response_time'],
                'median_response_time': results['median_response_time'],
                'actual_rps': results['requests_per_second_actual'],
                'bytes_transferred': results['bytes_transferred']
            },
            'storage_path': storage_path,
            'timestamp': results['end_time']
        }
        
        logger.info("Load test completed successfully")
        return response_data, 200
        
    except ValueError as e:
        logger.error(f"Invalid parameter value: {str(e)}")
        return {'error': f'Invalid parameter value: {str(e)}'}, 400
    except Exception as e:
        logger.error(f"Load test failed: {str(e)}")
        return {'error': f'Load test failed: {str(e)}'}, 500
EOF
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/requirements.txt"
  content  = <<-EOF
requests==2.31.0
google-cloud-monitoring==2.16.0
google-cloud-storage==2.10.0
functions-framework==3.4.0
EOF
}

# Cloud Function for load generation
resource "google_cloudfunctions_function" "load_test_function" {
  name        = "${local.resource_prefix}-function-${local.resource_suffix}"
  description = "Cloud Function for automated performance testing"
  runtime     = "python311"
  project     = var.project_id
  region      = var.region

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  max_instances         = var.function_max_instances
  entry_point           = "load_test_function"
  service_account_email = google_service_account.perf_test_sa.email

  source_archive_bucket = google_storage_bucket.test_results.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    PROJECT_ID  = var.project_id
    BUCKET_NAME = google_storage_bucket.test_results.name
  }

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.perf_test_sa_permissions
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.test_results.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Scheduler job for daily performance tests
resource "google_cloud_scheduler_job" "daily_perf_test" {
  name        = "${local.resource_prefix}-daily-test-${local.resource_suffix}"
  description = "Daily comprehensive performance test"
  schedule    = var.daily_test_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.load_test_function.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      target_url           = "http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}"
      duration_seconds     = var.default_test_duration
      concurrent_users     = var.default_concurrent_users
      requests_per_second  = var.default_requests_per_second
      project_id          = var.project_id
      bucket_name         = google_storage_bucket.test_results.name
    }))
  }

  depends_on = [
    google_cloudfunctions_function.load_test_function,
    google_compute_global_forwarding_rule.app_forwarding_rule
  ]
}

# Cloud Scheduler job for hourly light tests
resource "google_cloud_scheduler_job" "hourly_perf_test" {
  name        = "${local.resource_prefix}-hourly-test-${local.resource_suffix}"
  description = "Hourly light performance validation"
  schedule    = var.hourly_test_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.load_test_function.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      target_url           = "http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}"
      duration_seconds     = 60
      concurrent_users     = 5
      requests_per_second  = 5
      project_id          = var.project_id
      bucket_name         = google_storage_bucket.test_results.name
    }))
  }

  depends_on = [
    google_cloudfunctions_function.load_test_function,
    google_compute_global_forwarding_rule.app_forwarding_rule
  ]
}

# Monitoring dashboard
resource "google_monitoring_dashboard" "perf_test_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Performance Testing Dashboard - ${local.resource_prefix}"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "HTTP Load Balancer Request Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_backend_service\" AND resource.labels.backend_service_name=\"${google_compute_backend_service.app_backend.name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Requests/second"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Backend Response Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_backend_service\" AND resource.labels.backend_service_name=\"${google_compute_backend_service.app_backend.name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Latency (ms)"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 4
          widget = {
            title = "Performance Test Response Time"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/performance_test/response_time_avg\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Response Time (seconds)"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          yPos = 4
          widget = {
            title = "Instance Group Size"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance_group\" AND resource.labels.instance_group_name=\"${google_compute_region_instance_group_manager.app_group.name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Number of Instances"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_compute_backend_service.app_backend,
    google_compute_region_instance_group_manager.app_group
  ]
}

# Alert policy for high response times
resource "google_monitoring_alert_policy" "high_response_time" {
  display_name = "Performance Test - High Response Time - ${local.resource_prefix}"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id

  conditions {
    display_name = "Response time exceeds threshold"
    condition_threshold {
      filter         = "metric.type=\"custom.googleapis.com/performance_test/response_time_avg\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_response_time_threshold
      duration       = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content = "Performance test response time has exceeded ${var.alert_response_time_threshold} seconds"
  }
}

# Alert policy for high error rate
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "Performance Test - High Error Rate - ${local.resource_prefix}"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id

  conditions {
    display_name = "Error rate exceeds 5%"
    condition_threshold {
      filter         = "resource.type=\"gce_backend_service\" AND resource.labels.backend_service_name=\"${google_compute_backend_service.app_backend.name}\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_error_rate_threshold
      duration       = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content = "Load balancer error rate has exceeded ${var.alert_error_rate_threshold * 100}%"
  }

  depends_on = [google_compute_backend_service.app_backend]
}

# Notification channel (if email is provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Email Notification - ${local.resource_prefix}"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }
}

# Update alert policies to include notification channels
resource "google_monitoring_alert_policy" "high_response_time_with_notification" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Performance Test - High Response Time with Notifications - ${local.resource_prefix}"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id

  conditions {
    display_name = "Response time exceeds threshold"
    condition_threshold {
      filter         = "metric.type=\"custom.googleapis.com/performance_test/response_time_avg\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_response_time_threshold
      duration       = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_notification[0].id]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content = "Performance test response time has exceeded ${var.alert_response_time_threshold} seconds"
  }

  depends_on = [google_monitoring_notification_channel.email_notification]
}