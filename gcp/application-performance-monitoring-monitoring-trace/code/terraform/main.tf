# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Generate unique names with suffix
  instance_name    = "${var.resource_prefix}-web-app-${random_id.suffix.hex}"
  pubsub_topic     = "${var.resource_prefix}-alerts-${random_id.suffix.hex}"
  function_name    = "${var.resource_prefix}-optimizer-${random_id.suffix.hex}"
  dashboard_name   = "${var.resource_prefix}-dashboard-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Pub/Sub topic for performance alerts
resource "google_pubsub_topic" "performance_alerts" {
  name    = local.pubsub_topic
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create Pub/Sub subscription for Cloud Function processing
resource "google_pubsub_subscription" "performance_alerts_subscription" {
  name    = "${local.pubsub_topic}-subscription"
  topic   = google_pubsub_topic.performance_alerts.name
  project = var.project_id
  
  # Configure message acknowledgment and retry
  ack_deadline_seconds       = 20
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages     = false
  
  # Configure exponential backoff for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

# Create firewall rule for web application access
resource "google_compute_firewall" "allow_web_app" {
  name        = "${var.resource_prefix}-allow-web-app-${random_id.suffix.hex}"
  network     = "default"
  description = "Allow HTTP access to performance monitoring web application"
  
  allow {
    protocol = "tcp"
    ports    = ["5000"]
  }
  
  source_ranges = var.allowed_source_ranges
  target_tags   = ["web-server"]
  
  # Priority for firewall rule (lower numbers have higher priority)
  priority = 1000
}

# Create startup script for the sample application
locals {
  startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system packages
    apt-get update
    apt-get install -y python3 python3-pip nginx curl
    
    # Install required Python packages for monitoring
    pip3 install google-cloud-monitoring google-cloud-trace flask gunicorn
    
    # Create sample Flask application with monitoring instrumentation
    cat > /opt/app.py << 'APP_EOF'
from flask import Flask, request, jsonify
import time
import random
import os
import logging
from google.cloud import monitoring_v3
from google.cloud import trace_v1

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize monitoring client
try:
    monitoring_client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{os.environ.get('GOOGLE_CLOUD_PROJECT', '${var.project_id}')}"
    logger.info(f"Monitoring client initialized for project: {project_name}")
except Exception as e:
    logger.error(f"Failed to initialize monitoring client: {e}")
    monitoring_client = None
    project_name = None

@app.route('/api/data')
def get_data():
    """API endpoint that simulates variable response times and sends metrics"""
    start_time = time.time()
    
    # Simulate variable response time based on load
    base_delay = random.uniform(0.1, 0.5)
    load_factor = random.uniform(1.0, 4.0)  # Sometimes simulate high load
    delay = base_delay * load_factor
    time.sleep(delay)
    
    response_time = time.time() - start_time
    
    # Send custom metric to Cloud Monitoring
    if monitoring_client and project_name:
        try:
            series = monitoring_v3.TimeSeries()
            series.metric.type = "custom.googleapis.com/api/response_time"
            series.resource.type = "global"
            
            # Add metric labels for better categorization
            series.metric.labels["endpoint"] = "/api/data"
            series.metric.labels["method"] = "GET"
            
            point = series.points.add()
            point.value.double_value = response_time
            point.interval.end_time.seconds = int(time.time())
            
            monitoring_client.create_time_series(
                name=project_name, 
                time_series=[series]
            )
            
            logger.info(f"Metric sent: response_time={response_time:.3f}s")
            
        except Exception as e:
            logger.error(f"Failed to send monitoring metric: {e}")
    
    return jsonify({
        'data': f'Sample response generated at {time.strftime("%Y-%m-%d %H:%M:%S")}',
        'response_time': round(response_time, 3),
        'timestamp': time.time(),
        'load_factor': round(load_factor, 2)
    })

@app.route('/health')
def health():
    """Health check endpoint for monitoring"""
    return jsonify({
        'status': 'healthy',
        'timestamp': time.time(),
        'version': '1.0'
    })

@app.route('/load-test')
def load_test():
    """Endpoint that intentionally creates high load for testing alerts"""
    # Simulate heavy processing
    time.sleep(random.uniform(2.0, 5.0))
    return jsonify({
        'message': 'Load test completed',
        'timestamp': time.time()
    })

if __name__ == '__main__':
    logger.info("Starting performance monitoring sample application")
    app.run(host='0.0.0.0', port=5000, debug=False)
APP_EOF
    
    # Set up environment variables
    echo "export GOOGLE_CLOUD_PROJECT=${var.project_id}" >> /etc/environment
    
    # Create systemd service for the application
    cat > /etc/systemd/system/monitoring-app.service << 'SERVICE_EOF'
[Unit]
Description=Performance Monitoring Sample Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt
Environment=GOOGLE_CLOUD_PROJECT=${var.project_id}
ExecStart=/usr/bin/python3 /opt/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    # Enable and start the service
    systemctl daemon-reload
    systemctl enable monitoring-app.service
    systemctl start monitoring-app.service
    
    # Verify service is running
    sleep 10
    systemctl status monitoring-app.service
    
    logger.info "Sample application startup completed"
  EOF
}

# Create Compute Engine instance for sample application
resource "google_compute_instance" "web_app" {
  name         = local.instance_name
  machine_type = var.instance_machine_type
  zone         = var.zone
  
  # Use latest stable OS image
  boot_disk {
    initialize_params {
      image = "${var.instance_image_project}/${var.instance_image_family}"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  # Network configuration
  network_interface {
    network = "default"
    access_config {
      # Ephemeral public IP
    }
  }
  
  # Security and monitoring configuration
  tags = ["web-server"]
  
  # Enable monitoring and logging
  service_account {
    email = google_service_account.monitoring_sa.email
    scopes = [
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/compute.readonly"
    ]
  }
  
  # Install and configure the sample application
  metadata_startup_script = local.startup_script
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_compute_firewall.allow_web_app
  ]
}

# Create service account for monitoring operations
resource "google_service_account" "monitoring_sa" {
  account_id   = "${var.resource_prefix}-monitoring-${random_id.suffix.hex}"
  display_name = "Performance Monitoring Service Account"
  description  = "Service account for performance monitoring application and automation"
  project      = var.project_id
}

# Grant necessary IAM permissions to the service account
resource "google_project_iam_member" "monitoring_sa_roles" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/logging.logWriter",
    "roles/compute.viewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.monitoring_sa.email}"
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-${random_id.suffix.hex}"
  display_name = "Performance Optimizer Function Service Account"
  description  = "Service account for performance optimization Cloud Function"
  project      = var.project_id
}

# Grant Cloud Function service account necessary permissions
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/monitoring.viewer",
    "roles/cloudtrace.user",
    "roles/logging.logWriter",
    "roles/pubsub.subscriber"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source-${random_id.suffix.hex}.zip"
  
  source {
    content = <<-EOF
import json
import base64
import logging
from google.cloud import monitoring_v3
from google.cloud import trace_v1
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
monitoring_client = monitoring_v3.MetricServiceClient()
trace_client = trace_v1.TraceServiceClient()

@functions_framework.cloud_event
def performance_optimizer(cloud_event):
    """
    Process performance alerts and implement intelligent optimizations.
    
    This function analyzes monitoring alerts, queries distributed traces
    for bottleneck identification, and implements automated optimizations.
    """
    
    try:
        # Decode Pub/Sub message
        if 'data' not in cloud_event.data.get('message', {}):
            logger.error("No data found in cloud event message")
            return "No data in message"
            
        message_data = base64.b64decode(cloud_event.data['message']['data'])
        alert_data = json.loads(message_data.decode())
        
        logger.info(f"Processing alert: {alert_data}")
        
        # Extract project information
        project_id = alert_data.get('incident', {}).get('project_id')
        if not project_id:
            # Try alternative location for project ID
            project_id = alert_data.get('project_id', '${var.project_id}')
        
        project_name = f"projects/{project_id}"
        
        # Analyze performance metrics from the last 10 minutes
        end_time = monitoring_v3.TimeInterval()
        end_time.end_time.seconds = int(cloud_event.data.get('timestamp', 0))
        end_time.start_time.seconds = end_time.end_time.seconds - 600  # 10 minutes ago
        
        # Query for recent high response time metrics
        metric_query = monitoring_v3.ListTimeSeriesRequest(
            name=project_name,
            filter='metric.type="custom.googleapis.com/api/response_time"',
            interval=end_time,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        )
        
        try:
            time_series = monitoring_client.list_time_series(request=metric_query)
            
            high_response_times = []
            for series in time_series:
                for point in series.points:
                    if point.value.double_value > ${var.alert_threshold_seconds}:
                        high_response_times.append({
                            'value': point.value.double_value,
                            'timestamp': point.interval.end_time.seconds
                        })
            
            logger.info(f"Found {len(high_response_times)} high response time metrics")
            
        except Exception as e:
            logger.error(f"Error querying metrics: {e}")
            high_response_times = []
        
        # Query distributed traces for bottleneck analysis
        try:
            traces_request = trace_v1.ListTracesRequest(
                parent=project_name,
                page_size=20
            )
            
            traces = trace_client.list_traces(request=traces_request)
            
            slow_traces = []
            for trace in traces:
                for span in trace.spans:
                    # Calculate span duration in milliseconds
                    if span.end_time and span.start_time:
                        duration_ms = (
                            span.end_time.seconds - span.start_time.seconds
                        ) * 1000 + (
                            span.end_time.nanos - span.start_time.nanos
                        ) / 1000000
                        
                        if duration_ms > 1000:  # Spans over 1 second
                            slow_traces.append({
                                'trace_id': trace.trace_id,
                                'span_name': span.name,
                                'duration_ms': duration_ms,
                                'labels': dict(span.labels)
                            })
            
            logger.info(f"Analyzed traces, found {len(slow_traces)} slow spans")
            
        except Exception as e:
            logger.error(f"Error analyzing traces: {e}")
            slow_traces = []
        
        # Implement optimization strategies based on analysis
        optimization_actions = []
        
        if high_response_times:
            optimization_actions.append("cache_warming")
            logger.info("Recommended: Implement cache warming for frequently accessed data")
        
        if slow_traces:
            optimization_actions.append("connection_pooling")
            logger.info("Recommended: Review database connection pooling configuration")
            
            # Check for specific bottleneck patterns
            db_spans = [t for t in slow_traces if 'database' in t.get('span_name', '').lower()]
            if db_spans:
                optimization_actions.append("database_optimization")
                logger.info("Recommended: Database query optimization needed")
        
        # Log comprehensive analysis results
        analysis_result = {
            'alert_processed': True,
            'project_id': project_id,
            'high_response_count': len(high_response_times),
            'slow_trace_count': len(slow_traces),
            'optimization_actions': optimization_actions,
            'analysis_timestamp': end_time.end_time.seconds
        }
        
        logger.info(f"Performance analysis completed: {json.dumps(analysis_result)}")
        
        # In a production environment, this would trigger actual optimization actions
        # such as scaling resources, updating configurations, or warming caches
        
        return f"Performance optimization analysis completed: {len(optimization_actions)} actions recommended"
        
    except Exception as e:
        logger.error(f"Error in performance optimizer: {e}")
        return f"Error processing alert: {str(e)}"
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
google-cloud-monitoring>=2.11.0
google-cloud-trace>=1.7.0
google-cloud-logging>=3.0.0
functions-framework>=3.0.0
EOF
    filename = "requirements.txt"
  }
}

# Create Google Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.resource_prefix}-function-source-${random_id.suffix.hex}"
  location      = var.region
  project       = var.project_id
  force_destroy = true
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Configure lifecycle to manage old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Upload function source code to Storage bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Deploy Cloud Function for performance optimization
resource "google_cloudfunctions_function" "performance_optimizer" {
  name        = local.function_name
  description = "Intelligent performance optimization function that processes monitoring alerts"
  runtime     = var.function_runtime
  region      = var.region
  project     = var.project_id
  
  # Function configuration
  available_memory_mb   = var.function_memory_mb
  timeout               = var.function_timeout_seconds
  entry_point          = "performance_optimizer"
  service_account_email = google_service_account.function_sa.email
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Event trigger configuration
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.performance_alerts.name
    
    # Configure retry policy for failed executions
    failure_policy {
      retry = true
    }
  }
  
  # Environment variables for function
  environment_variables = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    ALERT_THRESHOLD     = tostring(var.alert_threshold_seconds)
    FUNCTION_REGION     = var.region
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_project_iam_member.function_sa_roles
  ]
}

