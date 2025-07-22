# Infrastructure as Code for Accelerating Gaming Backend Performance with Cloud Memorystore and Cloud CDN

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Accelerating Gaming Backend Performance with Cloud Memorystore and Cloud CDN".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for the following services:
  - Compute Engine (Admin)
  - Cloud Memorystore for Redis (Admin)
  - Cloud Storage (Admin)
  - Cloud CDN (Admin)
  - Cloud Load Balancing (Admin)
  - Service Account (Admin)
- For Terraform: Terraform CLI installed (>= 1.0)
- For Infrastructure Manager: Google Cloud Project with Infrastructure Manager API enabled

## Cost Considerations

This infrastructure will incur charges for:
- Cloud Memorystore Redis instance (~$50-80/month for standard_ha tier)
- Compute Engine instances (~$20-40/month for n2-standard-2)
- Cloud Storage and CDN usage (variable based on traffic)
- Load balancing resources (~$5-10/month)

Estimated total cost: $75-130/month for testing and development.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended native IaC service that provides state management and drift detection.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply gaming-backend-deployment \
    --location=${REGION} \
    --gcs-source="gs://your-bucket/infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe gaming-backend-deployment \
    --location=${REGION}
```

### Using Terraform

Terraform provides a consistent workflow for infrastructure management across multiple cloud providers.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init

# Review the execution plan
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply the infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# View outputs (IPs, URLs, connection details)
terraform output
```

### Using Bash Scripts

The bash scripts provide a quick deployment option using gcloud CLI commands.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy the infrastructure
./deploy.sh

# The script will output connection details and verification commands
```

## Configuration Options

### Infrastructure Manager Variables

Customize your deployment by modifying the input values:

- `project_id`: Your Google Cloud Project ID
- `region`: Primary region for resources (default: us-central1)
- `zone`: Compute zone for instances (default: us-central1-a)
- `redis_memory_size_gb`: Redis instance memory in GB (default: 1)
- `game_server_machine_type`: Compute instance type (default: n2-standard-2)
- `enable_high_availability`: Enable Redis HA mode (default: true)

### Terraform Variables

Edit `terraform/terraform.tfvars` or use command-line variables:

```hcl
# terraform.tfvars example
project_id = "my-gaming-project"
region = "us-central1"
zone = "us-central1-a"
redis_memory_size_gb = 2
game_server_machine_type = "n2-standard-4"
enable_high_availability = true
bucket_name_suffix = "prod"
```

### Bash Script Configuration

Modify environment variables in the script or export them before execution:

```bash
# Environment variables for bash deployment
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export REDIS_MEMORY_SIZE="2"
export MACHINE_TYPE="n2-standard-4"
```

## Post-Deployment Setup

After infrastructure deployment, complete these additional steps:

### 1. Configure Redis Connection

```bash
# Get Redis connection details
REDIS_HOST=$(gcloud redis instances describe gaming-redis-cluster \
    --region=${REGION} --format="value(host)")

# Test Redis connectivity from game server
gcloud compute ssh game-server --zone=${ZONE} --command="
    redis-cli -h ${REDIS_HOST} ping
