# Energy-Efficient Web Hosting with C4A and Hyperdisk
# This Terraform configuration deploys ARM-based C4A instances with Axion processors
# and high-performance Hyperdisk storage for sustainable web hosting

# Generate random suffix for resource naming to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention with random suffix
  name_prefix = "${var.environment}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    recipe      = "energy-efficient-web-hosting-c4a-hyperdisk"
    created_at  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs for the project
resource "google_project_service" "compute_api" {
  service = "compute.googleapis.com"
  
  disable_dependent_services = true
}

resource "google_project_service" "monitoring_api" {
  service = "monitoring.googleapis.com"
  
  disable_dependent_services = true
}

resource "google_project_service" "logging_api" {
  service = "logging.googleapis.com"
  
  disable_dependent_services = true
}

# Create VPC network for secure communication between resources
resource "google_compute_network" "energy_web_vpc" {
  name                    = "energy-web-vpc-${random_id.suffix.hex}"
  description             = "VPC network for energy-efficient web hosting with C4A instances"
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.compute_api]
}

# Create subnet within the VPC for web server instances
resource "google_compute_subnetwork" "energy_web_subnet" {
  name          = "energy-web-subnet-${random_id.suffix.hex}"
  description   = "Subnet for C4A instances with Axion processors"
  ip_cidr_range = var.vpc_cidr
  region        = var.region
  network       = google_compute_network.energy_web_vpc.id
}

# Firewall rule to allow HTTP traffic on port 80
resource "google_compute_firewall" "allow_http" {
  name        = "allow-http-${random_id.suffix.hex}"
  description = "Allow HTTP traffic on port 80 for web servers"
  network     = google_compute_network.energy_web_vpc.name
  direction   = "INGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

# Firewall rule to allow HTTPS traffic on port 443
resource "google_compute_firewall" "allow_https" {
  name        = "allow-https-${random_id.suffix.hex}"
  description = "Allow HTTPS traffic on port 443 for secure web access"
  network     = google_compute_network.energy_web_vpc.name
  direction   = "INGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

# Firewall rule to allow health check traffic from Google Cloud Load Balancer
resource "google_compute_firewall" "allow_health_checks" {
  name        = "allow-health-checks-${random_id.suffix.hex}"
  description = "Allow health check traffic from Google Cloud Load Balancer"
  network     = google_compute_network.energy_web_vpc.name
  direction   = "INGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  
  # Google Cloud Load Balancer health check source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web-server"]
}

# Create Hyperdisk Balanced volumes for high-performance storage
resource "google_compute_disk" "web_data_disks" {
  count = var.instance_count
  
  name = "web-data-disk-${count.index + 1}-${random_id.suffix.hex}"
  type = "hyperdisk-balanced"
  zone = var.zone
  size = var.disk_size_gb
  
  # Hyperdisk performance provisioning for energy-efficient I/O
  provisioned_iops       = var.disk_provisioned_iops
  provisioned_throughput = var.disk_provisioned_throughput
  
  labels = local.common_labels
  
  depends_on = [google_project_service.compute_api]
}

# Startup script for installing and configuring nginx web server
locals {
  startup_script = base64encode(templatefile("${path.module}/startup-script.sh", {
    hostname_placeholder = "HOSTNAME_PLACEHOLDER"
  }))
}

# Create C4A instances with Axion processors for energy-efficient web hosting
resource "google_compute_instance" "web_servers" {
  count = var.instance_count
  
  name         = "web-server-${count.index + 1}-${random_id.suffix.hex}"
  description  = "C4A instance ${count.index + 1} with Axion processor for energy-efficient web hosting"
  machine_type = var.machine_type
  zone         = var.zone
  
  # Enable migration for maintenance events
  scheduling {
    on_host_maintenance = "MIGRATE"
  }
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "${var.web_server_image_project}/${var.web_server_image_family}"
      size  = 20
      type  = "pd-balanced"
    }
  }
  
  # Attach Hyperdisk for additional storage
  attached_disk {
    source      = google_compute_disk.web_data_disks[count.index].id
    device_name = "data-disk"
  }
  
  # Network configuration
  network_interface {
    network    = google_compute_network.energy_web_vpc.id
    subnetwork = google_compute_subnetwork.energy_web_subnet.id
    
    # Assign external IP for internet access
    access_config {
      # Ephemeral external IP
    }
  }
  
  # Security and identification tags
  tags = ["web-server"]
  
  # Startup script for web server configuration
  metadata = {
    startup-script = base64decode(local.startup_script)
  }
  
  # Service account with monitoring permissions
  service_account {
    scopes = [
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/logging.write"
    ]
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_compute_disk.web_data_disks,
    google_project_service.compute_api
  ]
}

# Create unmanaged instance group for load balancing
resource "google_compute_instance_group" "web_instance_group" {
  name        = "web-instance-group-${random_id.suffix.hex}"
  description = "Instance group for energy-efficient web servers with C4A instances"
  zone        = var.zone
  
  # Add all web server instances to the group
  instances = google_compute_instance.web_servers[*].id
}

