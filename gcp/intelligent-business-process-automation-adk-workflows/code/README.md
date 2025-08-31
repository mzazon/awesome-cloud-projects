# Infrastructure as Code for Intelligent Business Process Automation with Agent Development Kit and Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Business Process Automation with Agent Development Kit and Workflows".

## Overview

This recipe deploys an intelligent business process automation system that combines:
- **Vertex AI Agent Development Kit** for natural language understanding
- **Cloud Workflows** for process orchestration 
- **Cloud SQL (PostgreSQL)** for state management and audit trails
- **Cloud Functions** for serverless business logic processing

The solution automatically processes business requests through AI-powered analysis, executes multi-step workflows based on intelligent routing decisions, and maintains complete audit trails in a managed database.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Bash Scripts**: Deployment and cleanup automation scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud Project with billing enabled
- Required APIs enabled:
  - Vertex AI API (`aiplatform.googleapis.com`)
  - Cloud Workflows API (`workflows.googleapis.com`)
  - Cloud SQL Admin API (`sqladmin.googleapis.com`)
  - Cloud Functions API (`cloudfunctions.googleapis.com`)
  - Cloud Build API (`cloudbuild.googleapis.com`)
  - Eventarc API (`eventarc.googleapis.com`)
  - Artifact Registry API (`artifactregistry.googleapis.com`)
  - Cloud Run API (`run.googleapis.com`)
  - Cloud Logging API (`logging.googleapis.com`)
- Appropriate IAM permissions for resource creation:
  - Vertex AI Admin
  - Workflows Admin
  - Cloud SQL Admin
  - Cloud Functions Admin
  - Service Account Admin
  - Project IAM Admin
- **For Terraform**: Terraform 1.0+ installed
- **For Infrastructure Manager**: Google Cloud CLI with Infrastructure Manager commands enabled

## Estimated Costs

**Testing Duration (45 minutes)**: $15-25 USD

Cost breakdown:
- Cloud SQL instance (db-f1-micro): ~$7-10
- Cloud Functions (3 functions): ~$2-3
- Vertex AI API usage: ~$3-5
- Cloud Workflows executions: ~$1-2
- Cloud Storage and networking: ~$2-5

> **Cost Optimization**: All resources are configured with minimal specifications for development/testing. Monitor usage through Google Cloud Console to avoid unexpected charges.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's managed infrastructure as code service that uses Terraform configurations.

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable inframanager.googleapis.com

# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/bpa-automation \
    --config-file=main.yaml \
    --import-existing-resources
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# When prompted, type 'yes' to confirm deployment
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your project and region
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

```yaml
variables:
  project_id:
    value: "your-project-id"
  region:
    value: "us-central1"
  db_tier:
    value: "db-f1-micro"  # For production: db-custom-2-4096
  backup_start_time:
    value: "03:00"        # UTC backup time
```

### Terraform Variables

Customize deployment by editing `terraform/variables.tf` or creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Database configuration
db_tier              = "db-f1-micro"
db_backup_start_time = "03:00"

# Function configuration
function_memory         = "256Mi"
function_timeout        = "60s"
function_max_instances  = 10

# Environment suffix for unique naming
environment_suffix = "dev"
```

### Bash Script Configuration

The bash scripts will prompt for required configuration or read from environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export DB_TIER="db-f1-micro"
```

## Architecture Components

The infrastructure creates the following resources:

### Database Layer
- **Cloud SQL PostgreSQL Instance**: Managed database with automated backups
- **Database Schema**: Tables for process requests, approvals, and audit trails
- **Security**: Private IP and encrypted connections

### Serverless Computing
- **Process Approval Function**: Handles decision-making logic
- **Notification Function**: Manages stakeholder communications  
- **AI Agent Function**: Processes natural language requests

### Orchestration
- **Cloud Workflows**: Intelligent process routing and execution
- **Workflow IAM**: Service accounts and permissions for secure execution