"
```

### 2. Upload Game Assets

```bash
# Upload sample assets to Cloud Storage
gsutil cp local-assets/* gs://gaming-assets-bucket/assets/

# Set appropriate cache headers
gsutil -m setmeta -h "Cache-Control:public, max-age=86400" \
    gs://gaming-assets-bucket/configs/**

gsutil -m setmeta -h "Cache-Control:public, max-age=604800" \
    gs://gaming-assets-bucket/assets/**
```

### 3. Verify CDN Configuration

```bash
# Get load balancer IP
FRONTEND_IP=$(gcloud compute addresses describe game-frontend-ip \
    --global --format="value(address)")

# Test CDN asset delivery
curl -I "http://${FRONTEND_IP}/assets/sample-texture.png"
```

## Monitoring and Observability

### Redis Performance Monitoring

```bash
# Monitor Redis performance metrics
gcloud redis instances describe gaming-redis-cluster \
    --region=${REGION} \
    --format="yaml(memorySizeGb,currentLocationId,state)"

# Check Redis memory usage
gcloud compute ssh game-server --zone=${ZONE} --command="
    redis-cli -h ${REDIS_HOST} info memory
"
```

### CDN Cache Performance

```bash
# View CDN cache statistics
gcloud compute backend-buckets describe game-assets-backend \
    --format="yaml(cdnPolicy)"

# Monitor cache hit ratios in Cloud Monitoring
gcloud logging read "resource.type=gce_backend_service" \
    --limit=10 --format="table(timestamp,httpRequest.requestUrl,httpRequest.cacheHit)"
```

### Load Balancer Health

```bash
# Check backend service health
gcloud compute backend-services get-health game-backend-service \
    --global \
    --format="table(status,healthStatus[].instance,healthStatus[].healthState)"
```

## Troubleshooting

### Common Issues

1. **Redis Connection Timeouts**
   ```bash
   # Check firewall rules for Redis port
   gcloud compute firewall-rules list --filter="name~redis"
   
   # Verify VPC connectivity
   gcloud compute networks subnets describe default --region=${REGION}
   ```

2. **CDN Cache Miss Issues**
   ```bash
   # Invalidate CDN cache
   gcloud compute url-maps invalidate-cdn-cache game-backend-map \
       --path="/assets/*" \
       --async
   ```

3. **Load Balancer 502 Errors**
   ```bash
   # Check instance group health
   gcloud compute instance-groups managed describe game-server-group \
       --zone=${ZONE}
   
   # Verify health check configuration
   gcloud compute health-checks describe game-server-health
   ```

### Debug Commands

```bash
# Enable debug logging for gcloud commands
export CLOUDSDK_CORE_LOG_LEVEL=debug

# Check API quotas and limits
gcloud compute project-info describe \
    --format="yaml(quotas)"

# View detailed resource states
gcloud compute operations list --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment (this removes all resources)
gcloud infra-manager deployments delete gaming-backend-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion completed
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Plan the destruction
terraform plan -destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Destroy all resources
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -auto-approve

# Clean up Terraform state
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run the cleanup script
./destroy.sh

# Verify all resources are deleted
gcloud redis instances list --region=${REGION}
gcloud compute instances list --zones=${ZONE}
gcloud compute addresses list --global
```

### Manual Cleanup Verification

```bash
# Double-check that expensive resources are deleted
echo "Verifying Redis instances..."
gcloud redis instances list --regions=${REGION}

echo "Verifying Compute instances..."
gcloud compute instances list --zones=${ZONE}

echo "Verifying Load Balancer components..."
gcloud compute forwarding-rules list --global
gcloud compute backend-services list --global

echo "Verifying Storage buckets..."
gsutil ls -p ${PROJECT_ID}
```

## Performance Optimization

### Redis Configuration Tuning

```bash
# Optimize Redis for gaming workloads
gcloud redis instances patch gaming-redis-cluster \
    --region=${REGION} \
    --redis-config="maxmemory-policy=allkeys-lru,timeout=300"
```

### CDN Cache Optimization

```bash
# Configure cache settings for different asset types
gcloud compute backend-buckets update game-assets-backend \
    --cache-mode=CACHE_ALL_STATIC \
    --default-ttl=86400 \
    --max-ttl=604800
```

### Auto-scaling Configuration

```bash
# Enable auto-scaling for game servers
gcloud compute instance-groups managed set-autoscaling game-server-group \
    --zone=${ZONE} \
    --max-num-replicas=10 \
    --min-num-replicas=1 \
    --target-cpu-utilization=0.7
```

## Security Best Practices

This infrastructure implements several security measures:

- **IAM**: Least-privilege service accounts for each component
- **Network Security**: VPC firewalls restrict access to necessary ports only
- **Data Encryption**: Redis AUTH enabled, HTTPS termination at load balancer
- **Access Control**: Private Redis instance, public assets served via CDN only

### Additional Security Hardening

```bash
# Enable VPC Flow Logs for network monitoring
gcloud compute networks subnets update default \
    --region=${REGION} \
    --enable-flow-logs

# Configure Cloud Armor for DDoS protection
gcloud compute security-policies create game-security-policy \
    --description="Gaming backend protection"

# Enable audit logging
gcloud logging sinks create game-audit-sink \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/security_logs \
    --log-filter="protoPayload.serviceName=compute.googleapis.com"
```

## Integration Examples

### Game Client Connection

```javascript
// Example game client Redis connection
const redis = require('redis');
const client = redis.createClient({
    host: 'REDIS_HOST_FROM_OUTPUT',
    password: 'REDIS_AUTH_FROM_OUTPUT',
    retry_unfulfilled_commands: true,
    retry_delay_on_cluster_down: 300,
    retry_delay_on_failover: 100
});

// Leaderboard operations
await client.zadd('global_leaderboard', score, playerId);
const topPlayers = await client.zrevrange('global_leaderboard', 0, 9, 'WITHSCORES');
```

### Asset Loading Example

```javascript
// Example game asset loading with CDN
const assetBaseUrl = 'https://FRONTEND_IP_FROM_OUTPUT/assets/';

async function loadGameAssets() {
    const assets = [
        'textures/player-sprite.png',
        'audio/background-music.mp3',
        'configs/level-data.json'
    ];
    
    return Promise.all(
        assets.map(asset => fetch(`${assetBaseUrl}${asset}`))
    );
}
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architectural context
2. Check Google Cloud documentation for service-specific guidance:
   - [Cloud Memorystore for Redis](https://cloud.google.com/memorystore/docs/redis)
   - [Cloud CDN](https://cloud.google.com/cdn/docs)
   - [Cloud Load Balancing](https://cloud.google.com/load-balancing/docs)
3. Use `gcloud feedback` to report CLI issues
4. For Terraform issues, consult the [Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development project first
2. Update variable descriptions and defaults appropriately
3. Maintain backward compatibility where possible
4. Update this README with any new configuration options
5. Verify cleanup procedures still work correctly