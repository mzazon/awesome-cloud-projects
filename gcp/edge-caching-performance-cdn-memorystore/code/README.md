# Infrastructure as Code for Edge Caching Performance with Cloud CDN and Memorystore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Edge Caching Performance with Cloud CDN and Memorystore".

## Overview

This recipe deploys an intelligent edge caching system using Google Cloud CDN for global content distribution and Memorystore for Redis as a high-performance cache layer. The solution implements dynamic cache policies, geographic data distribution strategies, and real-time cache invalidation workflows.

## Architecture

The solution deploys the following components:

- **Cloud CDN**: Global content delivery network with 200+ edge locations
- **Memorystore for Redis**: Fully managed Redis cache with high availability
- **Cloud Load Balancing**: Global load balancer with intelligent traffic routing
- **Cloud Storage**: Origin storage for static content
- **VPC Network**: Isolated network infrastructure for secure communication
- **Cloud Monitoring**: Performance monitoring and alerting

## Available Implementations

- **Infrastructure Manager**: Google Cloud's recommended IaC solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Bash Scripts**: Deployment and cleanup automation scripts

## Prerequisites

### General Requirements
- Google Cloud account with billing enabled
- Project with appropriate APIs enabled:
  - Compute Engine API
  - Cloud CDN API
  - Memorystore for Redis API
  - Cloud Storage API
  - Cloud DNS API
  - Cloud Monitoring API
  - Cloud Logging API
- IAM permissions for:
  - Compute Admin
  - Storage Admin
  - Redis Admin
  - Monitoring Admin
  - Logging Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Infrastructure Manager API enabled in your project

#### Terraform
- Terraform installed (version 1.0 or later)
- Google Cloud CLI installed and configured
- Application Default Credentials configured

#### Bash Scripts
- Google Cloud CLI installed and configured
- Bash shell (Linux/macOS) or WSL (Windows)
- `curl` and `openssl` utilities

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="edge-caching-deployment"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME} \
    --service-account projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source infrastructure-manager/ \
    --inputs-file infrastructure-manager/inputs.yaml
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Set executable permissions
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration

### Infrastructure Manager

Edit `infrastructure-manager/inputs.yaml` to customize your deployment:

```yaml
# Core configuration
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"

# Redis configuration
redis_memory_size_gb: 5
redis_version: "REDIS_6_X"

# CDN configuration
cache_mode: "CACHE_ALL_STATIC"
default_ttl: 3600
max_ttl: 86400

# Network configuration
network_name: "cdn-network"
subnet_name: "cdn-subnet"
subnet_cidr: "10.0.0.0/24"
```

### Terraform

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
# Core configuration
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Redis configuration
redis_memory_size_gb = 5
redis_version        = "REDIS_6_X"

# CDN configuration
cache_mode   = "CACHE_ALL_STATIC"
default_ttl  = 3600
max_ttl      = 86400

# Network configuration
network_name   = "cdn-network"
subnet_name    = "cdn-subnet"
subnet_cidr    = "10.0.0.0/24"
```

### Environment Variables

The bash scripts use the following environment variables:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export REDIS_MEMORY_SIZE="5"
export CACHE_DEFAULT_TTL="3600"
export CACHE_MAX_TTL="86400"
export NETWORK_CIDR="10.0.0.0/24"
```

## Deployment Details

### What Gets Deployed

1. **Network Infrastructure**
   - VPC network with custom subnet
   - Firewall rules for secure communication
   - Static IP address reservation

2. **Caching Infrastructure**
   - Memorystore for Redis instance with high availability
   - Cloud CDN with global distribution
   - Cloud Load Balancer with backend services

3. **Storage and Content**
   - Cloud Storage bucket for origin content
   - Sample content for testing
   - Health checks for backend services

4. **Monitoring and Logging**
   - Cloud Monitoring dashboards
   - Alerting policies for performance metrics
   - Logging configuration for debugging

### Expected Costs

**Monthly estimates (may vary by region and usage):**
- Memorystore for Redis (5GB): ~$35-45
- Cloud CDN (100GB transfer): ~$8-12
- Cloud Load Balancer: ~$18-25
- Cloud Storage (10GB): ~$0.20-0.30
- Networking (VPC): ~$0-5
- **Total estimated cost: $60-85/month**

