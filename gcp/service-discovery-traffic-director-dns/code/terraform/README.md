# Service Discovery with Traffic Director and Cloud DNS - Terraform

This Terraform configuration deploys a comprehensive service discovery solution using Google Cloud Traffic Director and Cloud DNS. The infrastructure provides intelligent load balancing, automatic health checking, and seamless service discovery across multiple zones.

## Architecture Overview

The solution implements:
- **VPC Network**: Custom VPC with subnet for service mesh communication
- **Service Instances**: Compute Engine instances deployed across multiple zones (us-central1-a, us-central1-b, us-central1-c)
- **Network Endpoint Groups (NEGs)**: Granular endpoint management for Traffic Director
- **Traffic Director**: Global control plane for intelligent load balancing and traffic routing
- **Cloud DNS**: Private and optional public DNS zones for service discovery
- **Health Checks**: Continuous monitoring of service health across all endpoints
- **Firewall Rules**: Security configuration for service mesh communication

## Prerequisites

1. **Google Cloud SDK**: Install and configure `gcloud` CLI
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Initialize and authenticate
   gcloud init
   gcloud auth application-default login
   ```

2. **Terraform**: Version 1.5.0 or later
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Google Cloud Project**: With appropriate APIs enabled
   ```bash
   # Create project (optional)
   gcloud projects create your-project-id
   
   # Set project
   gcloud config set project your-project-id
   
   # Enable required APIs
   gcloud services enable compute.googleapis.com
   gcloud services enable dns.googleapis.com
   gcloud services enable trafficdirector.googleapis.com
   ```

4. **Required Permissions**:
   - Compute Admin
   - DNS Administrator
   - Service Management Admin
   - Project IAM Admin (for service accounts)

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd gcp/service-discovery-traffic-director-dns/code/terraform/
```

### 2. Configure Variables
Create a `terraform.tfvars` file:
```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
service_name          = "myservice"
dns_zone_name        = "discovery-zone"
base_domain          = "example.com"
environment          = "prod"
machine_type         = "e2-medium"
instances_per_zone   = 2
create_public_dns    = false
create_test_client   = true
assign_external_ip   = false
enable_ssh           = true
```

### 3. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Verify Deployment
```bash
# Get service information
terraform output configuration_summary

# Test service discovery
terraform output connection_instructions
```

## Configuration Options

### Network Configuration
```hcl
# VPC and subnet settings
subnet_cidr = "10.0.0.0/24"
service_vip = "10.0.1.100"

# Security settings
enable_ssh         = true
ssh_source_ranges  = ["0.0.0.0/0"]  # Restrict in production
assign_external_ip = false          # Security best practice
```

### Service Configuration
```hcl
# Instance settings
machine_type       = "e2-medium"     # Adjust based on requirements
instances_per_zone = 2               # High availability
disk_size_gb      = 20              # Sufficient for basic services

# DNS settings
base_domain       = "example.com"    # Your domain
dns_ttl          = 300              # DNS record TTL
health_dns_ttl   = 60               # Health check DNS TTL
create_public_dns = false           # Enable for external access
```

### Traffic Director Configuration
```hcl
# Load balancing policy
locality_lb_policy = "ROUND_ROBIN"  # Options: ROUND_ROBIN, LEAST_REQUEST, etc.

# Health check settings
health_check_timeout           = 5   # Seconds
health_check_interval          = 10  # Seconds
health_check_healthy_threshold = 2   # Consecutive successful checks
health_check_unhealthy_threshold = 3 # Consecutive failed checks

# Circuit breaker settings
max_requests_per_connection = 1000
max_connections            = 1000
max_pending_requests       = 100
max_retries               = 3

# Outlier detection
consecutive_errors         = 3       # Errors before ejection
outlier_detection_interval = 30      # Detection interval (seconds)
base_ejection_time        = 30       # Base ejection time (seconds)
max_ejection_percent      = 50       # Max percentage to eject
min_health_percent        = 50       # Minimum healthy percentage
```

## Deployment Scenarios

### Development Environment
```hcl
# terraform.tfvars for development
project_id         = "dev-project-123"
environment        = "dev"
machine_type       = "e2-micro"
instances_per_zone = 1
create_test_client = true
enable_ssh         = true
assign_external_ip = true
```

### Production Environment
```hcl
# terraform.tfvars for production
project_id                = "prod-project-456"
environment              = "prod"
machine_type             = "e2-standard-4"
instances_per_zone       = 3
create_test_client       = false
enable_ssh               = false
assign_external_ip       = false
ssh_source_ranges        = ["10.0.0.0/8"]
health_check_interval    = 5
max_rate_per_endpoint    = 500
```

### Multi-Region Setup
For multi-region deployment, create separate Terraform configurations:
```bash
# Primary region
cd terraform-us-central1/
terraform apply -var="region=us-central1"

# Secondary region
cd terraform-us-west1/
terraform apply -var="region=us-west1"
```

## Testing and Validation

### 1. DNS Resolution Test
```bash
# From test client or any instance in the VPC
nslookup $(terraform output -raw domain_name)
```

### 2. Service Connectivity Test
```bash
# Test service response
SERVICE_DOMAIN=$(terraform output -raw domain_name)
curl -s http://$SERVICE_DOMAIN/ | jq .

# Test health endpoint
curl -s http://$SERVICE_DOMAIN/health | jq .
```

### 3. Load Balancing Verification
```bash
# Test distribution across instances
for i in {1..10}; do
  curl -s http://$(terraform output -raw domain_name)/ | jq -r '.zone + " - " + .instance'
done
```