# Create HTTP health check for load balancer monitoring
resource "google_compute_health_check" "web_health_check" {
  name        = "web-health-check-${random_id.suffix.hex}"
  description = "Health check for C4A web server instances"
  
  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold
  
  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# Create backend service for load balancer
resource "google_compute_backend_service" "web_backend_service" {
  name        = "web-backend-service-${random_id.suffix.hex}"
  description = "Backend service for energy-efficient web hosting with C4A instances"
  protocol    = "HTTP"
  
  # Associate health check
  health_checks = [google_compute_health_check.web_health_check.id]
  
  # Add instance group as backend
  backend {
    group = google_compute_instance_group.web_instance_group.id
  }
  
  # Load balancing configuration for optimal energy efficiency
  load_balancing_scheme = "EXTERNAL"
}

# Create URL map for request routing
resource "google_compute_url_map" "web_url_map" {
  name            = "web-url-map-${random_id.suffix.hex}"
  description     = "URL map for energy-efficient web hosting load balancer"
  default_service = google_compute_backend_service.web_backend_service.id
}

# Create HTTP proxy for the load balancer
resource "google_compute_target_http_proxy" "web_http_proxy" {
  name    = "web-http-proxy-${random_id.suffix.hex}"
  url_map = google_compute_url_map.web_url_map.id
}

# Create global forwarding rule (load balancer frontend)
resource "google_compute_global_forwarding_rule" "web_forwarding_rule" {
  name       = "web-forwarding-rule-${random_id.suffix.hex}"
  target     = google_compute_target_http_proxy.web_http_proxy.id
  port_range = "80"
}

# Create Cloud Monitoring dashboard for energy efficiency tracking
resource "google_monitoring_dashboard" "energy_efficiency_dashboard" {
  count = var.enable_monitoring_dashboard ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Energy-Efficient Web Hosting Dashboard - ${local.name_prefix}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "C4A Instance CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_name=~\"web-server-.*-${random_id.suffix.hex}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields      = ["resource.labels.instance_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "CPU Utilization (%)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Hyperdisk Performance Metrics"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_disk\" AND metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\" AND resource.labels.disk_name=~\"web-data-disk-.*-${random_id.suffix.hex}\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Read Ops/sec"
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
            title = "Load Balancer Request Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"http_load_balancer\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.monitoring_api]
}

# Create startup script file
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = <<-EOF
#!/bin/bash
# Startup script for C4A instances with energy-efficient web server configuration

# Update system packages
apt-get update
apt-get install -y nginx htop fio curl

# Create energy-efficient web page showcasing C4A capabilities
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Energy-Efficient Web Hosting</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background: #f5f5f5; 
            line-height: 1.6;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: white; 
            padding: 30px; 
            border-radius: 8px; 
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .eco-badge { 
            background: #34A853; 
            color: white; 
            padding: 5px 10px; 
            border-radius: 20px; 
            font-size: 12px; 
            display: inline-block;
            margin: 10px 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .info-card {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            border-left: 4px solid #34A853;
        }
        .info-card h3 {
            margin: 0 0 10px 0;
            color: #1a73e8;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 14px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌱 Energy-Efficient Web Hosting</h1>
        <span class="eco-badge">60% More Energy Efficient</span>
        
        <p>This website is powered by Google Cloud C4A instances with Axion processors and Hyperdisk storage, 
        delivering superior performance while reducing energy consumption and operational costs.</p>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>Server Information</h3>
                <strong>Hostname:</strong> $(hostname)<br>
                <strong>Timestamp:</strong> $(date)
            </div>
            
            <div class="info-card">
                <h3>Architecture</h3>
                <strong>Processor:</strong> ARM64 (Axion)<br>
                <strong>Instance Type:</strong> C4A
            </div>
            
            <div class="info-card">
                <h3>Storage</h3>
                <strong>Type:</strong> Hyperdisk Balanced<br>
                <strong>Performance:</strong> High IOPS & Throughput
            </div>
            
            <div class="info-card">
                <h3>Sustainability</h3>
                <strong>Energy Efficiency:</strong> 60% Better<br>
                <strong>Carbon Footprint:</strong> Reduced
            </div>
        </div>
        
        <h2>Benefits of C4A with Axion Processors</h2>
        <ul>
            <li><strong>Energy Efficiency:</strong> Up to 60% better energy efficiency compared to x86 instances</li>
            <li><strong>Performance:</strong> ARM Neoverse V2 architecture with advanced features</li>
            <li><strong>Cost Optimization:</strong> Up to 65% better price-performance ratio</li>
            <li><strong>Sustainability:</strong> Reduced carbon footprint for environmentally conscious computing</li>
            <li><strong>Reliability:</strong> Google's custom silicon designed for cloud workloads</li>
        </ul>
        
        <div class="footer">
            <p>Deployed with Terraform | Managed by Google Cloud | Powered by Renewable Energy</p>
        </div>
    </div>
</body>
</html>
HTML

# Enable and start nginx service
systemctl enable nginx
systemctl start nginx

# Create a simple health check endpoint
echo "OK" > /var/www/html/health

# Log successful startup
echo "$(date): C4A web server startup completed successfully" >> /var/log/startup.log
EOF
}