> **Note**: Actual costs depend on traffic volume, cache hit ratios, and geographic distribution. Monitor costs through Cloud Billing console.

## Validation

After deployment, verify your infrastructure:

### Check Redis Instance
```bash
# Get Redis instance details
gcloud redis instances describe intelligent-cache-${RANDOM_SUFFIX} \
    --region ${REGION}

# Test Redis connectivity (from a VM in the same VPC)
redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} ping
```

### Test CDN Performance
```bash
# Get CDN endpoint IP
CDN_IP=$(gcloud compute addresses describe cdn-ip-address \
    --global --format="value(address)")

# Test cache miss (first request)
time curl -I https://${CDN_IP}/index.html

# Test cache hit (subsequent request)
time curl -I https://${CDN_IP}/index.html
```

### Verify Monitoring
```bash
# Check monitoring dashboard
gcloud monitoring dashboards list --format="table(displayName,name)"

# View cache performance metrics
gcloud monitoring metrics list --filter="metric.type:cdn"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Remove state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable compute.googleapis.com redis.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Redis Connection Issues**
   - Verify VPC network connectivity
   - Check firewall rules
   - Ensure Redis instance is in READY state

4. **CDN Cache Issues**
   - Check backend service health
   - Verify cache headers in responses
   - Review cache invalidation policies

### Debug Commands

```bash
# Check deployment status
gcloud deployments describe ${DEPLOYMENT_NAME}

# View logs
gcloud logging read "resource.type=gce_instance" --limit 50

# Check resource health
gcloud compute backend-services get-health ${BACKEND_SERVICE_NAME} --global
```

## Performance Optimization

### Cache Tuning

1. **TTL Optimization**
   - Static content: 24-48 hours
   - Dynamic content: 5-15 minutes
   - API responses: 1-5 minutes

2. **Cache Key Strategy**
   - Include relevant headers
   - Normalize query parameters
   - Handle user-specific content

3. **Invalidation Patterns**
   - Use tag-based invalidation
   - Implement time-based refresh
   - Monitor cache hit ratios

### Redis Optimization

1. **Memory Management**
   - Use appropriate eviction policies
   - Monitor memory usage
   - Implement key expiration

2. **Connection Pooling**
   - Optimize connection limits
   - Use connection pooling
   - Monitor connection metrics

## Security Considerations

### Network Security
- VPC networks provide isolation
- Firewall rules restrict access
- Private IP addresses used internally

### Access Control
- IAM roles follow least privilege
- Service accounts for automation
- API keys secured in Secret Manager

### Data Protection
- Encryption at rest and in transit
- SSL/TLS termination at load balancer
- Redis AUTH enabled

## Monitoring and Alerting

### Key Metrics

1. **Cache Performance**
   - Cache hit ratio (target: >90%)
   - Origin response time
   - Edge response time

2. **Redis Metrics**
   - Memory utilization
   - Connection count
   - Command latency

3. **Network Metrics**
   - Bandwidth utilization
   - Request volume
   - Error rates

### Alerting Policies

Set up alerts for:
- Cache hit ratio below 85%
- Redis memory usage above 80%
- Backend service health failures
- High error rates (>5%)

## Best Practices

1. **Regular Monitoring**
   - Review performance metrics weekly
   - Adjust TTL values based on usage
   - Monitor cost trends

2. **Content Strategy**
   - Optimize cacheable content
   - Use appropriate cache headers
   - Implement smart invalidation

3. **Scaling Considerations**
   - Monitor Redis memory usage
   - Plan for traffic growth
   - Consider multi-region deployment

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult Google Cloud documentation:
   - [Cloud CDN Documentation](https://cloud.google.com/cdn/docs)
   - [Memorystore for Redis Documentation](https://cloud.google.com/memorystore/docs/redis)
   - [Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)

## Contributing

To modify this infrastructure:

1. Update the appropriate IaC files
2. Test changes in a development environment
3. Validate with `terraform plan` or equivalent
4. Update documentation if needed
5. Test cleanup procedures

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to your organization's policies for production use.