### 4. Failover Testing
```bash
# Stop an instance to test failover
gcloud compute instances stop INSTANCE_NAME --zone=ZONE

# Verify traffic routes to healthy instances
curl -s http://$(terraform output -raw domain_name)/ | jq .
```

### 5. Health Check Monitoring
```bash
# Check backend service health
gcloud compute backend-services get-health \
  $(terraform output -raw backend_service_name) --global
```

## Monitoring and Observability

### Google Cloud Console URLs
Access monitoring dashboards using the output URLs:
```bash
# Get all management URLs
terraform output management_urls
```

### Key Metrics to Monitor
- **Backend Service Health**: Healthy vs. unhealthy endpoints
- **Request Rate**: Requests per second per endpoint
- **Latency**: Response times across zones
- **Error Rate**: HTTP 4xx and 5xx responses
- **Instance Health**: Compute Engine instance status

### Logs and Debugging
```bash
# View startup script logs
gcloud compute ssh INSTANCE_NAME --zone=ZONE \
  --command="sudo tail -f /var/log/startup-script.log"

# Check nginx access logs
gcloud compute ssh INSTANCE_NAME --zone=ZONE \
  --command="sudo tail -f /var/log/nginx/access.log"

# View health monitoring logs
gcloud compute ssh INSTANCE_NAME --zone=ZONE \
  --command="sudo tail -f /var/log/health-monitor.log"
```

## Advanced Features

### Custom Health Checks
Modify the startup script template to implement custom health checks:
```bash
# Edit templates/startup.sh.tpl
# Add custom health check logic in the /health endpoint
```

### Traffic Splitting
Implement canary deployments by modifying the URL map:
```hcl
# Add to main.tf for traffic splitting
resource "google_compute_url_map" "canary_url_map" {
  # Configure weighted traffic routing
}
```

### Service Mesh Integration
Enable Envoy proxy for advanced service mesh features:
```hcl
# The startup script includes basic Envoy configuration
# Customize /etc/envoy/envoy.yaml for specific requirements
```

## Troubleshooting

### Common Issues

1. **Health Checks Failing**
   ```bash
   # Check firewall rules
   gcloud compute firewall-rules list --filter="name~health-check"
   
   # Verify nginx status
   gcloud compute ssh INSTANCE_NAME --zone=ZONE \
     --command="sudo systemctl status nginx"
   ```

2. **DNS Resolution Issues**
   ```bash
   # Check DNS zone configuration
   gcloud dns managed-zones describe ZONE_NAME
   
   # Verify DNS records
   gcloud dns record-sets list --zone=ZONE_NAME
   ```

3. **Traffic Director Not Routing**
   ```bash
   # Check backend service configuration
   gcloud compute backend-services describe BACKEND_SERVICE_NAME --global
   
   # Verify NEG endpoints
   gcloud compute network-endpoint-groups list-network-endpoints NEG_NAME --zone=ZONE
   ```

4. **Instance Startup Issues**
   ```bash
   # Check startup script execution
   gcloud compute ssh INSTANCE_NAME --zone=ZONE \
     --command="sudo journalctl -u google-startup-scripts.service"
   ```

### Performance Tuning

1. **Optimize Health Check Frequency**
   ```hcl
   health_check_interval = 5  # Reduce for faster failover
   ```

2. **Adjust Circuit Breaker Thresholds**
   ```hcl
   consecutive_errors = 2     # More sensitive failure detection
   max_ejection_percent = 30  # Conservative ejection policy
   ```

3. **Scale Instance Count**
   ```hcl
   instances_per_zone = 4     # Higher availability
   ```

## Cleanup

### Destroy Infrastructure
```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Verify cleanup
gcloud compute instances list
gcloud dns managed-zones list
```

### Selective Cleanup
```bash
# Remove specific resources
terraform destroy -target=google_compute_instance.test_client

# Clean up DNS records only
terraform destroy -target=google_dns_record_set.service_a_record
```

## Cost Optimization

### Estimated Monthly Costs (USD)
- **Compute Instances**: ~$20/instance/month (e2-medium)
- **Load Balancer**: ~$18/month
- **DNS Zones**: ~$0.50/month per zone
- **Data Transfer**: Variable based on usage

### Cost Reduction Strategies
1. **Use Preemptible Instances**: 60-90% cost reduction
   ```hcl
   scheduling {
     preemptible = true
   }
   ```

2. **Right-size Instances**: Use e2-micro for development
   ```hcl
   machine_type = "e2-micro"  # $5/month per instance
   ```

3. **Optimize Instance Count**: Balance cost vs. availability
   ```hcl
   instances_per_zone = 1  # Minimum for testing
   ```

## Security Best Practices

1. **Network Security**
   - Disable external IPs for production instances
   - Restrict SSH access to specific IP ranges
   - Use Identity-Aware Proxy for secure access

2. **Service Security**
   - Enable HTTPS with SSL certificates
   - Implement authentication and authorization
   - Regular security updates via startup scripts

3. **Access Control**
   - Use least privilege IAM roles
   - Enable audit logging
   - Implement network segmentation

## Support and Resources

- **Google Cloud Documentation**: [Traffic Director](https://cloud.google.com/traffic-director/docs)
- **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Cloud DNS**: [Best Practices](https://cloud.google.com/dns/docs/best-practices)
- **Service Mesh**: [Concepts](https://cloud.google.com/service-mesh/docs/overview)

For issues with this Terraform configuration, review the original recipe documentation or consult the Google Cloud documentation for specific services.