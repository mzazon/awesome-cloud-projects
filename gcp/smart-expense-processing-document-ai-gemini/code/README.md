# Infrastructure as Code for Smart Expense Processing using Document AI and Gemini

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Expense Processing using Document AI and Gemini".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 531.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Document AI API
  - Vertex AI API
  - Cloud Workflows
  - Cloud SQL
  - Cloud Storage
  - Cloud Functions
  - Cloud Run
- `curl` and `openssl` utilities installed
- Python 3.11+ (for Cloud Functions)
- PostgreSQL client (`psql`) for database operations

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create smart-expense-processing \
    --location=${REGION} \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/smart-expense-processing-document-ai-gemini/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe smart-expense-processing \
    --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts and wait for deployment completion
```

## Architecture Components

This infrastructure deployment creates:

### AI Processing Layer
- **Document AI Expense Processor**: Specialized processor for receipt data extraction
- **Vertex AI Gemini Model**: Advanced AI for expense validation and policy compliance

### Data Storage
- **Cloud SQL PostgreSQL**: Managed database for expense records and audit trails
- **Cloud Storage Bucket**: Receipt image storage with lifecycle management

### Orchestration & Processing
- **Cloud Workflows**: Serverless orchestration for expense processing pipeline
- **Cloud Functions**: Microservices for validation logic and reporting
- **Cloud Run Services**: Scalable containerized applications (if needed)

### Monitoring & Security
- **Cloud Monitoring Dashboard**: Real-time metrics and alerting
- **IAM Roles & Policies**: Least-privilege access controls
- **VPC Security**: Network isolation and firewall rules

## Configuration

### Required Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | Yes |
| `zone` | Deployment zone | `us-central1-a` | No |
| `db_instance_tier` | Cloud SQL instance size | `db-f1-micro` | No |
| `storage_class` | Cloud Storage class | `STANDARD` | No |

### Optional Customizations

```bash
# Custom database configuration
export TF_VAR_db_instance_tier="db-g1-small"
export TF_VAR_db_storage_size="20"

# Custom storage configuration  
export TF_VAR_storage_class="NEARLINE"
export TF_VAR_storage_location="US"

# Custom function configuration
export TF_VAR_function_memory="512"
export TF_VAR_function_timeout="300"
```

## Post-Deployment Setup

### 1. Initialize Database Schema

```bash
# Connect to Cloud SQL instance
gcloud sql connect smart-expense-db --user=postgres --database=expenses

# Run schema initialization (provided in deployment output)
```

### 2. Test Document AI Processor

```bash
# Get processor details from deployment output
export PROCESSOR_ID=$(terraform output -raw processor_id)

# Test with sample receipt
curl -X POST \
    -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    -H "Content-Type: application/json" \
    "https://${REGION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}:process" \
    -d @test-receipt.json
```

### 3. Validate Workflow Execution

```bash
# Execute test workflow
gcloud workflows run expense-processing-workflow \
    --location=${REGION} \
    --data='{"employee_email":"test@company.com","category":"meals"}'
```

## Monitoring & Operations

### View Deployment Status

```bash
# Infrastructure Manager
gcloud infra-manager deployments describe smart-expense-processing \
    --location=${REGION}

# Terraform
terraform show
```

### Access Monitoring Dashboard

1. Navigate to Cloud Monitoring in Google Cloud Console
2. Select "Dashboards" from the left menu
3. Find "Expense Processing Dashboard"
4. Monitor processing metrics and error rates

### View Logs

```bash
# Cloud Functions logs
gcloud functions logs read expense-validator --limit=50

# Workflow execution logs
gcloud workflows executions list expense-processing-workflow \
    --location=${REGION} \
    --limit=10
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**
   ```bash
   # Enable required APIs
   gcloud services enable documentai.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable workflows.googleapis.com
   ```

2. **Permission Denied**
   ```bash
   # Verify IAM roles
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Cloud SQL Connection Issues**
   ```bash
   # Check instance status
   gcloud sql instances describe smart-expense-db
   
   # Test connectivity
   gcloud sql connect smart-expense-db --user=postgres
   ```

4. **Document AI Quota Exceeded**
   ```bash
   # Check quota usage
   gcloud compute project-info describe \
       --format="table(quotas[].metric,quotas[].usage,quotas[].limit)"
   ```

### Debug Commands

```bash
# Check all deployed resources
gcloud resource-manager projects list --filter="${PROJECT_ID}"

# Verify Cloud Function deployment
gcloud functions describe expense-validator

# Check workflow status
gcloud workflows describe expense-processing-workflow --location=${REGION}

# Test database connectivity
gcloud sql instances describe smart-expense-db --format="value(ipAddresses[0].ipAddress)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete smart-expense-processing \
    --location=${REGION}

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for resource deletion confirmation
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources manually
gcloud sql instances delete smart-expense-db --quiet
gsutil -m rm -r gs://expense-receipts-*
gcloud functions delete expense-validator --quiet
gcloud functions delete expense-report-generator --quiet
gcloud workflows delete expense-processing-workflow --location=${REGION} --quiet
```

## Cost Estimation

### Development/Testing Environment
- Cloud SQL (db-f1-micro): ~$7/month
- Cloud Storage (10GB): ~$0.20/month
- Cloud Functions (1M invocations): ~$0.40/month
- Document AI (1000 pages): ~$15/month
- Vertex AI Gemini calls: ~$2-5/month
- **Total: ~$25-30/month**

### Production Environment
- Cloud SQL (db-g1-small): ~$25/month
- Cloud Storage (100GB): ~$2/month
- Cloud Functions (10M invocations): ~$4/month
- Document AI (10,000 pages): ~$150/month
- Vertex AI Gemini calls: ~$20-50/month
- **Total: ~$200-250/month**

## Security Considerations

### Implemented Security Features

- **IAM Least Privilege**: Custom service accounts with minimal required permissions
- **Data Encryption**: All data encrypted at rest and in transit
- **Network Security**: VPC firewall rules and private IP addressing
- **API Security**: OAuth 2.0 authentication for all service calls
- **Audit Logging**: Comprehensive audit trail for all operations

### Additional Security Recommendations

1. Enable VPC Service Controls for additional network isolation
2. Implement customer-managed encryption keys (CMEK) for sensitive data
3. Configure Cloud Armor for DDoS protection if exposing public endpoints
4. Set up Cloud Security Command Center for unified security monitoring
5. Implement data loss prevention (DLP) scanning for PII in documents

## Support

### Documentation References
- [Document AI Expense Parser](https://cloud.google.com/document-ai/docs/processors-list#expense_processor)
- [Vertex AI Gemini API](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/gemini)
- [Cloud Workflows](https://cloud.google.com/workflows/docs)
- [Cloud SQL PostgreSQL](https://cloud.google.com/sql/docs/postgres)

### Getting Help
- For infrastructure issues: Review deployment logs and error messages
- For Google Cloud platform issues: Consult [Google Cloud Support](https://cloud.google.com/support)
- For recipe-specific questions: Refer to the original recipe documentation

### Contributing
To report issues or suggest improvements to this infrastructure code:
1. Check existing issues and documentation
2. Provide detailed error messages and reproduction steps
3. Include environment details (CLI versions, project configuration)
4. Submit through your organization's standard channels