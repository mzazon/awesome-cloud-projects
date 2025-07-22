# Infrastructure as Code for Hybrid Classical-Quantum AI Workflows with Cirq and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Classical-Quantum AI Workflows with Cirq and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Project with billing enabled and appropriate quotas
- Quantum Computing Service access (requires special approval from Google Cloud)
- The following APIs enabled:
  - Compute Engine API
  - Cloud Storage API
  - Cloud Functions API
  - Vertex AI API
  - Notebooks API
  - Cloud Build API (for Infrastructure Manager)
- Appropriate IAM permissions:
  - Compute Admin
  - Storage Admin
  - Cloud Functions Admin
  - Vertex AI Admin
  - Project Editor (or equivalent granular permissions)
- Python 3.8+ with quantum computing libraries (for local development)
- Estimated cost: $150-300 for quantum processor usage, Vertex AI training, and compute resources

> **Important**: Quantum Computing Service access requires special approval from Google Cloud. Contact your Google Cloud representative to request access to quantum processors before deploying this infrastructure.

## Architecture Overview

This infrastructure deploys a hybrid quantum-classical portfolio optimization system that includes:

- **Vertex AI Workbench**: Managed Jupyter environment with quantum computing libraries
- **Cloud Storage**: Data storage for models, results, and analytics
- **Cloud Functions**: Serverless orchestration for hybrid workflows
- **Quantum Computing Integration**: Cirq framework setup for quantum algorithm execution
- **Monitoring Infrastructure**: Performance tracking and alerting

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for infrastructure as code, providing native integration with Google Cloud services.

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/quantum-portfolio-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/quantum-infrastructure.git" \
    --git-source-directory="." \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/quantum-portfolio-deployment
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem support.

```bash
# Navigate to Terraform directory
cd terraform/

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
export TF_VAR_zone="us-central1-a"

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Automated deployment scripts provide a simple, step-by-step deployment process.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts and monitor progress
```

## Configuration Variables

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    default: "quantum-portfolio-project"
  
  region:
    description: "Google Cloud Region"
    type: string
    default: "us-central1"
  
  machine_type:
    description: "Vertex AI Workbench machine type"
    type: string
    default: "n1-standard-4"
  
  enable_quantum_processor:
    description: "Enable real quantum processor access"
    type: boolean
    default: false
```

### Terraform Variables

Customize deployment by setting these variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Workbench configuration
workbench_machine_type = "n1-standard-4"
workbench_disk_size_gb = 100

# Storage configuration
bucket_location = "US"
bucket_storage_class = "STANDARD"

# Cloud Function configuration
function_memory_mb = 1024
function_timeout_seconds = 540

# Quantum computing settings
enable_quantum_processor = false
quantum_processor_id = ""  # Set if you have quantum processor access

# Monitoring settings
enable_monitoring = true
monitoring_notification_channels = ["your-email@example.com"]

# Cost optimization
enable_spot_instances = true
enable_preemptible_instances = true
```

### Bash Script Environment Variables

Set these variables before running deployment scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export WORKBENCH_MACHINE_TYPE="n1-standard-4"
export BUCKET_LOCATION="US"
export FUNCTION_MEMORY="1024MB"
export ENABLE_MONITORING="true"
export QUANTUM_PROCESSOR_ID=""  # Leave empty for simulation only
```

## Post-Deployment Setup

After infrastructure deployment, complete these setup steps:

### 1. Configure Quantum Environment

```bash
# Access Vertex AI Workbench
gcloud notebooks instances describe quantum-workbench-[suffix] --location=${ZONE}

# Install quantum computing packages (run in Workbench terminal)
pip install cirq>=1.3.0 cirq-google>=1.3.0 tensorflow-quantum>=0.7.3

