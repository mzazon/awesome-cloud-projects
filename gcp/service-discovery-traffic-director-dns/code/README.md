# Infrastructure as Code for Service Discovery with Traffic Director and Cloud DNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Discovery with Traffic Director and Cloud DNS".

## Solution Overview

This implementation creates an intelligent service discovery system using Google Cloud Traffic Director as the global control plane for service mesh traffic management, integrated with Cloud DNS for service-aware resolution. The solution provides automated traffic routing, intelligent load balancing across multiple zones, and zero-downtime deployment capabilities through progressive traffic shifting.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated resource management

## Architecture Components

The infrastructure includes:
- **Cloud DNS**: Private and public DNS zones for service discovery
- **Traffic Director**: Global control plane for intelligent traffic management
- **Compute Engine**: Service instances distributed across multiple zones
- **Network Endpoint Groups (NEGs)**: Granular endpoint management for load balancing
- **Health Checks**: Continuous monitoring for automatic failover
- **Load Balancing**: Global HTTP(S) load balancer with intelligent routing
- **VPC Networking**: Secure networking foundation with custom subnets

## Prerequisites

### Required Tools
- Google Cloud SDK (gcloud CLI) installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- Bash shell environment (for script-based deployment)

### Required Permissions
Your Google Cloud account needs the following roles:
- `roles/compute.admin` - Compute Engine administration
- `roles/dns.admin` - Cloud DNS administration  
- `roles/trafficdirector.admin` - Traffic Director administration
- `roles/servicenetworking.admin` - Service networking administration
- `roles/iam.serviceAccountAdmin` - Service account management

### Prerequisites Setup
```bash
# Enable required APIs
gcloud services enable compute.googleapis.com \
    dns.googleapis.com \
    trafficdirector.googleapis.com \
    container.googleapis.com \
    servicenetworking.googleapis.com

# Set default project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
```

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment configuration
gcloud infra-manager deployments create service-discovery-deployment \
    --location=${REGION} \
    --gcs-source=gs://your-bucket/infrastructure-manager/main.yaml \
    --service-account=your-service-account@${PROJECT_ID}.iam.gserviceaccount.com

# Apply the deployment
gcloud infra-manager deployments apply service-discovery-deployment \
    --location=${REGION}

# Check deployment status
gcloud infra-manager deployments describe service-discovery-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud compute instances list --filter="name~service-discovery"
gcloud dns managed-zones list
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `zones` | List of zones for multi-zone deployment | `["us-central1-a", "us-central1-b", "us-central1-c"]` | No |
| `service_name` | Base name for service resources | `microservice` | No |
| `domain_name` | DNS domain for service discovery | `example.com` | No |
| `machine_type` | Compute Engine instance type | `e2-medium` | No |
| `health_check_interval` | Health check interval in seconds | `10` | No |

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region = "us-central1"
zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
service_name = "my-microservice"
domain_name = "my-service.example.com"
machine_type = "e2-medium"
```

### Infrastructure Manager Variables

Update the `variables` section in `infrastructure-manager/main.yaml`:

```yaml
variables:
  project_id:
    value: "your-project-id"
  region:
    value: "us-central1"
  service_name:
    value: "my-microservice"
  domain_name:
    value: "my-service.example.com"
```

## Validation & Testing

### Verify Deployment

```bash
# Check service instances
gcloud compute instances list --filter="labels.service=microservice"

# Verify DNS zones
gcloud dns managed-zones list

# Check Traffic Director configuration
gcloud compute backend-services describe microservice-backend --global

# Test health checks
gcloud compute backend-services get-health microservice-backend --global

# Verify NEG endpoints
gcloud compute network-endpoint-groups list-network-endpoints microservice-neg-us-central1-a \
    --zone=us-central1-a
```

### Test Service Discovery

```bash
# Create test client instance
gcloud compute instances create test-client \
    --zone=us-central1-a \
    --machine-type=e2-micro \
    --subnet=service-mesh-subnet \
    --image-family=debian-11 \
    --image-project=debian-cloud

# Test DNS resolution
gcloud compute ssh test-client --zone=us-central1-a --command="nslookup microservice.example.com"

# Test load balancing
for i in {1..10}; do
    gcloud compute ssh test-client --zone=us-central1-a \
        --command="curl -s http://microservice.example.com/ | jq -r '.zone + \" - \" + .instance'"
done
```

### Performance Testing

```bash
# Install Apache Bench on test client
gcloud compute ssh test-client --zone=us-central1-a --command="sudo apt-get update && sudo apt-get install -y apache2-utils"

# Run load test
gcloud compute ssh test-client --zone=us-central1-a \
    --command="ab -n 1000 -c 10 http://microservice.example.com/"
```

## Monitoring & Observability

### View Traffic Director Metrics

```bash
# Check backend service health
gcloud compute backend-services get-health microservice-backend --global

# View URL map configuration
gcloud compute url-maps describe microservice-url-map

# Check forwarding rule status
gcloud compute forwarding-rules describe microservice-forwarding-rule --global
```

### Cloud Monitoring Integration

The infrastructure automatically creates monitoring resources. Access dashboards through:
- Google Cloud Console > Monitoring > Dashboards
- Traffic Director metrics in Cloud Monitoring
- Custom dashboards for service performance

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete service-discovery-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud compute instances list --filter="labels.service=microservice"
gcloud dns managed-zones list --filter="name~discovery-zone"
```

### Manual Cleanup (if needed)

