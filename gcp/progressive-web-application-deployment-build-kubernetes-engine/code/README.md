# Infrastructure as Code for Progressive Web Application Deployment with Cloud Build and Google Kubernetes Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Progressive Web Application Deployment with Cloud Build and Google Kubernetes Engine".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0+)
- Docker installed locally for container image testing
- Terraform installed (version 1.0+) if using Terraform implementation
- Appropriate GCP permissions:
  - Cloud Build Editor
  - Kubernetes Engine Admin
  - Storage Admin
  - Source Repository Administrator
  - Service Account User
- Estimated cost: $20-40 for GKE clusters, Load Balancer, and Cloud Build during testing period

## Architecture Overview

This solution deploys a Progressive Web Application (PWA) using:
- **Cloud Build** for CI/CD pipeline automation
- **Google Kubernetes Engine (GKE)** for container orchestration with blue-green deployment
- **Cloud Storage** for static asset hosting
- **Cloud Load Balancing** for traffic distribution
- **Container Registry** for container image storage
- **Cloud Source Repositories** for source code management

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/pwa-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="."
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply the configuration
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Variables

### Common Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `zone` | GCP zone for resources | `us-central1-a` | No |
| `cluster_name_blue` | Name for blue GKE cluster | `pwa-cluster-blue` | No |
| `cluster_name_green` | Name for green GKE cluster | `pwa-cluster-green` | No |
| `node_count` | Initial number of nodes per cluster | `2` | No |
| `machine_type` | Machine type for GKE nodes | `e2-medium` | No |
| `disk_size_gb` | Disk size for GKE nodes | `30` | No |
| `min_node_count` | Minimum nodes for autoscaling | `1` | No |
| `max_node_count` | Maximum nodes for autoscaling | `5` | No |

### Terraform-Specific Variables

Create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
cluster_name_blue  = "pwa-cluster-blue"
cluster_name_green = "pwa-cluster-green"
node_count         = 2
machine_type       = "e2-medium"
disk_size_gb       = 30
min_node_count     = 1
max_node_count     = 5
```

## Deployment Process

### 1. Infrastructure Deployment

The infrastructure deployment creates:
- Two GKE clusters (blue and green environments)
- Cloud Storage bucket for static assets
- Cloud Source Repository for code
- IAM service accounts and permissions
- Cloud Build triggers
- Container Registry repositories

### 2. Application Deployment

After infrastructure deployment:
1. The sample PWA code is automatically uploaded to the Cloud Source Repository
2. Cloud Build triggers automatically build and deploy the application
3. The application is deployed to both blue and green GKE clusters
4. Load balancer distributes traffic between environments

### 3. Validation

Post-deployment validation includes:
- Verifying GKE cluster health
- Testing PWA functionality
- Validating blue-green deployment
- Checking load balancer configuration

## Monitoring and Logging

The deployed infrastructure includes:
- **Cloud Monitoring**: Automatic metrics collection for GKE clusters
- **Cloud Logging**: Centralized logging for all components
- **Health Checks**: Kubernetes liveness and readiness probes
- **Alerting**: Configurable alerts for deployment failures

## Security Features

- **IAM**: Least privilege access controls
- **Network Security**: Private GKE clusters with authorized networks
- **Container Security**: Automated vulnerability scanning
- **Secret Management**: Secure handling of sensitive data
- **RBAC**: Kubernetes role-based access control

## Scaling Configuration

The solution includes automatic scaling:
- **Horizontal Pod Autoscaler**: Scales pods based on CPU/memory usage
- **Cluster Autoscaler**: Scales GKE nodes based on pod requirements
- **Load Balancer**: Distributes traffic across healthy instances

## Blue-Green Deployment

The blue-green deployment strategy provides:
- **Zero Downtime**: Seamless switching between environments
- **Quick Rollback**: Instant rollback to previous version
- **Testing**: Validation in green environment before production
- **Risk Mitigation**: Reduced deployment risk

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/pwa-deployment
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   - Ensure your account has the required IAM roles
   - Check service account permissions for Cloud Build

2. **Quota Limits**:
   - Verify GKE node quotas in your project
   - Check Cloud Build concurrent build limits

3. **Network Issues**:
   - Ensure firewall rules allow required traffic
   - Check VPC network configuration

4. **Build Failures**:
   - Review Cloud Build logs for detailed error messages
   - Verify container image registry permissions

### Debug Commands

```bash
# Check GKE cluster status
gcloud container clusters list --region=${REGION}

# View Cloud Build history
gcloud builds list --limit=10

# Check container images
gcloud container images list --repository=gcr.io/${PROJECT_ID}/pwa-demo

# View logs
gcloud logging read "resource.type=k8s_cluster" --limit=50
```

## Cost Optimization

- **GKE Autopilot**: Consider using GKE Autopilot for reduced costs
- **Preemptible Instances**: Use preemptible VMs for development environments
- **Resource Limits**: Configure appropriate resource requests and limits
- **Monitoring**: Set up billing alerts and cost monitoring

## Customization

### Adding Custom Domains

1. Update the ingress configuration with your domain
2. Configure SSL certificates using Google-managed certificates
3. Update DNS records to point to the load balancer IP

### Scaling Configuration

Modify the autoscaling parameters in the Kubernetes deployment:
- Adjust `minReplicas` and `maxReplicas` for HPA
- Configure resource requests and limits
- Update cluster autoscaling bounds

### Security Hardening

- Enable Binary Authorization for container image verification
- Configure Pod Security Standards
- Implement network policies for traffic isolation
- Enable audit logging for compliance

## Integration with Other Services

### Cloud CDN
- Configure Cloud CDN for static asset caching
- Optimize cache policies for PWA resources

### Cloud Monitoring
- Set up custom dashboards for application metrics
- Configure SLO monitoring for reliability tracking

### Cloud Security Command Center
- Enable security scanning for vulnerabilities
- Configure compliance monitoring

## Support and Documentation

- [Google Kubernetes Engine Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Progressive Web Apps Guide](https://web.dev/progressive-web-apps/)
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements before production use.