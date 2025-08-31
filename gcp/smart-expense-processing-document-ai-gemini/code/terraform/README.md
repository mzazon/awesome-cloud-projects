# Smart Expense Processing Infrastructure - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying the Smart Expense Processing system using Document AI and Gemini on Google Cloud Platform.

## Architecture Overview

The infrastructure deploys a complete AI-powered expense processing system that:

- **Extracts** receipt data using Document AI's specialized expense parser
- **Validates** expenses using Gemini's advanced reasoning capabilities  
- **Orchestrates** approval workflows with Cloud Workflows
- **Stores** structured data in Cloud SQL PostgreSQL
- **Generates** automated reports and analytics
- **Monitors** system performance with comprehensive dashboards

## Infrastructure Components

### Core Services
- **Document AI Processor**: Expense parser for receipt data extraction
- **Cloud SQL PostgreSQL**: Managed database for expense data storage
- **Cloud Storage**: Receipt archive and function source code storage
- **Cloud Functions**: Expense validation and report generation services
- **Cloud Workflows**: Orchestration of the complete processing pipeline
- **Vertex AI**: Gemini model integration for intelligent validation

### Supporting Services
- **Secret Manager**: Secure storage of database credentials
- **Cloud Monitoring**: Performance monitoring and alerting
- **Cloud Scheduler**: Automated report generation scheduling
- **Cloud Logging**: Centralized logging and audit trails
- **IAM**: Secure service-to-service authentication

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Account** with billing enabled
2. **Google Cloud CLI** installed and configured (version 431.0.0 or later)
3. **Terraform** installed (version 1.5.0 or later)
4. **Appropriate GCP Permissions**:
   - Project Editor or Owner role
   - Service Account Admin role
   - Cloud SQL Admin role
   - Storage Admin role
   - Cloud Functions Admin role

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/smart-expense-processing-document-ai-gemini/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Database configuration
database_password = "YourSecurePassword123!"
database_user     = "expense_app"

# Optional customizations
environment                = "production"
database_tier             = "db-f1-micro"
max_function_instances    = 10
enable_scheduled_reports  = true
notification_email        = "admin@yourcompany.com"

# Policy limits (in USD)
meal_daily_limit             = 75.00
hotel_nightly_limit          = 300.00
equipment_approval_threshold = 500.00
entertainment_limit          = 150.00
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Post-Deployment Setup

After successful deployment:

1. **Create Document AI Processor** (manual step required):
   ```bash
   # Note the processor ID from the console or API response
   export PROCESSOR_ID="your-processor-id"
   
   # Update terraform.tfvars with the processor ID
   echo 'document_ai_processor_id = "'$PROCESSOR_ID'"' >> terraform.tfvars
   
   # Re-apply to configure the processor
   terraform apply
   ```

2. **Set up Database Schema**:
   ```bash
   # Connect to the database and create tables
   gcloud sql connect $(terraform output -raw database_instance_name) --user=postgres
   
   # In the SQL prompt, create the expenses table:
   CREATE TABLE expenses (
       id SERIAL PRIMARY KEY,
       employee_email VARCHAR(255) NOT NULL,
       vendor_name VARCHAR(255),
       expense_date DATE,
       total_amount DECIMAL(10,2),
       currency VARCHAR(3) DEFAULT 'USD',
       category VARCHAR(100),
       description TEXT,
       receipt_url VARCHAR(500),
       extracted_data JSONB,
       validation_status VARCHAR(50) DEFAULT 'pending',
       approval_status VARCHAR(50) DEFAULT 'pending',
       approver_email VARCHAR(255),
       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
       updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   ```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region | `us-central1` | No |
| `environment` | Environment label | `development` | No |

### Database Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `database_version` | PostgreSQL version | `POSTGRES_15` | No |
| `database_tier` | Machine type | `db-f1-micro` | No |
| `database_password` | App user password | - | Yes |
| `deletion_protection` | Prevent accidental deletion | `true` | No |

### Policy Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `meal_daily_limit` | Daily meal expense limit | `$75.00` |
| `hotel_nightly_limit` | Nightly hotel limit | `$300.00` |
| `equipment_approval_threshold` | Equipment pre-approval threshold | `$500.00` |
| `entertainment_limit` | Entertainment expense limit | `$150.00` |

### Advanced Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `max_function_instances` | Cloud Function scaling limit | `10` |
| `enable_scheduled_reports` | Enable automated reports | `true` |
| `report_schedule` | Cron schedule for reports | `0 9 * * 1` |
| `force_destroy` | Allow bucket destruction | `false` |

## Testing the Deployment

### 1. Test Expense Validation Function