```bash
# Delete remaining DNS records
gcloud dns record-sets list --zone=discovery-zone --format="value(name,type)" | \
    while read name type; do
        if [[ "$type" != "NS" && "$type" != "SOA" ]]; then
            gcloud dns record-sets delete "$name" --zone=discovery-zone --type="$type" --quiet
        fi
    done

# Force delete DNS zones
gcloud dns managed-zones delete discovery-zone --quiet
gcloud dns managed-zones delete discovery-zone-public --quiet

# Delete any remaining compute resources
gcloud compute instances list --filter="labels.service=microservice" --format="value(name,zone)" | \
    while read name zone; do
        gcloud compute instances delete "$name" --zone="$zone" --quiet
    done
```

## Troubleshooting

### Common Issues

**Health Checks Failing**
```bash
# Check firewall rules
gcloud compute firewall-rules list --filter="name~health-check"

# Verify service endpoints
gcloud compute instances list --filter="labels.service=microservice"

# Check instance startup scripts
gcloud compute instances get-serial-port-output INSTANCE_NAME --zone=ZONE
```

**DNS Resolution Issues**
```bash
# Verify DNS zone configuration
gcloud dns managed-zones describe discovery-zone

# Check DNS records
gcloud dns record-sets list --zone=discovery-zone

# Test from different network
gcloud compute ssh test-client --command="dig microservice.example.com"
```

**Traffic Director Not Working**
```bash
# Check backend service configuration
gcloud compute backend-services describe microservice-backend --global

# Verify NEG endpoints
gcloud compute network-endpoint-groups list-network-endpoints microservice-neg-us-central1-a --zone=us-central1-a

# Check URL map rules
gcloud compute url-maps describe microservice-url-map
```

### Debug Commands

```bash
# Enable debug logging for gcloud
export CLOUDSDK_CORE_VERBOSITY=debug

# Check API enablement
gcloud services list --enabled --filter="name~(compute|dns|trafficdirector)"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" \
    --filter="bindings.members:user:$(gcloud config get-value account)"
```

## Cost Optimization

### Resource Costs

Estimated monthly costs (us-central1):
- Compute Engine instances (6x e2-medium): ~$120
- Cloud DNS (2 zones): ~$1
- Traffic Director configuration: ~$5
- Load balancing: ~$20
- **Total estimated cost: ~$146/month**

### Cost Reduction Tips

```bash
# Use preemptible instances for dev/test
gcloud compute instances create microservice-preemptible \
    --preemptible \
    --machine-type=e2-small

# Use smaller machine types
gcloud compute instance-templates create microservice-template-small \
    --machine-type=e2-small

# Delete unused DNS zones
gcloud dns managed-zones delete unused-zone
```

## Security Considerations

### Network Security

- All instances use private subnets with no external IPs
- Firewall rules restrict traffic to necessary ports only
- Health check traffic uses Google Cloud's secure ranges

### IAM Best Practices

- Service accounts use least privilege access
- Instance service accounts have minimal required permissions
- DNS zones are private by default for internal services

### SSL/TLS Configuration

```bash
# Create SSL certificate for HTTPS
gcloud compute ssl-certificates create microservice-ssl-cert \
    --domains=microservice.example.com

# Update load balancer to use HTTPS
gcloud compute target-https-proxies create microservice-https-proxy \
    --url-map=microservice-url-map \
    --ssl-certificates=microservice-ssl-cert
```

## Customization Examples

### Adding Additional Zones

```bash
# Add instances in new zone
export NEW_ZONE="us-central1-f"
gcloud compute instances create microservice-${NEW_ZONE}-1 \
    --source-instance-template=microservice-template \
    --zone=${NEW_ZONE}

# Create NEG for new zone
gcloud compute network-endpoint-groups create microservice-neg-${NEW_ZONE} \
    --network-endpoint-type=GCE_VM_IP_PORT \
    --zone=${NEW_ZONE} \
    --network=service-mesh-vpc \
    --subnet=service-mesh-subnet
```

### Implementing Canary Deployments

```bash
# Create canary backend service
gcloud compute backend-services create microservice-backend-canary \
    --global \
    --load-balancing-scheme=INTERNAL_SELF_MANAGED \
    --protocol=HTTP \
    --health-checks=microservice-health-check

# Update URL map for traffic splitting
gcloud compute url-maps add-path-matcher microservice-url-map \
    --path-matcher-name=canary-matcher \
    --default-service=microservice-backend \
    --path-rules="/v2/*=microservice-backend-canary"
```

### Multi-Region Deployment

```bash
# Create instances in different region
export REGION_2="us-west1"
gcloud compute instances create microservice-${REGION_2}-1 \
    --zone=${REGION_2}-a \
    --source-instance-template=microservice-template
```

## Advanced Features

### Traffic Splitting Configuration

The infrastructure supports advanced traffic management:
- Weighted traffic distribution
- Header-based routing
- Path-based routing
- Fault injection for testing

### Health Check Customization

```bash
# Create custom health check
gcloud compute health-checks create http microservice-custom-health \
    --port=8080 \
    --request-path="/api/health" \
    --check-interval=5s \
    --timeout=3s \
    --healthy-threshold=1 \
    --unhealthy-threshold=2
```

### Observability Integration

```bash
# Enable detailed monitoring
gcloud compute backend-services update microservice-backend \
    --global \
    --enable-logging \
    --logging-sample-rate=1.0
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult Google Cloud documentation:
   - [Traffic Director Documentation](https://cloud.google.com/traffic-director/docs)
   - [Cloud DNS Documentation](https://cloud.google.com/dns/docs)
   - [Compute Engine Documentation](https://cloud.google.com/compute/docs)

## Contributing

When modifying this infrastructure:
1. Test changes in a development environment first
2. Update documentation to reflect changes
3. Validate syntax using provider tools
4. Follow Google Cloud best practices
5. Update cost estimates if resource changes affect pricing