### AI/ML Services
- **Vertex AI Integration**: Natural language understanding capabilities
- **Agent Development Kit**: Business process interpretation

### Security
- **IAM Roles and Policies**: Least privilege access controls
- **Service Accounts**: Dedicated accounts for each service
- **VPC Security**: Private networking where applicable

## Post-Deployment Configuration

After deployment, you'll need to:

1. **Initialize Database Schema**: The database schema is automatically created during deployment

2. **Configure Workflow Triggers**: Test the workflow execution:
   ```bash
   # Get the workflow name from outputs
   gcloud workflows execute [WORKFLOW_NAME] \
       --location=${REGION} \
       --data='{"request_id":"test-001","process_type":"expense_approval","requester_email":"test@company.com","request_data":{"amount":"250"}}'
   ```

3. **Test AI Agent Function**: Verify natural language processing:
   ```bash
   # Get function URL from outputs
   curl -X POST [AGENT_FUNCTION_URL] \
       -H "Content-Type: application/json" \
       -d '{"message":"I need approval for a $500 expense","user_email":"employee@company.com"}'
   ```

4. **Verify Database Connectivity**: Check that all functions can connect to the database

## Monitoring and Observability

The infrastructure includes monitoring capabilities:

- **Cloud Logging**: All functions log to Cloud Logging
- **Cloud Monitoring**: Automatic metrics for all Google Cloud services
- **Audit Trails**: Complete process tracking in the database
- **Workflow Execution Logs**: Detailed workflow execution history

Access logs and metrics through:
```bash
# View function logs
gcloud functions logs read [FUNCTION_NAME] --region=${REGION}

# View workflow executions
gcloud workflows executions list --workflow=[WORKFLOW_NAME] --location=${REGION}

# Monitor database performance
gcloud sql operations list --instance=[DB_INSTANCE_NAME]
```

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege IAM**: Each service has minimal required permissions
- **Private Networking**: Cloud SQL uses private IP when possible
- **Encryption**: Data encrypted in transit and at rest
- **Service Accounts**: Dedicated service accounts for each component
- **Audit Logging**: Complete audit trail of all operations

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/bpa-automation
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# When prompted, type 'yes' to confirm deletion
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has the required IAM roles
3. **Database Connection Issues**: Check firewall rules and authorized networks
4. **Function Deployment Failures**: Verify Cloud Build API is enabled

### Debugging Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check resource status
gcloud sql instances list
gcloud functions list --region=${REGION}
gcloud workflows list --location=${REGION}

# View detailed logs
gcloud logging read "resource.type=cloud_function" --limit=50
```

### Support Resources

- [Google Cloud Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)

## Advanced Configuration

### Production Considerations

For production deployments, consider these modifications:

1. **Database High Availability**:
   ```hcl
   db_tier = "db-custom-4-8192"
   availability_type = "REGIONAL"
   backup_configuration {
     enabled                        = true
     start_time                     = "03:00"
     point_in_time_recovery_enabled = true
     transaction_log_retention_days = 7
   }
   ```

2. **Enhanced Security**:
   ```hcl
   database_flags = [
     {
       name  = "log_connections"
       value = "on"
     },
     {
       name  = "log_disconnections" 
       value = "on"
     }
   ]
   ```

3. **Scaling Configuration**:
   ```hcl
   function_max_instances = 100
   function_min_instances = 1
   function_memory = "512Mi"
   ```

4. **Monitoring and Alerting**:
   - Set up Cloud Monitoring alerts for function failures
   - Configure database performance monitoring
   - Enable audit log analysis

## Version History

- **v1.0**: Initial infrastructure implementation
- **v1.1**: Added monitoring and security enhancements

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and documentation
3. Verify all security configurations
4. Test the complete deployment and cleanup process
5. Update cost estimates if resource configurations change

## License

This infrastructure code is provided as part of the Google Cloud Recipes collection. See the main repository license for details.