# Test quantum simulation
python3 -c "
import cirq
qubit = cirq.GridQubit(0, 0)
circuit = cirq.Circuit(cirq.H(qubit), cirq.measure(qubit, key='result'))
simulator = cirq.Simulator()
result = simulator.run(circuit, repetitions=100)
print('Quantum simulation successful!')
"
```

### 2. Upload Application Code

```bash
# Upload quantum optimization scripts
gsutil cp ../scripts/* gs://quantum-portfolio-[suffix]/scripts/

# Upload sample data (if available)
gsutil cp sample_data/* gs://quantum-portfolio-[suffix]/data/
```

### 3. Test Hybrid Workflow

```bash
# Get Cloud Function URL
FUNCTION_URL=$(gcloud functions describe quantum-optimizer-[suffix] --region=${REGION} --format="value(httpsTrigger.url)")

# Test hybrid optimization
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "portfolio_data": {
        "n_assets": 8,
        "risk_aversion": 1.0
      }
    }'
```

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **Cloud Monitoring**: Custom metrics for portfolio performance and quantum algorithm efficiency
- **Cloud Logging**: Centralized logging for all components
- **Error Reporting**: Automatic error detection and alerting
- **Performance Dashboards**: Pre-configured dashboards for system health

Access monitoring:

```bash
# View logs
gcloud logging read "resource.type=cloud_function" --limit=50

# List custom metrics
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/portfolio/*"

# Access dashboards
echo "https://console.cloud.google.com/monitoring/dashboards"
```

## Security Considerations

The infrastructure implements security best practices:

- **IAM Least Privilege**: Minimal required permissions for each service
- **Network Security**: Private IPs and VPC firewall rules
- **Data Encryption**: Encryption at rest and in transit
- **Secret Management**: Cloud Secret Manager for sensitive data
- **Audit Logging**: Comprehensive audit trail

## Cost Optimization

Several cost optimization features are included:

- **Preemptible Instances**: Option to use lower-cost preemptible VMs
- **Auto-scaling**: Automatic scaling based on demand
- **Resource Scheduling**: Scheduled shutdown of non-production resources
- **Storage Lifecycle**: Automatic data archiving and cleanup

Monitor costs:

```bash
# View current costs
gcloud billing accounts list
gcloud billing projects describe ${PROJECT_ID}

# Set up budget alerts (replace BILLING_ACCOUNT_ID)
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Quantum Portfolio Budget" \
    --budget-amount=500USD
```

## Troubleshooting

### Common Issues

1. **Quantum Processor Access**:
   ```bash
   # Verify quantum service access
   gcloud services list --enabled --filter="name:quantum.googleapis.com"
   
   # If not enabled, contact Google Cloud support
   ```

2. **Vertex AI Workbench Issues**:
   ```bash
   # Check instance status
   gcloud notebooks instances describe quantum-workbench-[suffix] --location=${ZONE}
   
   # Restart if needed
   gcloud notebooks instances stop quantum-workbench-[suffix] --location=${ZONE}
   gcloud notebooks instances start quantum-workbench-[suffix] --location=${ZONE}
   ```

3. **Cloud Function Timeout**:
   ```bash
   # Increase timeout in terraform/main.tf or via console
   # Check function logs
   gcloud functions logs read quantum-optimizer-[suffix] --region=${REGION}
   ```

4. **Storage Permissions**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://quantum-portfolio-[suffix]
   
   # Fix permissions if needed
   gsutil iam ch serviceAccount:quantum-service@${PROJECT_ID}.iam.gserviceaccount.com:objectAdmin gs://quantum-portfolio-[suffix]
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud commands
gcloud config set core/verbosity debug

# For bash scripts
export DEBUG=true
./scripts/deploy.sh
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/quantum-portfolio-deployment

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
# Script will handle resource deletion in proper order
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud compute instances list
gcloud storage buckets list
gcloud functions list
gcloud notebooks instances list --location=${ZONE}

# Check for any remaining billing
gcloud billing projects describe ${PROJECT_ID}
```

## Advanced Configuration

### Custom Quantum Algorithms

To deploy custom quantum algorithms:

1. Modify `quantum_portfolio_optimizer.py` in the scripts directory
2. Update the Cloud Function code to reference new algorithms
3. Redeploy using your chosen IaC method

### Integration with Existing Systems

For enterprise integration:

- Configure VPC peering for network connectivity
- Set up IAM service accounts for cross-project access
- Implement custom monitoring dashboards
- Configure data pipeline integration

### Multi-Region Deployment

To deploy across multiple regions:

1. Copy the infrastructure configuration
2. Update region variables for each deployment
3. Configure cross-region data replication
4. Set up global load balancing if needed

## Performance Tuning

Optimize performance based on workload:

- **CPU-Intensive Workloads**: Use compute-optimized machine types
- **Memory-Intensive Tasks**: Increase Vertex AI Workbench memory
- **High-Throughput Requirements**: Enable multiple Cloud Function instances
- **Large Datasets**: Configure regional persistent disks

## Support and Resources

- **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
- **Google Cloud Documentation**: [Quantum Computing Service](https://cloud.google.com/quantum)
- **Cirq Documentation**: [https://quantumai.google/cirq](https://quantumai.google/cirq)
- **Vertex AI Guide**: [https://cloud.google.com/vertex-ai/docs](https://cloud.google.com/vertex-ai/docs)
- **Community Support**: Google Cloud Quantum Computing Community

For issues with this infrastructure code, please refer to the troubleshooting section above or consult the original recipe documentation.

## License

This infrastructure code is provided as part of the cloud recipes collection. Refer to the repository license for usage terms.