```bash
# Get the function URL
VALIDATOR_URL=$(terraform output -raw expense_validator_function_url)

# Test with sample expense data
curl -X POST "$VALIDATOR_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "vendor_name": "Business Restaurant",
    "total_amount": 45.50,
    "expense_date": "2025-01-15",
    "category": "meals",
    "description": "Client lunch meeting",
    "employee_email": "test@company.com"
  }'
```

### 2. Test Workflow Execution

```bash
# Get workflow name
WORKFLOW_NAME=$(terraform output -raw expense_workflow_name)

# Execute workflow with test data
gcloud workflows run $WORKFLOW_NAME \
  --location=$(terraform output -raw region) \
  --data='{
    "receipt_content": "base64-encoded-receipt-image",
    "mime_type": "image/jpeg",
    "employee_email": "test@company.com",
    "category": "meals",
    "description": "Business lunch"
  }'
```

### 3. Generate Test Report

```bash
# Get report generator URL
REPORT_URL=$(terraform output -raw report_generator_function_url)

# Generate a test report
curl -X POST "$REPORT_URL" \
  -H "Content-Type: application/json" \
  -d '{"report_type": "weekly"}'
```

## Monitoring and Observability

### Access Monitoring Dashboard

```bash
# Get dashboard URL
echo "https://console.cloud.google.com/monitoring/dashboards/custom/$(terraform output -raw monitoring_dashboard_id)"
```

### View Logs

```bash
# View Cloud Function logs
gcloud logging read 'resource.type="cloud_function"' --limit=50

# View Workflow logs  
gcloud logging read 'resource.type="workflows_workflow"' --limit=20

# View Database logs
gcloud logging read 'resource.type="cloudsql_database"' --limit=30
```

### Check System Health

```bash
# Check function status
gcloud functions describe $(terraform output -raw expense_validator_function_name) \
  --region=$(terraform output -raw region)

# Check database status
gcloud sql instances describe $(terraform output -raw database_instance_name)

# Check workflow status
gcloud workflows describe $(terraform output -raw expense_workflow_name) \
  --location=$(terraform output -raw region)
```

## Cost Management

### Estimated Monthly Costs

- **Cloud SQL Instance**: ~$25-50 (depending on usage)
- **Cloud Functions**: ~$5-15 (depending on invocations)  
- **Cloud Storage**: ~$1-5 (depending on storage and operations)
- **Document AI**: ~$10-30 (depending on documents processed)
- **Vertex AI Gemini**: ~$5-20 (depending on API calls)
- **Other Services**: ~$5-10

**Total Estimated**: ~$50-130 per month

### Cost Optimization Tips

1. **Use appropriate database tiers** for your workload
2. **Configure function concurrency limits** to control costs
3. **Implement storage lifecycle policies** for long-term savings
4. **Monitor API usage** to avoid unexpected charges
5. **Use budget alerts** to track spending

## Security Considerations

### Implemented Security Features

- **IAM least privilege** access for all service accounts
- **Encrypted storage** for all data at rest
- **HTTPS/TLS** for all data in transit
- **Secret Manager** for credential storage
- **Audit logging** for all administrative actions
- **Network security** with private service access

### Additional Security Recommendations

1. **Restrict database access** to specific IP ranges in production
2. **Enable VPC Service Controls** for additional network security
3. **Implement regular security scanning** of function code
4. **Review IAM permissions** quarterly
5. **Enable organization policy** constraints

## Troubleshooting

### Common Issues

#### Document AI Processor Not Found
```bash
# Verify processor exists and get ID
gcloud ai document-processors list --location=$(terraform output -raw region)

# Update terraform.tfvars with correct processor ID
echo 'document_ai_processor_id = "correct-processor-id"' >> terraform.tfvars
terraform apply
```

#### Database Connection Issues
```bash
# Check database status
gcloud sql instances describe $(terraform output -raw database_instance_name)

# Test connectivity
gcloud sql connect $(terraform output -raw database_instance_name) --user=postgres
```

#### Function Deployment Failures
```bash
# Check function logs
gcloud functions logs read $(terraform output -raw expense_validator_function_name) \
  --region=$(terraform output -raw region)

# Redeploy function
terraform taint google_cloudfunctions2_function.expense_validator
terraform apply
```

### Getting Help

- **Terraform Documentation**: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- **Google Cloud Documentation**: https://cloud.google.com/docs
- **Recipe Documentation**: ../smart-expense-processing-document-ai-gemini.md

## Cleanup

To remove all deployed resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm deletion when prompted
# Type 'yes' to proceed
```

⚠️ **Warning**: This will permanently delete all resources and data. Ensure you have backups if needed.

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Check Terraform provider documentation for configuration options

## Contributing

When modifying this infrastructure:

1. **Test changes** in a development environment first
2. **Update documentation** for any new variables or resources
3. **Follow Terraform best practices** for resource naming and organization
4. **Validate configurations** using `terraform validate` and `terraform plan`
5. **Add appropriate comments** for complex configurations