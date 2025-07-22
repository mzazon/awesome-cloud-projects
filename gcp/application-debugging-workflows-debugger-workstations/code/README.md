# Infrastructure as Code for Application Debugging Workflows with Cloud Debugger and Cloud Workstations

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Debugging Workflows with Cloud Debugger and Cloud Workstations".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Workstations
  - Artifact Registry
  - Cloud Run
  - Cloud Build
  - Cloud Logging
  - Cloud Monitoring
- Docker installed (for custom container image builds)
- Estimated cost: $30-50 for full testing period

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Enable required APIs
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/debug-workflow \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo=https://github.com/your-org/your-repo \
    --git-source-directory=infrastructure-manager \
    --git-source-ref=main
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Workstations Cluster**: Managed development environment infrastructure
- **Workstation Configuration**: Template with custom debugging tools
- **Artifact Registry Repository**: Container image repository for custom tools
- **Custom Container Image**: Extended workstation image with debugging capabilities
- **Sample Cloud Run Application**: Target application for debugging demonstrations
- **IAM Roles and Permissions**: Secure access controls for debugging workflows
- **Monitoring and Logging**: Observability for debugging sessions

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

```yaml
variables:
  project_id: "your-project-id"
  region: "us-central1"
  zone: "us-central1-a"
  workstation_machine_type: "e2-standard-4"
  workstation_disk_size: "200"
  enable_monitoring: true
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Workstation configuration
workstation_machine_type = "e2-standard-4"
workstation_disk_size    = 200
workstation_idle_timeout = 7200

# Container image configuration
include_debug_tools = true
include_python_tools = true
include_nodejs_tools = true

# Monitoring configuration
enable_monitoring = true
enable_logging    = true

# Application configuration
sample_app_memory = "512Mi"
sample_app_cpu    = "1"
```

### Bash Script Environment Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export WORKSTATION_MACHINE_TYPE="e2-standard-4"
export WORKSTATION_DISK_SIZE="200"
export ENABLE_MONITORING="true"
```

## Deployment Process

### Phase 1: Foundation Setup
1. Enable required Google Cloud APIs
2. Create IAM service accounts and roles
3. Set up Artifact Registry repository
4. Build custom workstation container image

### Phase 2: Workstation Infrastructure
1. Create Cloud Workstations cluster
2. Configure workstation template with custom image
3. Set up networking and security controls
4. Configure monitoring and logging integration

### Phase 3: Application Deployment
1. Deploy sample application to Cloud Run
2. Configure application logging and monitoring
3. Set up debugging access patterns
4. Validate end-to-end connectivity

### Phase 4: Workstation Provisioning
1. Create workstation instance from template
2. Configure debugging environment variables
3. Set up access controls and timeouts
4. Validate debugging tools and connectivity

## Accessing Your Debugging Environment

After deployment:

1. **Get Workstation Access URL**:
   ```bash
   # Using gcloud CLI
   gcloud workstations describe WORKSTATION_NAME \
       --location=REGION \
       --cluster=CLUSTER_NAME \
       --config=CONFIG_NAME \
       --format="value(host)"
   
   # Using Terraform output
   terraform output workstation_url
   ```

2. **Access Browser-Based IDE**:
   - Open the workstation URL in your browser
   - Authenticate with your Google Cloud credentials
   - VS Code will load with debugging tools pre-installed

3. **Connect to Sample Application**:
   ```bash
   # Get application URL
   terraform output sample_app_url
   
   # Test application from workstation terminal
   curl "APPLICATION_URL/health"
   ```

## Available Debugging Tools

The custom workstation image includes:

- **General Debugging**: gdb, strace, tcpdump, htop
- **Python Tools**: debugpy, pdb++, ipdb
- **Node.js Tools**: node-inspect, Chrome DevTools integration
- **VS Code Extensions**: Python debugger, JavaScript debugger
- **Network Tools**: curl, jq, network analysis utilities
- **Monitoring Integration**: Cloud Logging, Cloud Monitoring clients

## Security Considerations

- Workstations run in private Google Cloud networks
- IAM controls restrict access to authorized users
- Container images are scanned for vulnerabilities
- Debugging sessions are logged for audit purposes
- Network access is controlled through VPC configurations
- Secrets and credentials are managed through Secret Manager

## Monitoring and Observability

### Cloud Monitoring Dashboards

- Workstation resource utilization
- Debugging session duration and frequency
- Application performance during debugging
- Network connectivity metrics

### Cloud Logging Integration

- Workstation activity logs
- Application request logs
- Debugging session artifacts
- Security and access logs

### Custom Metrics

- Debug session success rates
- Time to resolution for issues
- Resource utilization patterns
- Cost optimization opportunities

## Troubleshooting

### Common Issues

1. **Workstation Won't Start**:
   - Check IAM permissions
   - Verify custom image build success
   - Review cluster resource limits

2. **Cannot Access Application**:
   - Verify Cloud Run service deployment
   - Check network connectivity
   - Review firewall rules

3. **Debugging Tools Missing**:
   - Check custom image build logs
   - Verify container registry access
   - Review workstation configuration

### Debugging Commands

```bash
# Check workstation status
gcloud workstations describe WORKSTATION_NAME \
    --location=REGION \
    --cluster=CLUSTER_NAME \
    --config=CONFIG_NAME

# View workstation logs
gcloud logging read "resource.type=\"gce_instance\" AND 
                    resource.labels.instance_name:workstation" \
    --limit=50

# Check application logs
gcloud logging read "resource.type=\"cloud_run_revision\" AND 
                    resource.labels.service_name=\"SERVICE_NAME\"" \
    --limit=20
```

## Cost Optimization

### Automatic Resource Management

- Workstations auto-stop after idle timeout (default: 2 hours)
- Cloud Run scales to zero when not in use
- Artifact Registry charged only for storage used
- Monitoring and logging with standard retention policies

### Cost Monitoring

```bash
# Check current costs
gcloud billing budgets list --billing-account=BILLING_ACCOUNT

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT \
    --display-name="Debug Workflow Budget" \
    --budget-amount=100
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/debug-workflow
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Script will prompt for confirmation before deletion
```

### Manual Cleanup Verification

```bash
# Verify workstation deletion
gcloud workstations list --location=us-central1

# Verify Cloud Run service deletion
gcloud run services list --region=us-central1

# Verify Artifact Registry cleanup
gcloud artifacts repositories list --location=us-central1

# Check for remaining resources
gcloud compute instances list
gcloud container images list
```

## Advanced Configuration

### Custom Debugging Tools

To add additional debugging tools to the workstation image:

1. Modify the `Dockerfile` in the custom image build
2. Add tool installation commands
3. Rebuild and push the image to Artifact Registry
4. Update workstation configuration to use new image

### Multi-Language Support

Configure language-specific debugging environments:

```yaml
# Infrastructure Manager configuration
workstation_configs:
  - name: "python-debug"
    container_image: "python-debug-image:latest"
    machine_type: "e2-standard-4"
  - name: "nodejs-debug"
    container_image: "nodejs-debug-image:latest"
    machine_type: "e2-standard-2"
```

### Integration with CI/CD

Connect debugging workflows with build pipelines:

```yaml
# Cloud Build trigger for debug environment
triggers:
  - name: "debug-env-trigger"
    github:
      owner: "your-org"
      name: "your-repo"
      push:
        branch: "debug-.*"
    filename: "cloudbuild-debug.yaml"
```

## Support and Documentation

- [Cloud Workstations Documentation](https://cloud.google.com/workstations/docs)
- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent repository.