# Create notification channel for Pub/Sub integration
resource "google_monitoring_notification_channel" "pubsub_channel" {
  display_name = "Performance Alert Pub/Sub Channel"
  description  = "Notification channel for automated performance monitoring alerts"
  type         = "pubsub"
  project      = var.project_id
  
  labels = {
    topic = google_pubsub_topic.performance_alerts.id
  }
  
  # Enable the notification channel
  enabled = true
}

# Create alert policy for high API response times
resource "google_monitoring_alert_policy" "high_response_time" {
  display_name = "High API Response Time Alert - ${var.environment}"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  documentation {
    content   = "API response time has exceeded ${var.alert_threshold_seconds} seconds. Automated performance optimization has been triggered."
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "API Response Time Condition"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/api/response_time\" resource.type=\"global\""
      duration        = var.alert_duration
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_threshold_seconds
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
      
      # Configure trigger conditions
      trigger {
        count = 1
      }
    }
  }
  
  # Configure alert strategy
  alert_strategy {
    auto_close = "1800s" # Auto-close after 30 minutes
  }
  
  # Connect to Pub/Sub notification channel
  notification_channels = [
    google_monitoring_notification_channel.pubsub_channel.name
  ]
  
  depends_on = [google_project_service.apis]
}

# Create custom monitoring dashboard
resource "google_monitoring_dashboard" "performance_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Intelligent Performance Monitoring Dashboard - ${var.environment}"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "API Response Time"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"custom.googleapis.com/api/response_time\" resource.type=\"global\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Response Time (seconds)"
                scale = "LINEAR"
              }
              timeshiftDuration = "0s"
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Executions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"cloudfunctions.googleapis.com/function/executions\" resource.label.function_name=\"${local.function_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
              yAxis = {
                label = "Executions per second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Compute Instance CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.label.instance_name=\"${local.instance_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "CPU Utilization"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  project = var.project_id
  
  depends_on = [google_project_service.apis]
}